import AVFoundation
import CoreImage
import HassCore
import Network
import UIKit
import XCTest
@preconcurrency import WebRTC
@testable import HassUI

// MARK: - Layer census

/// The debug layer census counts what costs the render server; a window with known layers must read back as those counts.
@MainActor
final class LayerCensusHostedTests: XCTestCase {
    /// A window on the app's scene: the census only walks windows that belong to a scene.
    private func sceneWindow(_ root: UIViewController) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.view.layoutIfNeeded()
        return window
    }

    private func counts(_ line: String, _ key: String) -> Int {
        line.split(separator: " ").compactMap { pair -> Int? in
            let parts = pair.split(separator: "=")
            return parts.count == 2 && parts[0] == key ? Int(parts[1]) : nil
        }.first ?? -1
    }

    func testCensusCountsMasksGradientsShapesShadowsAndEffects() throws {
        let root = UIViewController()
        let window = try sceneWindow(root)
        defer { window.isHidden = true }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        host.backgroundColor = UIColor.black.withAlphaComponent(0.5) // Big and not opaque.
        root.view.addSubview(host)

        let gradient = CAGradientLayer()
        gradient.frame = CGRect(x: 0, y: 0, width: 50, height: 50)
        gradient.colors = [UIColor.red.cgColor, UIColor.blue.cgColor]
        host.layer.addSublayer(gradient)
        let shape = CAShapeLayer()
        shape.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 20, height: 20)).cgPath
        shape.borderWidth = 1
        host.layer.addSublayer(shape)
        let masked = CALayer()
        masked.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        masked.mask = CALayer()
        masked.masksToBounds = true
        masked.cornerRadius = 8
        host.layer.addSublayer(masked)
        let shadowed = CALayer()
        shadowed.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        shadowed.shadowOpacity = 1
        shadowed.shadowRadius = 4
        host.layer.addSublayer(shadowed)
        let pathShadow = CALayer()
        pathShadow.shadowOpacity = 1
        pathShadow.shadowRadius = 4
        pathShadow.shadowPath = CGPath(rect: .init(x: 0, y: 0, width: 5, height: 5), transform: nil)
        host.layer.addSublayer(pathShadow)
        let fading = CALayer()
        fading.opacity = 0.5
        fading.sublayers = nil
        fading.addSublayer(CALayer())
        host.layer.addSublayer(fading)
        let rasterized = CATextLayer()
        rasterized.shouldRasterize = true
        rasterized.string = "x"
        host.layer.addSublayer(rasterized)
        let animated = CALayer()
        animated.add(CABasicAnimation(keyPath: "opacity"), forKey: "fade")
        host.layer.addSublayer(animated)
        host.layer.addSublayer(CAReplicatorLayer())
        host.layer.addSublayer(CAEmitterLayer())
        let hidden = CALayer()
        hidden.isHidden = true
        host.layer.addSublayer(hidden)
        host.addSubview(UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial)))
        window.layoutIfNeeded()

        let report = LayerCensus.run()
        let lines = report.split(separator: "\n").map(String.init)
        let windowLine = lines.first { $0.hasPrefix("window:") } ?? ""
        XCTAssertTrue(lines.contains { $0.hasPrefix("scroll:") } && lines.contains { $0.hasPrefix("classes:") }, report)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "gradients"), 1)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "shapes"), 1)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "masks"), 1)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "clipRounded"), 1)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "shadowNoPath"), 1)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "shadowPath"), 1)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "groupOpacity"), 1)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "rasterized"), 1)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "animations"), 1)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "replicators"), 1)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "emitters"), 1)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "hidden"), 1)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "effects"), 1)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "bigNonOpaque"), 1)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "textLayers"), 1)
        XCTAssertGreaterThanOrEqual(counts(windowLine, "borders"), 1)
        XCTAssertGreaterThan(counts(windowLine, "layers"), 10)
    }

    func testDetailModeListsTheNotableLayers() throws {
        setenv("FENTON_LAYER_CENSUS_DETAIL", "1", 1)
        defer { unsetenv("FENTON_LAYER_CENSUS_DETAIL") }
        let root = UIViewController()
        let window = try sceneWindow(root)
        defer { window.isHidden = true }
        let gradient = CAGradientLayer()
        gradient.frame = CGRect(x: 0, y: 0, width: 20, height: 20)
        root.view.layer.addSublayer(gradient)
        let shape = CAShapeLayer()
        root.view.layer.addSublayer(shape)
        let clipped = CALayer()
        clipped.masksToBounds = true
        clipped.cornerRadius = 4
        clipped.mask = CALayer()
        clipped.shadowOpacity = 1
        clipped.shadowRadius = 2
        clipped.opacity = 0.5
        clipped.addSublayer(CALayer())
        clipped.shouldRasterize = true
        clipped.add(CABasicAnimation(keyPath: "position"), forKey: "move")
        root.view.layer.addSublayer(clipped)
        let plainClip = CALayer()
        plainClip.masksToBounds = true
        plainClip.shadowOpacity = 1
        plainClip.shadowRadius = 2
        plainClip.shadowPath = CGPath(rect: .init(x: 0, y: 0, width: 1, height: 1), transform: nil)
        root.view.layer.addSublayer(plainClip)
        root.view.addSubview(UIVisualEffectView(effect: UIBlurEffect(style: .light)))
        let detail = LayerCensus.run().split(separator: "\n").filter { $0.hasPrefix("  d") }.joined(separator: "\n")
        for tag in ["gradient", "shape", "mask", "clipRounded", "clip", "shadowNoPath", "shadow", "groupOpacity", "rasterized", "anim:move", "filter"] {
            XCTAssertTrue(detail.contains(tag), "detail lists \(tag)")
        }
    }
}

