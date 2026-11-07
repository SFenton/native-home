#if os(iOS)
import HassDesign
import UIKit

/// The look of ``UKPrimaryButton`` (`PrimaryButtonStyle`): the 50 pt capsule, and its fill and label colours.
@MainActor
public enum UKPrimaryButtonStyle {
    /// The button's height, and twice its corner radius.
    public static let height: CGFloat = PrimaryButtonStyle.height

    /// The fill and label colours: the tint with white, or a family's glyph colour with dark text. Both are fixed, in light and
    /// dark sheets alike (the same values as `PrimaryButtonStyle.colors(_:)`).
    public static func colors(_ family: ColorFamily?) -> (fill: UIColor, label: UIColor) {
        guard let family else { return (UIColor(HassTokens.RGB.Ink.actionFill), .white) }
        return (UIColor(rgb: family.spec.glyph), UIColor(HassTokens.RGB.Ink.onFamilyFill))
    }
}

/// A screen's one primary action (`.agents/design/direction-g.md`, Controls: Primary buttons): a 50 pt capsule filled with
/// G's `#0071E3` and a white label, or a family's colour with dark text. The label wraps and the button grows at large
/// Dynamic Type rather than truncating.
///
/// ```swift
/// let save = UKPrimaryButton("Save") { model.save() }
/// let water = UKPrimaryButton("Start Watering", family: .water, isBusy: sending, busyTitle: "Starting") { start() }
/// save.isEnabled = model.canSave          // dims to 40% with the quick fade
/// ```
///
/// While `isBusy` the label gives way to an arc spinner and the busy title; the button keeps its colour and size and ignores
/// presses; VoiceOver reads the title with value "Busy". Fill it horizontally with constraints (it takes its parent's width).
public final class UKPrimaryButton: UIControl {
    /// The action; runs on touch-up inside unless the button is busy.
    public var action: () -> Void
    public var title: String { didSet { refresh() } }
    public var systemImage: String? { didSet { refresh() } }
    public var family: ColorFamily? { didSet { applyColors(animated: true) } }
    public var busyTitle: String? { didSet { refresh() } }
    public var isBusy: Bool { didSet { if isBusy != oldValue { refresh() } } }

    /// The title shown and spoken while busy.
    public var activeTitle: String { isBusy ? (busyTitle ?? title) : title }

    /// Holds the busy arc still (a UI test launch: a turning arc keeps XCUITest from ever seeing the app idle).
    public var holdsSpinnerStill: Bool {
        get { spinner.isPaused }
        set { spinner.isPaused = newValue }
    }

    private let fill = UIView()
    private let label = UILabel()
    private let icon = UIImageView()
    private let spinner = UKArcSpinnerView(.inline, label: "Loading")
    private let content = UIStackView()
    private var lastColors: (fill: UIColor, label: UIColor)?

    public init(_ title: String, systemImage: String? = nil, family: ColorFamily? = nil, isBusy: Bool = false,
                busyTitle: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.family = family
        self.isBusy = isBusy
        self.busyTitle = busyTitle
        self.action = action
        super.init(frame: .zero)
        build()
        refresh()
        applyColors(animated: false)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func build() {
        fill.isUserInteractionEnabled = false
        addSubview(fill)
        fill.ukPin(to: self)
        label.font = UKFont.preferred(.body, weight: .semibold)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body, scale: .default)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        spinner.setContentHuggingPriority(.required, for: .horizontal)
        spinner.isAccessibilityElement = false
        content.axis = .horizontal
        content.alignment = .center
        content.spacing = HassTokens.Spacing.s
        content.isUserInteractionEnabled = false
        [spinner, icon, label].forEach(content.addArrangedSubview)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        let minHeight = heightAnchor.constraint(greaterThanOrEqualToConstant: UKPrimaryButtonStyle.height)
        NSLayoutConstraint.activate([
            minHeight,
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.topAnchor.constraint(equalTo: topAnchor, constant: HassTokens.Spacing.s),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -HassTokens.Spacing.s),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: HassTokens.Spacing.xl),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -HassTokens.Spacing.xl),
        ])
        fill.layer.cornerCurve = .continuous
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    private func refresh() {
        label.text = activeTitle
        spinner.isHidden = !isBusy
        spinner.accessibilityLabel = activeTitle
        if let systemImage, !isBusy {
            icon.image = UIImage(systemName: systemImage)
            icon.isHidden = false
        } else {
            icon.isHidden = true
        }
        accessibilityLabel = activeTitle
        accessibilityValue = isBusy ? "Busy" : ""
        invalidateIntrinsicContentSize()
    }

    private func applyColors(animated: Bool) {
        let colors = UKPrimaryButtonStyle.colors(family)
        defer { lastColors = colors }
        let apply = { [self] in
            fill.backgroundColor = colors.fill
            label.textColor = colors.label
            icon.tintColor = colors.label
            spinner.color = colors.label
        }
        if animated, lastColors != nil, lastColors?.fill != colors.fill, window != nil { UKMotion.stateColor(apply) } else { apply() }
    }

    @objc private func tapped() {
        if !isBusy { action() }
    }

    public override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            // Enabling or disabling fades with `quick`.
            UKMotion.animate(.quick) { [self] in alpha = currentAlpha }
            accessibilityTraits = isEnabled ? .button : [.button, .notEnabled]
        }
    }

    public override var isHighlighted: Bool {
        didSet { alpha = currentAlpha } // The press dim is immediate.
    }

    private var currentAlpha: CGFloat {
        if !isEnabled { return CGFloat(HassTokens.ControlState.disabledOpacity) }
        return isHighlighted && !isBusy ? CGFloat(HassTokens.ControlState.pressedOpacity) : 1
    }

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !isBusy && super.point(inside: point, with: event)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // The title wraps within the button's width (fixed by its parent), never at its own last width.
        UKWrapWidth.set(label, in: self, reserving: 2 * HassTokens.Spacing.xl + UKWrapWidth.reserved(besides: label, in: content))
        // A capsule, not a fixed radius: a wrapped label makes the button taller than 50 pt, and its ends stay round.
        fill.layer.cornerRadius = bounds.height / 2
    }
}
#endif
