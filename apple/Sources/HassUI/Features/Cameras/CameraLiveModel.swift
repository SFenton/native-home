import AVFoundation
import CoreImage
import Foundation
import QuartzCore
import HassCore
import HassTelemetry
import Observation
#if canImport(WebRTC) && canImport(UIKit)
import WebRTC
#endif

/// Drives live video for one camera: WebRTC first, HLS if that fails, the snapshot if both do.
///
/// A stream that fell back to HLS keeps trying WebRTC in the background (``defaultUpgradeDelays``): HLS runs seconds
/// behind, and WebRTC usually missed its first-frame budget only because the network was still settling after the app
/// returned. The HLS picture stays up until a WebRTC frame decodes, then the stream swaps to it without leaving live.
///
/// One model per camera is shared by every tile and viewer through ``CameraStreamPool``, so a viewer opened
/// from a tile shows the frames the tile is already playing. Each attempt gets its mode's
/// ``CameraStreamMode/firstFrameTimeout`` to show a frame before the next mode is tried. Views keep the
/// snapshot up until ``state`` is live, so nothing blanks while streams connect or fall back.
@MainActor
@Observable
final class CameraLiveModel {
    // MARK: - State

    /// Mode and phase (connecting, live, failed).
    private(set) var state: CameraStreamState
    /// The HLS player while HLS is the current mode.
    private(set) var hlsPlayer: AVPlayer?
    #if canImport(WebRTC) && canImport(UIKit)
    /// The WebRTC session while WebRTC is the current mode.
    private(set) var webRTCPeer: WebRTCCameraPeer?
    #endif

    /// The last live frame of a stream the pool paused, shown over the snapshot until the next first frame.
    private(set) var pausedFrame: CGImage?

    /// Whether the camera's sound is off (the default; web cameras open muted).
    private(set) var isMuted = true
    /// Whether a stream is connecting or playing (``start(connection:)`` ran and ``stop()`` has not).
    private(set) var isRunning = false
    /// When the stream last stopped showing frames (stalled, or suspended in the background); cleared by the next
    /// first frame. The viewer's reconnecting pill reads "Last live 6:51 PM" from it.
    private(set) var lastLiveAt: Date?

    let camera: HomeConfig.Camera
    /// Called when every mode failed, so the pool can drop the stream's retention.
    @ObservationIgnored var onExhausted: (() -> Void)?
    /// Called when a stream shows its first frame (the pool forgets the camera's failed attempts).
    @ObservationIgnored var onLive: (() -> Void)?
    /// Called when a live stream stopped delivering frames and was taken down, so the pool can restart it with its
    /// retry backoff.
    @ObservationIgnored var onStalled: (() -> Void)?
    /// Called when ``isMuted`` changes, so the pool can update the app's audio session.
    @ObservationIgnored var onMuteChange: (() -> Void)?
    @ObservationIgnored private var hlsVideoOutput: AVPlayerItemVideoOutput?

    /// Opens a mode's player for a model (production opens go2rtc WebRTC or HLS through Home Assistant); tests
    /// substitute one that records instead of touching the network.
    @ObservationIgnored let opener: CameraStreamOpener?
    /// How long each mode may take to show its first frame (``CameraStreamMode/firstFrameTimeout``; tests shorten it).
    @ObservationIgnored private let firstFrameTimeout: (CameraStreamMode) -> Duration