// MARK: - Device status

/// The sensor source reads the phone; on a simulator it has no battery, so the facts a person can rely on are the version, the
/// permission it was handed and that a missing fix means no address.
@MainActor
final class SystemDeviceStatusSourceHostedTests: XCTestCase {
    func testAppVersionReadsTheBundleAsVersionAndBuild() {
        let info = Bundle.main.infoDictionary
        let expected = "\(info?["CFBundleShortVersionString"] as? String ?? "0") (\(info?["CFBundleVersion"] as? String ?? "0"))"
        XCTAssertEqual(SystemDeviceStatusSource.appVersion, expected)
    }

    func testAStatusWithoutAFixHasNoAddressAndEchoesThePermission() async {
        let source = SystemDeviceStatusSource()
        let denied = LocationPermission(authorization: .denied)
        let status = await source.status(for: SensorContext(trigger: .launch, permission: denied))
        XCTAssertNil(status.place)
        XCTAssertEqual(status.locationPermission, denied)
        XCTAssertEqual(status.appVersion, SystemDeviceStatusSource.appVersion)
        XCTAssertEqual(status.network?.canReadWiFi, false, "Wi-Fi names need a location permission")
        XCTAssertNotNil(status.audioOutputs)
    }

    func testAnAuthorizedPermissionCanReadWiFiAndAFixIsGeocodedOrLeftOut() async throws {
        let source = SystemDeviceStatusSource()
        let fix = LocationFix(latitude: 37.3349, longitude: -122.0090, horizontalAccuracy: 5)
        let permission = LocationPermission(authorization: .whenInUse)
        let status = await source.status(for: SensorContext(trigger: .manual, fix: fix, permission: permission))
        XCTAssertEqual(status.network?.canReadWiFi, true)
        if let place = status.place {
            XCTAssertEqual(place.coordinate?.count, 2)
            XCTAssertFalse(place.timeZone?.isEmpty ?? true)
        }
    }
}

// MARK: - Camera audio

