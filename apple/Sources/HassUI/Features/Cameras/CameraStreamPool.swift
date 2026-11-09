import HassCore
import HassTelemetry
import Observation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The app's camera streams: one ``CameraLiveModel`` per camera, shared by every tile and viewer (web
/// `stream-manager.js` pooling plus `rtcStreamRetention.ts`).
///
/// A tile and the viewer it opens show the same stream, so the viewer is live the moment it opens. Once a
/// camera has been shown its stream keeps running for the session (``CameraStreamRetention``), so moving
/// between Home, Security and the viewer never reconnects. Every stream stops when the app goes to the
/// background and the retained ones restart when it returns; their snapshots cover the gap.
///
/// **Coming back from the background** the websocket may be gone or dead, and Home Assistant's commands for a
/// stream (`auth/sign_path`, `camera/stream`) are dropped by HAKit without an answer when they are caught by a
/// reconnect (owner report 2026-10-16: streams never came back). So the return first makes the connection
/// answer (``HassConnection/ensureLive(timeout:)``), then starts the streams, and any stream that is still
/// wanted but not running, or gave up while the socket was down, restarts when the socket next becomes ready.
/// A healthy stream is never touched. See `.agents/platforms/apple/connection-lifecycle.md`, "Camera streams".
@MainActor
@Observable
final class CameraStreamPool {
    /// The app's pool.
    static let shared = CameraStreamPool()

    @ObservationIgnored private var models: [String: CameraLiveModel] = [:]
    @ObservationIgnored private var retention: CameraStreamRetention
    @ObservationIgnored private weak var connection: HassConnection?
    @ObservationIgnored private let modes: [CameraStreamMode]
    @ObservationIgnored private let opener: CameraStreamOpener?
    @ObservationIgnored private let prepareConnection: @MainActor (HassConnection) async -> Void
    // Read in `deinit`, which is nonisolated; only the main actor writes it.
    @ObservationIgnored nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var census: ResourceCensus.Registration?
    /// The foreground restart while it waits for the connection; nil when none is pending.
    @ObservationIgnored private var resumeTask: Task<Void, Never>?
    /// Waits before each automatic retry of a stream that failed every mode; the stream stays on its snapshot
    /// after the last one (web `stream-manager.js`: 2 s doubling, five attempts).
    @ObservationIgnored private let retryDelays: [Duration]
    @ObservationIgnored private let stallAfter: Duration
    @ObservationIgnored private let stallCheckInterval: Duration
    @ObservationIgnored private let upgradeDelays: [Duration]
    @ObservationIgnored private let frameCounter: (@MainActor (CameraLiveModel) -> Int?)?
    /// How long a retained stream keeps running with no view showing it before it is paused (short enough to stop
    /// decoding behind a page with no camera, long enough that Home to Security, whose tiles share the stream, never does).
    @ObservationIgnored let pauseAfterHidden: Duration
    /// Pending pauses by camera id (a view showing the camera again cancels its pause).
    @ObservationIgnored private var pauseTasks: [String: Task<Void, Never>] = [:]
    /// Pending automatic retries by camera id, and how many each camera has used since it last went live.
    @ObservationIgnored private var retryTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var retryAttempts: [String: Int] = [:]

