#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// A status chip (`StatusChipButton`, pattern: `.agents/patterns/status-rail.md`): a capsule with a glyph, a title and a summary,
/// drawn by the Home rail, Security's two chips and the room rails.
///
/// An active chip fills with its family's chip colour (or a computed ``ChipTint``) and a slight top highlight; a neutral one sits on
/// the thin module. A change of colour cross-fades inside the capsule, the glyph and the summary only, so the chip's size (a longer
/// state text) never slides. With no `action` the chip is inert: one static element and no hint.
///
/// ```swift
/// let chip = UKStatusChipView()
/// bag.observe { chip.configure(title: "Lights", summary: "3 On", symbol: "lightbulb.2", family: .lights, isActive: true, tint: nil) { open() } }
/// ```
@MainActor
final class UKStatusChipView: UIControl {
    private let ground = CALayer()
    private let highlight = CAGradientLayer()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private var symbol = ""
    private var fill: ChipTint?
    private var title = ""
    private var summary = ""
    private var hasAction = false
    private var onTap: (() -> Void)?
    /// The size the containers above were last told about (``UIView/ukRemeasureContainers(ifSizeChangedFrom:)``).
    private var measured = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(ground)
        highlight.colors = [UIColor.white.withAlphaComponent(ChipTint.highlight).cgColor, UIColor.clear.cgColor]
        highlight.startPoint = CGPoint(x: 0.5, y: 0)
        highlight.endPoint = CGPoint(x: 0.5, y: 0.5)
        ground.masksToBounds = true
        ground.addSublayer(highlight)
        titleLabel.textColor = .white
        // A chip narrower than its text wraps at word boundaries: never truncated, never scaled (section-sides verdict V1).
        for label in [titleLabel, summaryLabel] {
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
        }
        iconView.contentMode = .center
        for view in [iconView, titleLabel, summaryLabel] as [UIView] {
            view.isAccessibilityElement = false
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            titleLabel.font = UKFont.rowTitle(traitCollection)
            summaryLabel.font = UKFont.preferred(.subheadline, monospacedDigit: true, traits: traitCollection)
            iconView.image = UKFont.symbol(symbol, style: .body, weight: .semibold, filled: fill != nil, traits: traitCollection)
            setNeedsLayout()
            invalidateIntrinsicContentSize()
            ukRemeasureContainers(ifSizeChangedFrom: &measured)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(transparencyChanged),
                                               name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func tapped() { onTap?() }
    @objc private func transparencyChanged() { applyColors(animated: false) }

    /// Shows a chip. The first call never animates; later ones cross-fade the colours.
    /// - Parameters:
    ///   - title: The chip's name.
    ///   - summary: The state under it.
    ///   - symbol: The SF Symbol (filled while the chip is).
    ///   - family: The colour family; nil draws neutral.
    ///   - isActive: Whether the family fill applies.
    ///   - tint: A computed look that wins over `family`.
    ///   - action: What a tap does; nil draws an inert chip.
    func configure(title: String, summary: String, symbol: String, family: ColorFamily?, isActive: Bool, tint: ChipTint?,
                   animated: Bool = true, action: (() -> Void)? = nil) {
        let newFill = StatusChipStyle.fillTint(family, isActive: isActive, tint: tint)
        let colorsChanged = newFill != fill
        let textChanged = title != self.title || summary != self.summary || symbol != self.symbol || (newFill != nil) != (fill != nil)
        self.title = title
        self.summary = summary
        self.symbol = symbol
        fill = newFill
        onTap = action
        hasAction = action != nil
        isUserInteractionEnabled = hasAction
        titleLabel.ukSetWrappedText(title)
        summaryLabel.ukSetWrappedText(summary)
        iconView.image = UKFont.symbol(symbol, style: .body, weight: .semibold, filled: newFill != nil, traits: traitCollection)
        applyColors(animated: animated && colorsChanged && window != nil)
        updateAccessibility()
        if textChanged {
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
        // The rail around the chip measures it again when the chip's size changed.
        ukRemeasureContainers(ifSizeChangedFrom: &measured)
    }

    private func applyColors(animated: Bool) {
        let ink = UIColor(HassTokens.RGB.Surface.secondaryOnModule)
        let groundColor = fill.map { UIColor(rgb: $0.fill) } ?? UKInk.module(.thin, reduceTransparency: UIAccessibility.isReduceTransparencyEnabled)
        UKMotion.stateFade("StatusChip", animated: animated) {
            ground.backgroundColor = groundColor.cgColor
            highlight.opacity = fill == nil ? 0 : 1
        }
        let glyph = fill.map { UIColor(rgb: $0.glyph) } ?? ink
        let text = fill != nil ? UIColor.white : ink
        UKMotion.stateFade("StatusChip", view: iconView, animated: animated) { [iconView] in iconView.tintColor = glyph }
        UKMotion.stateFade("StatusChip", view: summaryLabel, animated: animated) { [summaryLabel] in summaryLabel.textColor = text }
    }

    private func updateAccessibility() {
        isAccessibilityElement = true
        accessibilityLabel = "\(title), \(summary)"
        accessibilityHint = hasAction ? "Opens its details" : nil
        accessibilityTraits = hasAction ? .button : .staticText
    }

    // MARK: Layout

    private func layoutValues(width: CGFloat) -> (size: CGSize, icon: CGRect, title: CGRect, summary: CGRect) {
        let leading = HassTokens.Spacing.m, trailing = HassTokens.Spacing.l
        let icon = iconView.image?.size ?? .zero
        let textX = leading + icon.width + HassTokens.Spacing.s
        let available = max(1, width - textX - trailing)
        let titleSize = titleLabel.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude))
        let summarySize = summaryLabel.sizeThatFits(CGSize(width: available, height: .greatestFiniteMagnitude))
        let textHeight = ceil(titleSize.height) + ceil(summarySize.height)
        let height = max(StatusChipStyle.minHeight, textHeight + 2 * HassTokens.Spacing.xs)
        let textWidth = ceil(min(max(titleSize.width, summarySize.width), available))
        let y = (height - textHeight) / 2
        return (CGSize(width: min(width, textX + textWidth + trailing), height: height),
                CGRect(x: leading, y: (height - icon.height) / 2, width: icon.width, height: icon.height),
                CGRect(x: textX, y: y, width: ceil(titleSize.width), height: ceil(titleSize.height)),
                CGRect(x: textX, y: y + ceil(titleSize.height), width: ceil(summarySize.width), height: ceil(summarySize.height)))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        layoutValues(width: size.width.isFinite && size.width < 100_000 ? size.width : 10_000).size
    }