/// A delegate WebRTC would hand the playout device.
private final class StubAudioDelegate: NSObject, RTCAudioDeviceDelegate, @unchecked Sendable {
    var deliverRecordedData: RTCAudioDeviceDeliverRecordedDataBlock { { _, _, _, _, _, _, _ in noErr } }
    var preferredInputSampleRate: Double { 48_000 }
    var preferredInputIOBufferDuration: TimeInterval { 0.01 }
    var preferredOutputSampleRate: Double { 48_000 }
    var preferredOutputIOBufferDuration: TimeInterval { 0.01 }
    var getPlayoutData: RTCAudioDeviceGetPlayoutDataBlock { { _, _, _, _, _ in noErr } }
    func notifyAudioInputParametersChange() {}
    func notifyAudioOutputParametersChange() {}
    func notifyAudioInputInterrupted() {}
    func notifyAudioOutputInterrupted() {}
    func dispatchAsync(_ block: @escaping () -> Void) { block() }
    func dispatchSync(_ block: @escaping () -> Void) { block() }
}

@MainActor
final class CameraAudioHostedTests: XCTestCase {
    func testSoundIsOffUntilACameraIsUnmutedAndTurnsOffAgain() {
        let session = CameraAudioSession.shared
        session.setAudible(false)
        XCTAssertFalse(session.isAudible)
        session.setAudible(true)
        XCTAssertTrue(session.isAudible)
        session.setAudible(true) // No change: nothing happens.
        XCTAssertTrue(session.isAudible)
        session.setAudible(false)
        XCTAssertFalse(session.isAudible)
    }

    func testThePlayoutDeviceIsReceiveOnlyAndNeverRecords() {
        let device = CameraPlayoutDevice.shared
        XCTAssertEqual(device.deviceOutputSampleRate, 48_000)
        XCTAssertEqual(device.deviceInputSampleRate, 48_000)
        XCTAssertEqual(device.outputNumberOfChannels, 1)
        XCTAssertEqual(device.inputNumberOfChannels, 1)
        XCTAssertEqual(device.outputIOBufferDuration, 0.01)
        XCTAssertEqual(device.inputIOBufferDuration, 0.01)
        XCTAssertEqual(device.outputLatency, 0)
        XCTAssertEqual(device.inputLatency, 0)
        XCTAssertFalse(device.isRecordingInitialized)
        XCTAssertFalse(device.initializeRecording())
        XCTAssertFalse(device.isRecording)
        XCTAssertFalse(device.startRecording(), "The microphone is never opened")
        XCTAssertTrue(device.stopRecording())
    }

    func testPlayoutStartsAndStopsWithWebRTCAndOnlyRunsWhileAudible() {
        let device = CameraPlayoutDevice.shared
        let delegate = StubAudioDelegate()
        XCTAssertTrue(device.initialize(with: delegate))
        XCTAssertTrue(device.isInitialized && device.isPlayoutInitialized)
        XCTAssertTrue(device.initializePlayout())
        XCTAssertFalse(device.isPlaying)
        device.setAudible(true)
        XCTAssertTrue(device.startPlayout())
        XCTAssertTrue(device.isPlaying)
        device.setAudible(false)
        XCTAssertTrue(device.stopPlayout())
        XCTAssertFalse(device.isPlaying)
        // A route change or interruption while sound is wanted restarts the engine without a crash.
        device.setAudible(true)
        _ = device.startPlayout()
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: nil)
        NotificationCenter.default.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
                                        userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        HostedPage.wait(0.3)
        device.setAudible(false)
        XCTAssertTrue(device.terminateDevice())
        XCTAssertFalse(device.isInitialized)
        XCTAssertFalse(device.isPlaying)
    }
}

// MARK: - WebRTC camera peer

/// A throwaway go2rtc: a local websocket that records what the app sends and answers as a receive-only camera would.
private final class FakeSignalling: @unchecked Sendable {
    enum Mode { case answer, error }
    let listener: NWListener
    private let queue = DispatchQueue(label: "fake.signalling")
    private let lock = NSLock()
    private var received: [String] = []
    private let mode: Mode
    private var answerer: RTCPeerConnection?
    private let factory = RTCPeerConnectionFactory()
    private var connections: [NWConnection] = []

    init(mode: Mode) throws {
        self.mode = mode
        let parameters = NWParameters.tcp
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    }

    var messages: [String] { lock.withLock { received } }