    /// - Parameters:
    ///   - modes: Modes each stream tries, in order.
    ///   - retainsShownStreams: Keep shown streams running for the session (web parity).
    ///   - observesApp: Stop and restart streams with the app's background and foreground transitions, and
    ///     restart stalled ones when the connection becomes ready again.
    ///   - opener: Replaces how each mode opens its stream (tests).
    ///   - retryDelays: Waits before each automatic retry of a wanted stream that failed every mode; empty turns
    ///     automatic retries off.
    ///   - pauseAfterHidden: How long a retained stream runs with no view showing it before it is paused.
    ///   - stallAfter: How long a live stream's frame count may stay put before the stream is restarted.
    ///   - stallCheckInterval: How often the frame count is read.
    ///   - upgradeDelays: Waits before each background WebRTC attempt on a stream playing over HLS.
    ///   - frameCounter: Replaces how frames are counted (tests).
    ///   - prepareConnection: Runs when the app returns, before streams restart; the default makes the websocket
    ///     answer, reconnecting it if it is dead.
    init(modes: [CameraStreamMode] = CameraLiveModel.defaultModes, retainsShownStreams: Bool = true, observesApp: Bool = true,
         opener: CameraStreamOpener? = nil,
         retryDelays: [Duration] = CameraStreamPool.defaultRetryDelays,
         pauseAfterHidden: Duration = .seconds(4),
         stallAfter: Duration = FrameStallDetector.defaultStallAfter, stallCheckInterval: Duration = .seconds(1),
         upgradeDelays: [Duration] = CameraLiveModel.defaultUpgradeDelays,
         frameCounter: (@MainActor (CameraLiveModel) -> Int?)? = nil,
         prepareConnection: @escaping @MainActor (HassConnection) async -> Void = { _ = await $0.ensureLive() }) {
        self.modes = modes
        self.opener = opener
        self.retryDelays = retryDelays
        self.pauseAfterHidden = pauseAfterHidden
        self.stallAfter = stallAfter
        self.stallCheckInterval = stallCheckInterval
        self.upgradeDelays = upgradeDelays
        self.frameCounter = frameCounter
        self.prepareConnection = prepareConnection
        retention = CameraStreamRetention(retainsShownStreams: retainsShownStreams)
        census = ResourceCensus.shared.register { [weak self] in self?.liveResources ?? [:] }
        guard observesApp else { return }
        let center = NotificationCenter.default
        #if canImport(UIKit)
        observers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enterBackground() }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enterForeground() }
            },
        ]
        #endif
        observers.append(center.addObserver(forName: HassConnection.didBecomeReadyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.connectionBecameReady() }
        })
    }

    /// What the pool holds right now (`ResourceCensus`).
    var liveResources: [String: Int] {
        [
            "CameraPool.observers": observers.count,
            "CameraPool.resumeTask": resumeTask == nil ? 0 : 1,
            "CameraPool.pauseTasks": pauseTasks.count,
            "CameraPool.models": models.count,
            "CameraPool.running": models.values.filter(\.isRunning).count,
        ]
    }

    deinit {
        // Block observers stay registered until removed; dropping the tokens would leave them behind.
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Models

    /// The shared model for a camera, created on first use (not started).
    ///
    /// A memoizing lookup: views call it from `body`, and since the cache is not observed, filling it never
    /// invalidates a view. Views observe the returned model's own state.
    func model(for camera: HomeConfig.Camera) -> CameraLiveModel {
        if let model = models[camera.id] { return model }
        let model = CameraLiveModel(camera: camera, modes: modes, opener: opener, stallAfter: stallAfter,
                                   stallCheckInterval: stallCheckInterval, upgradeDelays: upgradeDelays,
                                   frameCounter: frameCounter)
        model.onExhausted = { [weak self] in self?.exhausted(camera) }
        model.onLive = { [weak self] in self?.retryAttempts[camera.id] = nil }
        model.onStalled = { [weak self] in self?.scheduleRetry(camera) }
        model.onMuteChange = { [weak self] in self?.updateAudio() }
        models[camera.id] = model
        return model
    }

    /// The wait before each automatic retry: 2 s doubling, five attempts (web `stream-manager.js`).
    static let defaultRetryDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32)]

    /// Whether the camera's stream should be running now (tests and diagnostics).
    func shouldRun(_ camera: HomeConfig.Camera) -> Bool { retention.shouldRun(camera.id) }

    // MARK: - Views

    /// A view showing the camera appeared: starts its stream unless it is already connecting or live.
    ///
    /// While the app is coming back from the background the start waits for the connection check with the rest
    /// (``enterForeground()``).
    @discardableResult
    func appear(_ camera: HomeConfig.Camera, connection: HassConnection) -> CameraLiveModel {
        self.connection = connection
        let model = model(for: camera)
        retryAttempts[camera.id] = nil
        pauseTasks[camera.id]?.cancel()
        pauseTasks[camera.id] = nil
        if retention.appear(camera.id, isRunning: model.isRunning) == .start, resumeTask == nil {
            model.start(connection: connection)
        }
        return model
    }

    /// A view showing the camera disappeared: stops its stream only if nothing retains it.
    func disappear(_ camera: HomeConfig.Camera) {
        CameraTrace.record("\(camera.rtcStreamId) hidden, \(max(0, retention.viewers[camera.id, default: 0] - 1)) views left")
        if retention.disappear(camera.id) == .stop {
            models[camera.id]?.stop()
        } else if retention.retainsShownStreams, retention.viewers[camera.id] == nil {
            schedulePause(camera)
        }
    }

    /// Pauses a retained stream that no view has shown for ``pauseAfterHidden``: the session stops retaining it, the stream
    /// stops, and its last live frame stays up. A view showing it again (``appear(_:connection:)``) cancels this or, once
    /// paused, restarts it.
    private func schedulePause(_ camera: HomeConfig.Camera) {
        pauseTasks[camera.id]?.cancel()
        let delay = pauseAfterHidden
        pauseTasks[camera.id] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            pauseTasks[camera.id] = nil
            guard retention.viewers[camera.id] == nil, retention.release(camera.id) == .stop,
                  let model = models[camera.id], model.isRunning else { return }
            retryTasks[camera.id]?.cancel()
            retryTasks[camera.id] = nil
            CameraTrace.record("\(camera.rtcStreamId) paused, no view shows it")
            await model.pause()
        }
    }

    /// Restarts a camera whose modes all failed (the viewer's retry).
    func retry(_ camera: HomeConfig.Camera, connection: HassConnection) {
        self.connection = connection
        retryAttempts[camera.id] = nil
        retention.retry(camera.id)
        model(for: camera).start(connection: connection)
    }

    // MARK: - App lifecycle

    func enterBackground() {
        CameraTrace.record("pool background, \(models.values.filter(\.isRunning).count) running")
        resumeTask?.cancel()
        resumeTask = nil
        pauseTasks.values.forEach { $0.cancel() }
        pauseTasks = [:]
        retryTasks.values.forEach { $0.cancel() }
        retryTasks = [:]
        for id in retention.enterBackground() {
            models[id]?.suspend()
        }
        // Sound never keeps playing behind the app; cameras reopen muted like the web's pooled cards.
        models.values.forEach { $0.setMuted(true) }
    }

    /// The app is returning. Streams restart once the connection answers; the snapshots stay up meanwhile.
    func enterForeground() {
        let ids = retention.enterForeground()
        retryAttempts = [:]
        guard let connection, !ids.isEmpty else { return }
        CameraTrace.record("pool foreground, \(ids.count) wanted, connection \(connection.status)")
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            if let self { await prepareConnection(connection) }
            guard !Task.isCancelled, let self else { return }
            resumeTask = nil
            CameraTrace.record("pool resuming, connection \(connection.status)")
            startStalled(connection)
        }
    }

    /// The websocket became ready (first connect, or after a drop). Streams that are wanted but not running, or
    /// that gave up while the socket was down, start again; connecting and live ones are left alone.
    func connectionBecameReady() {
        guard resumeTask == nil, let connection else { return }
        retryAttempts = [:]
        startStalled(connection)
    }

    /// A stream failed every mode. It drops its retention, and while a view still wants it (and the app is in the
    /// foreground) it is tried again after a growing wait, so a stream that failed on a slow or changing network
    /// (the first seconds after the app returns) comes back by itself instead of staying on the snapshot until
    /// the next launch. Web parity: `stream-manager.js` reconnects with backoff, `RtcPilotCamera.tsx` retries.
    private func exhausted(_ camera: HomeConfig.Camera) {
        retention.failed(camera.id)
        guard !modes.isEmpty else { return }
        scheduleRetry(camera)
    }

    /// Restarts a camera after a growing wait while a view (or the session's retention) wants it: used for streams that
    /// failed every mode and for live streams whose frames stopped (``CameraLiveModel/onStalled``).
    private func scheduleRetry(_ camera: HomeConfig.Camera) {
        guard retention.wanted.contains(camera.id) else { return }
        let attempt = retryAttempts[camera.id, default: 0]
        guard attempt < retryDelays.count else {
            CameraTrace.record("\(camera.rtcStreamId) gave up after \(attempt) retries")
            return
        }
        retryAttempts[camera.id] = attempt + 1
        let delay = retryDelays[attempt]
        CameraTrace.record("\(camera.rtcStreamId) retry \(attempt + 1) in \(delay)")
        retryTasks[camera.id]?.cancel()
        retryTasks[camera.id] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.retryFailed(camera)
        }
    }

    private func retryFailed(_ camera: HomeConfig.Camera) {
        retryTasks[camera.id] = nil
        guard resumeTask == nil, let connection, let model = models[camera.id],
              !model.isRunning, retention.shouldRun(camera.id) else { return }
        CameraTrace.record("\(camera.rtcStreamId) retrying")
        retention.retry(camera.id)
        model.start(connection: connection)
    }

    /// Starts every wanted stream that is not running or has failed.
    private func startStalled(_ connection: HassConnection) {
        for id in retention.wanted {
            guard let model = models[id], !model.isRunning || model.state.phase == .failed else { continue }
            CameraTrace.record("\(model.camera.rtcStreamId) restarting (running \(model.isRunning), \(model.state.phase))")
            model.start(connection: connection)
        }
    }

    // MARK: - Audio

    private func updateAudio() {
        #if canImport(UIKit)
        CameraAudioSession.shared.setAudible(models.values.contains { !$0.isMuted })
        #endif
    }
}
