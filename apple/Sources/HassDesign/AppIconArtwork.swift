import SwiftUI

/// The app icon's art: full-bleed tinted glass over a dusk glow, with a house and a heart on it (owner mockups of
/// 2026-10-17, `Pairs.dc.html`, corrected the same day: the inset tile and its frame were mockup presentation, so the
/// glass covers the whole square, "B · Full-Bleed" in each pair's colours; 100-unit glyph coordinates).
///
/// This one view is the source of truth: `tools/render_app_icons.sh` renders the asset catalog's 1024 pt PNGs from it,
/// and the Settings → App Icon picker draws it as the preview, so the two cannot drift. It is full-bleed and square: iOS
/// applies the corner mask and Liquid Glass adds its own edge, so the art draws no rounded corners and no hairline (HIG App
/// icons: provide unmasked layers). Callers that show it as a tile clip it themselves.
///
/// Layers, bottom to top: the dusk glow (a 165 degree gradient and two radial glows, so a faint warmth shows through),
/// the pair's tint across the whole square, a top light, the house (a four-pane window cut out) and the heart on a ring.
/// The glyph is 80% of the icon's width, centred (owner, 2026-10-17); the ring is the glass itself, the house with the
/// ring's outline cut out of it, so it matches the glass around it wherever the glow shifts the colour.
///
/// Three appearances follow HIG App icons, "Appearances" (default, dark and tinted Home Screen icons): the standard art; a
/// dark one, the same art with a deeper tint over a darker glow ("base dark on light ... no excessive brightness"); and a
/// tinted one, a greyscale of the same elements that the system colours with the user's tint.
public struct AppIconArtwork: View {
    /// The Home Screen appearance being drawn.
    public enum Appearance: Sendable {
        /// The default (light) icon.
        case standard
        /// The dark icon: a deeper dusk, the same tile and glyph.
        case dark
        /// The tinted icon: opaque greyscale, with a bright glyph the system tints.
        case tinted
    }

    private let tint: UInt32
    private let tintOpacity: Double
    private let glyph: UInt32
    private let appearance: Appearance

    /// Creates the art.
    /// - Parameters:
    ///   - tint: The glass tile's tint, `0xRRGGBB`.
    ///   - tintOpacity: Its opacity over the glow.
    ///   - glyph: The house and heart colour, `0xRRGGBB`.
    ///   - appearance: Which Home Screen appearance to draw.
    public init(tint: UInt32, tintOpacity: Double = 0.86, glyph: UInt32, appearance: Appearance = .standard) {
        self.tint = tint
        self.tintOpacity = tintOpacity
        self.glyph = glyph
        self.appearance = appearance
    }