    func start() async -> URL {
        await withCheckedContinuation { continuation in
            let once = NSLock()
            nonisolated(unsafe) var resumed = false
            listener.stateUpdateHandler = { [listener] state in
                guard case .ready = state else { return }
                once.lock(); defer { once.unlock() }
                guard !resumed, let port = listener.port else { return }
                resumed = true
                continuation.resume(returning: URL(string: "ws://127.0.0.1:\(port.rawValue)/api/webrtc/ws")!)
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        connections.forEach { $0.cancel() }
        answerer?.close()
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        read(connection)
    }

    private func read(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self, error == nil else { return }
            if let data, let text = String(data: data, encoding: .utf8), !text.isEmpty {
                self.lock.withLock { self.received.append(text) }
                self.handle(text, on: connection)
            }
            self.read(connection)
        }
    }

    private func handle(_ text: String, on connection: NWConnection) {
        guard case let .offer(sdp)? = WebRTCSignal(text: text) else { return }
        switch mode {
        case .error:
            send(.error("stream not found"), on: connection)
        case .answer:
            // A candidate before the answer must be queued by the app, not dropped.
            send(.candidate("candidate:1 1 udp 2130706431 127.0.0.1 9 typ host"), on: connection)
            send(.candidate(""), on: connection)
            let configuration = RTCConfiguration()
            configuration.sdpSemantics = .unifiedPlan
            guard let peer = factory.peerConnection(with: configuration, constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: nil) else { return }
            answerer = peer
            peer.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp)) { [weak self] error in
                guard error == nil else { return }
                peer.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { answer, _ in
                    guard let answer else { return }
                    peer.setLocalDescription(answer) { _ in self?.send(.answer(answer.sdp), on: connection) }
                }
            }
        }
    }

    private func send(_ signal: WebRTCSignal, on connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(content: Data(signal.encoded().utf8), contentContext: context, isComplete: true, completion: .idempotent)
    }
}

/// Counts a peer's reports from any thread.
private final class PeerReports: @unchecked Sendable {
    private let lock = NSLock()
    private var firstFrames = 0, failures = 0
    func frame() { lock.withLock { firstFrames += 1 } }
    func failed() { lock.withLock { failures += 1 } }
    var snapshot: (frames: Int, failures: Int) { lock.withLock { (firstFrames, failures) } }
}

@MainActor
final class WebRTCCameraPeerHostedTests: XCTestCase {
    private func waitUntil(_ timeout: TimeInterval = 8, _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end { try? await Task.sleep(for: .milliseconds(50)) }
    }

    func testANewPeerIsReceiveOnlyWithMutedAudio() async throws {
        let reports = PeerReports()
        let peer = try XCTUnwrap(WebRTCCameraPeer(socketURL: URL(string: "ws://127.0.0.1:1/x")!, onFirstFrame: reports.frame, onFailure: reports.failed))
        XCTAssertNotNil(peer.videoTrack)
        XCTAssertNotNil(peer.audioTrack)
        XCTAssertTrue(peer.isMuted, "Cameras open muted")
        peer.isMuted = false
        XCTAssertEqual(peer.audioTrack?.isEnabled, true)
        XCTAssertFalse(peer.isMuted)
        peer.isMuted = true
        XCTAssertEqual(peer.audioTrack?.isEnabled, false)
        peer.stop()
        peer.stop() // Closing twice is harmless.
        XCTAssertEqual(reports.snapshot.failures, 0, "Stopping is not a failure")
    }

    func testAnUnreachableSignallingServerFailsOnceAndStopsReportingAfterThat() async throws {
        let reports = PeerReports()
        let peer = try XCTUnwrap(WebRTCCameraPeer(socketURL: URL(string: "ws://127.0.0.1:1/api/webrtc/ws")!, onFirstFrame: reports.frame, onFailure: reports.failed))
        peer.start()
        await waitUntil { reports.snapshot.failures > 0 }
        XCTAssertEqual(reports.snapshot.failures, 1)
        peer.stop()
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(reports.snapshot.failures, 1, "A failed peer reports once")
    }

