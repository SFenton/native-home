#if os(iOS)
import HassCore
import UIKit

// MARK: - Symbol part

/// One SF Symbol drawn on its own (`sh.symbol-part@1`): a size that scales with Dynamic Type, a rendering, a tint for a monochrome one, the
/// trim of its leading ink and a turn in degrees.
///
/// It takes the symbol's name, not the rule that chose it: the renderer resolves the rule from state and calls ``show(name:)``, so a change of
/// state is one image swap. A name this device cannot draw is replaced before it gets here (``ServerUISymbolFallback``). An `image` part is a
/// VoiceOver image with its label; a `hidden` one is skipped.
@MainActor
final class UKSymbolPartView: UIView, UKStackMeasuring {
    private let imageView = UIImageView()
    /// The symbol name drawn now.
    private(set) var name = ""
    /// How many times the image was built, for tests that a tick which changes nothing builds none.
    private(set) var drawCount = 0
    /// The part drawn now.
    private(set) var applied: ServerUISymbolPart?
    private var appliedLabel: String?
    private var appliedOnce = false
    private var size = ServerUISymbolPart.Size(points: 17)
    private var rendering = ServerUISymbolPart.Rendering.monochrome
    private var trim = ServerUISymbolPart.Trim.none
    private(set) var degrees = 0.0
    private var inset: CGFloat = 0

    /// The size the symbol is drawn at now, after Dynamic Type, for tests and for a caller that needs it.
    private(set) var drawnPoints: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        isUserInteractionEnabled = false
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKSymbolPartView, _) in
            view.redraw()
            view.ukRemeasureContainers(includingSelf: true)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Draws the part's fixed fields; the name follows with ``show(name:)``.
    func apply(_ value: ServerUISymbolPart, label: String?) {
        // An observation tick that changes neither the part nor its label draws nothing again.
        if applied == value, appliedLabel == label, appliedOnce { return }
        applied = value
        appliedLabel = label
        appliedOnce = true
        size = value.size
        rendering = value.rendering
        trim = value.trim
        imageView.tintColor = value.tint.map(UKStyledText.color) ?? .label
        switch value.accessibility {
        case .hidden:
            isAccessibilityElement = false
            accessibilityLabel = nil
        case .image:
            isAccessibilityElement = true
            accessibilityTraits = .image
            accessibilityLabel = label
        }
        redraw()
    }

    /// Shows the symbol `name`.
    func show(name: String) {
        guard name != self.name else { return }
        self.name = name
        redraw()
        ukRemeasureContainers(includingSelf: true)
    }

    /// Turns the symbol by `degrees`, clockwise. A turn is a state, not a movement, so it is not animated.
    func turn(by degrees: Double) {
        guard degrees != self.degrees else { return }
        self.degrees = degrees
        imageView.transform = CGAffineTransform(rotationAngle: CGFloat(degrees * .pi / 180))
    }

    /// The point size at the person's text size: scaled as `relativeTo` is, and never more than `maxScale` times the authored size.
    private func points() -> CGFloat {
        guard let relativeTo = size.relativeTo else { return CGFloat(size.points) }
        let scaled = UIFontMetrics(forTextStyle: UKStyledText.textStyle(relativeTo)).scaledValue(for: CGFloat(size.points), compatibleWith: traitCollection)
        return size.maxScale.map { min(scaled, CGFloat(size.points * $0)) } ?? scaled
    }

    private func redraw() {
        drawCount += 1
        drawnPoints = points()
        var configuration = UIImage.SymbolConfiguration(pointSize: drawnPoints, weight: .regular)
        if rendering == .multicolor { configuration = configuration.applying(UIImage.SymbolConfiguration.preferringMulticolor()) }
        let image = name.isEmpty ? nil : UIImage(systemName: name, withConfiguration: configuration)
        imageView.image = rendering == .monochrome ? image?.withRenderingMode(.alwaysTemplate) : image
        inset = trim == .leading ? image.map { UKSymbolInk.leadingInset(of: $0, name: name, points: drawnPoints) } ?? 0 : 0
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        guard let image = imageView.image else { return CGSize(width: drawnPoints, height: drawnPoints) }
        return CGSize(width: ceil(image.size.width - inset), height: ceil(image.size.height))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    override func layoutSubviews() {
        super.layoutSubviews()
        let natural = imageView.image?.size ?? .zero
        // The drawn width sits on the leading edge of whatever the page gives this view; inside a stack the two are the same.
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let drawn = max(0, natural.width - inset)
        let midX = rtl ? bounds.width - drawn / 2 : drawn / 2
        let center = CGPoint(x: midX - (rtl ? -inset : inset) / 2, y: bounds.midY)
        let transform = imageView.transform
        imageView.transform = .identity
        imageView.bounds = CGRect(origin: .zero, size: natural)
        imageView.center = center
        imageView.transform = transform
    }

    var stackNaturalWidth: CGFloat { intrinsicContentSize.width }
    var stackFillsWidth: Bool { false }
    var stackShrinks: Bool { false }
}

extension UKSymbolPartView: UKGridMeasuring {
    func gridHeight(forWidth width: CGFloat) -> CGFloat { intrinsicContentSize.height }
}

// MARK: - Leading ink

/// The empty space before a symbol's ink, measured once for each name and size (`trim: leading`), so symbols of different widths line up.
@MainActor
enum UKSymbolInk {
    private static var memo: [String: CGFloat] = [:]

    /// The points between the image's leading edge and its first inked column.
    static func leadingInset(of image: UIImage, name: String, points: CGFloat) -> CGFloat {
        let key = "\(name)@\(points)"
        if let known = memo[key] { return known }
        let scale: CGFloat = 4
        let width = Int(ceil(image.size.width * scale)), height = Int(ceil(image.size.height * scale))
        guard width > 0, height > 0, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let cgImage = image.cgImage else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) as UnsafeMutablePointer<UInt8>? else { return 0 }
        var first = width
        for column in 0..<width where first == width {
            for row in 0..<height where data[row * width + column] > 8 { first = column; break }
        }
        let inset = first == width ? 0 : CGFloat(first) / scale
        memo[key] = inset
        return inset
    }
}
#endif
