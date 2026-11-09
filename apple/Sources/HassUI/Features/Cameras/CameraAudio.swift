#if canImport(UIKit)
import AVFoundation
import Foundation
#if canImport(WebRTC)
@preconcurrency import WebRTC
#endif

// MARK: - Session

/// The audio session for camera sound (web Audio / Muted pill).
///
/// Cameras start muted. The session is only activated (category `.playback`, so sound plays with the Ring/Silent
/// switch on, HIG: Playing audio) while a camera is unmuted, so opening a camera never interrupts other audio;
/// muting the last camera deactivates it and lets the interrupted app resume.
@MainActor
final class CameraAudioSession {
    static let shared = CameraAudioSession()

    private(set) var isAudible = false

    /// Turns camera sound on or off for the whole app.
    func setAudible(_ audible: Bool) {
        guard audible != isAudible else { return }
        isAudible = audible
        let session = AVAudioSession.sharedInstance()
        if audible {
            try? session.setCategory(.playback, mode: .moviePlayback)
            try? session.setActive(true)
            #if canImport(WebRTC)
            CameraPlayoutDevice.shared.setAudible(true)
            #endif
        } else {
            // Stop the engine first: deactivating with I/O running fails ("busy"), which would leave the session
            // active and the interrupted app silent.
            #if canImport(WebRTC)
            CameraPlayoutDevice.shared.setAudible(false)
            #endif
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

#if canImport(WebRTC)
// MARK: - WebRTC playout

/// A playout-only WebRTC audio device: pulls decoded camera audio from WebRTC into an `AVAudioEngine`.
///
/// WebRTC's built-in audio device opens a voice-processing unit with the microphone input enabled, which would ask
/// for microphone access just to hear a camera. This device never records. It runs its engine only while a
/// camera is unmuted (``setAudible(_:)``); WebRTC mixes every enabled remote track, and a muted camera's track is
/// disabled, so only unmuted cameras are heard.
final class CameraPlayoutDevice: NSObject, RTCAudioDevice, @unchecked Sendable {
    static let shared = CameraPlayoutDevice()

    /// WebRTC delivers 48 kHz mono 16-bit PCM; the engine's mixer converts it to the hardware format.
    private static let sampleRate: Double = 48_000
    /// Largest render quantum we expect from the engine.
    private static let maxFrames = 8_192

    private let lock = NSLock()
    /// Serializes engine starts and stops, which come from the main thread and WebRTC's worker thread. The
    /// render block never takes it, so holding it across `start()` is safe.
    private let transition = NSLock()
    private var observers: [NSObjectProtocol] = []
    /// Delivers audio notifications off the posting thread: an engine posts while starting, inside `transition`.
    private let notifications: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var delegate: (any RTCAudioDeviceDelegate)?
    private var engine: AVAudioEngine?
    private var playoutRequested = false
    private var audible = false
    private var initialized = false
    /// Scratch buffer for WebRTC's Int16 samples; allocated once so the render thread never allocates.
    private let scratch = UnsafeMutablePointer<Int16>.allocate(capacity: CameraPlayoutDevice.maxFrames)

    override private init() {
        super.init()
        // The engine stops on an interruption, a route change or a media-services reset; start a fresh one.
        let center = NotificationCenter.default
        let restart: @Sendable (Notification) -> Void = { [weak self] _ in self?.restartEngine() }
        observers = [
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: notifications, using: restart),
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: notifications, using: restart),
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: notifications) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if raw == AVAudioSession.InterruptionType.ended.rawValue { self?.restartEngine() }
            },
        ]
    }

    /// Drops a stopped engine and starts again if sound is still wanted.
    private func restartEngine() {
        let dropped = transition.withLock { () -> Bool in
            let stale = lock.withLock { () -> AVAudioEngine? in
                guard let engine, !engine.isRunning else { return nil }
                self.engine = nil
                return engine
            }
            stale?.stop()
            return stale != nil
        }
        guard dropped else { return }
        if lock.withLock({ audible }) { try? AVAudioSession.sharedInstance().setActive(true) }
        updateEngine()
    }

    /// Starts or stops sound (``CameraAudioSession`` calls this on the main thread).
    func setAudible(_ audible: Bool) {
        lock.withLock { self.audible = audible }
        updateEngine()
    }

    // MARK: Engine

    private func updateEngine() {
        transition.lock()
        defer { transition.unlock() }
        let (shouldRun, pull) = lock.withLock { (audible && playoutRequested, delegate?.getPlayoutData) }
        if shouldRun, let pull {
            guard lock.withLock({ engine == nil }) else { return }
            let engine = makeEngine(pull: pull)
            do {
                try engine.start()
                lock.withLock { self.engine = engine }
            } catch {
                engine.stop()
            }
        } else {
            let running = lock.withLock { () -> AVAudioEngine? in
                defer { engine = nil }
                return engine
            }
            running?.stop()
        }
    }

    private func makeEngine(pull: @escaping RTCAudioDeviceGetPlayoutDataBlock) -> AVAudioEngine {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
        let scratch = scratch
        let maxFrames = Self.maxFrames
        let source = AVAudioSourceNode(format: format) { isSilence, timestamp, frameCount, output -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(output)
            let frames = Int(min(Int(frameCount), maxFrames))
            var flags = AudioUnitRenderActionFlags()
            var pcm = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 2), mData: scratch)
            )
            let status = pull(&flags, timestamp, 0, UInt32(frames), &pcm)
            guard status == noErr, let samples = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else {
                isSilence.pointee = true
                for buffer in buffers { memset(buffer.mData, 0, Int(buffer.mDataByteSize)) }
                return noErr
            }
            for index in 0..<frames { samples[index] = Float(scratch[index]) / 32_768 }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        return engine
    }

    // MARK: RTCAudioDevice

    var deviceInputSampleRate: Double { Self.sampleRate }
    var inputIOBufferDuration: TimeInterval { 0.01 }
    var inputNumberOfChannels: Int { 1 }
    var inputLatency: TimeInterval { 0 }
    var deviceOutputSampleRate: Double { Self.sampleRate }
    var outputIOBufferDuration: TimeInterval { 0.01 }
    var outputNumberOfChannels: Int { 1 }
    var outputLatency: TimeInterval { 0 }
    var isInitialized: Bool { lock.withLock { initialized } }

    func initialize(with delegate: any RTCAudioDeviceDelegate) -> Bool {
        lock.withLock {
            self.delegate = delegate
            initialized = true
        }
        return true
    }

    func terminateDevice() -> Bool {
        lock.withLock {
            playoutRequested = false
            initialized = false
        }
        updateEngine()
        lock.withLock { delegate = nil }
        return true
    }

    var isPlayoutInitialized: Bool { isInitialized }
    func initializePlayout() -> Bool { true }
    var isPlaying: Bool { lock.withLock { playoutRequested } }

    func startPlayout() -> Bool {
        lock.withLock { playoutRequested = true }
        updateEngine()
        return true
    }

    func stopPlayout() -> Bool {
        lock.withLock { playoutRequested = false }
        updateEngine()
        return true
    }

    // Receive-only: nothing is ever recorded, so the microphone is never opened.
    var isRecordingInitialized: Bool { false }
    func initializeRecording() -> Bool { false }
    var isRecording: Bool { false }
    func startRecording() -> Bool { false }
    func stopRecording() -> Bool { true }
}
#endif
#endif
