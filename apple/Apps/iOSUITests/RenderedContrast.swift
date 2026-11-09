import XCTest

/// Rendered-pixel contrast, the evidence for a contrast issue the audit misjudges (FestivalNativeApps
/// `IPadAuditRenderedContrast`, simplified). The iPad audit fails dark text on light materials that
/// measure well above 4.5:1 on screen; this measures the element's own frame in a capture from the same
/// run: the glyph pixels' upper quartile (text core) against the median pixel (surface), as a WCAG ratio.
@MainActor
enum RenderedContrast {
    /// A full-screen capture as RGBA bytes, with its scale to screen points.
    struct Capture {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        let scale: CGFloat
        /// `.up` normally. In iPad landscape XCUIScreen returns `.left`: the raw buffer is the portrait
        /// panel, so a landscape frame must be turned before sampling (measured 2026-10-10; unturned, it
        /// sampled unrelated pixels and could pass or fail any element).
        let orientation: UIImage.Orientation

        static func screen() -> Capture? {
            let screenshot = XCUIScreen.main.screenshot()
            // Draw through UIImage so the capture follows the interface orientation: the raw CGImage stays
            // portrait in landscape while element frames are landscape (seen on iPad, 2026-10-11).
            let format = UIGraphicsImageRendererFormat()
            format.scale = screenshot.image.scale
            let upright = UIGraphicsImageRenderer(size: screenshot.image.size, format: format).image { _ in
                screenshot.image.draw(at: .zero)
            }
            guard let image = upright.cgImage else { return nil }
            let width = image.width, height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            // The pixels are upright now, so frames map directly; passing the raw orientation on rotated them a
            // second time and sampled the wrong place (1.0:1 for every iPad landscape issue, 2026-10-11).
            return Capture(pixels: pixels, width: width, height: height, scale: screenshot.image.scale,
                           orientation: .up)
        }
    }

    /// The part of `frame` (screen points) the capture holds, in raw pixels, or nil when it holds none.
    static func pixelRect(of frame: CGRect, in capture: Capture) -> CGRect? {
        let points: CGRect
        switch capture.orientation {
        case .up:
            points = frame
        case .left:
            // Screen (x, y) sits at raw (short side - maxY, x): the buffer is the portrait panel.
            points = CGRect(x: CGFloat(capture.width) / capture.scale - frame.maxY, y: frame.minX,
                            width: frame.height, height: frame.width)
        default:
            return nil
        }
        let rect = CGRect(x: points.minX * capture.scale, y: points.minY * capture.scale,
                          width: points.width * capture.scale, height: points.height * capture.scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: capture.width, height: capture.height))
        guard rect.width >= 2, rect.height >= 2 else { return nil }
        return rect
    }

    /// The WCAG relative luminance (0 black, 1 white) of the pixel under a screen point, or nil when the point is
    /// off the capture. For asserting that a sheet is light or dark.
    static func luminance(at point: CGPoint, in capture: Capture) -> Double? {
        let x = Int(point.x * capture.scale), y = Int(point.y * capture.scale)
        guard x >= 0, y >= 0, x < capture.width, y < capture.height else { return nil }
        let i = (y * capture.width + x) * 4
        return luminance(capture.pixels[i], capture.pixels[i + 1], capture.pixels[i + 2])
    }

    /// The sRGB colour (0...255 per channel) of the pixel under a screen point, or nil when the point is off the capture.
    static func rgb(at point: CGPoint, in capture: Capture) -> (red: Int, green: Int, blue: Int)? {
        let x = Int(point.x * capture.scale), y = Int(point.y * capture.scale)
        guard x >= 0, y >= 0, x < capture.width, y < capture.height else { return nil }
        let i = (y * capture.width + x) * 4
        return (Int(capture.pixels[i]), Int(capture.pixels[i + 1]), Int(capture.pixels[i + 2]))
    }

    /// WCAG contrast of the text against its surface inside `frame` (screen points), or nil when the
    /// frame is empty or off the capture (then there is no evidence and the issue stays open).
    static func ratio(of frame: CGRect, in capture: Capture) -> Double? {
        guard let rect = pixelRect(of: frame, in: capture) else { return nil }
        var luminances: [Double] = []
        luminances.reserveCapacity(Int(rect.width * rect.height))
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let i = (y * capture.width + x) * 4
                luminances.append(luminance(capture.pixels[i], capture.pixels[i + 1], capture.pixels[i + 2]))
            }
        }
        let sorted = luminances.sorted()
        let surface = sorted[sorted.count / 2]
        // Glyph pixels differ clearly from the surface and the text core is the far tail of that distance. (The upper
        // quartile measured borders and state washes instead once a whole tile became the audited element: 1.4:1 for
        // dark-on-light Hue Sync intensity tiles on iPad, 2026-10-12.)
        let glyphs = luminances.filter { abs($0 - surface) > 0.05 }.sorted { abs($0 - surface) < abs($1 - surface) }
        guard !glyphs.isEmpty else { return 1 }
        let text = glyphs[min(glyphs.count - 1, (glyphs.count * 97) / 100)]
        return (max(text, surface) + 0.05) / (min(text, surface) + 0.05)
    }

    private static func luminance(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double {
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
