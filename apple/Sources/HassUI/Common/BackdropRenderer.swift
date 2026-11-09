import CoreImage
import CryptoKit
import HassCore
import ImageIO
import UniformTypeIdentifiers

/// Draws, stores and finds the pre-blurred house photo (``HouseBackdropStore`` decides when).
///
/// One Core Image pass makes the whole backdrop: the photo covers the window magnified by
/// ``BackdropRenderSpec/scale``, is saturated, then blurred by the setting's radius in points. The result is the
/// finished wallpaper (the view only draws and offsets it, no live blur, no scale effect) and is stored as a JPEG
/// named for everything that shaped it (``BackdropRenderSpec/cacheName(photo:)``).
enum BackdropRenderer {
    /// Saturation boost (direction G: `saturate(1.1)`; the web's is 1.04).
    static let saturation = 1.1
    /// Render files kept in the cache folder besides the one on screen: the last few slider positions.
    static let keptRenders = 8
    /// The file holding the name of the render on screen, read at launch before anything is measured.
    static let latestName = "latest.txt"
    /// Files from earlier recipes, removed on the first refresh.
    static let retiredNames = ["house-blurred.png", "house-blurred-g.png"]
    /// JPEG quality of a stored render (a blurred picture hides every artifact at this setting).
    static let jpegQuality = 0.92

    /// Shared so its Metal resources are made once. Works in sRGB, not linear light, so a blur mixes colors the way the
    /// web's CSS `blur()` does.
    private static let context: CIContext = {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CIContext(options: [.cacheIntermediates: false, .workingColorSpace: srgb, .outputColorSpace: srgb])
    }()

    /// A short stable digest of a photo's pixels, which names its renders. The same photo served again gets the same
    /// digest, so it neither re-renders nor leaves a second file.
    nonisolated static func digest(of photo: CGImage) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("\(photo.width)x\(photo.height)".utf8))
        if let data = photo.dataProvider?.data as Data? { hasher.update(data: data) }
        return hasher.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Renders the backdrop once.
    /// - Parameters:
    ///   - photo: The decoded house photo.
    ///   - spec: The window, density and setting.
    /// - Returns: The render at `spec.renderWidth` x `spec.renderHeight`, or nil when Core Image can't draw it.
    nonisolated static func render(_ photo: CGImage, spec: BackdropRenderSpec) -> CGImage? {
        let width = CGFloat(spec.renderWidth), height = CGFloat(spec.renderHeight)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let image = CIImage(cgImage: photo)
        let source = image.extent.size
        guard source.width > 0, source.height > 0 else { return nil }
        // Cover the window, magnified like the web's `scale(1.05)` (direction G: 1.06), centered.
        let cover = max(width / source.width, height / source.height) * BackdropRenderSpec.scale
        // The photo placed over the window with its edge pixels extended to infinity, so nothing downstream sees a
        // transparent edge (clamping an already infinite image would blank it, so this is the only clamp).
        let placed: CIImage
        if cover < 1 {
            // Lanczos reads a few source pixels past each edge, so it gets an opaque margin that wide. Its result is cut
            // to whole pixels at a whole-pixel offset: an edge row covered only in part would be translucent, and the
            // clamp would carry that to infinity.
            let pad = (3 / cover).rounded(.up) + 2
            let inner = CGRect(x: 0, y: 0, width: (source.width * cover).rounded(.down), height: (source.height * cover).rounded(.down))
            let offset = CGAffineTransform(translationX: ((width - inner.width) / 2).rounded(), y: ((height - inner.height) / 2).rounded())
            placed = image.clampedToExtent().cropped(to: image.extent.insetBy(dx: -pad, dy: -pad))
                .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: cover, kCIInputAspectRatioKey: 1])
                .cropped(to: inner).transformed(by: offset).clampedToExtent()
        } else {
            let offset = CGAffineTransform(translationX: (width - source.width * cover) / 2, y: (height - source.height * cover) / 2)
            placed = image.clampedToExtent().transformed(by: CGAffineTransform(scaleX: cover, y: cover).concatenating(offset))
        }
        var output = placed.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation])
        if spec.renderSigma > 0 { output = output.applyingGaussianBlur(sigma: spec.renderSigma) }
        return context.createCGImage(output.cropped(to: bounds), from: bounds)
    }

    // MARK: - Files

    /// Reads a stored render, decoded now: an image source decodes lazily, and a full-window JPEG decoded on its first
    /// draw would cost the main thread instead of the caller's (off-main) thread.
    nonisolated static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// Writes a render as JPEG; false when it can't.
    @discardableResult
    nonisolated static func write(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// Records which render is on screen, so the next launch can draw it before anything is measured.
    nonisolated static func markLatest(_ name: String, in directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(name.utf8).write(to: directory.appending(path: latestName), options: .atomic)
    }

    /// The render on screen when the app last ran and its name, if the file is still there.
    nonisolated static func loadLatest(in directory: URL) -> (name: String, image: CGImage)? {
        guard let data = try? Data(contentsOf: directory.appending(path: latestName)),
              let name = String(data: data, encoding: .utf8), !name.isEmpty, !name.contains("/"),
              let image = load(directory.appending(path: name)) else { return nil }
        return (name, image)
    }

    /// Deletes the oldest renders beyond `keep`, never `protected`.
    nonisolated static func prune(_ directory: URL, keep: Int = keptRenders, protecting protected: String) {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        let renders = files.filter { $0.pathExtension == "jpg" && $0.lastPathComponent.hasPrefix("backdrop-") }
        guard renders.count > keep else { return }
        func modified(_ url: URL) -> Date { (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast }
        for url in renders.sorted(by: { modified($0) > modified($1) }).dropFirst(keep) where url.lastPathComponent != protected {
            try? fileManager.removeItem(at: url)
        }
    }

    /// Removes files left by earlier recipes.
    nonisolated static func removeRetired(in directory: URL) {
        for name in retiredNames {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
    }

    /// The render for `spec`: the stored file when there is one, else rendered now and stored. Runs off the main thread.
    nonisolated static func renderOrLoad(_ photo: CGImage, digest: String, spec: BackdropRenderSpec, in directory: URL) -> (image: CGImage, rendered: Bool)? {
        let name = spec.cacheName(photo: digest)
        let url = directory.appending(path: name)
        if let stored = load(url) { return (stored, false) }
        guard let image = render(photo, spec: spec) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        write(image, to: url)
        prune(directory, protecting: name)
        return (image, true)
    }
}
