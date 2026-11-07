#if os(iOS)
import HassDesign
import UIKit

/// What a tile's surface is made of: the ground, a level band, the sheen and the hairline, as plain colours. The UIKit counterpart
/// of `TintedGlassGround`, `TintedGlassSheen`, `TintedGlassRim` and `GlassTileFace.solidGround`: the same decisions, drawn with
/// layers (``UKGlassTileFaceView``).
///
/// All colours are resolved for one trait collection, so the paint is plain values that compare and cache.
struct UKTilePaint: Equatable {
    /// A flat colour, or a vertical gradient.
    struct Fill: Equatable {
        var top: UIColor
        var bottom: UIColor?

        static func flat(_ color: UIColor) -> Fill { Fill(top: color, bottom: nil) }
    }

    /// A band from the leading edge as wide as `fraction` of the tile.
    struct Band: Equatable {
        var fill: Fill
        var fraction: Double
    }

    /// The top highlight and bottom shade over the ground.
    enum Sheen: Equatable {
        case none
        /// Tinted glass: a white highlight at the top fading to clear at ``TileFinish/Tokens/sheenClearStop`` and a black shade at the bottom.
        case glass(top: Double, bottom: Double)
        /// The solid finish's faint white highlight from the top to the centre.
        case solidHighlight(opacity: Double)
    }

    /// The 1 pt hairline.
    enum Rim: Equatable {
        case none
        /// White, lit at the top.
        case lit(top: Double, bottom: Double)
        /// One colour (a light sheet's separator).
        case solid(UIColor)
    }

    var ground: Fill
    /// A band over the ground from the leading edge.
    var band: Band?
    /// A shade over the part of a white-ink filled face that progress has not reached, from the trailing edge.
    var shade: (color: UIColor, fraction: Double)?
    var sheen: Sheen
    var rim: Rim
    /// The tinted face's 1 pt stroke in the caller's tint.
    var stroke: UIColor?

    static func == (lhs: UKTilePaint, rhs: UKTilePaint) -> Bool {
        lhs.ground == rhs.ground && lhs.band == rhs.band && lhs.sheen == rhs.sheen && lhs.rim == rhs.rim && lhs.stroke == rhs.stroke
            && lhs.shade?.color == rhs.shade?.color && lhs.shade?.fraction == rhs.shade?.fraction
    }
}

/// The inputs that decide a tile's paint.
struct UKTilePaintInput {
    var style: TileFaceStyle
    var surface: TileSurface
    var appearance: TileAppearance
    var finish: TileFinish
    var tint: UIColor
    /// The tint made legible as a glyph on the appearance (the stroke's colour).
    var tintGlyph: UIColor
    var wash: UIColor?
    var level: Double?
    var levelTint: UIColor?
    var isEnabled: Bool
    var isUnavailable: Bool
    var reduceTransparency: Bool
    var traits: UITraitCollection
    /// The read-only face draws no sheen, hairline or tint stroke.
    var isFlat = false
}