    @ObservationIgnored private weak var connection: HassConnection?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var attempt: Task<Void, Never>?
    /// KVO on the HLS item and player. (Combine's `publisher(for:).values` delivered only the initial
    /// values here, so a playing stream never reported its first frame.)
    @ObservationIgnored private var hlsObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var census: ResourceCensus.Registration?
    /// Watches a live stream's frame count; nil unless a stream is live.
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private let stallAfter: Duration
    @ObservationIgnored private let stallCheckInterval: Duration
    /// Waits before each background WebRTC attempt while HLS plays; one attempt per entry, then HLS stays.
    @ObservationIgnored private let upgradeDelays: [Duration]
    /// The wait and the attempt in flight; nil when none is scheduled.
    @ObservationIgnored private var upgrade: Task<Void, Never>?
    /// Attempts used since the stream last started.
    @ObservationIgnored private var upgradeAttempts = 0
    /// Whether a background WebRTC attempt is open (its first frame promotes it).
    @ObservationIgnored private var candidateOpen = false
    #if canImport(WebRTC) && canImport(UIKit)
    /// The background WebRTC session, not yet shown by any view.
    @ObservationIgnored private var candidatePeer: WebRTCCameraPeer?
    #endif
    /// Replaces how the frame count is read (tests, and the Debug freeze below).
    @ObservationIgnored private let frameCounter: (@MainActor (CameraLiveModel) -> Int?)?
    #if DEBUG
    /// Debug fault injection (`FENTON_CAMERA_FREEZE_ONCE=<go2rtc stream id>`): the named camera's frame count stops
    /// advancing the first time it is read while live, as a camera that stops sending does, so a journey can watch the
    /// watchdog restart the stream. Only that first stream freezes.
    @ObservationIgnored private var frozenCount: Int?
    @ObservationIgnored private var didFreeze = false
    #endif

    // MARK: - Init

    /// - Parameters:
    ///   - camera: The camera to stream.
    ///   - modes: Modes to try in order; defaults to ``defaultModes``.
    ///   - opener: Replaces the network opening of each mode (tests).
    ///   - firstFrameTimeout: Replaces each mode's first-frame timeout (tests).
    ///   - stallAfter: How long a live stream's frame count may stay put before it is taken down and restarted
    ///     (web `FRAME_STALL_MS`, 8 s).
    ///   - stallCheckInterval: How often the frame count is read (web `FRAME_CHECK_MS`, 1 s).
    ///   - upgradeDelays: Waits before each background WebRTC attempt while HLS plays; empty turns upgrades off.
    ///   - frameCounter: Replaces how the frame count is read (tests).
    init(camera: HomeConfig.Camera, modes: [CameraStreamMode] = CameraLiveModel.defaultModes, opener: CameraStreamOpener? = nil,
         firstFrameTimeout: @escaping (CameraStreamMode) -> Duration = \.firstFrameTimeout,
         stallAfter: Duration = FrameStallDetector.defaultStallAfter, stallCheckInterval: Duration = .seconds(1),
         upgradeDelays: [Duration] = CameraLiveModel.defaultUpgradeDelays,
         frameCounter: (@MainActor (CameraLiveModel) -> Int?)? = nil) {
        self.camera = camera
        self.upgradeDelays = upgradeDelays
        self.opener = opener
        self.firstFrameTimeout = firstFrameTimeout
        self.stallAfter = stallAfter
        self.stallCheckInterval = stallCheckInterval
        self.frameCounter = frameCounter
        state = CameraStreamState(modes: modes)
        census = ResourceCensus.shared.register { [weak self] in self?.liveResources ?? [:] }
    }

    /// What this model holds right now (`ResourceCensus`): players, the attempt task and KVO observations.
    var liveResources: [String: Int] {
        var players = hlsPlayer == nil ? 0 : 1
        #if canImport(WebRTC) && canImport(UIKit)
        players += webRTCPeer == nil ? 0 : 1
        #endif
        return [
            "Camera.players": players,
            "Camera.attempts": attempt == nil ? 0 : 1,
            "Camera.watchdogs": watchdog == nil ? 0 : 1,
            "Camera.upgrades": upgrade == nil ? 0 : 1,
            "Camera.observations": hlsObservations.count,
        ]
    }

    /// The wait before each background WebRTC attempt while a stream plays over HLS: three tries over about three minutes,
    /// so a camera that cannot do WebRTC costs little.
    static let defaultUpgradeDelays: [Duration] = [.seconds(15), .seconds(45), .seconds(120)]

