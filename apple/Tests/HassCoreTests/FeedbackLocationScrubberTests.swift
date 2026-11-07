import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import HassCore

// MARK: - Fixtures

/// Test media written to a private temporary folder.
enum FeedbackMediaFixture {
    /// A fresh folder for one test's files.
    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fenton-feedback-media-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A small solid image, optionally GPS-tagged.
    static func image(in folder: URL, name: String, type: UTType, gps: Bool) throws -> URL {
        let url = folder.appendingPathComponent(name)
        let context = try #require(CGContext(
            data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        let image = try #require(context.makeImage())
        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        )
        var properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "FixtureCam"],
        ]
        if gps {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 37.3349, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.0090, kCGImagePropertyGPSLongitudeRef: "W",
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// A two-frame H.264 QuickTime movie, optionally carrying an ISO 6709 location.
    static func movie(in folder: URL, name: String, location: Bool) async throws -> URL {
        let url = folder.appendingPathComponent(name)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        if location {
            let item = AVMutableMetadataItem()
            item.identifier = .quickTimeMetadataLocationISO6709
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            item.value = "+37.3349-122.0090/" as NSString
            writer.metadata = [item]
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
            ]
        )
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<2 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixels = try #require(buffer)
            adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }
}

// MARK: - Tests

@Suite("Feedback location scrubbing")
struct FeedbackLocationScrubberTests {
    @Test("A GPS-tagged photo loses only its location", arguments: [UTType.jpeg, .heic, .png])
    func photo(type: UTType) async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let ext = type.preferredFilenameExtension ?? "img"
        let url = try FeedbackMediaFixture.image(in: folder, name: "p.\(ext)", type: type, gps: true)
        #expect(try FeedbackLocationScrubber.imageHasLocation(url))

        try await FeedbackLocationScrubber.scrub(url, isVideo: false)

        #expect(try !FeedbackLocationScrubber.imageHasLocation(url))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == type.identifier)
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 8)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(leftovers == ["p.\(ext)"])
    }

    @Test("A photo without location is left byte-for-byte")
    func cleanPhoto() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try FeedbackMediaFixture.image(in: folder, name: "p.jpg", type: .jpeg, gps: false)
        let before = try Data(contentsOf: url)
        try await FeedbackLocationScrubber.scrub(url, isVideo: false)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test("A located movie is re-wrapped without location; a clean one is untouched")
    func movie() async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let located = try await FeedbackMediaFixture.movie(in: folder, name: "m.mov", location: true)
        #expect(try await FeedbackLocationScrubber.movieHasLocation(located))
        try await FeedbackLocationScrubber.scrub(located, isVideo: true)
        #expect(try await !FeedbackLocationScrubber.movieHasLocation(located))
        let tracks = try await AVURLAsset(url: located).loadTracks(withMediaType: .video)
        #expect(tracks.count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["m.mov"])

        let clean = try await FeedbackMediaFixture.movie(in: folder, name: "c.mov", location: false)
        let before = try Data(contentsOf: clean)
        try await FeedbackLocationScrubber.scrub(clean, isVideo: true)
        #expect(try Data(contentsOf: clean) == before)
    }

    @Test("Unreadable files are reported as unreadable", arguments: [false, true])
    func unreadable(isVideo: Bool) async throws {
        let folder = try FeedbackMediaFixture.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(isVideo ? "x.mov" : "x.png")
        try Data(repeating: 7, count: 16).write(to: url)
        await #expect(throws: FeedbackLocationScrubber.Failure.unreadable) {
            try await FeedbackLocationScrubber.scrub(url, isVideo: isVideo)
        }
    }
}