extension UKTilePaint {
    /// The paint for a tile.
    static func make(_ input: UKTilePaintInput) -> UKTilePaint {
        let traits = input.traits
        func resolve(_ color: UIColor) -> UIColor { color.resolvedColor(with: traits) }
        let style = input.style
        let tokens = TileFinish.Tokens.tintedGlass(on: input.surface)
        let glass = input.finish != .solid
        var paint = UKTilePaint(ground: .flat(.clear), band: nil, shade: nil, sheen: .none, rim: .none, stroke: nil)

        /// A band as wide as the level (or `fallback` when there is none).
        func band(default fallback: Double? = nil, _ fill: Fill) -> Band? {
            guard let level = input.level ?? fallback, level > 0 else { return nil }
            return Band(fill: fill, fraction: min(1, level))
        }
        /// The dark ground of an off, tinted or error face.
        func neutral(dense: Bool) -> UIColor {
            switch input.surface {
            case .sheet: return resolve(UKInk.sheetCell)
            case .page:
                if glass {
                    return dense ? UIColor.ukRGB(HassTokens.Palette.moduleDense, 0.78) : UIColor.ukRGB(HassTokens.Palette.moduleThin, tokens.underlay)
                }
                return UKInk.module(dense ? .dense : .thin, reduceTransparency: input.reduceTransparency)
            }
        }
        /// A lit tile's band over its base.
        func litBand() -> Band? {
            var top = UIColor(LitTile.bandTopToken), bottom = UIColor(LitTile.bandBottomToken)
            if let levelTint = input.levelTint {
                let overlay = resolve(levelTint).ukOpacity(LitTile.bulbTint)
                top = resolve(overlay).ukOver(top)
                bottom = resolve(overlay).ukOver(bottom)
            }
            return band(default: 1, Fill(top: top, bottom: bottom))
        }
        /// A white-ink family or room fill: the colour over the dark underlay at the finish's opacity (opaque in a sheet).
        func tinted(_ fill: UInt32) -> UIColor {
            if glass, input.surface == .page, tokens.fillOpacity < 1 {
                return UIColor.ukRGB(fill, tokens.fillOpacity).ukOver(.ukRGB(HassTokens.Palette.moduleThin, tokens.fillUnderlay))
            }
            return .ukRGB(fill)
        }

        switch style {
        case .off, .tinted, .error:
            var ground = neutral(dense: style == .error)
            if let wash = input.wash { ground = resolve(wash).ukOpacity(input.appearance.washOpacity).ukOver(ground) }
            paint.ground = .flat(ground)
            paint.band = band(.flat(resolve(input.levelTint ?? input.tint).ukOpacity(0.32)))
        case .lit:
            paint.ground = .flat(UIColor(LitTile.baseToken))
            paint.band = litBand()
        case let .colored(rgb):
            paint.ground = .flat(glass ? tinted(rgb) : .ukRGB(rgb))
        case let .filled(family):
            let fill = family.spec.fill ?? 0xFFD60A
            if family.spec.darkInk {
                paint.ground = Fill(top: UIColor(LitTile.powerTopToken), bottom: .ukRGB(fill))
                if let level = input.level, level > 0 {
                    paint.band = Band(fill: .flat(UIColor.white.withAlphaComponent(TileFaceStyle.progressLighten)), fraction: min(1, level))
                }
            } else {
                paint.ground = .flat(glass ? tinted(fill) : .ukRGB(fill))
                if let level = input.level, level > 0 {
                    paint.shade = (UIColor.black.withAlphaComponent(TileFaceStyle.progressShade), 1 - min(1, level))
                }
            }
        }

        // The sheen and hairline.
        if glass {
            let bareLightCell = input.surface == .sheet && input.appearance == .light && !style.isFilledOrLit
            if !bareLightCell, !input.isFlat, !TileFinish.omitted.contains("sheen") {
                // A room's or Quick Link's fill in a sheet gets only the bottom shade, never a highlight.
                let highlight = !(input.surface == .sheet && style.isColored)
                paint.sheen = .glass(top: highlight ? tokens.sheenTop : 0, bottom: tokens.sheenBottom)
            }
            if !input.isFlat, !TileFinish.omitted.contains("rim") {
                let onLightCell = input.appearance == .light && !style.isFilledOrLit
                paint.rim = onLightCell ? .solid(resolve(UKInk.separator)) : .lit(top: tokens.rimTop, bottom: tokens.rimBottom)
            }
        } else if case let .filled(family) = style, !family.spec.darkInk {
            // The slight top highlight from the mockups.
            paint.sheen = .solidHighlight(opacity: 0.10)
        }
        if style == .tinted, !input.isFlat {
            paint.stroke = resolve(input.tintGlyph).ukOpacity(input.isEnabled ? 0.5 : 0.25).ukOpacity(input.isUnavailable ? 0.5 : 1)
        }
        // The dynamic wrappers `ukOpacity` makes resolve here, once.
        paint.stroke = paint.stroke.map { $0.resolvedColor(with: traits) }
        return paint
    }
}

// MARK: - Finish image

/// The sheen, hairline and tint stroke of a tile, drawn once as one translucent image and cached by size: a grid of equal tiles
/// shares a handful of images, and a tile never redraws them while it scrolls (performance.md: layers are real cost on a page
/// of 120 tiles; direction-g.md, Layers: no live blur).
@MainActor
enum UKTileFinishImage {
    private struct Key: Hashable {
        var width: Int
        var height: Int
        var scale: Int
        var radius: Int
        var sheen: String
        var rim: String
        var stroke: String
    }

    private static var cache: [Key: UIImage] = [:]

    /// The image for a tile of `size`, or nil when the paint has no sheen, hairline or stroke.
    static func image(size: CGSize, scale: CGFloat, radius: CGFloat, paint: UKTilePaint) -> UIImage? {
        if paint.sheen == .none, paint.rim == .none, paint.stroke == nil { return nil }
        guard size.width > 1, size.height > 1 else { return nil }
        let key = Key(width: Int((size.width * scale).rounded()), height: Int((size.height * scale).rounded()), scale: Int(scale * 100),
                      radius: Int(radius * 100), sheen: "\(paint.sheen)", rim: "\(paint.rim)", stroke: paint.stroke.map { "\($0.ukRGBA)" } ?? "")
        if let image = cache[key] { return image }
        let image = render(size: CGSize(width: CGFloat(key.width) / scale, height: CGFloat(key.height) / scale), scale: scale, radius: radius, paint: paint)
        if cache.count > 64 { cache.removeAll() }
        cache[key] = image
        return image
    }