    override var intrinsicContentSize: CGSize { sizeThatFits(CGSize(width: 10_000, height: 0)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let values = layoutValues(width: bounds.width)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ground.frame = bounds
        ground.cornerRadius = UKChipShape.cornerRadius(height: bounds.height, title: titleLabel.font, summary: summaryLabel.font)
        ground.cornerCurve = .continuous
        highlight.frame = ground.bounds
        CATransaction.commit()
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func place(_ view: UIView, _ rect: CGRect) {
            view.frame = mirror ? CGRect(x: bounds.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height) : rect
        }
        place(iconView, values.icon)
        place(titleLabel, values.title)
        place(summaryLabel, values.summary)
        let alignment: NSTextAlignment = mirror ? .right : .left
        titleLabel.textAlignment = alignment
        summaryLabel.textAlignment = alignment
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Traits (and so fonts) can reach a chip only once it is in a window.
        if window != nil { ukRemeasureContainers(ifSizeChangedFrom: &measured) }
    }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { alpha = isHighlighted ? 0.8 : 1 } }
    }
}

/// The corner radius of a status chip: a chip that wraps keeps the radius of a one-line chip at the current text size, so a tall
/// chip is a rounded rectangle with the same ends as its siblings, not a stadium whose curve clips the first line (section-sides V1).
enum UKChipShape {
    /// - Parameters:
    ///   - height: The chip's height.
    ///   - title: The title's font.
    ///   - summary: The summary's font.
    /// - Returns: `min(height, oneLineHeight) / 2`.
    static func cornerRadius(height: CGFloat, title: UIFont?, summary: UIFont?) -> CGFloat {
        let lines = ceil(title?.lineHeight ?? 0) + ceil(summary?.lineHeight ?? 0)
        let oneLine = max(StatusChipStyle.minHeight, lines + 2 * HassTokens.Spacing.xs)
        return min(height, oneLine) / 2
    }
}
#endif
