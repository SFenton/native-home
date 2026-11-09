#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The prompt that offers door and camera alerts on Home until it is answered: the UIKit counterpart of
/// ``NotificationPermissionBanner``. It shows while `PushCoordinator.showsPermissionBanner` and hides itself otherwise, so a page
/// can always keep it in its layout (a hidden arranged subview of a stack view takes no room).
final class UKNotificationPermissionBannerView: UIView {
    private let push: PushCoordinator?
    private let bag = UKObservationBag()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let turnOn = UIButton(type: .system)
    private let notNow = UIButton(type: .system)

    init(push: PushCoordinator?) {
        self.push = push
        super.init(frame: .zero)
        // The thin module fill, with the chip radius.
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
        messageLabel.text = NotificationPermissionCopy.message
        let text = UIStackView(arrangedSubviews: [titleLabel, messageLabel])
        text.axis = .vertical
        text.spacing = HassTokens.Spacing.xs
        text.isAccessibilityElement = true
        text.accessibilityIdentifier = "push.banner.text"
        text.accessibilityLabel = "\(NotificationPermissionCopy.title). \(NotificationPermissionCopy.message)"

        var prominent = UIButton.Configuration.borderedProminent()
        prominent.title = NotificationPermissionCopy.turnOn
        prominent.baseBackgroundColor = UIColor(rgb: HassTokens.Palette.tintFill)
        prominent.baseForegroundColor = .white
        turnOn.configuration = prominent
        turnOn.accessibilityIdentifier = "push.banner.turnOn"
        turnOn.addAction(UIAction { [weak self] _ in
            guard let push = self?.push else { return }
            Task { await push.enableNotifications() }
        }, for: .touchUpInside)
        var plain = UIButton.Configuration.bordered()
        plain.title = NotificationPermissionCopy.notNow
        plain.baseForegroundColor = .white
        plain.baseBackgroundColor = UIColor.white.withAlphaComponent(0.2)
        notNow.configuration = plain
        notNow.accessibilityIdentifier = "push.banner.notNow"
        notNow.addAction(UIAction { [weak self] _ in self?.push?.dismissPermissionBanner() }, for: .touchUpInside)
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
            // The text fills the stack's content width (fixed by the host), so the stack's `.leading` alignment (for the buttons)
            // never lets the wrapped text decide the banner's width.
            text.widthAnchor.constraint(equalTo: stack.layoutMarginsGuide.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isAccessibilityElement = false
        accessibilityIdentifier = "push.banner"
        accessibilityContainerType = .semanticGroup
        restyle()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKNotificationPermissionBannerView, _) in view.restyle() }
        bag.observe { [weak self] in
            guard let self else { return }
            self.isHidden = !(self.push?.showsPermissionBanner ?? false)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

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
        text.append(NSAttributedString(string: " " + NotificationPermissionCopy.title))
        text.addAttributes([.font: font, .foregroundColor: UIColor.white], range: NSRange(location: 0, length: text.length))
        titleLabel.attributedText = text
    }
}
#endif
