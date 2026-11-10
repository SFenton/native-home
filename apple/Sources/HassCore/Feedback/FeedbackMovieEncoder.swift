#if !os(watchOS) // AVAssetReader and AVAssetWriter video encoding is not used on watchOS; the Watch never attaches media.
import AVFoundation
import CoreMedia
import Foundation

/// Re-encodes a movie to a size target: an H.264 MP4 whose bitrate is computed from its duration.
///
/// Export presets carry their own bitrates and have no size target, so a long clip stays over the limit at
/// every preset. This encoder picks the bitrate that lands the file at ``budgetFraction`` of the limit
/// and the resolution that bitrate can carry, then reads and writes the samples itself
/// (decision: Option A in `.agents/design/feedback-media-compression.md`; policy in `.agents/pages/settings/feedback.md`).
enum FeedbackMovieEncoder {
    // MARK: Policy

    /// Share of the limit the first attempt aims for, leaving room for container overhead.
    static let budgetFraction = 0.92
    /// AAC bitrate for the audio track, bits per second.
    static let audioBitRate = 64_000
    /// Video bitrate below which the picture is not worth sending, bits per second.
    static let floorBitRate = 200_000
    /// Highest video bitrate asked of the encoder, bits per second.
    static let ceilingBitRate = 12_000_000
    /// Share of the previous bitrate each retry uses after an overshoot.
    static let retryFraction = 0.8
    /// Highest frame rate written.
    static let maxFrameRate = 30.0

    /// Video bitrate (bits per second) that lands the file at the budget, or `nil` when it is under the floor.
    ///
    /// - Parameters:
    ///   - limit: Largest allowed file size in bytes.
    ///   - duration: Clip length in seconds.
    ///   - hasAudio: Whether an audio track is written.
    static func videoBitRate(limit: Int64, duration: Double, hasAudio: Bool) -> Int? {
        guard duration > 0 else { return nil }
        let total = Double(limit) * budgetFraction * 8 / duration
        let video = Int(total) - (hasAudio ? audioBitRate : 0)
        return video >= floorBitRate ? min(video, ceilingBitRate) : nil
    }

    /// Longest edge, in pixels, that a video bitrate can carry; never above the source.
    static func longEdge(bitRate: Int, source: Int) -> Int {
        let ladder: Int
        switch bitRate {
        case 3_500_000...: ladder = 1920
        case 1_800_000...: ladder = 1280
        case 900_000...: ladder = 960
        default: ladder = 640
        }
        return min(source, ladder)
    }

    /// Longest edges a retry can step down to, below the first attempt's ladder.
    static let retryEdges = [1920, 1280, 960, 640, 480, 320]
    /// Most encodes tried for one clip.
    static let maxAttempts = 3

    /// The next smaller long edge for a retry after an overshoot, or `edge` when none is smaller.
    static func smallerEdge(than edge: Int) -> Int {
        retryEdges.first { $0 < edge } ?? edge
    }

    /// Even pixel dimensions with the source aspect and the given longest edge.
    static func dimensions(source: CGSize, longEdge: Int) -> (width: Int, height: Int) {
        let sourceLong = max(source.width, source.height)
        guard sourceLong > 0 else { return (2, 2) }
        let scale = min(1, Double(longEdge) / Double(sourceLong))
        func even(_ value: CGFloat) -> Int { max(2, Int((value * scale / 2).rounded()) * 2) }
        return (even(source.width), even(source.height))
    }

    // MARK: Encode

    /// Records each attempt (bitrate and long edge), so a test can assert the retry ladder ran.
    final class AttemptLog: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [(bitRate: Int, edge: Int)] = []

        /// The attempts so far, in order.
        var attempts: [(bitRate: Int, edge: Int)] { lock.withLock { stored } }

