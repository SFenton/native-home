#if os(iOS)
import HassCore
import HassDesign
import Observation
import UIKit

// MARK: - Clock

/// The one-second clock behind a live countdown (`TimelineView(.periodic(by: 1))`): it ticks only while some observation asks for it, so a
/// tile with nothing to count down costs no timer. Read `now` inside an observation while ``setRunning(_:)`` is true.
@MainActor
@Observable
final class UKRoomsClock {
    private(set) var now = Date()
    @ObservationIgnored private var timer: Timer?

    /// Starts or stops the second tick.
    func setRunning(_ running: Bool) {
        if running, timer == nil {
            now = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.now = Date() }
            }
        } else if !running {
            timer?.invalidate()
            timer = nil
        }
    }

    deinit { MainActor.assumeIsolated { timer?.invalidate() } }
}

/// The signed-in household member and whether they administer the house (`householdViewer`, `householdViewerIsAdmin`).
@MainActor
@Observable
final class UKRoomsViewer {
    var resident: HouseholdResident?
    var isAdmin = false
}

// MARK: - Grid remeasuring

extension UKDynamicGridView {
    /// Measures every tile again, up through the grids and columns around this one: a tile whose text now wraps differently changed its
    /// height, and a grid keeps its measured tracks until told.
    func remeasure() {
        var view: UIView? = self
        while let current = view {
            if let grid = current as? UKDynamicGridView { grid.invalidateMeasure() }
            current.setNeedsLayout()
            view = current.superview
        }
    }
}

extension UIView {
    /// Tells the grids above that this view's height may have changed.
    func ukHeightMayHaveChanged() {
        var view = superview
        while let current = view {
            if let grid = current as? UKDynamicGridView { grid.remeasure(); return }
            view = current.superview
        }
    }
}

// MARK: - Status chip

/// A status chip (`StatusChipButton`): a capsule with a glyph, the title over the state, filled in its family's chip colour while active
/// and on the thin module otherwise. Chips with an action are buttons ("Opens its details"); an inert chip is a single element.
@MainActor
final class UKRoomChipView: UIControl {
    private let ground = UKModuleView(.thin, cornerRadius: StatusChipStyle.minHeight / 2)
    private let tintGround = UIView()
    private let highlight = CAGradientLayer()
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private var symbol = ""
    private var tint: ChipTint?
    private var handler: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        ground.isUserInteractionEnabled = false
        tintGround.isUserInteractionEnabled = false
        tintGround.clipsToBounds = true
        tintGround.layer.cornerCurve = .continuous
        highlight.colors = [UIColor.white.withAlphaComponent(ChipTint.highlight).cgColor, UIColor.clear.cgColor]
        highlight.startPoint = CGPoint(x: 0.5, y: 0)
        highlight.endPoint = CGPoint(x: 0.5, y: 0.5)
        tintGround.layer.addSublayer(highlight)
        icon.contentMode = .center
        icon.isUserInteractionEnabled = false
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        summaryLabel.numberOfLines = 0
        for label in [titleLabel, summaryLabel] { label.isUserInteractionEnabled = false }
        [ground, tintGround, icon, titleLabel, summaryLabel].forEach(addSubview)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        ukOnContentSizeChange { [weak self] in self?.restyleFonts() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the chip.
    /// - Parameter action: nil draws an inert chip, which is not a button.
    func configure(title: String, summary: String, symbol: String, family: ColorFamily?, isActive: Bool, tint: ChipTint?,
                   action: (() -> Void)?, animated: Bool = true) {
        let fill = StatusChipStyle.fillTint(family, isActive: isActive, tint: tint)
        let sizeChanged = titleLabel.text != title || summaryLabel.text != summary || self.symbol != symbol
        UKMotion.stateFade("StatusChip", view: self, animated: animated) { [self] in
            titleLabel.text = title
            summaryLabel.text = summary
            self.symbol = symbol
            self.tint = fill
            ground.alpha = fill == nil ? 1 : 0
            tintGround.alpha = fill == nil ? 0 : 1
            if let fill { tintGround.backgroundColor = UIColor(rgb: fill.fill) }
            summaryLabel.textColor = fill != nil ? .white : UIColor(HassTokens.RGB.Surface.secondaryOnModule)
            icon.tintColor = fill.map { UIColor(rgb: $0.glyph) } ?? UIColor(HassTokens.RGB.Surface.secondaryOnModule)
            restyleFonts()
        }
        handler = action
        accessibilityLabel = "\(title), \(summary)"
        if action != nil {
            isAccessibilityElement = true
            accessibilityTraits = .button
            accessibilityHint = "Opens its details"
        } else {
            isAccessibilityElement = true
            accessibilityTraits = []
            accessibilityHint = nil
        }
        isEnabled = true
        if sizeChanged { invalidateIntrinsicContentSize(); setNeedsLayout() }
    }

    private func restyleFonts() {
        titleLabel.font = UKFont.rowTitle(traitCollection)
        summaryLabel.font = UKFont.preferred(.subheadline, monospacedDigit: true, traits: traitCollection)
        icon.image = UKFont.symbol(symbol, style: .body, weight: .semibold, filled: tint != nil, traits: traitCollection)
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    @objc private func tapped() { handler?() }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted && handler != nil ? 0.7 : 1 }
    }

