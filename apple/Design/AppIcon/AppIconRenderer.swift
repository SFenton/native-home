import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders the app's icons from `AppIconArtwork` into the asset catalog: for every ``AppIconChoice`` an
/// `<assetName>.appiconset` holding `light.png`, `dark.png` and `tinted.png` (1024 × 1024, opaque sRGB, no alpha
/// channel, as the App Store requires) and its `Contents.json`. Run it through `tools/render_app_icons.sh`, which
/// compiles this file with `AppIconChoice.swift`, `AppIconArtwork.swift` and `Color+RGB.swift`.
///
/// Usage: `render_app_icons <Assets.xcassets> [contact-sheet.png]`. The optional contact sheet is a 4 × 2 grid of the
/// eight light icons on the mockup's dark ground, for checking the renders against `Pairs.dc.html`.
@main
struct AppIconRenderer {
    static let side = 1024

    @MainActor
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            FileHandle.standardError.write(Data("usage: render_app_icons <Assets.xcassets> [contact-sheet.png]\n".utf8))
            exit(2)
        }
        let catalog = URL(fileURLWithPath: arguments[1], isDirectory: true)
        for choice in AppIconChoice.allCases {
            let folder = catalog.appending(path: "\(choice.assetName).appiconset", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, appearance) in [("light", AppIconArtwork.Appearance.standard), ("dark", .dark), ("tinted", .tinted)] {
                let image = try render(choice, appearance, side: side)
                try write(image, to: folder.appending(path: "\(name).png"))
            }
            try Data(contentsJSON.utf8).write(to: folder.appending(path: "Contents.json"))
            print("rendered \(choice.assetName)")
        }
        if arguments.count >= 3 { try writeContactSheet(to: URL(fileURLWithPath: arguments[2])) }
    }

    /// The icon set's `Contents.json`: one universal 1024 image, plus its dark and tinted appearances (iOS 18).
    static let contentsJSON = """
        {
          "images" : [
            { "filename" : "light.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
            { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
            { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ], "filename" : "tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
          ],
          "info" : { "author" : "xcode", "version" : 1 }
        }

        """

    /// The art at `side` × `side` pixels, flattened to opaque sRGB.
    @MainActor
    static func render(_ choice: AppIconChoice, _ appearance: AppIconArtwork.Appearance, side: Int) throws -> CGImage {
        let artwork = AppIconArtwork(tint: choice.tint, tintOpacity: AppIconChoice.tintOpacity,
                                     glyph: choice.glyph, appearance: appearance)
            .frame(width: CGFloat(side), height: CGFloat(side))
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 1
        guard let rendered = renderer.cgImage else { throw RenderError.noImage }
        return try flatten(rendered, side: side)
    }

    /// Redraws into an sRGB bitmap with no alpha channel (the App Store rejects icons with one).
    static func flatten(_ image: CGImage, side: Int) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw RenderError.noContext }
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let flat = context.makeImage() else { throw RenderError.noImage }
        return flat
    }

    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw RenderError.noDestination
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw RenderError.noDestination }
    }

    /// Eight light icons in a 4 × 2 grid, each clipped to the icon corner radius, on the mockup's dark ground.
    @MainActor
    static func writeContactSheet(to url: URL) throws {
        let cell = 360, gap = 80, margin = 80
        let width = margin * 2 + cell * 4 + gap * 3, height = margin * 2 + cell * 2 + gap
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw RenderError.noContext }
        context.setFillColor(CGColor(srgbRed: 0.055, green: 0.067, blue: 0.086, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for (index, choice) in AppIconChoice.allCases.enumerated() {
            let image = try render(choice, .standard, side: cell)
            let x = margin + (index % 4) * (cell + gap)
            let y = height - margin - cell - (index / 4) * (cell + gap)
            let rect = CGRect(x: x, y: y, width: cell, height: cell)
            context.saveGState()
            context.addPath(CGPath(roundedRect: rect, cornerWidth: CGFloat(cell) * 0.224, cornerHeight: CGFloat(cell) * 0.224, transform: nil))
            context.clip()
            context.draw(image, in: rect)
            context.restoreGState()
        }
        guard let sheet = context.makeImage() else { throw RenderError.noImage }
        try write(sheet, to: url)
    }

    enum RenderError: Error { case noImage, noContext, noDestination }
}
