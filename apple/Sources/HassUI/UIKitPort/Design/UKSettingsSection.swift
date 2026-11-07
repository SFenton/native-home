#if os(iOS)
import HassDesign
import UIKit

// MARK: - Inline alert

/// A warning or error shown inline under the control it concerns (`InlineAlert`). A warning is primary ink on an orange wash,
/// read as "Warning: …"; an error is red text with no box, read as "Error: …".
final class UKInlineAlertView: UIView {
    typealias Severity = InlineAlert.Severity

    init(_ message: String, symbol: String? = nil, severity: Severity = .warning) {
        super.init(frame: .zero)
        let symbolName = symbol ?? (severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
        let icon = UIImageView()
        icon.isAccessibilityElement = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        let text = UILabel.uk(.subheadline, ink: severity == .error ? UKDesignInk.error : UKDesignInk.primary)
        text.text = message
        let stack = UIStackView(arrangedSubviews: [icon, text])
        stack.axis = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = HassTokens.Spacing.s
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        switch severity {
        case .warning:
            icon.image = UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.body)))
            icon.tintColor = UKDesignInk.warning
            let inset = HassTokens.Spacing.m
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: topAnchor, constant: inset), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            ])
            backgroundColor = UKDesignInk.warning.withAlphaComponent(HassTokens.Wash.alert)
            layer.cornerRadius = HassTokens.Radius.chip
            layer.cornerCurve = .continuous
            accessibilityLabel = "Warning: \(message)"
        case .error:
            icon.image = UIImage(systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.subheadline)))
            icon.tintColor = UKDesignInk.error
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
            accessibilityLabel = "Error: \(message)"
        }
        // SwiftUI's combined alert reads "Warning: …" as one element while its text stays a static text of its own: a labelled
        // group holding the message reproduces both.
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        text.isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Selectable option row

/// One choice in a single-choice list (`SelectableOptionRow`): icon, label and what it does, a checkmark and a 2 pt tint
/// border on the selected one, on a regular material. VoiceOver: a button named by the title with the description as its value,
/// selected when chosen.
final class UKSelectableOptionRow: UIControl {
    private let tint: UIColor
    private let iconView = UIImageView()
    private let titleLabel = UILabel.uk(.headline, ink: UKDesignInk.primary)
    private let detailLabel = UILabel.uk(.subheadline, ink: UKDesignInk.secondary)
    private let check = UIImageView()
    private let border = UIView()
    private let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    var onTap: (() -> Void)?

    var isSelectedChoice: Bool { didSet { restyle(animated: true) } }
    var isDisabled: Bool { didSet { isEnabled = !isDisabled; restyle(animated: false); UKMotion.quick { self.alpha = self.isDisabled ? 0.5 : 1 } } }