        func record(bitRate: Int, edge: Int) { lock.withLock { stored.append((bitRate, edge)) } }
    }

    /// Writes the movie at `source` to `target` within `limit` bytes.
    ///
    /// - Parameter log: Receives every attempt; nil outside tests.
    /// - Returns: The byte count of `target`.
    /// - Throws: ``FeedbackMediaFitter/Failure`` when it can't be read or made small enough, and
    ///   `CancellationError` when the task is cancelled (nothing of the attempt is left beside `target`).
    static func encode(_ source: URL, to target: URL, limit: Int64, log: AttemptLog? = nil) async throws -> Int64 {
        let asset = AVURLAsset(url: source)
        guard (try? await asset.load(.isReadable)) == true,
              let video = try? await asset.loadTracks(withMediaType: .video).first,
              let duration = try? await asset.load(.duration).seconds, duration.isFinite, duration > 0,
              let naturalSize = try? await video.load(.naturalSize),
              let transform = try? await video.load(.preferredTransform)
        else { throw FeedbackMediaFitter.Failure.unreadable }
        let audio = try? await asset.loadTracks(withMediaType: .audio).first
        let frameRate = (try? await video.load(.nominalFrameRate)) ?? 0
        let input = FeedbackMovieEncoderInput(
            asset: asset, video: video, audio: audio, naturalSize: naturalSize, transform: transform,
            frameRate: min(maxFrameRate, frameRate > 0 ? Double(frameRate) : maxFrameRate)
        )
        try Task.checkCancellation()
        guard var bitRate = videoBitRate(limit: limit, duration: duration, hasAudio: audio != nil) else {
            throw FeedbackMediaFitter.Failure.tooLarge
        }
        let sourceLong = Int(max(naturalSize.width, naturalSize.height))
        var edge = longEdge(bitRate: bitRate, source: sourceLong)
        // The writer may leave temporary siblings behind after a cancel, so every attempt works in a private
        // folder that is always removed whole: nothing of the clip outlives the call except the result.
        let work = target.deletingLastPathComponent().appendingPathComponent(".encode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let output = work.appendingPathComponent("out.mp4")
        for _ in 0..<maxAttempts {
            try? FileManager.default.removeItem(at: output)
            log?.record(bitRate: bitRate, edge: edge)
            try await write(input, to: output, bitRate: bitRate, longEdge: edge)
            let size = try FeedbackMediaFitter.byteCount(output)
            if size <= limit {
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.moveItem(at: output, to: target)
                return size
            }
            // An overshoot means the encoder is at its quality floor for this size: step down a rung too.
            bitRate = max(floorBitRate, Int(Double(bitRate) * retryFraction))
            edge = smallerEdge(than: edge)
        }
        throw FeedbackMediaFitter.Failure.tooLarge
    }

    /// Runs one reader-to-writer pass into `target` at `bitRate`, scaled so the long edge is at most `longEdge`.
    ///
    /// - Throws: `CancellationError` when the task is cancelled, ``FeedbackMediaFitter/Failure/unreadable`` when the pass fails.
    private static func write(_ input: FeedbackMovieEncoderInput, to target: URL, bitRate: Int, longEdge: Int) async throws {
        try Task.checkCancellation()
        let size = dimensions(source: input.naturalSize, longEdge: longEdge)
        let session: Session
        do {
            session = try Session(input, to: target, size: size, bitRate: bitRate)
        } catch {
            throw FeedbackMediaFitter.Failure.unreadable
        }
        try await withTaskCancellationHandler {
            try await session.run()
        } onCancel: {
            session.cancel()
        }
    }
}

// MARK: - Session

/// What the reader needs from the source, loaded once and reused by every attempt.
///
/// `@unchecked`: `AVAssetTrack` is not `Sendable` in the SDK (checked 2026-11-06), and the tracks are only read.
struct FeedbackMovieEncoderInput: @unchecked Sendable {
    let asset: AVURLAsset
    let video: AVAssetTrack
    let audio: AVAssetTrack?
    let naturalSize: CGSize
    let transform: CGAffineTransform
    let frameRate: Double
}