    /// WebRTC then HLS on iOS. macOS (hosted tests) has no player views, so no live modes.
    /// Debug builds honor `FENTON_CAMERA_MODE=webrtc|hls` to pin one mode for tests.
    static var defaultModes: [CameraStreamMode] {
        #if canImport(UIKit)
        #if DEBUG
        if let pinned = ProcessInfo.processInfo.environment["FENTON_CAMERA_MODE"],
           let mode = CameraStreamMode.allCases.first(where: { $0.rawValue.lowercased() == pinned.lowercased() }) {
            return [mode]
        }
        #endif
        #if canImport(WebRTC)
        return [.webRTC, .hls]
        #else
        return [.hls]
        #endif
        #else
        return []
        #endif
    }

    // MARK: - Lifecycle

    /// Starts (or restarts) from the first mode.
    func start(connection: HassConnection) {
        self.connection = connection
        CameraTrace.record("\(camera.rtcStreamId) start (running \(isRunning), \(state.phase))")
        stop()
        state.restart()
        upgradeAttempts = 0
        isRunning = state.phase != .failed
        if !isRunning { onExhausted?() } // No live modes: the snapshot is all there is.
        connectCurrentMode()
    }

    /// Stops every stream. The state keeps its phase, which is only right for a stream that is going away.
    func stop() {
        generation += 1
        attempt?.cancel()
        attempt = nil
        isRunning = false
        tearDownPlayers()
    }

    /// Stops the stream because the app is leaving the foreground, and says so: the phase goes back to
    /// connecting, so views put the snapshot back over the (now empty) player instead of leaving a black frame
    /// that read "Live" until the stream restarted. ``start(connection:)`` follows on return.
    func suspend() {
        let wasLive = state.phase == .live
        stop()
        state.restart()
        if wasLive { lastLiveAt = Date() }
        CameraTrace.record("\(camera.rtcStreamId) suspended")
    }

    /// Stops the stream because no view shows it, keeping its last live frame on screen until it is wanted again
    /// (``CameraStreamPool/pauseAfterHidden``). The frame is converted off the main actor.
    func pause() async {
        let source = liveFrameSource()
        suspend()
        guard let source else { return }
        let image = await source.image()
        // A view may have shown the camera again while the frame converted; then the stream is connecting.
        if !isRunning { pausedFrame = image }
    }

    // MARK: - Controls

    /// Turns the camera's sound on or off (web `toggleCameraStreamMuted`).
    func setMuted(_ muted: Bool) {
        guard muted != isMuted else { return }
        isMuted = muted
        applyMute()
        onMuteChange?()
    }

    /// The current live frame (web `webrtc-screenshot`), or `nil` while nothing is playing. Grabbing it is cheap;
    /// ``CameraFrame/image()`` converts it off the main actor.
    func liveFrameSource() -> CameraFrame? {
        #if canImport(WebRTC) && canImport(UIKit)
        if let frame = webRTCPeer?.frames.latestFrame() { return .webRTC(frame) }
        #endif
        guard let player = hlsPlayer, let output = hlsVideoOutput else { return nil }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        let current = output.hasNewPixelBuffer(forItemTime: time) ? time : player.currentTime()
        return output.copyPixelBuffer(forItemTime: current, itemTimeForDisplay: nil).map(CameraFrame.pixels)
    }

    private func applyMute() {
        hlsPlayer?.isMuted = isMuted
        #if canImport(WebRTC) && canImport(UIKit)
        webRTCPeer?.isMuted = isMuted
        #endif
    }

    /// A player showed its first frame.
    func firstFrame(_ mode: CameraStreamMode) {
        if mode == .webRTC, candidateOpen {
            promoteCandidate()
            return
        }
        guard mode == state.mode, state.phase == .connecting else { return }
        CameraTrace.record("\(camera.rtcStreamId) first frame \(mode)")
        state.firstFrame(mode)
        pausedFrame = nil
        attempt?.cancel()
        attempt = nil
        lastLiveAt = nil
        startWatchdog()
        onLive?()
        scheduleUpgrade()
    }