    init(title: String, detail: String, symbol: String, tint: UIColor, isSelected: Bool, isDisabled: Bool = false, onTap: (() -> Void)? = nil) {
        self.tint = tint
        isSelectedChoice = isSelected
        self.isDisabled = isDisabled
        self.onTap = onTap
        super.init(frame: .zero)
        let radius = HassTokens.Radius.tile
        material.layer.cornerRadius = radius
        material.layer.cornerCurve = .continuous
        material.clipsToBounds = true
        material.isUserInteractionEnabled = false
        border.layer.cornerRadius = radius
        border.layer.cornerCurve = .continuous
        border.layer.borderWidth = 2
        border.isUserInteractionEnabled = false
        iconView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.title3)))
        iconView.contentMode = .center
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.widthAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        check.image = UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.body, weight: .semibold)))
        check.tintColor = tint
        check.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.text = title
        detailLabel.text = detail
        let texts = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        texts.axis = .vertical
        texts.spacing = HassTokens.Spacing.xs
        let row = UIStackView(arrangedSubviews: [iconView, texts, check])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = HassTokens.Spacing.m
        row.isUserInteractionEnabled = false
        for view in [material, border, row] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let pad = HassTokens.Spacing.m
        NSLayoutConstraint.activate([
            material.topAnchor.constraint(equalTo: topAnchor), material.bottomAnchor.constraint(equalTo: bottomAnchor),
            material.leadingAnchor.constraint(equalTo: leadingAnchor), material.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.topAnchor.constraint(equalTo: topAnchor), border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.leadingAnchor.constraint(equalTo: leadingAnchor), border.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: pad), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad), row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isEnabled = !isDisabled
        alpha = isDisabled ? 0.5 : 1
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityValue = detail
        restyle(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func tapped() { onTap?() }

    private func restyle(animated: Bool) {
        let changes = {
            self.iconView.tintColor = self.isSelectedChoice ? self.tint : UKDesignSurface.secondaryInSheet
            self.border.layer.borderColor = (self.isSelectedChoice ? self.tint : UIColor.clear).cgColor
            self.check.alpha = self.isSelectedChoice ? 1 : 0
        }
        if animated, window != nil { UKMotion.state(changes) } else { changes() }
        var traits: UIAccessibilityTraits = isSelectedChoice ? [.button, .selected] : .button
        // Explicit traits replace the control's own, so a disabled choice names itself ("dimmed") here.
        if !isEnabled { traits.insert(.notEnabled) }
        accessibilityTraits = traits
    }
}

// MARK: - Form text

/// `FormHeader` and `FormFooter` as labels, for a custom form: secondary ink readable on the grouped ground (3.3:1 for the
/// system's), or the wallpaper's 85% ink on a page. Headers carry the heading trait.
@MainActor
enum UKFormText {
    static func header(_ title: String, onWallpaper: Bool = false, style: UIFont.TextStyle = .title3) -> UILabel {
        let label = UILabel.uk(style, weight: .bold, ink: onWallpaper ? UKDesignSurface.secondaryOnWallpaper : UKDesignInk.secondary)
        label.text = title
        label.accessibilityTraits = [.header, .staticText]
        return label
    }

    static func footer(_ text: String, onWallpaper: Bool = false) -> UILabel {
        let label = UILabel.uk(.footnote, ink: onWallpaper ? UKSettingsInk.wallpaperFooter : UKDesignInk.secondary)
        label.text = text
        return label
    }
}

// MARK: - Info box

/// A tinted notice with a title and optional message (`InfoBox.Tone`). Text stays in the primary label colour on a light wash of
/// the tone (green for success, grey for neutral), so it keeps 4.5:1 in both appearances.
final class UKInfoBoxView: UIView {
    typealias Tone = InfoBox.Tone

    init(title: String, message: String? = nil, tone: Tone = .neutral) {
        super.init(frame: .zero)
        let tint = tone == .success ? UKDesignInk.success : UKDesignInk.secondary
        let icon = UIImageView(image: UIImage(systemName: tone == .success ? "checkmark.circle.fill" : "info.circle.fill",
                                              withConfiguration: UIImage.SymbolConfiguration(font: .ukFont(.headline))))
        icon.tintColor = tint
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.isAccessibilityElement = false
        let titleLabel = UILabel.uk(.headline, ink: UKDesignInk.primary)
        titleLabel.text = title
        let heading = UIStackView(arrangedSubviews: [icon, titleLabel])
        heading.axis = .horizontal
        heading.alignment = .firstBaseline
        heading.spacing = HassTokens.Spacing.s
        let stack = UIStackView(arrangedSubviews: [heading])
        stack.axis = .vertical
        stack.spacing = HassTokens.Spacing.xs
        if let message {
            let body = UILabel.uk(.subheadline, ink: UKDesignInk.primary)
            body.text = message
            stack.addArrangedSubview(body)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let inset = HassTokens.Spacing.m
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: inset), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
        ])
        backgroundColor = tint.withAlphaComponent(HassTokens.Wash.notice)
        layer.cornerRadius = HassTokens.Radius.chip
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityLabel = [title, message].compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = .staticText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