/// One reader/writer pass. Each track is pumped on its own queue; ``cancel()`` stops both.
private final class Session: @unchecked Sendable {
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private var pumps: [Pump] = []
    private let lock = NSLock()
    private var cancelled = false
    private var stopRequested = false

    /// Prepares the reader, writer and one pump per track for a single pass.
    ///
    /// - Parameters:
    ///   - input: The source tracks and their geometry.
    ///   - target: Where the MP4 is written.
    ///   - size: Output pixel size, even on both sides.
    ///   - bitRate: Average video bitrate in bits per second.
    /// - Throws: When the reader or writer cannot be created or a track cannot be added.
    init(_ input: FeedbackMovieEncoderInput, to target: URL, size: (width: Int, height: Int), bitRate: Int) throws {
        reader = try AVAssetReader(asset: input.asset)
        writer = try AVAssetWriter(outputURL: target, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        writer.metadata = []

        // Decode to 8-bit 4:2:0 SDR Rec.709 (HDR sources are tone-mapped); the writer input scales and
        // the input's transform keeps the picture upright.
        let colour: [String: Any] = [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ]
        let videoOutput = AVAssetReaderTrackOutput(track: input.video, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            AVVideoColorPropertiesKey: colour,
        ])
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspect,
            AVVideoColorPropertiesKey: colour,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: true,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                AVVideoExpectedSourceFrameRateKey: Int(input.frameRate.rounded()),
                AVVideoMaxKeyFrameIntervalKey: Int(input.frameRate.rounded()) * 2,
            ] as [String: Any],
        ])
        videoInput.transform = input.transform
        videoInput.expectsMediaDataInRealTime = false
        guard reader.canAdd(videoOutput), writer.canAdd(videoInput) else { throw FeedbackMediaFitter.Failure.unreadable }
        reader.add(videoOutput)
        writer.add(videoInput)
        pumps.append(Pump(
            output: videoOutput, input: videoInput, reader: reader, writer: writer, label: "video",
            minFrameInterval: CMTime(seconds: 1 / FeedbackMovieEncoder.maxFrameRate - 0.001, preferredTimescale: 1_000)
        ))

        // Audio is a bonus: a track that can't be read or written is dropped and the clip goes out silent.
        if let audio = input.audio {
            var stereo = AudioChannelLayout()
            stereo.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
            let audioOutput = AVAssetReaderTrackOutput(track: audio, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                // Names the stereo layout so multichannel sources downmix.
                AVChannelLayoutKey: Data(bytes: &stereo, count: MemoryLayout<AudioChannelLayout>.size),
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: FeedbackMovieEncoder.audioBitRate,
            ])
            audioInput.expectsMediaDataInRealTime = false
            if reader.canAdd(audioOutput), writer.canAdd(audioInput) {
                reader.add(audioOutput)
                writer.add(audioInput)
                pumps.append(Pump(output: audioOutput, input: audioInput, reader: reader, writer: writer, label: "audio"))
            }
        }
    }

    /// Ends the pass after the writer refused a sample: pumps stop at their next sample, and any still waiting
    /// for the writer are released.
    private func abort() {
        lock.withLock { stopRequested = true }
        for pump in pumps { pump.finish(markFinished: false) }
    }

    /// Starts the reader unless the pass was cancelled first, or `nil`. `startReading()` raises if reading was
    /// already cancelled, so the pass never cancels the reader before it starts.
    private func beginReading() -> Bool? {
        lock.withLock { cancelled ? nil : reader.startReading() }
    }

    /// Runs the pass to completion. The writer is only touched here and on the pump queues.
    func run() async throws {
        for pump in pumps {
            pump.onFailure = { [weak self] in self?.abort() }
            pump.isStopped = { [weak self] in self?.isStopRequested ?? true }
        }
        guard let reading = beginReading() else { throw CancellationError() }
        guard reading, writer.startWriting() else {
            reader.cancelReading()
            writer.cancelWriting()
            throw failure()
        }
        writer.startSession(atSourceTime: .zero)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for pump in pumps { pump.start(group: group) }
            group.notify(queue: .global()) { done.resume() }
        }
        // The reader is only cancelled once no pump can be inside `copyNextSampleBuffer()`: cancelling it
        // under a blocked copy tears down state that call is still using.
        for pump in pumps { pump.drain() }
        guard !isStopRequested, reader.status == .completed, writer.status == .writing else {
            reader.cancelReading()
            writer.cancelWriting()
            throw failure()
        }
        await writer.finishWriting()
        guard !isCancelled else { throw CancellationError() }
        guard writer.status == .completed else { throw failure() }
    }

    /// Asks the pass to stop: every pump ends at its next sample, and ``run()`` then throws `CancellationError`.
    func cancel() {
        lock.withLock {
            cancelled = true
            stopRequested = true
        }
    }

    /// Whether the pass should stop at the next sample (cancelled or the writer refused one).
    private var isStopRequested: Bool { lock.withLock { stopRequested } }

    /// Whether ``cancel()`` was called.
    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// The error for a pass that did not complete: cancellation if it was cancelled, else unreadable.
    private func failure() -> Error {
        isCancelled ? CancellationError() : FeedbackMediaFitter.Failure.unreadable
    }
}

