#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Art

/// The app icon's art (``AppIconArtwork``, standard appearance) drawn with Core Graphics: the dusk glow, the pair's tint across the
/// whole square, a top light, and the house with the heart on its cut-out ring. The paths and the glow's numbers are the SwiftUI
/// view's own (``AppIconArtwork/house``, ``AppIconArtwork/Standard``), so a preview can never differ from the icon it stands for.
final class UKAppIconArtworkView: UIView {
    private let tint: UInt32
    private let tintOpacity: Double
    private let glyph: UInt32

    init(tint: UInt32, tintOpacity: Double, glyph: UInt32) {
        self.tint = tint
        self.tintOpacity = tintOpacity
        self.glyph = glyph
        super.init(frame: .zero)
        isOpaque = true
        backgroundColor = .black
        contentMode = .redraw
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let side = min(bounds.width, bounds.height)
        guard side > 0 else { return }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let square = CGRect(x: 0, y: 0, width: side, height: side)
        context.saveGState()
        context.clip(to: square)

        // The 165 degree gradient: the corners take the end colours.
        let angle = 165.0 * Double.pi / 180
        let direction = CGVector(dx: sin(angle), dy: -cos(angle))
        let length = side * (abs(sin(angle)) + abs(cos(angle)))
        let middle = CGPoint(x: side / 2, y: side / 2)
        let stops = AppIconArtwork.Standard.background
        if let gradient = CGGradient(colorsSpace: space, colors: stops.map { UIColor(rgb: $0.color).cgColor } as CFArray,
                                     locations: stops.map { CGFloat($0.location) }) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: middle.x - direction.dx * length / 2, y: middle.y - direction.dy * length / 2),
                end: CGPoint(x: middle.x + direction.dx * length / 2, y: middle.y + direction.dy * length / 2),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        // The two glows: `radial-gradient(circle at X Y, colour, transparent P%)`.
        for glow in AppIconArtwork.Standard.glows {
            let color = UIColor(red: glow.red, green: glow.green, blue: glow.blue, alpha: glow.opacity)
            let reach = side * hypot(max(glow.x, 1 - glow.x), max(glow.y, 1 - glow.y)) * glow.reach
            if let gradient = CGGradient(colorsSpace: space, colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) {
                context.drawRadialGradient(gradient, startCenter: CGPoint(x: side * glow.x, y: side * glow.y), startRadius: 0,
                                           endCenter: CGPoint(x: side * glow.x, y: side * glow.y), endRadius: reach, options: [])
            }
        }
        // The tint across the whole square, then the top light: white at 18% fading to nothing by 46% of the height.
        context.setFillColor(UIColor(rgb: tint, alpha: tintOpacity).cgColor)
        context.fill(square)
        if let light = CGGradient(colorsSpace: space, colors: [UIColor(white: 1, alpha: 0.18).cgColor, UIColor(white: 1, alpha: 0).cgColor,
                                                              UIColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 0.46, 1]) {
            context.drawLinearGradient(light, start: .zero, end: CGPoint(x: 0, y: side), options: [])
        }

        // The glyph: 80% of the icon's width, centred, in 100-unit coordinates.
        let box = side * AppIconArtwork.glyphFraction
        let unit = box / 100
        let place = CGAffineTransform(translationX: (side - box) / 2, y: (side - box) / 2).scaledBy(x: unit, y: unit)
        var heartTransform = CGAffineTransform(translationX: 55, y: 60).scaledBy(x: 0.40, y: 0.40).concatenating(place)
        guard let heart = AppIconArtwork.heart.cgPath.copy(using: &heartTransform) else { context.restoreGState(); return }
        let stroked = heart.copy(strokingWithWidth: 16 * 0.40 * unit, lineCap: .butt, lineJoin: .round, miterLimit: 10)
        let ring = stroked.union(heart)
        var houseTransform = place
        let house = AppIconArtwork.house.cgPath.copy(using: &houseTransform)
        let glyphColor = UIColor(rgb: glyph).cgColor
        // The house with the ring's outline cut out of it, so the ring is the glass itself.
        context.saveGState()
        let cut = CGMutablePath()
        cut.addRect(square.insetBy(dx: -side, dy: -side))
        cut.addPath(ring)
        context.addPath(cut)
        context.clip(using: .evenOdd)
        if let house {
            context.addPath(house)
            context.setFillColor(glyphColor)
            context.fillPath(using: .evenOdd)
        }
        context.restoreGState()
        context.addPath(heart)
        context.setFillColor(glyphColor)
        context.fillPath()
        context.restoreGState()
    }
}

/// A small copy of an app icon (``AppIconPreview``): the art clipped to the system's icon corner radius, with a hairline so
/// the edge reads on a white sheet as on a dark one. Decorative.
final class UKAppIconPreviewView: UIView {
    /// The Home Screen icon's corner radius as a fraction of its side.
    static let cornerFraction = AppIconPreview.cornerFraction

    init(choice: AppIconChoice, side: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: side, height: side))
        let art = UKAppIconArtworkView(tint: choice.tint, tintOpacity: AppIconChoice.tintOpacity, glyph: choice.glyph)
        art.frame = bounds
        art.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(art)
        layer.cornerRadius = side * Self.cornerFraction
        layer.cornerCurve = .continuous
        clipsToBounds = true
        let hairline = UIView()
        hairline.isUserInteractionEnabled = false
        hairline.frame = bounds
        hairline.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hairline.layer.cornerRadius = side * Self.cornerFraction
        hairline.layer.cornerCurve = .continuous
        hairline.layer.borderWidth = 0.5
        hairline.layer.borderColor = UIColor.label.withAlphaComponent(0.14).cgColor
        addSubview(hairline)
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: UKAppIconPreviewView, _) in
            view.subviews.last?.layer.borderColor = UIColor.label.withAlphaComponent(0.14).resolvedColor(with: view.traitCollection).cgColor
        }
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Choice cell

#endif
