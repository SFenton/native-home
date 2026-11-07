import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

// MARK: - Fixtures

/// Test media written to a private temporary folder.
enum FeedbackUITestMedia {
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
}