    public var body: some View {
        Canvas { context, size in
            var context = context
            draw(in: &context, side: min(size.width, size.height))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, side s: CGFloat) {
        let colors = palette
        drawGround(in: &context, colors: colors, side: s)

        // The glyph: 80% of the icon's width, centred, in 100-unit coordinates.
        let box = s * Self.glyphFraction
        let unit = box / 100
        let place = CGAffineTransform(translationX: (s - box) / 2, y: (s - box) / 2).scaledBy(x: unit, y: unit)
        // The heart sits at (55, 60) at 0.40 scale, inside a ring of the same shape stroked 16 units wide. The ring is the
        // glass itself: the house is drawn with the ring's outline cut out of it, so the ring is whatever colour the glass
        // has there (glow, tint and light) and no second layer of tint is stacked on it.
        let heart = Self.heart.applying(CGAffineTransform(translationX: 55, y: 60).scaledBy(x: 0.40, y: 0.40).concatenating(place))
        let ring = heart.strokedPath(StrokeStyle(lineWidth: 16 * 0.40 * unit, lineJoin: .round)).union(heart)
        context.drawLayer { layer in
            layer.clip(to: ring, options: .inverse)
            layer.fill(Self.house.applying(place), with: .color(colors.glyph), style: FillStyle(eoFill: true))
        }
        context.fill(heart, with: .color(colors.glyph))
    }

    /// The glyph's width as a fraction of the icon's (owner, 2026-10-17).
    public static let glyphFraction: CGFloat = 0.80

    /// The glass: the dusk glow, the tint over the whole square and the top light.
    private func drawGround(in context: inout GraphicsContext, colors: Palette, side s: CGFloat) {
        drawBackground(in: &context, colors: colors, side: s)
        let square = Path(CGRect(x: 0, y: 0, width: s, height: s))
        context.fill(square, with: .color(colors.tile.opacity(colors.tileOpacity)))
        // The top light: white at 18% fading to nothing by 46% of the height.
        context.fill(square, with: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0.18), location: 0), .init(color: .white.opacity(0), location: 0.46)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: s)))
    }

    /// The dusk glow: a 165° diagonal gradient with an amber glow low right and a paler one low left.
    private func drawBackground(in context: inout GraphicsContext, colors: Palette, side s: CGFloat) {
        let square = Path(CGRect(x: 0, y: 0, width: s, height: s))
        // CSS `linear-gradient(165deg, ...)`: the gradient line passes through the centre at 165° clockwise from up, and is
        // long enough that the corners take the end colours.
        let angle = 165.0 * .pi / 180
        let direction = CGVector(dx: sin(angle), dy: -cos(angle))
        let length = s * (abs(sin(angle)) + abs(cos(angle)))
        let middle = CGPoint(x: s / 2, y: s / 2)
        context.fill(square, with: .linearGradient(
            Gradient(stops: colors.background),
            startPoint: CGPoint(x: middle.x - direction.dx * length / 2, y: middle.y - direction.dy * length / 2),
            endPoint: CGPoint(x: middle.x + direction.dx * length / 2, y: middle.y + direction.dy * length / 2)))
        // CSS `radial-gradient(circle at X Y, colour, transparent P%)`: P% of the distance to the farthest corner.
        for glow in colors.glows {
            let reach = s * hypot(max(glow.x, 1 - glow.x), max(glow.y, 1 - glow.y)) * glow.reach
            context.fill(square, with: .radialGradient(
                Gradient(colors: [glow.color, glow.color.opacity(0)]),
                center: CGPoint(x: s * glow.x, y: s * glow.y), startRadius: 0, endRadius: reach))
        }
    }

    // MARK: - Palettes

    /// The standard appearance's dusk glow, shared with the UIKit port's drawing of the same art (`UKAppIconArtworkView`).
    public enum Standard {
        /// The 165 degree gradient's stops.
        public static let background: [(color: UInt32, location: Double)] = [(0x23324D, 0), (0x4B4A52, 0.48), (0x7A5E3A, 1)]
        /// The two radial glows: centre and reach as fractions of the side, colour in sRGB.
        public static let glows: [(x: CGFloat, y: CGFloat, reach: CGFloat, red: Double, green: Double, blue: Double, opacity: Double)] = [
            (0.74, 0.80, 0.42, 1, 184 / 255, 102 / 255, 0.55),
            (0.22, 0.72, 0.36, 1, 214 / 255, 150 / 255, 0.32),
        ]
    }

    private struct Glow {
        var x: CGFloat
        var y: CGFloat
        var reach: CGFloat
        var color: Color
    }

    private struct Palette {
        var background: [Gradient.Stop]
        var glows: [Glow]
        var tile: Color
        var tileOpacity: Double
        var glyph: Color
    }

    private var palette: Palette {
        switch appearance {
        case .standard:
            Palette(
                background: Standard.background.map { .init(color: Color(rgb: $0.color), location: $0.location) },
                glows: Standard.glows.map { Glow(x: $0.x, y: $0.y, reach: $0.reach, color: Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.opacity)) },
                tile: Color(rgb: tint), tileOpacity: tintOpacity, glyph: Color(rgb: glyph))
        case .dark:
            // The same art one stop deeper: a near-black dusk with the glows held back, so the glass tile still reads.
            Palette(
                background: [.init(color: Color(rgb: 0x0C121E), location: 0), .init(color: Color(rgb: 0x1B1B20), location: 0.48),
                             .init(color: Color(rgb: 0x33271A), location: 1)],
                glows: [Glow(x: 0.74, y: 0.80, reach: 0.42, color: Color(.sRGB, red: 1, green: 184 / 255, blue: 102 / 255, opacity: 0.26)),
                        Glow(x: 0.22, y: 0.72, reach: 0.36, color: Color(.sRGB, red: 1, green: 214 / 255, blue: 150 / 255, opacity: 0.14))],
                tile: Color(rgb: tint), tileOpacity: 0.92, glyph: Color(rgb: glyph))
        case .tinted:
            // Greyscale for the system's tint: dark ground, mid-grey glass, near-white glyph (the system maps luminance to
            // the tint, so the glyph is the brightest thing).
            Palette(
                background: [.init(color: Color(rgb: 0x2A2A2C), location: 0), .init(color: Color(rgb: 0x161617), location: 0.48),
                             .init(color: Color(rgb: 0x3A3A3C), location: 1)],
                glows: [Glow(x: 0.74, y: 0.80, reach: 0.42, color: Color(.sRGB, white: 0.55, opacity: 0.40)),
                        Glow(x: 0.22, y: 0.72, reach: 0.36, color: Color(.sRGB, white: 0.7, opacity: 0.2))],
                tile: Color(.sRGB, white: 0.16), tileOpacity: 0.82, glyph: Color(.sRGB, white: 0.96))
        }
    }

    // MARK: - Geometry (100-unit glyph coordinates)

    /// The house with its four-pane window cut out (even-odd fill).
    public nonisolated static let house: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 50, y: 12))
        path.addLine(to: CGPoint(x: 90, y: 44))
        path.addQuadCurve(to: CGPoint(x: 89, y: 47), control: CGPoint(x: 92, y: 46))
        path.addLine(to: CGPoint(x: 82, y: 47))
        path.addLine(to: CGPoint(x: 82, y: 84))
        path.addQuadCurve(to: CGPoint(x: 78, y: 88), control: CGPoint(x: 82, y: 88))
        path.addLine(to: CGPoint(x: 22, y: 88))
        path.addQuadCurve(to: CGPoint(x: 18, y: 84), control: CGPoint(x: 18, y: 88))
        path.addLine(to: CGPoint(x: 18, y: 47))
        path.addLine(to: CGPoint(x: 11, y: 47))
        path.addQuadCurve(to: CGPoint(x: 10, y: 44), control: CGPoint(x: 8, y: 46))
        path.closeSubpath()
        for (x, y) in [(25.0, 59.0), (37.0, 59.0), (25.0, 71.0), (37.0, 71.0)] {
            path.addRect(CGRect(x: x, y: y, width: 9.5, height: 9.5))
        }
        return path
    }()

    /// The heart, drawn in a 100-unit box before it is scaled to 0.40 and moved to (55, 60).
    public nonisolated static let heart: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 50, y: 88))
        path.addCurve(to: CGPoint(x: 8, y: 34), control1: CGPoint(x: 20, y: 66), control2: CGPoint(x: 8, y: 50))
        path.addCurve(to: CGPoint(x: 32, y: 10), control1: CGPoint(x: 8, y: 20), control2: CGPoint(x: 19, y: 10))
        path.addCurve(to: CGPoint(x: 50, y: 21), control1: CGPoint(x: 40, y: 10), control2: CGPoint(x: 46, y: 14))
        path.addCurve(to: CGPoint(x: 68, y: 10), control1: CGPoint(x: 54, y: 14), control2: CGPoint(x: 60, y: 10))
        path.addCurve(to: CGPoint(x: 92, y: 34), control1: CGPoint(x: 81, y: 10), control2: CGPoint(x: 92, y: 20))
        path.addCurve(to: CGPoint(x: 50, y: 88), control1: CGPoint(x: 92, y: 50), control2: CGPoint(x: 80, y: 66))
        path.closeSubpath()
        return path
    }()
}