    // MARK: - Upgrade to WebRTC

    /// While a stream plays over HLS, tries WebRTC again after the next wait, out of sight. Nothing on screen changes
    /// unless the attempt shows a frame (``promoteCandidate()``).
    private func scheduleUpgrade() {
        guard isRunning, state.canUpgrade, state.mode == .hls, state.modes.contains(.webRTC),
              upgradeAttempts < upgradeDelays.count else { return }
        let delay = upgradeDelays[upgradeAttempts]
        upgradeAttempts += 1
        let current = generation
        CameraTrace.record("\(camera.rtcStreamId) upgrade \(upgradeAttempts) to WebRTC in \(delay)")
        upgrade = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard let self, current == self.generation, let connection = self.connection else { return }
                self.candidateOpen = true
                CameraTrace.record("\(self.camera.rtcStreamId) upgrade open webRTC")
                if let opener = self.opener {
                    try await opener(self, .webRTC, connection, current)
                } else {
                    try await self.openWebRTC(connection, generation: current, asCandidate: true)
                }
                try await Task.sleep(for: self.firstFrameTimeout(.webRTC))
                try Task.checkCancellation()
                self.abandonCandidate(generation: current)
            } catch is CancellationError {
            } catch {
                self?.abandonCandidate(generation: current)
            }
        }
    }

    /// The background attempt failed or timed out: drop it and wait for the next one. HLS never stopped playing.
    private func abandonCandidate(generation failed: Int) {
        guard failed == generation, candidateOpen else { return }
        CameraTrace.record("\(camera.rtcStreamId) upgrade to WebRTC failed")
        upgrade?.cancel()
        upgrade = nil
        dropCandidate()
        scheduleUpgrade()
    }

    private func dropCandidate() {
        candidateOpen = false
        #if canImport(WebRTC) && canImport(UIKit)
        candidatePeer?.stop()
        candidatePeer = nil
        #endif
    }

    /// The background WebRTC session decoded a frame: it replaces HLS, and the phase stays live throughout, so the
    /// snapshot never comes back and nothing re-fades.
    private func promoteCandidate() {
        guard state.canUpgrade, state.mode == .hls else { return dropCandidate() }
        CameraTrace.record("\(camera.rtcStreamId) upgraded to WebRTC")
        upgrade?.cancel()
        upgrade = nil
        candidateOpen = false
        #if canImport(WebRTC) && canImport(UIKit)
        let peer = candidatePeer
        candidatePeer = nil
        #endif
        tearDownPlayers() // HLS; the candidate was taken out first.
        #if canImport(WebRTC) && canImport(UIKit)
        webRTCPeer = peer
        #endif
        applyMute()
        state.upgrade(to: .webRTC)
        pausedFrame = nil
        startWatchdog()
        onLive?()
    }

    // MARK: - Frame watchdog

    /// Starts watching the live stream's frame count (web `stream-manager.js` `_checkFrames`). One task per live
    /// stream, one read a second on the main actor: the WebRTC count is kept by the decoder's own callback and the
    /// HLS count comes from the player's clock, so nothing runs per frame.
    private func startWatchdog() {
        watchdog?.cancel()
        let current = generation
        let limit = stallAfter
        let interval = stallCheckInterval
        watchdog = Task { [weak self] in
            var detector = FrameStallDetector(stallAfter: limit)
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self, current == self.generation else { return }
                guard let frames = self.currentFrameCount() else { continue }
                if detector.observe(frames: frames, at: .now) {
                    self.stalled()
                    return
                }
            }
        }
    }

    /// A live stream stopped delivering frames: it goes back to its snapshot (the phase leaves live, so the tile's dot
    /// goes and the snapshot cross-fades back over the player) and the pool restarts it with its retry backoff.
    private func stalled() {
        CameraTrace.record("\(camera.rtcStreamId) frames stopped for \(stallAfter), restarting")
        stop()
        state.restart()
        lastLiveAt = Date()
        onStalled?()
    }

    /// The live stream's frame count, or nil when nothing is playing.
    private func currentFrameCount() -> Int? {
        if let frameCounter { return frameCounter(self) }
        let real = realFrameCount()
        #if DEBUG
        if let frozenCount { return frozenCount }
        if !didFreeze, let real, ProcessInfo.processInfo.environment["FENTON_CAMERA_FREEZE_ONCE"] == camera.rtcStreamId {
            didFreeze = true
            frozenCount = real
            CameraTrace.record("\(camera.rtcStreamId) frames frozen for the watchdog test")
        }
        #endif
        return real
    }

    private func realFrameCount() -> Int? {
        #if canImport(WebRTC) && canImport(UIKit)
        if let peer = webRTCPeer { return peer.frames.frameCount }
        #endif
        guard let player = hlsPlayer else { return nil }
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? Int(seconds * 4) : nil // A live playlist's play position advances while frames do.
    }

    // MARK: - Attempts

    private func connectCurrentMode() {
        guard let mode = state.mode, let connection else { return }
        generation += 1
        let current = generation
        tearDownPlayers()
        attempt = Task { [weak self] in
            do {
                CameraTrace.record("\(self?.camera.rtcStreamId ?? "?") open \(mode)")
                if let self, let opener {
                    try await opener(self, mode, connection, current)
                } else {
                    switch mode {
                    case .hls: try await self?.openHLS(connection, generation: current)
                    case .webRTC: try await self?.openWebRTC(connection, generation: current)
                    }
                }
                CameraTrace.record("\(self?.camera.rtcStreamId ?? "?") opened \(mode), waiting for a frame")
                try await Task.sleep(for: self?.firstFrameTimeout(mode) ?? mode.firstFrameTimeout)
                // A sleep whose timer already fired returns normally even if the first frame cancelled it while
                // the main actor was busy, so a live stream must not be failed by its stale timeout.
                try Task.checkCancellation()
                self?.modeFailed(mode, generation: current)
            } catch is CancellationError {
            } catch {
                self?.modeFailed(mode, generation: current)
            }
        }
    }

    private func modeFailed(_ mode: CameraStreamMode, generation failed: Int) {
        if mode == .webRTC, candidateOpen { return abandonCandidate(generation: failed) }
        guard failed == generation, mode == state.mode else { return }
        CameraTrace.record("\(camera.rtcStreamId) \(mode) failed")
        attempt?.cancel()
        attempt = nil
        state.failed(mode)
        tearDownPlayers()
        if state.phase == .failed {
            isRunning = false
            onExhausted?()
        }
        connectCurrentMode()
    }

    /// Commands sent while the socket is down can be dropped by HAKit without an answer, so the first one waits
    /// for it (a connected socket costs nothing).
    private func waitForSocket(_ connection: HassConnection) async {
        if case .connected = connection.status { return }
        _ = await connection.awaitConnected(timeout: .seconds(10))
    }

    private func openHLS(_ connection: HassConnection, generation current: Int) async throws {
        await waitForSocket(connection)
        guard current == generation else { throw CancellationError() }
        let path = try await connection.cameraStreamPath(entityId: camera.entityId)
        guard current == generation else { throw CancellationError() }
        guard let url = CameraStreamEndpoints.hlsURL(path: path, baseURL: connection.server.baseURL) else {
            throw URLError(.badURL)
        }
        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        hlsVideoOutput = output
        let player = AVPlayer(playerItem: item)
        player.isMuted = isMuted
        player.preventsDisplaySleepDuringVideoPlayback = false
        hlsPlayer = player
        hlsObservations = [
            item.observe(\.status) { @Sendable [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor in self?.modeFailed(.hls, generation: current) }
            },
            player.observe(\.timeControlStatus) { @Sendable [weak self] player, _ in
                guard player.timeControlStatus == .playing else { return }
                Task { @MainActor in self?.firstFrame(.hls) }
            },
        ]
        player.play()
    }

    private func openWebRTC(_ connection: HassConnection, generation current: Int, asCandidate: Bool = false) async throws {
        #if canImport(WebRTC) && canImport(UIKit)
        await waitForSocket(connection)
        guard current == generation else { throw CancellationError() }
        let signed = try await connection.signPath(CameraStreamEndpoints.webRTCSocketPath)
        guard current == generation else { throw CancellationError() }
        guard let url = CameraStreamEndpoints.webRTCSocketURL(
            signedPath: signed,
            streamId: camera.rtcStreamId,
            baseURL: connection.server.baseURL
        ) else { throw URLError(.badURL) }
        let peer = WebRTCCameraPeer(socketURL: url) { [weak self] in
            Task { @MainActor in
                guard current == self?.generation else { return }
                self?.firstFrame(.webRTC)
            }
        } onFailure: { [weak self] in
            Task { @MainActor in self?.modeFailed(.webRTC, generation: current) }
        }
        guard let peer else { throw URLError(.cannotConnectToHost) }
        if asCandidate, !candidateOpen { // Abandoned while signing.
            peer.stop()
            throw CancellationError()
        }
        peer.isMuted = isMuted
        if asCandidate { candidatePeer = peer } else { webRTCPeer = peer }
        peer.start()
        #else
        throw URLError(.unsupportedURL)
        #endif
    }

    private func tearDownPlayers() {
        upgrade?.cancel()
        upgrade = nil
        dropCandidate()
        watchdog?.cancel()
        watchdog = nil
        #if DEBUG
        frozenCount = nil
        #endif
        hlsObservations.forEach { $0.invalidate() }
        hlsObservations = []
        if let player = hlsPlayer {
            // An emptied player releases its item, video output and AVFoundation's observers; dropping it alone left
            // notification observers and timebases behind on every restart (`.agents/patterns/resume-lifecycle.md`).
            player.pause()
            if let output = hlsVideoOutput { player.currentItem?.remove(output) }
            player.replaceCurrentItem(with: nil)
        }
        hlsPlayer = nil
        hlsVideoOutput = nil
        #if canImport(WebRTC) && canImport(UIKit)
        webRTCPeer?.stop()
        webRTCPeer = nil
        #endif
    }
}

