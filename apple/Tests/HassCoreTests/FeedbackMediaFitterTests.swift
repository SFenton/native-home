import CoreGraphics
import Foundation
@testable import HassCore
import ImageIO
import Testing
import UniformTypeIdentifiers

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
}
