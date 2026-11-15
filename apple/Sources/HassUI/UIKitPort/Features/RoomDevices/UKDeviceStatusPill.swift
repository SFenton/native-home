#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// A labelled reading with a tone glyph (`DeviceStatusPill`; web `StatusPill`), on the sheet's cell colour. At accessibility sizes the
/// icon sits above the text, giving the value the pill's full width.
@MainActor
final class UKDeviceStatusPill: UIView, UKGridMeasuring {
    private let icon = UIImageView()
    private let titleLabel = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
    private let valueLabel = UILabel.uk(.subheadline, weight: .semibold, monospacedDigit: true, ink: UKDesignInk.primary)
    private let content = UIStackView()
    private var item: HumidifierController.InfoItem

    init(item: HumidifierController.InfoItem) {
        self.item = item
        super.init(frame: .zero)
        backgroundColor = UKDesignSurface.sheetCell
        layer.cornerRadius = HassTokens.Radius.tile
        layer.cornerCurve = .continuous
        icon.contentMode = .center
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        let texts = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        texts.axis = .vertical
        texts.spacing = 2
        content.addArrangedSubview(icon)
        content.addArrangedSubview(texts)
        addSubview(content)
        content.ukPin(to: self, insets: UIEdgeInsets(top: HassTokens.Spacing.m, left: HassTokens.Spacing.m, bottom: HassTokens.Spacing.m, right: HassTokens.Spacing.m))
        heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
        isAccessibilityElement = true
        apply(animated: false)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKDeviceStatusPill, _) in view.apply(animated: false) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(_ next: HumidifierController.InfoItem) {
        guard next != item else { return }
        item = next
        apply(animated: true)
    }

    private func apply(animated: Bool) {
        let stacked = traitCollection.isAccessibilitySize
        content.axis = stacked ? .vertical : .horizontal
        // Stacked, the texts take the pill's full width (a leading alignment sized them from their own wrap width, 24 pt, a letter a line).
        content.alignment = stacked ? .fill : .center
        icon.contentMode = stacked ? .left : .center
        content.spacing = stacked ? HassTokens.Spacing.s : HassTokens.Spacing.s
        icon.image = UIImage(systemName: SymbolMap.symbol(for: item.icon), withConfiguration: UIImage.SymbolConfiguration(font: UKFont.preferred(.body)))
        titleLabel.text = item.title
        valueLabel.text = item.value
        let tint = Self.color(item.tone)
        if animated { UKMotion.stateFade("DeviceStatusPill", view: icon, animated: true) { [icon] in icon.tintColor = tint } } else { icon.tintColor = tint }
        accessibilityLabel = item.title
        accessibilityValue = item.value
        accessibilityIdentifier = "humidifier.info.\(item.title)"
    }

    static func color(_ tone: HumidifierController.InfoItem.Tone) -> UIColor {
        switch tone {
        case .ok: UIColor(ColorFamily.occupancy.glyphToken)
        case .active: UIColor(ColorFamily.water.glyphToken)
        case .warning: UKInk.warning
        case .danger: UKInk.danger
        case .neutral: UKDesignInk.secondary
        case .unavailable: UIColor(HassTokens.RGB.Ink.unavailable)
        }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        ceil(systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                     withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
    }
}
#endif
