import XCTest

/// Samples a screenshot for the plain base colour that shows where the wallpaper does not reach (`.agents/patterns/page-backdrop.md`
/// R7), shared by ``WallpaperJourneyTests`` and ``SinglePageMotionJourneyTests`` (mid-push). Run the app with
/// `FENTON_BACKDROP_FIXTURE=1`: the fixture photo stays several times brighter than the base under every scrim stop.
@MainActor
enum WallpaperSampling {
    /// How far (0-255, per channel) a sample may sit from the plain base under the scrim and still count as plain.
    static let plainTolerance = 3
    /// Points in from the window's edge, clear of the antialiased rim.
    static let edgeInset: CGFloat = 4
    /// The base color's channels (`HouseBackdropStyle.base`, `#111723`).
    static let base = [17.0, 23.0, 35.0]
    /// The scrim's black opacity by fraction of the window height (`HouseBackdropStyle.scrimStops`).
    static let scrim: [(location: Double, opacity: Double)] = [(0, 0.44), (0.28, 0.45), (0.50, 0.46), (0.75, 0.52), (1, 0.64)]

    /// The plain base color under the scrim at `fraction` of the window's height: what shows where there is no photo.
    static func plain(atFraction fraction: Double) -> [Double] {
        let f = min(max(fraction, 0), 1)
        var opacity = scrim[scrim.count - 1].opacity
        for (low, high) in zip(scrim, scrim.dropFirst()) where f <= high.location {
            opacity = low.opacity + (high.opacity - low.opacity) * (f - low.location) / (high.location - low.location)
            break
        }
        return base.map { $0 * (1 - opacity) }
    }

    /// The window's corners and edge midpoints, in screen points.
    static func samplePoints(of window: CGRect) -> [(name: String, point: CGPoint)] {
        let inset = edgeInset
        let (minX, maxX, minY, maxY) = (window.minX + inset, window.maxX - inset, window.minY + inset, window.maxY - inset)
        return [
            ("top-left", CGPoint(x: minX, y: minY)), ("top", CGPoint(x: window.midX, y: minY)),
            ("top-right", CGPoint(x: maxX, y: minY)), ("left", CGPoint(x: minX, y: window.midY)),
            ("right", CGPoint(x: maxX, y: window.midY)), ("bottom-left", CGPoint(x: minX, y: maxY)),
            ("bottom", CGPoint(x: window.midX, y: maxY)), ("bottom-right", CGPoint(x: maxX, y: maxY)),
        ]
    }

    /// The samples of `points` (the window's by default) that show the plain base, with their colour. The fixture photo is far
    /// brighter, so only a dark page element, such as a full-bleed recipe photo, could come close, and it would not match the base to
    /// within a few levels.
    static func uncovered(in app: XCUIApplication, points: ((CGRect) -> [(name: String, point: CGPoint)])? = nil) -> [String] {
        let window = app.windows.firstMatch.frame
        guard let capture = RenderedContrast.Capture.screen() else { return ["no capture"] }
        return (points ?? samplePoints(of:))(window).compactMap { name, point in
            let x = Int(point.x * capture.scale), y = Int(point.y * capture.scale)
            guard x >= 0, y >= 0, x < capture.width, y < capture.height else { return "\(name) off the capture" }
            let i = (y * capture.width + x) * 4
            let pixel = [Double(capture.pixels[i]), Double(capture.pixels[i + 1]), Double(capture.pixels[i + 2])]
            let expected = plain(atFraction: (point.y - window.minY) / window.height)
            let isPlain = zip(pixel, expected).allSatisfy { abs($0 - $1) <= Double(plainTolerance) }
            return isPlain ? "\(name) rgb \(pixel.map { Int($0) })" : nil
        }
    }
}