    func testTheOfferAsksForReceiveOnlyVideoAndAudioAndTheAnswerIsAccepted() async throws {
        let server = try FakeSignalling(mode: .answer)
        let url = await server.start()
        defer { server.stop() }
        let reports = PeerReports()
        let peer = try XCTUnwrap(WebRTCCameraPeer(socketURL: url, onFirstFrame: reports.frame, onFailure: reports.failed))
        peer.start()
        await waitUntil { server.messages.contains { text in if case .offer? = WebRTCSignal(text: text) { true } else { false } } }
        let offer = try XCTUnwrap(server.messages.compactMap { text -> String? in
            if case let .offer(sdp)? = WebRTCSignal(text: text) { sdp } else { nil }
        }.first)
        XCTAssertTrue(offer.contains("m=video") && offer.contains("m=audio"))
        XCTAssertTrue(offer.contains("a=recvonly"), "The app only receives")
        XCTAssertFalse(offer.contains("a=sendrecv"))
        try? await Task.sleep(for: .milliseconds(1500)) // The answer and the queued candidate arrive.
        XCTAssertEqual(reports.snapshot.failures, 0, "A good answer is not a failure")
        peer.stop()
    }

    func testAServerErrorFailsThePeer() async throws {
        let server = try FakeSignalling(mode: .error)
        let url = await server.start()
        defer { server.stop() }
        let reports = PeerReports()
        let peer = try XCTUnwrap(WebRTCCameraPeer(socketURL: url, onFirstFrame: reports.frame, onFailure: reports.failed))
        peer.start()
        await waitUntil { reports.snapshot.failures > 0 }
        XCTAssertEqual(reports.snapshot.failures, 1)
    }

    func testThePeerReportsFailureWhenWebRTCSaysItFailedOrClosed() async throws {
        let reports = PeerReports()
        let peer = try XCTUnwrap(WebRTCCameraPeer(socketURL: URL(string: "ws://127.0.0.1:1/x")!, onFirstFrame: reports.frame, onFailure: reports.failed))
        let rtc = RTCPeerConnectionFactory()
        let other = try XCTUnwrap(rtc.peerConnection(with: RTCConfiguration(), constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: nil))
        peer.peerConnection(other, didChange: RTCPeerConnectionState.connected)
        peer.peerConnection(other, didChange: RTCIceConnectionState.connected)
        XCTAssertEqual(reports.snapshot.failures, 0)
        // The delegate callbacks that carry nothing must be harmless.
        peer.peerConnection(other, didChange: RTCSignalingState.stable)
        peer.peerConnectionShouldNegotiate(other)
        peer.peerConnection(other, didChange: RTCIceGatheringState.complete)
        peer.peerConnection(other, didRemove: [])
        peer.peerConnection(other, didGenerate: RTCIceCandidate(sdp: "candidate:1 1 udp 1 127.0.0.1 9 typ host", sdpMLineIndex: 0, sdpMid: "0"))
        peer.peerConnection(other, didChange: RTCIceConnectionState.failed)
        XCTAssertEqual(reports.snapshot.failures, 1)
        peer.peerConnection(other, didChange: RTCPeerConnectionState.closed)
        XCTAssertEqual(reports.snapshot.failures, 1)
        peer.peerConnection(other, didGenerate: RTCIceCandidate(sdp: "candidate:2", sdpMLineIndex: 0, sdpMid: "0")) // Finished: ignored.
        peer.peerConnection(other, didChange: RTCPeerConnectionState.failed)
        other.close()
    }

    // MARK: Frames

