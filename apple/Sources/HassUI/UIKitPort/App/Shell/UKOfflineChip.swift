#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// "Offline. Showing last known values." under the header while no network path exists: the UIKit counterpart of
/// ``OfflineChip`` and its overlay ``OfflineOverlay``. A dense dark capsule with a 0.5 pt rim, read as one element.
final class UKOfflineChipView: UIView {
    private let icon = UIImageView()
    private let label = UILabel()
    private let stack = UIStackView()
    private let module = UKModuleView(.dense, cornerRadius: 0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        // The dense module fill; the capsule radius follows the height.
        module.isUserInteractionEnabled = false
        module.isAccessibilityElement = false
        addSubview(module)
        module.ukPin(to: self)
        layer.borderColor = UIColor.white.withAlphaComponent(0.14).cgColor
        layer.borderWidth = 0.5
        icon.tintColor = UIColor.white.withAlphaComponent(0.85)
        icon.isAccessibilityElement = false
        label.text = "Offline. Showing last known values."
        label.textColor = .white
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        stack.axis = .horizontal
        stack.spacing = HassTokens.Spacing.s
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: HassTokens.Spacing.s, leading: HassTokens.Spacing.m,
                                                                 bottom: HassTokens.Spacing.s, trailing: HassTokens.Spacing.m)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = "Offline. Showing last known values."
        accessibilityIdentifier = "offline.chip"
        restyle()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKOfflineChipView, _) in view.restyle() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Wraps the text at `width` (the widest the chip may be). The chip's width comes from its text, so a label that wrapped at
    /// its own last width would feed back into the width it is given: on the folded Duo, rotating back to portrait, that loop
    /// ran inside the rotation's animation until the watchdog ended the app (owner, 2026-10-31).
    func setMaxWidth(_ width: CGFloat) {
        let text = max(0, width - stack.directionalLayoutMargins.leading - stack.directionalLayoutMargins.trailing
                       - stack.spacing - (icon.image?.size.width ?? 0)).rounded(.down)
        if label.preferredMaxLayoutWidth != text { label.preferredMaxLayoutWidth = text }
    }

    private func restyle() {
        let font = UKShellFont.preferred(.footnote, weight: .semibold, traits: traitCollection)
        label.font = font
        icon.image = UIImage(systemName: "icloud.slash", withConfiguration: UIImage.SymbolConfiguration(font: font))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layer.cornerCurve = .continuous
        module.moduleCornerRadius = bounds.height / 2
    }
}

/// Shows ``UKOfflineChipView`` over the shell while the connection says there is no network path, and says so
/// (`Announcer`). The chip hangs `headerEnd` + 4 pt from the top of the window and 16 pt from the trailing edge, fading in and
/// dropping from the top (Reduce Motion: a cross-fade).
@MainActor
final class UKOfflineOverlay {
    private weak var host: UIView?
    private let chip = UKOfflineChipView()
    private var topConstraint: NSLayoutConstraint?
    private var isShown = false
    private var announced: Bool?

    private var constraints: [NSLayoutConstraint] = []

    /// The chip joins `host` only while it shows (or is animating out): a hidden chip that stayed in the shell's layout, still
    /// offset by its exit transform, took part in a layout loop that ran through the folded Duo's rotation back to portrait until
    /// the watchdog ended the app (owner, 2026-10-31).
    init(host: UIView) {
        self.host = host
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.alpha = 0
        let top = chip.topAnchor.constraint(equalTo: host.topAnchor, constant: HassTokens.Spacing.xs)
        topConstraint = top
        constraints = [
            top,
            chip.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -HassTokens.Spacing.l),
            chip.leadingAnchor.constraint(greaterThanOrEqualTo: host.leadingAnchor, constant: HassTokens.Spacing.l),
        ]
    }

    /// The host's width changed: the chip's text wraps within it (``UKOfflineChipView/setMaxWidth(_:)``).
    func hostLaidOut() {
        guard let host, chip.superview != nil else { return }
        chip.setMaxWidth(host.bounds.width - 2 * HassTokens.Spacing.l)
    }

    /// `headerEnd` is where the header ends in the window (``UKShellEnvironment/headerEdgeCap``).
    func update(isOffline: Bool, headerEnd: CGFloat, reduceMotion: Bool) {
        topConstraint?.constant = headerEnd + HassTokens.Spacing.xs
        if let announced, announced != isOffline { Announcer.announce(Self.announcement(isOffline: isOffline)) }
        announced = isOffline
        guard isOffline != isShown else { return }
        isShown = isOffline
        guard let host else { return }
        if isOffline, chip.superview == nil {
            chip.transform = .identity
            host.addSubview(chip)
            NSLayoutConstraint.activate(constraints)
            hostLaidOut()
        }
        guard chip.superview != nil else { return }
        host.layoutIfNeeded()
        let hidden = CGAffineTransform(translationX: 0, y: reduceMotion ? 0 : -(headerEnd + chip.bounds.height))
        if isOffline {
            chip.transform = hidden
            chip.alpha = 0
        }
        let animations = {
            self.chip.alpha = isOffline ? 1 : 0
            self.chip.transform = isOffline ? .identity : hidden
        }
        let finish: (Bool) -> Void = { _ in
            guard !self.isShown else { return }
            NSLayoutConstraint.deactivate(self.constraints)
            self.chip.removeFromSuperview()
            self.chip.transform = .identity
        }
        if reduceMotion {
            UIView.animate(withDuration: MotionTokens.crossFadeDuration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: animations, completion: finish)
        } else {
            UIView.animate(springDuration: MotionTokens.standardDuration, bounce: 0, options: [.allowUserInteraction], animations: animations, completion: finish)
        }
    }

    /// What VoiceOver hears when the connection goes offline or comes back.
    static func announcement(isOffline: Bool) -> String {
        OfflineOverlay.announcement(isOffline: isOffline)
    }
}
#endif
