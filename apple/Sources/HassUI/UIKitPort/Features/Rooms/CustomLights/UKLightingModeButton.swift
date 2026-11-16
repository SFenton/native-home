#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// Reports an intent that became unsafe while its menu or confirmation was open.
@MainActor
enum UKCustomLightsFailure {
    static func report() {
        NSLog("Custom lights action failed or its source became unavailable")
        UIAccessibility.post(notification: .announcement, argument: "Couldn't change lights. Check the connection and try again.")
    }
}

// MARK: - Lighting Mode row

/// The Lighting Mode row: palette icon, then the mode's swatch and name in the tint with the pop-up chevrons (`LightingModeButton`,
/// web `modeSelect`). A pop-up menu of the modes showing the current one (HIG, Pop-up buttons): no sheet and no plain chevron. A
/// `UIButton` whose primary action is the menu, drawn as a module row with the pressed highlight of ``UKRowButton``.
@MainActor
final class UKLightingModeButton: UIButton {
    private let row: UKRowView
    private let highlightView = UIView()
    private let swatchHolder = UIView()
    private var swatchView: UKGradientSwatch?
    private var swatchColors: [UIColor] = []
    private let modeLabel = UILabel.uk(.body, ink: UKInk.action)
    private var mode = ""
    private let label: String
    private let select: (String) -> Void

    init(title: String = CustomLightsConfig.lightingModeTitle, select: @escaping (String) -> Void) {
        label = title
        self.select = select
        let chevron = UIImageView(image: UIImage(systemName: "chevron.up.chevron.down",
                                                 withConfiguration: UIImage.SymbolConfiguration(font: UKFont.footnoteEmphasis())))
        chevron.tintColor = UKInk.action
        chevron.contentMode = .center
        chevron.isAccessibilityElement = false
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        swatchHolder.setContentHuggingPriority(.required, for: .horizontal)
        swatchHolder.setContentCompressionResistancePriority(.required, for: .horizontal)
        swatchHolder.isAccessibilityElement = false
        modeLabel.isAccessibilityElement = false
        let accessory = UIStackView(arrangedSubviews: [swatchHolder, modeLabel, chevron])
        accessory.axis = .horizontal
        accessory.alignment = .center
        accessory.spacing = HassTokens.Spacing.s
        accessory.isUserInteractionEnabled = false
        row = UKRowView(UKRowContent(title, symbol: "paintpalette"), accessory: accessory)
        super.init(frame: .zero)
        highlightView.backgroundColor = UKDesignInk.primary
        highlightView.alpha = 0
        highlightView.isUserInteractionEnabled = false
        row.isUserInteractionEnabled = false
        for view in [highlightView, row] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            view.ukPin(to: self)
        }
        showsMenuAsPrimaryAction = true
        isAccessibilityElement = true
        accessibilityIdentifier = "customLights.mode"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the mode, its swatch and the modes the select offers.
    func configure(mode: String, swatch: [CustomLightsConfig.RGB], modes: [String]) {
        self.mode = mode
        modeLabel.text = mode
        setSwatch(swatch.map(UIColor.init(lightRGB:)))
        let actions = modes.map { option in
            UIAction(title: option, state: option == mode ? .on : .off) { [weak self] _ in self?.select(option) }
        }
        // An inline `Picker` in a `Menu`: the modes as one group titled for the setting.
        menu = UIMenu(title: label, options: .displayInline, children: actions)
    }

    private func setSwatch(_ colors: [UIColor]) {
        guard colors != swatchColors else { return }
        swatchColors = colors
        let replace = {
            self.swatchView?.removeFromSuperview()
            self.swatchView = nil
            if !colors.isEmpty {
                let view = UKGradientSwatch(colors: colors)
                view.translatesAutoresizingMaskIntoConstraints = false
                self.swatchHolder.addSubview(view)
                view.ukPin(to: self.swatchHolder)
                self.swatchView = view
            }
            self.swatchHolder.isHidden = colors.isEmpty
        }
        // The swatch's colours follow state (`stateColorTransition`).
        if swatchHolder.window != nil {
            UKMotion.stateFade("LightingModeButton", view: swatchHolder, animated: true, replace)
        } else {
            replace()
        }
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            if isHighlighted {
                highlightView.alpha = 0.10
            } else {
                UKMotion.quick { self.highlightView.alpha = 0 }
            }
        }
    }

    override var accessibilityLabel: String? {
        get { label }
        set {}
    }

    override var accessibilityValue: String? {
        get { mode }
        set {}
    }

    override var accessibilityHint: String? {
        get { "Shows the lighting modes." }
        set {}
    }

    override var accessibilityTraits: UIAccessibilityTraits {
        get { .button }
        set {}
    }
}

extension UIColor {
    /// A Home Assistant `rgb_color` (`Color.init(rgb:)`).
    convenience init(lightRGB rgb: CustomLightsConfig.RGB) {
        self.init(red: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }
}
#endif