/// Opens one mode's stream for a model: it must leave the model's players set up and return, after which the
/// model waits for a first frame. The arguments are the model, the mode, the connection and the model's attempt
/// generation (stale attempts are ignored).
typealias CameraStreamOpener = @MainActor (CameraLiveModel, CameraStreamMode, HassConnection, Int) async throws -> Void

/// A grabbed live frame, converted to an image off the main actor.
enum CameraFrame: @unchecked Sendable {
    /// An HLS frame from `AVPlayerItemVideoOutput`.
    case pixels(CVPixelBuffer)
    #if canImport(WebRTC) && canImport(UIKit)
    /// A decoded WebRTC frame.
    case webRTC(RTCVideoFrame)
    #endif

    /// The frame as an upright image.
    nonisolated func image() async -> CGImage? {
        switch self {
        case let .pixels(buffer):
            let image = CIImage(cvPixelBuffer: buffer)
            return CameraFrameContext.shared.createCGImage(image, from: image.extent)
        #if canImport(WebRTC) && canImport(UIKit)
        case let .webRTC(frame):
            return CameraFrameImage.image(from: frame)
        #endif
        }
    }
}

/// One Core Image context for every frame conversion (contexts are expensive and thread-safe).
enum CameraFrameContext {
    nonisolated(unsafe) static let shared = CIContext(options: [.cacheIntermediates: false])
}
