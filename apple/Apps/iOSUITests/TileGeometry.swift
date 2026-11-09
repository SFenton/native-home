import XCTest

/// Where a tile's ink sits, read from a screenshot. A tile is one accessibility element and its glyph and chevron are
/// hidden from VoiceOver, so XCUITest cannot ask for their frames; the pixels are the evidence (owner, 2026-10-16:
/// "chevrons vertically centred", "title and subtitle feel too high up").
@MainActor
enum TileGeometry {
    typealias RGB = (r: Int, g: Int, b: Int)

    /// The colour under a screen point, or nil when it is off the capture.
    static func rgb(at point: CGPoint, in capture: RenderedContrast.Capture) -> RGB? {
        let x = Int(point.x * capture.scale), y = Int(point.y * capture.scale)
        guard x >= 0, y >= 0, x < capture.width, y < capture.height else { return nil }
        let i = (y * capture.width + x) * 4
        return (Int(capture.pixels[i]), Int(capture.pixels[i + 1]), Int(capture.pixels[i + 2]))
    }

    /// The bounding box, in screen points, of the pixels inside `region` that differ from `background` by more than
    /// `threshold` (summed over the three channels), or nil when none do.
    static func inkBounds(in region: CGRect, background: RGB, threshold: Int = 150,
                          capture: RenderedContrast.Capture) -> CGRect? {
        let scale = capture.scale
        let minX = max(0, Int(region.minX * scale)), maxX = min(capture.width, Int(region.maxX * scale))
        let minY = max(0, Int(region.minY * scale)), maxY = min(capture.height, Int(region.maxY * scale))
        guard minX < maxX, minY < maxY else { return nil }
        var left = Int.max, right = -1, top = Int.max, bottom = -1
        for y in minY..<maxY {
            for x in minX..<maxX {
                let i = (y * capture.width + x) * 4
                let delta = abs(Int(capture.pixels[i]) - background.r) + abs(Int(capture.pixels[i + 1]) - background.g)
                    + abs(Int(capture.pixels[i + 2]) - background.b)
                guard delta > threshold else { continue }
                left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard right >= 0 else { return nil }
        return CGRect(x: CGFloat(left) / scale, y: CGFloat(top) / scale,
                      width: CGFloat(right - left + 1) / scale, height: CGFloat(bottom - top + 1) / scale)
    }

    /// Whether `colour` is within `tolerance` of `0xRRGGBB` on every channel.
    static func matches(_ colour: RGB, _ hex: UInt32, tolerance: Int = 8) -> Bool {
        abs(colour.r - Int((hex >> 16) & 0xFF)) <= tolerance && abs(colour.g - Int((hex >> 8) & 0xFF)) <= tolerance
            && abs(colour.b - Int(hex & 0xFF)) <= tolerance
    }

    /// The colour a tinted glass tile draws for a flat family or room fill (`0xRRGGBB`) at a fraction of its height
    /// (`.agents/design/direction-g.md`, Tile finish): the fill itself in a sheet, and 78% over the dark underlay on the page
    /// (the wallpaper behind is taken as mid grey, so allow the page's tolerance), then the sheen's bottom shade, a black
    /// gradient from clear at 46% of the height to 8% at the bottom edge. Valid below the middle of the tile, where the
    /// highlight is gone.
    static func glass(_ hex: UInt32, onPage: Bool, heightFraction: Double) -> RGB {
        func channel(_ shift: UInt32) -> Double {
            let fill = Double((hex >> shift) & 0xFF)
            let module = Double(0x1C)
            let base = onPage ? fill * 0.78 + (1 - 0.78) * (module * 0.5 + 65 * 0.5) : fill
            let shade = 0.08 * max(0, heightFraction - 0.46) / 0.54
            return base * (1 - shade)
        }
        return (Int(channel(16).rounded()), Int(channel(8).rounded()), Int(channel(0).rounded()))
    }

    /// Whether `colour` is the tinted glass rendering of `hex` at `heightFraction` of a tile's height (``glass``). The page
    /// allows for the unknown wallpaper behind the translucent fill.
    static func matchesGlass(_ colour: RGB, _ hex: UInt32, onPage: Bool = false, heightFraction: Double) -> Bool {
        let expected = glass(hex, onPage: onPage, heightFraction: heightFraction)
        let tolerance = onPage ? 16 : 8
        return abs(colour.r - expected.r) <= tolerance && abs(colour.g - expected.g) <= tolerance && abs(colour.b - expected.b) <= tolerance
    }

    /// The chevron's ink inside a tile: the trailing 32 pt, clear of the tile's rounded corners (top and bottom 14 pt).
    /// - Parameters:
    ///   - frame: The tile's frame in screen points.
    ///   - capture: A capture of the screen the tile is on.
    /// - Returns: The chevron's bounding box, or nil when none is drawn. The tile must have a flat fill.
    static func chevron(in frame: CGRect, capture: RenderedContrast.Capture) -> CGRect? {
        guard let background = rgb(at: CGPoint(x: frame.maxX - 18, y: frame.minY + 6), in: capture) else { return nil }
        let region = CGRect(x: frame.maxX - 32, y: frame.minY + 14, width: 28, height: frame.height - 28)
        return inkBounds(in: region, background: background, capture: capture)
    }

    /// The glyph and text ink inside a flat-filled tile, clear of the chevron column.
    static func content(in frame: CGRect, capture: RenderedContrast.Capture, reservesChevron: Bool = true) -> CGRect? {
        // Clear of the rounded corners and the lit rim (inside them the capture shows the page behind, which reads as ink).
        let region = CGRect(x: frame.minX + 14, y: frame.minY + 8,
                            width: frame.width - 28 - (reservesChevron ? 22 : 0), height: frame.height - 16)
        // Tinted glass shades the tile top to bottom (white highlight, black shade), so one background sample near the
        // bottom reads the highlight as ink. Each row is compared with the fill beside the region in that same row.
        let scale = capture.scale
        let sampleX = region.maxX + 2
        let minY = max(0, Int(region.minY * scale)), maxY = min(capture.height, Int(region.maxY * scale))
        let minX = max(0, Int(region.minX * scale)), maxX = min(capture.width, Int(region.maxX * scale))
        guard minX < maxX, minY < maxY, let _ = rgb(at: CGPoint(x: sampleX, y: region.minY), in: capture) else { return nil }
        var left = Int.max, right = -1, top = Int.max, bottom = -1
        for y in minY..<maxY {
            guard let background = rgb(at: CGPoint(x: sampleX, y: CGFloat(y) / scale), in: capture) else { continue }
            for x in minX..<maxX {
                let i = (y * capture.width + x) * 4
                let delta = abs(Int(capture.pixels[i]) - background.r) + abs(Int(capture.pixels[i + 1]) - background.g)
                    + abs(Int(capture.pixels[i + 2]) - background.b)
                guard delta > 150 else { continue }
                left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard right >= 0 else { return nil }
        return CGRect(x: CGFloat(left) / scale, y: CGFloat(top) / scale,
                      width: CGFloat(right - left + 1) / scale, height: CGFloat(bottom - top + 1) / scale)
    }
}