    private static func format(_ scale: CGFloat) -> UIGraphicsImageRendererFormat {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return format
    }

    /// A black continuous rounded rectangle (alpha only), the shape every part is cut from.
    private static func shape(size: CGSize, scale: CGFloat, inset: CGFloat, radius: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: size, format: format(scale)).image { context in
            let layer = CALayer()
            // `render(in:)` draws a layer at its own origin, so the inset is a translation.
            layer.frame = CGRect(origin: .zero, size: CGSize(width: size.width - 2 * inset, height: size.height - 2 * inset))
            context.cgContext.translateBy(x: inset, y: inset)
            layer.cornerRadius = max(0, radius - inset)
            layer.cornerCurve = .continuous
            layer.backgroundColor = UIColor.black.cgColor
            layer.render(in: context.cgContext)
        }
    }

    private static func gradient(_ stops: [(UIColor, CGFloat)]) -> CGGradient {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGGradient(colorsSpace: space, colors: stops.map { $0.0.cgColor } as CFArray, locations: stops.map { $0.1 })
            ?? CGGradient(colorsSpace: space, colors: [UIColor.clear.cgColor, UIColor.clear.cgColor] as CFArray, locations: [0, 1])!
    }

    /// `paint` over the shape `mask` as a source-in fill.
    private static func fill(_ mask: UIImage, size: CGSize, scale: CGFloat, with draw: (CGContext) -> Void) -> UIImage {
        UIGraphicsImageRenderer(size: size, format: format(scale)).image { context in
            mask.draw(in: CGRect(origin: .zero, size: size))
            context.cgContext.setBlendMode(.sourceIn)
            draw(context.cgContext)
        }
    }

    private static func render(size: CGSize, scale: CGFloat, radius: CGFloat, paint: UKTilePaint) -> UIImage {
        let rect = CGRect(origin: .zero, size: size)
        let outer = shape(size: size, scale: scale, inset: 0, radius: radius)
        var layers: [UIImage] = []

        switch paint.sheen {
        case .none: break
        case let .glass(top, bottom):
            let clearStop = CGFloat(TileFinish.Tokens.sheenClearStop)
            // Premultiplied interpolation by hand: white fading to clear, then clear fading to black.
            let g = gradient([(UIColor.white.withAlphaComponent(top), 0), (UIColor.white.withAlphaComponent(0), clearStop),
                              (UIColor.black.withAlphaComponent(0), clearStop), (UIColor.black.withAlphaComponent(bottom), 1)])
            layers.append(fill(outer, size: size, scale: scale) { $0.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: []) })
        case let .solidHighlight(opacity):
            let g = gradient([(UIColor.white.withAlphaComponent(opacity), 0), (UIColor.white.withAlphaComponent(0), 1)])
            layers.append(fill(outer, size: size, scale: scale) {
                $0.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height / 2), options: [.drawsAfterEndLocation])
            })
        }

        // The ring: the shape minus the shape inset by the line width (`strokeBorder`).
        let needsRing = paint.rim != .none || paint.stroke != nil
        if needsRing {
            let inner = shape(size: size, scale: scale, inset: 1, radius: radius)
            let ring = UIGraphicsImageRenderer(size: size, format: format(scale)).image { _ in
                outer.draw(in: rect)
                inner.draw(in: rect, blendMode: .destinationOut, alpha: 1)
            }
            switch paint.rim {
            case .none: break
            case let .lit(top, bottom):
                let g = gradient([(UIColor.white.withAlphaComponent(top), 0), (UIColor.white.withAlphaComponent(bottom), 1)])
                layers.append(fill(ring, size: size, scale: scale) { $0.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: []) })
            case let .solid(color):
                layers.append(fill(ring, size: size, scale: scale) { $0.setFillColor(color.cgColor); $0.fill(rect) })
            }
            if let stroke = paint.stroke {
                layers.append(fill(ring, size: size, scale: scale) { $0.setFillColor(stroke.cgColor); $0.fill(rect) })
            }
        }

        return UIGraphicsImageRenderer(size: size, format: format(scale)).image { _ in
            for layer in layers { layer.draw(in: rect) }
        }
    }
}
#endif
