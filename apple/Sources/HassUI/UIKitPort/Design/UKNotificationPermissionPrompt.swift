#if os(iOS)
import HassDesign
import UIKit

// MARK: - Value/closure notification prompt

/// Canonical banner over explicit copy and user intents; no account, entity or permission reads.
class UKNotificationPermissionPromptView: UIView {
    struct Copy: Equatable {
        let title: String
        let message: String
        let enable: String
        let dismiss: String
    }

    private var copy: Copy
    var onEnable: () -> Void
    var onDismiss: () -> Void
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let turnOn = UIButton(type: .system)
    private let notNow = UIButton(type: .system)
    private let text = UIStackView()

    init(copy: Copy, onEnable: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.copy = copy
        self.onEnable = onEnable
        self.onDismiss = onDismiss
        super.init(frame: .zero)
        let module = UKModuleView(.thin, cornerRadius: HassTokens.Radius.chip)
        module.isUserInteractionEnabled = false
        module.isAccessibilityElement = false
        addSubview(module)
        module.ukPin(to: self)
        layer.cornerRadius = HassTokens.Radius.chip
        layer.cornerCurve = .continuous
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.font = UKShellFont.preferred(.subheadline)
        messageLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        messageLabel.text = copy.message
        [titleLabel, messageLabel].forEach(text.addArrangedSubview)
        text.axis = .vertical
        text.spacing = HassTokens.Spacing.xs
        text.isAccessibilityElement = true
        text.accessibilityIdentifier = "push.banner.text"
        text.accessibilityLabel = "\(copy.title). \(copy.message)"

        var prominent = UIButton.Configuration.borderedProminent()
        prominent.title = copy.enable
        prominent.baseBackgroundColor = UIColor(rgb: HassTokens.Palette.tintFill)
        prominent.baseForegroundColor = .white
        turnOn.configuration = prominent
        turnOn.accessibilityIdentifier = "push.banner.turnOn"
        turnOn.addAction(UIAction { [weak self] _ in self?.onEnable() }, for: .touchUpInside)
        var plain = UIButton.Configuration.bordered()
        plain.title = copy.dismiss
        plain.baseForegroundColor = .white
        plain.baseBackgroundColor = UIColor.white.withAlphaComponent(0.2)
        notNow.configuration = plain
        notNow.accessibilityIdentifier = "push.banner.notNow"
        notNow.addAction(UIAction { [weak self] _ in self?.onDismiss() }, for: .touchUpInside)
        for button in [turnOn, notNow] { button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true }

        let stack = UIStackView(arrangedSubviews: [text, turnOn, notNow])
        stack.axis = .vertical
        stack.spacing = HassTokens.Spacing.s
        stack.alignment = .leading
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: HassTokens.Spacing.m, leading: HassTokens.Spacing.m,
                                                                 bottom: HassTokens.Spacing.m, trailing: HassTokens.Spacing.m)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            text.widthAnchor.constraint(equalTo: stack.layoutMarginsGuide.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        accessibilityIdentifier = "push.banner"
        accessibilityContainerType = .semanticGroup
        restyle()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKNotificationPermissionPromptView, _) in view.restyle() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Reuses native controls and AX identities while copy changes; pending requests disable both actions.
    func apply(copy: Copy, busy: Bool) {
        if self.copy != copy {
            self.copy = copy
            messageLabel.text = copy.message
            text.accessibilityLabel = "\(copy.title). \(copy.message)"
            turnOn.configuration?.title = copy.enable
            notNow.configuration?.title = copy.dismiss
            restyle()
        }
        turnOn.isEnabled = !busy
        notNow.isEnabled = !busy
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        UKWrapWidth.set([titleLabel, messageLabel], in: self, reserving: 2 * HassTokens.Spacing.m)
    }

    private func restyle() {
        let font = UKShellFont.preferred(.headline, traits: traitCollection)
        let attachment = NSTextAttachment()
        attachment.image = UIImage(systemName: "bell.badge.fill", withConfiguration: UIImage.SymbolConfiguration(font: font))?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        let text = NSMutableAttributedString(attachment: attachment)
        text.append(NSAttributedString(string: " " + copy.title))
        text.addAttributes([.font: font, .foregroundColor: UIColor.white], range: NSRange(location: 0, length: text.length))
        titleLabel.attributedText = text
    }
}
#endif