    private func metrics(maxWidth: CGFloat) -> (icon: CGSize, text: CGFloat, title: CGSize, summary: CGSize, size: CGSize) {
        let iconSize = icon.image?.size ?? CGSize(width: 24, height: 24)
        let lead = HassTokens.Spacing.m, trail = HassTokens.Spacing.l, gap = HassTokens.Spacing.s
        let unbounded = CGFloat.greatestFiniteMagnitude
        let available = maxWidth >= unbounded / 2 ? unbounded : max(1, maxWidth - lead - trail - gap - iconSize.width)
        let titleSize = titleLabel.sizeThatFits(CGSize(width: available, height: unbounded))
        let summarySize = summaryLabel.sizeThatFits(CGSize(width: available, height: unbounded))
        let text = ceil(min(max(titleSize.width, summarySize.width), available))
        let textHeight = ceil(titleSize.height) + ceil(summarySize.height)
        let height = max(StatusChipStyle.minHeight, max(textHeight, iconSize.height) + 2 * HassTokens.Spacing.xs)
        return (iconSize, text, titleSize, summarySize, CGSize(width: lead + iconSize.width + gap + text + trail, height: height))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { metrics(maxWidth: size.width).size }
    override var intrinsicContentSize: CGSize { metrics(maxWidth: .greatestFiniteMagnitude).size }

    override func layoutSubviews() {
        super.layoutSubviews()
        ground.frame = bounds
        tintGround.frame = bounds
        let radius = UKChipShape.cornerRadius(height: bounds.height, title: titleLabel.font, summary: summaryLabel.font)
        tintGround.layer.cornerRadius = radius
        ground.moduleCornerRadius = radius
        highlight.frame = tintGround.bounds
        let measured = metrics(maxWidth: bounds.width)
        let lead = HassTokens.Spacing.m, gap = HassTokens.Spacing.s
        let textHeight = ceil(measured.title.height) + ceil(measured.summary.height)
        let top = (bounds.height - textHeight) / 2
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func place(_ rect: CGRect) -> CGRect { mirror ? CGRect(x: bounds.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height) : rect }
        icon.frame = place(CGRect(x: lead, y: (bounds.height - measured.icon.height) / 2, width: measured.icon.width, height: measured.icon.height))
        let textX = lead + measured.icon.width + gap
        titleLabel.frame = place(CGRect(x: textX, y: top, width: measured.text, height: ceil(measured.title.height)))
        summaryLabel.frame = place(CGRect(x: textX, y: top + ceil(measured.title.height), width: measured.text, height: ceil(measured.summary.height)))
        titleLabel.textAlignment = mirror ? .right : .left
        summaryLabel.textAlignment = mirror ? .right : .left
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        handler != nil && super.point(inside: point, with: event)
    }
}
#endif
