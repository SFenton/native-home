#if os(iOS)
import HassDesign
import UIKit

/// A labeled status value with a tone (`StatusPill`, pattern: `.agents/patterns/status-pill.md`). Read-only: VoiceOver reads the
/// label, then the value and detail, as one element.
///
/// ```swift
/// bag.observe { [weak pill] in pill?.configure(label: "Garage", value: store.entity(id).state, symbol: "door.garage.closed", tone: .ok) }
/// ```
@MainActor
final class UKStatusPillView: UIView, UKGridMeasuring {
    private(set) var label: String
    private(set) var value: String
    private(set) var detail: String?
    private(set) var symbol: String
    private(set) var tone: StatusPill.Tone
    private let surface: StatusPill.Surface
    /// The first values have not arrived (`EnvironmentValues.valuesPending`): the value is a muted placeholder, never "Unavailable".
    var valuesPending = false { didSet { if valuesPending != oldValue { refresh(animated: false) } } }

    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let iconView = UIImageView()
    private let labelView = UILabel()
    private let valueView = UILabel()
    private let detailView = UILabel()
    private let pendingBar = UKPendingValueBar()

    init(label: String, value: String, detail: String? = nil, symbol: String, tone: StatusPill.Tone = .neutral, surface: StatusPill.Surface = .page) {
        self.label = label
        self.value = value
        self.detail = detail
        self.symbol = symbol
        self.tone = tone
        self.surface = surface
        super.init(frame: .zero)
        layer.cornerRadius = HassTokens.Radius.chip
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        switch surface {
        case .page: addSubview(blur)
        case .groupedList: backgroundColor = .secondarySystemGroupedBackground
        case .module: break
        }
        iconView.contentMode = .center
        labelView.textColor = UKInk.secondary
        valueView.textColor = UKInk.primary
        detailView.textColor = UKInk.secondary
        for view in [labelView, valueView, detailView] { view.numberOfLines = 0 }
        for view in [iconView, labelView, valueView, detailView, pendingBar] as [UIView] { view.isAccessibilityElement = false; addSubview(view) }
        isAccessibilityElement = true
        ukOnContentSizeChange { [weak self] in self?.refresh(animated: false) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows new values; a tone change cross-fades the icon.
    func configure(label: String, value: String, detail: String? = nil, symbol: String, tone: StatusPill.Tone = .neutral) {
        let toneChanged = tone != self.tone
        self.label = label
        self.value = value
        self.detail = detail
        self.symbol = symbol
        self.tone = tone
        refresh(animated: toneChanged)
    }

    private func refresh(animated: Bool) {
        iconView.image = UKFont.symbol(symbol, style: .body, traits: traitCollection)
        labelView.font = UKFont.preferred(.footnote, traits: traitCollection)
        valueView.font = UKFont.rowTitle(traitCollection, monospacedDigit: true)
        detailView.font = UKFont.preferred(.footnote, traits: traitCollection)
        labelView.text = label
        valueView.text = valuesPending ? nil : value
        valueView.isHidden = valuesPending
        pendingBar.isHidden = !valuesPending
        detailView.text = valuesPending ? nil : detail
        detailView.isHidden = valuesPending || detail == nil
        let color = UIColor(StatusPill.colorToken(valuesPending ? .unavailable : tone))
        if animated, window != nil {
            MotionAudit.noteStateColor("StatusPill")
            UIView.animate(withDuration: UKMotion.stateDuration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) { self.iconView.tintColor = color }
        } else {
            iconView.tintColor = color
        }
        accessibilityLabel = label
        accessibilityValue = valuesPending ? StatusPill.pendingValue : StatusPill.accessibilityValue(value: value, detail: detail)
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    private struct Frames {
        var size: CGSize
        var icon, label, value, detail, pending: CGRect
    }

    private func frames(width: CGFloat) -> Frames {
        let pad = HassTokens.Spacing.m
        let gap = HassTokens.Spacing.s
        let iconSize = iconView.image?.size ?? .zero
        let textWidth = max(1, width - 2 * pad - iconSize.width - gap)
        func height(_ label: UILabel) -> CGFloat {
            ceil(label.sizeThatFits(CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude)).height)
        }
        let labelHeight = height(labelView)
        var y = pad
        let labelFrame = CGRect(x: pad + iconSize.width + gap, y: y, width: textWidth, height: labelHeight)
        y += labelHeight + 2
        var valueFrame = CGRect.zero, pendingFrame = CGRect.zero, detailFrame = CGRect.zero
        if valuesPending {
            let size = pendingBar.sizeThatFits(.zero)
            pendingFrame = CGRect(x: labelFrame.minX, y: y, width: size.width, height: size.height)
            y += size.height
        } else {
            let valueHeight = height(valueView)
            valueFrame = CGRect(x: labelFrame.minX, y: y, width: textWidth, height: valueHeight)
            y += valueHeight
            if detail != nil {
                let detailHeight = height(detailView)
                detailFrame = CGRect(x: labelFrame.minX, y: y + 2, width: textWidth, height: detailHeight)
                y += 2 + detailHeight
            }
        }
        let total = max(y + pad, HassTokens.minTarget)
        // The icon sits on the first text baseline (`HStack(alignment: .firstTextBaseline)`).
        let baseline = labelFrame.minY + labelView.font.ascender
        let iconBaseline = iconView.image?.baselineOffsetFromBottom ?? 0
        let iconFrame = CGRect(x: pad, y: baseline - (iconSize.height - iconBaseline), width: iconSize.width, height: iconSize.height)
        return Frames(size: CGSize(width: width, height: total), icon: iconFrame, label: labelFrame, value: valueFrame, detail: detailFrame, pending: pendingFrame)
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { frames(width: width).size.height }

    override func sizeThatFits(_ size: CGSize) -> CGSize { frames(width: size.width).size }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frames = frames(width: bounds.width)
        blur.frame = bounds
        iconView.frame = frames.icon
        labelView.frame = frames.label
        valueView.frame = frames.value
        detailView.frame = frames.detail
        pendingBar.frame = frames.pending
    }
}
#endif