/// Copies one track's samples from the reader to the writer.
private final class Pump: @unchecked Sendable {
    private let output: AVAssetReaderOutput
    private let input: AVAssetWriterInput
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var group: DispatchGroup?
    /// Called when the writer refuses a sample, so the sibling pump and the reader stop instead of waiting.
    var onFailure: (() -> Void)?
    /// Whether the pass asked every pump to stop.
    var isStopped: (() -> Bool)?

    /// Samples closer together than this are dropped (the frame-rate cap); nil keeps every sample.
    private let minFrameInterval: CMTime?
    /// Presentation time of the last sample written; only the pump's own queue touches it.
    private var lastKept = CMTime.invalid

    /// - Parameters:
    ///   - output: The reader output to pull samples from.
    ///   - input: The writer input to append them to.
    ///   - label: Names the pump's queue (`video` or `audio`).
    ///   - minFrameInterval: Drops samples closer than this to the last one kept; `nil` keeps all.
    init(
        output: AVAssetReaderOutput, input: AVAssetWriterInput, reader: AVAssetReader, writer: AVAssetWriter, label: String,
        minFrameInterval: CMTime? = nil
    ) {
        self.minFrameInterval = minFrameInterval
        self.reader = reader
        self.writer = writer
        self.output = output
        self.input = input
        queue = DispatchQueue(label: "fenton.feedback.encode.\(label)")
    }

    /// Starts pulling samples on the pump's queue; leaves `group` when the track is done or stopped.
    func start(group: DispatchGroup) {
        group.enter()
        lock.lock()
        self.group = group
        lock.unlock()
        input.requestMediaDataWhenReady(on: queue) { [self] in
            while input.isReadyForMoreMediaData {
                // Copying from a reader that is not reading raises, so end the pump first.
                guard isStopped?() != true, writer.status == .writing, reader.status == .reading else {
                    // Finish the input even when stopping, or the writer holds the sibling input back for ever.
                    finish(markFinished: true)
                    return
                }
                guard let sample = output.copyNextSampleBuffer() else {
                    finish(markFinished: true)
                    return
                }
                if let minFrameInterval {
                    let time = sample.presentationTimeStamp
                    if lastKept.isValid, time < lastKept + minFrameInterval { continue }
                    lastKept = time
                }
                if !input.append(sample) {
                    finish(markFinished: false)
                    onFailure?()
                    return
                }
            }
        }
    }

    /// Waits for any block still running on this pump's queue.
    func drain() { queue.sync {} }

    /// Ends this pump. With `markFinished` false the pass stops waiting for it without touching the writer.
    func finish(markFinished: Bool) {
        lock.lock()
        let group = group
        self.group = nil
        lock.unlock()
        guard let group else { return }
        if markFinished, writer.status == .writing { input.markAsFinished() }
        group.leave()
    }
}
#endif