    private func pixelFrame(rotation: RTCVideoRotation = ._0) throws -> RTCVideoFrame {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 8, 6, kCVPixelFormatType_32BGRA, [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary, &buffer)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(CVPixelBufferGetBaseAddress(pixels), 0x80, CVPixelBufferGetBytesPerRow(pixels) * 6)
        CVPixelBufferUnlockBaseAddress(pixels, [])
        return RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixels), rotation: rotation, timeStampNs: 0)
    }

    func testTheFrameMonitorReportsTheFirstFrameOnceAndKeepsTheLatest() throws {
        let reports = PeerReports()
        let monitor = WebRTCFrameMonitor(onFirstFrame: reports.frame)
        XCTAssertNil(monitor.latestFrame())
        XCTAssertEqual(monitor.frameCount, 0)
        monitor.renderFrame(nil)
        monitor.setSize(CGSize(width: 8, height: 6))
        XCTAssertEqual(monitor.frameCount, 0, "No frame, no count")
        monitor.renderFrame(try pixelFrame())
        monitor.renderFrame(try pixelFrame())
        XCTAssertEqual(monitor.frameCount, 2)
        XCTAssertEqual(reports.snapshot.frames, 1, "The first frame is reported once")
        XCTAssertNotNil(monitor.latestFrame())
    }

    func testFramesBecomeUprightImagesWhateverTheirRotationOrBuffer() throws {
        let straight = try XCTUnwrap(CameraFrameImage.image(from: try pixelFrame()))
        XCTAssertEqual(straight.width, 8)
        XCTAssertEqual(straight.height, 6)
        let quarter = try XCTUnwrap(CameraFrameImage.image(from: try pixelFrame(rotation: ._90)))
        XCTAssertEqual(quarter.width, 6, "A quarter turn swaps the sides")
        XCTAssertEqual(try XCTUnwrap(CameraFrameImage.image(from: try pixelFrame(rotation: ._270))).width, 6)
        let half = try XCTUnwrap(CameraFrameImage.image(from: try pixelFrame(rotation: ._180)))
        XCTAssertEqual(half.width, 8)

        // Software-decoded video arrives as I420 planes.
        let i420 = RTCI420Buffer(width: 8, height: 6)
        memset(UnsafeMutablePointer(mutating: i420.dataY), 0x80, Int(i420.strideY) * 6)
        memset(UnsafeMutablePointer(mutating: i420.dataU), 0x80, Int(i420.strideU) * Int(i420.chromaHeight))
        memset(UnsafeMutablePointer(mutating: i420.dataV), 0x80, Int(i420.strideV) * Int(i420.chromaHeight))
        let soft = try XCTUnwrap(CameraFrameImage.image(from: RTCVideoFrame(buffer: i420, rotation: ._0, timeStampNs: 0)))
        XCTAssertEqual(soft.width, 8)
        XCTAssertEqual(soft.height, 6)
    }
}

// MARK: - Scan camera

/// The still photo of the printed date is shrunk before it goes to EverShelf; a small one and a non-image pass through.
@MainActor
final class ScanCameraHostedTests: XCTestCase {
    private func jpeg(_ side: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side / 2), format: format).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side / 2))
        }
    }

    func testABigPhotoIsScaledDownToTheLongestSideLimit() throws {
        let big = jpeg(3200)
        let small = CaptureSessionBox.downscaled(big)
        let image = try XCTUnwrap(UIImage(data: small))
        XCTAssertEqual(max(image.size.width, image.size.height), 1600, accuracy: 1)
        XCTAssertLessThan(small.count, big.count)
        XCTAssertEqual(image.size.width / image.size.height, 2, accuracy: 0.01, "The shape is kept")
    }

    func testASmallPhotoAndNonImageDataAreLeftAlone() {
        let small = jpeg(800)
        XCTAssertEqual(CaptureSessionBox.downscaled(small), small)
        let text = Data("not an image".utf8)
        XCTAssertEqual(CaptureSessionBox.downscaled(text), text)
        XCTAssertEqual(CaptureSessionBox.downscaled(jpeg(2000), maxSide: 1000).count < jpeg(2000).count, true)
    }

    func testThePreviewViewIsBackedByAVideoPreviewLayer() {
        let box = CaptureSessionBox()
        let view = CameraPreview.PreviewView()
        view.previewLayer.session = box.session
        XCTAssertTrue(view.layer is AVCaptureVideoPreviewLayer)
        XCTAssertTrue(view.previewLayer.session === box.session)
    }
}
