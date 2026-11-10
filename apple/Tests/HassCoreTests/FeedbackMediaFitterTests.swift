import AVFoundation
import CoreGraphics
import Foundation
@testable import HassCore
import ImageIO
import Testing
import UniformTypeIdentifiers
import VideoToolbox

// MARK: - Movie fixtures

/// High-entropy movies that no fixed export preset can shrink to a small limit.
enum NoisyMovieFixture {
    /// Writes a noisy H.264 QuickTime movie (optionally rotated, optionally with a PCM audio track).
    static func make(
        in folder: URL, width: Int = 640, height: Int = 480, seconds: Int = 4, fps: Int = 12,
        rotated: Bool = false, audio: Bool = false, block: Int = 1, fastStart: Bool = false
    ) async throws -> URL {
        let url = folder.appendingPathComponent(audio ? "video-only.mov" : "noisy.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 16_000_000],
        ])
        writer.shouldOptimizeForNetworkUse = fastStart
        if rotated { video.transform = CGAffineTransform(rotationAngle: .pi / 2) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(video)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        let textureWidth = width + seconds * fps * 3 + 8
        let textureHeight = height + seconds * fps * 2 + 8
        var texture = [UInt32](repeating: 0, count: block == 1 ? 0 : textureWidth * textureHeight)
        if block > 1 {
            var colours: [UInt32] = []
            let columns = textureWidth / block + 1
            for index in 0..<(columns * (textureHeight / block + 1)) {
                colours.append(UInt32(truncatingIfNeeded: (UInt64(index) &* 0x9E37_79B9_7F4A_7C15 ^ 0xA5A5_5A5A) >> 20))
            }
            for y in 0..<textureHeight {
                for x in 0..<textureWidth { texture[y * textureWidth + x] = colours[(y / block) * columns + x / block] }
            }
        }
        for frame in 0..<(seconds * fps) {
            try await waitReady(video, writer: writer)
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let base = try #require(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt32.self)
            let stride = CVPixelBufferGetBytesPerRow(pixels) / 4
            if block == 1 {
                // xorshift: fresh pseudo-random pixels every frame, which no encoder can predict.
                var state = UInt32(truncatingIfNeeded: seed >> 32) | 1
                for index in 0..<(stride * height) {
                    state ^= state << 13
                    state ^= state >> 17
                    state ^= state << 5
                    base[index] = state
                }
            } else {
                // One textured picture panned a few pixels per frame: coherent, like real footage.
                for y in 0..<height {
                    texture.withUnsafeBufferPointer { source in
                        (base + y * stride).update(from: source.baseAddress! + (y + frame * 2) * textureWidth + frame * 3, count: width)
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        video.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return audio ? try await addAudio(to: url, seconds: seconds, in: folder) : url
    }

    /// An iPhone-style HDR clip: HEVC Main10, 10-bit 4:2:0, BT.2020 with HLG, 60 fps. Nil when the host cannot write it.
    static func makeHDR(in folder: URL, seconds: Int = 3, fps: Int = 60) async throws -> URL? {
        let width = 640, height = 360
        let url = folder.appendingPathComponent("hdr.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String,
                AVVideoAverageBitRateKey: 8_000_000,
            ] as [String: Any],
        ]
        guard writer.canApply(outputSettings: settings, forMediaType: .video) else { return nil }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(video) else { return nil }
        writer.add(video)
        guard writer.startWriting() else { return nil }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * fps) {
            try await waitReady(video, writer: writer)
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, nil, &buffer)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let luma = try #require(CVPixelBufferGetBaseAddressOfPlane(pixels, 0)).assumingMemoryBound(to: UInt16.self)
            let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0) / 2
            for y in 0..<height {
                for x in 0..<width {
                    let block = UInt64((x + frame * 3) / 8) &* 73_856_093 ^ UInt64((y + frame * 2) / 8) &* 19_349_663
                    luma[y * lumaStride + x] = UInt16(64 + (block &* 0x9E37_79B9) >> 7 & 0x1FF) << 6
                }
            }
            let chroma = try #require(CVPixelBufferGetBaseAddressOfPlane(pixels, 1)).assumingMemoryBound(to: UInt16.self)
            let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 1) / 2
            for y in 0..<(height / 2) { for x in 0..<width { chroma[y * chromaStride + x] = 512 << 6 } }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
        }
        video.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { return nil }
        return url
    }

    /// Waits for the input to take data, throwing instead of hanging if the writer stalls.
    static func waitReady(_ input: AVAssetWriterInput, writer: AVAssetWriter) async throws {
        let deadline = ContinuousClock.now + .seconds(20)
        while !input.isReadyForMoreMediaData {
            if ContinuousClock.now > deadline || writer.status == .failed {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    /// Muxes a generated tone under the video with a passthrough export, avoiding hand-built sample buffers.
    private static func addAudio(to video: URL, seconds: Int, in folder: URL) async throws -> URL {
        let tone = folder.appendingPathComponent("tone.caf")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let file = try AVAudioFile(forWriting: tone, settings: format.settings)
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<2 {
            let samples = try #require(buffer.floatChannelData?[channel])
            for index in 0..<Int(frames) { samples[index] = sinf(Float(index) * 0.05) * 0.2 }
        }
        try file.write(from: buffer)

        let videoAsset = AVURLAsset(url: video)
        let toneAsset = AVURLAsset(url: tone)
        let composition = AVMutableComposition()
        let sourceVideo = try #require(try await videoAsset.loadTracks(withMediaType: .video).first)
        let sourceTone = try #require(try await toneAsset.loadTracks(withMediaType: .audio).first)
        let range = CMTimeRange(start: .zero, duration: try await videoAsset.load(.duration))
        let videoTrack = try #require(composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
        try videoTrack.insertTimeRange(range, of: sourceVideo, at: .zero)
        videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
        let audioTrack = try #require(composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
        try audioTrack.insertTimeRange(range, of: sourceTone, at: .zero)

        let output = folder.appendingPathComponent("noisy.mov")
        let export = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        try await export.export(to: output, as: .mov)
        try? FileManager.default.removeItem(at: video)
        try? FileManager.default.removeItem(at: tone)
        return output
    }
}

@Suite("Feedback media fitting")
struct FeedbackMediaFitterTests {
    /// A noisy PNG, which compresses poorly, so a JPEG copy is much smaller.
    static func noisyPNG(in folder: URL, side: Int = 1200) throws -> URL {
        let url = folder.appendingPathComponent("noise.png")
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for index in pixels.indices where index % 4 != 3 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            pixels[index] = UInt8(truncatingIfNeeded: seed >> 33)
        }
        let image = try pixels.withUnsafeMutableBytes { buffer -> CGImage in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            return try #require(context.makeImage())
        }
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func smallFilesAreUntouched() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try FeedbackMediaFixture.image(in: folder, name: "p.png", type: .png, gps: false)
        let before = try Data(contentsOf: url)
        let fitted = try await FeedbackMediaFitter.fit(url, isVideo: false)
        #expect(fitted.url == url && !fitted.compressed)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func largePhotosBecomeSmallerJPEGs() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try Self.noisyPNG(in: folder)
        let original = try FeedbackMediaFitter.byteCount(url)
        let limit = original / 2
        let fitted = try await FeedbackMediaFitter.fit(url, isVideo: false, limit: limit)
        #expect(fitted.compressed)
        #expect(fitted.byteCount <= limit)
        #expect(fitted.url.pathExtension == "jpg")
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let source = try #require(CGImageSourceCreateWithURL(fitted.url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    }

    @Test func photosThatCannotFitAreRefused() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try FeedbackMediaFixture.image(in: folder, name: "p.jpg", type: .jpeg, gps: false)
        await #expect(throws: FeedbackMediaFitter.Failure.tooLarge) {
            try await FeedbackMediaFitter.fit(url, isVideo: false, limit: 10)
        }
    }

    @Test func moviesThatCannotFitAreRefused() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await FeedbackMediaFixture.movie(in: folder, name: "m.mov", location: false)
        let fitted = try await FeedbackMediaFitter.fit(url, isVideo: true)
        #expect(!fitted.compressed)
        await #expect(throws: FeedbackMediaFitter.Failure.tooLarge) {
            try await FeedbackMediaFitter.fit(url, isVideo: true, limit: 10)
        }
    }

    @Test func unreadableFiles() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("x.png")
        try Data(repeating: 7, count: 64).write(to: image)
        await #expect(throws: FeedbackMediaFitter.Failure.unreadable) {
            try await FeedbackMediaFitter.fit(image, isVideo: false, limit: 10)
        }
        let movie = folder.appendingPathComponent("x.mov")
        try Data(repeating: 7, count: 64).write(to: movie)
        await #expect(throws: FeedbackMediaFitter.Failure.unreadable) {
            try await FeedbackMediaFitter.fit(movie, isVideo: true, limit: 10)
        }
        await #expect(throws: FeedbackMediaFitter.Failure.unreadable) {
            try await FeedbackMediaFitter.fit(folder.appendingPathComponent("missing.png"), isVideo: false)
        }
    }

    // MARK: Movies

    @Test func longNoisyMovieIsCompressedToFit() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await NoisyMovieFixture.make(in: folder, seconds: 8, block: 8)
        let limit: Int64 = 300_000
        let original = try FeedbackMediaFitter.byteCount(url)
        #expect(original > limit * 4)
        let fitted = try await FeedbackMediaFitter.fit(url, isVideo: true, limit: limit)
        #expect(fitted.compressed)
        #expect(fitted.byteCount <= limit)
        #expect(fitted.url.deletingLastPathComponent() == folder)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let asset = AVURLAsset(url: fitted.url)
        #expect(try await asset.load(.isPlayable))
        #expect(abs(try await asset.load(.duration).seconds - 8) < 0.2)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(abs(size.width / size.height - 640.0 / 480.0) < 0.02)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
    }

    @Test func rotationAndAudioAreKept() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await NoisyMovieFixture.make(in: folder, width: 480, height: 320, seconds: 3, rotated: true, audio: true, block: 8)
        let fitted = try await FeedbackMediaFitter.fit(url, isVideo: true, limit: 300_000)
        #expect(fitted.byteCount <= 300_000)
        let asset = AVURLAsset(url: fitted.url)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let transform = try await track.load(.preferredTransform)
        #expect(abs(transform.b) > 0.9 && abs(transform.c) > 0.9)
        let size = try await track.load(.naturalSize).applying(transform)
        #expect(abs(size.height) > abs(size.width))
    }

    @Test func clipsBelowTheBitrateFloorAreRefused() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await NoisyMovieFixture.make(in: folder, width: 160, height: 120, seconds: 2)
        await #expect(throws: FeedbackMediaFitter.Failure.tooLarge) {
            try await FeedbackMediaFitter.fit(url, isVideo: true, limit: 20_000)
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["noisy.mov"])
    }

    @Test func overshootRetriesThenRefuses() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await NoisyMovieFixture.make(in: folder, seconds: 2, fps: 30)
        let log = FeedbackMovieEncoder.AttemptLog()
        // 60_000 bytes over 2 s is about 221 kbps of video: above the 200 kbps floor, so it encodes, but
        // per-frame noise cannot reach it even at the smallest rung.
        await #expect(throws: FeedbackMediaFitter.Failure.tooLarge) {
            try await FeedbackMovieEncoder.encode(url, to: folder.appendingPathComponent("noisy-small.mp4"), limit: 60_000, log: log)
        }
        let attempts = log.attempts
        #expect(attempts.count == FeedbackMovieEncoder.maxAttempts)
        #expect(attempts.first?.bitRate == 220_800)
        #expect(zip(attempts, attempts.dropFirst()).allSatisfy { $0.edge > $1.edge && $0.bitRate >= $1.bitRate })
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names == ["noisy.mov"], "left behind: \(names)")
    }

    @Test func aFirstOvershootIsFixedByTheNextRung() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await NoisyMovieFixture.make(in: folder, seconds: 8, block: 8)
        let log = FeedbackMovieEncoder.AttemptLog()
        let target = folder.appendingPathComponent("noisy-small.mp4")
        let size = try await FeedbackMovieEncoder.encode(url, to: target, limit: 300_000, log: log)
        #expect(size <= 300_000)
        #expect(log.attempts.count >= 2, "the first attempt was expected to overshoot: \(log.attempts)")
        #expect(try FeedbackMediaFitter.byteCount(target) == size)
    }

    @Test func sixtyFramesPerSecondIsCappedAtThirty() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await NoisyMovieFixture.make(in: folder, width: 320, height: 240, seconds: 3, fps: 60, block: 8)
        let fitted = try await FeedbackMediaFitter.fit(url, isVideo: true, limit: 150_000)
        let asset = AVURLAsset(url: fitted.url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.nominalFrameRate) <= 30.5)
        #expect(abs(try await asset.load(.duration).seconds - 3) < 0.2)
    }

    @Test func anHDRClipBecomesSDRRec709H264() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        guard let url = try await NoisyMovieFixture.makeHDR(in: folder) else {
            try Test.cancel("This host cannot write HEVC Main10 HLG; the hosted iPhone run covers it.")
            return
        }
        let limit: Int64 = 300_000
        let fitted = try await FeedbackMediaFitter.fit(url, isVideo: true, limit: limit)
        #expect(fitted.byteCount <= limit)
        let asset = AVURLAsset(url: fitted.url)
        #expect(try await asset.load(.isPlayable))
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.nominalFrameRate) <= 30.5)
        let description = try #require(try await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(description) == kCMVideoCodecType_H264)
        let extensions = try #require(CMFormatDescriptionGetExtensions(description) as? [String: Any])
        #expect(extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String == kCMFormatDescriptionColorPrimaries_ITU_R_709_2 as String)
        #expect(extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String == kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String)
        #expect(extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String == kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2 as String)
    }

    @Test func cancellationLeavesNoPartialOutput() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await NoisyMovieFixture.make(in: folder, seconds: 6, block: 8)
        let task = Task { try await FeedbackMediaFitter.fit(url, isVideo: true, limit: 400_000) }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names == ["noisy.mov"], "left behind: \(names)")
    }

    @Test("Cancelling at any moment leaves only the input", arguments: [0, 3, 40, 150, 500])
    func cancellationAtAnyMoment(delay: Int) async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try await NoisyMovieFixture.make(in: folder, seconds: 6, block: 8)
        let task = Task { try await FeedbackMediaFitter.fit(url, isVideo: true, limit: 400_000) }
        if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
        task.cancel()
        // A late cancel can lose the race to a finished encode; either way nothing else is left.
        let result = await task.result
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        switch result {
        case .success(let fitted): #expect(names == [fitted.url.lastPathComponent], "left behind: \(names)")
        case .failure: #expect(names == ["noisy.mov"], "left behind: \(names)")
        }
    }

    @Test func aMovieCutOffMidwayIsUnreadable() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // With the index first, a truncated file still opens but its samples run out part way through.
        let url = try await NoisyMovieFixture.make(in: folder, seconds: 4, block: 8, fastStart: true)
        let data = try Data(contentsOf: url)
        try data.prefix(data.count / 2).write(to: url)
        await #expect(throws: FeedbackMediaFitter.Failure.unreadable) {
            try await FeedbackMediaFitter.fit(url, isVideo: true, limit: 150_000)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names == ["noisy.mov"], "left behind: \(names)")
    }

    @Test func bitratePolicy() {
        let limit: Int64 = 10 * 1_048_576
        // 60 s with audio: 92% of 10 MiB over a minute is about 1.29 Mbps, less 64 kbps audio.
        let rate = FeedbackMovieEncoder.videoBitRate(limit: limit, duration: 60, hasAudio: true)
        #expect(rate == Int(Double(limit) * 0.92 * 8 / 60) - 64_000)
        #expect(FeedbackMovieEncoder.videoBitRate(limit: limit, duration: 600, hasAudio: true) == nil)
        #expect(FeedbackMovieEncoder.videoBitRate(limit: limit, duration: 0, hasAudio: false) == nil)
        #expect(FeedbackMovieEncoder.videoBitRate(limit: limit, duration: 1, hasAudio: false) == 12_000_000)
        #expect(FeedbackMovieEncoder.longEdge(bitRate: 4_000_000, source: 3840) == 1920)
        #expect(FeedbackMovieEncoder.longEdge(bitRate: 2_000_000, source: 3840) == 1280)
        #expect(FeedbackMovieEncoder.longEdge(bitRate: 1_000_000, source: 3840) == 960)
        #expect(FeedbackMovieEncoder.longEdge(bitRate: 300_000, source: 3840) == 640)
        #expect(FeedbackMovieEncoder.longEdge(bitRate: 4_000_000, source: 800) == 800)
        let size = FeedbackMovieEncoder.dimensions(source: CGSize(width: 1920, height: 1080), longEdge: 640)
        #expect(size.width == 640 && size.height == 360)
        let tiny = FeedbackMovieEncoder.dimensions(source: CGSize(width: 100, height: 50), longEdge: 640)
        #expect(tiny.width == 100 && tiny.height == 50)
        #expect(FeedbackMovieEncoder.smallerEdge(than: 1920) == 1280)
        #expect(FeedbackMovieEncoder.smallerEdge(than: 700) == 640)
        #expect(FeedbackMovieEncoder.smallerEdge(than: 320) == 320)
        #expect(FeedbackMovieEncoder.dimensions(source: .zero, longEdge: 640) == (2, 2))
    }
}
