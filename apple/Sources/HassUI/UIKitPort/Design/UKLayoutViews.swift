#if os(iOS)
import HassDesign
import UIKit

// MARK: - Flow

/// `FlowLayout`'s arithmetic: children at their ideal sizes, left to right, wrapping like words in a paragraph.
enum UKFlowSolver {
    /// The frames of children whose ideal sizes are `sizes`, in a container `width` wide. A child wider than the container is narrowed
    /// to it (its height is `height(index, width)` there).
    static func frames(sizes: [CGSize], width: CGFloat, spacing: CGFloat, rightToLeft: Bool = false, height: (Int, CGFloat) -> CGFloat) -> (frames: [CGRect], height: CGFloat) {
        var frames: [CGRect] = []
        var rowIndices: [Int] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var y: CGFloat = 0
        var rows: [(indices: [Int], height: CGFloat)] = []
        var itemSizes: [CGSize] = sizes.enumerated().map { index, size in
            size.width > width ? CGSize(width: width, height: height(index, width)) : size
        }
        for index in itemSizes.indices {
            let size = itemSizes[index]
            let needed = rowIndices.isEmpty ? size.width : rowWidth + spacing + size.width
            if needed > width, !rowIndices.isEmpty {
                rows.append((rowIndices, rowHeight))
                rowIndices = [index]
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowIndices.append(index)
                rowWidth = needed
                rowHeight = max(rowHeight, size.height)
            }
        }
        if !rowIndices.isEmpty { rows.append((rowIndices, rowHeight)) }
        frames = Array(repeating: .zero, count: itemSizes.count)
        for row in rows {
            // Every row starts at the leading edge: the left, or the right in a right-to-left layout.
            var x = rightToLeft ? width : 0
            for index in row.indices {
                let size = itemSizes[index]
                frames[index] = CGRect(x: rightToLeft ? x - size.width : x, y: y, width: size.width, height: size.height)
                x += rightToLeft ? -(size.width + spacing) : size.width + spacing
            }
            y += row.height + spacing
        }
        itemSizes.removeAll()
        return (frames, max(0, y - spacing))
    }
}

/// `FlowLayout` over views: chips under an ingredient, room and option capsules. Children report their ideal size from
/// `sizeThatFits`.
@MainActor
final class UKFlowView: UIView, UKGridMeasuring {
    var spacing: CGFloat { didSet { setNeedsLayout() } }
    private(set) var children: [UIView] = []

    init(spacing: CGFloat) {
        self.spacing = spacing
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setChildren(_ views: [UIView]) {
        children.forEach { $0.removeFromSuperview() }
        children = views
        views.forEach(addSubview)
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    private func solve(width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let sizes = children.map { $0.sizeThatFits(unbounded) }
        return UKFlowSolver.frames(sizes: sizes, width: width, spacing: spacing, rightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft) {
            children[$0].sizeThatFits(CGSize(width: $1, height: CGFloat.greatestFiniteMagnitude)).height
        }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { solve(width: width).height }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: solve(width: size.width).height) }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: solve(width: max(bounds.width, 1)).height) }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (view, frame) in zip(children, solve(width: bounds.width).frames) { view.frame = frame }
    }
}

// MARK: - Chip rail

/// A page's row of status chips (`ChipRail`, pattern: `.agents/patterns/status-rail.md`): it scrolls sideways in compact width and wraps in
/// regular width (or at accessibility text sizes, where a sideways row would show one and a half chips), and on a window with a hinge
/// it stops ``ChipRailMetrics/hingeGap`` short of the fold.
///
/// Pass the chips as views that report their size from `sizeThatFits`.
@MainActor
final class UKChipRailView: UIView, UKGridMeasuring {
    private let scrollView = UIScrollView()
    private let flow = UKFlowView(spacing: HassTokens.Spacing.s)
    private var chips: [UIView] = []
    /// The window's hinge in window coordinates, if any.
    var hinge: CGRect? { didSet { if hinge != oldValue { setNeedsLayout() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.clipsToBounds = true
        scrollView.accessibilityIdentifier = "chipRail.scroll"
        scrollView.contentInsetAdjustmentBehavior = .never
        registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitPreferredContentSizeCategory.self]) { (view: UKChipRailView, _) in view.rebuild() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The layout for the current window.
    var mode: ChipRailMode {
        .resolve(isAccessibilitySize: traitCollection.ukIsAccessibilitySize)
    }

    func setChips(_ chips: [UIView]) {
        self.chips = chips
        rebuild()
    }

    private func rebuild() {
        scrollView.removeFromSuperview()
        flow.removeFromSuperview()
        chips.forEach { $0.removeFromSuperview() }
        switch mode {
        case .scroll:
            addSubview(scrollView)
            chips.forEach(scrollView.addSubview)
        case .wrap:
            flow.setChildren(chips)
            addSubview(flow)
        }
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    private var rowSizes: [CGSize] { chips.map { $0.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)) } }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        switch mode {
        case .scroll: rowSizes.map(\.height).max() ?? 0
        case .wrap: flow.gridHeight(forWidth: max(0, width - 2 * HassTokens.Spacing.l))
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: gridHeight(forWidth: max(bounds.width, 1))) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let margin = HassTokens.Spacing.l
        switch mode {
        case .scroll:
            // Measured on the full-width frame, so the inset never feeds back into the frame it is computed from.
            let railFrame = hinge == nil ? .zero : convert(bounds, to: nil)
            let inset = ChipRailMetrics.appliedInset(measured: ChipRailMetrics.trailingInset(railFrame: railFrame, hinge: hinge), hinge: hinge)
            let width = max(0, bounds.width - inset)
            scrollView.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            let sizes = rowSizes
            let rowHeight = sizes.map(\.height).max() ?? 0
            let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
            var x = margin
            var frames: [CGRect] = []
            for size in sizes {
                frames.append(CGRect(x: x, y: 0, width: size.width, height: size.height))
                x += size.width + HassTokens.Spacing.s
            }
            let natural = CGSize(width: max(margin, x - HassTokens.Spacing.s + margin), height: rowHeight)
            let content = ChipRailMetrics.hostedContentSize(natural: natural, bounds: scrollView.bounds.size)
            scrollView.contentSize = content
            // Chips start at the leading edge: the left, or the right in a right-to-left layout.
            for (chip, frame) in zip(chips, frames) {
                chip.frame = mirror ? CGRect(x: natural.width - frame.maxX + (content.width - natural.width), y: frame.minY, width: frame.width, height: frame.height) : frame
            }
            if scrollView.contentOffset.x == 0, mirror {
                scrollView.contentOffset.x = ChipRailMetrics.hostedLeadingOffset(contentWidth: content.width, boundsWidth: scrollView.bounds.width, isRightToLeft: true)
            }
        case .wrap:
            flow.frame = CGRect(x: margin, y: 0, width: max(0, bounds.width - 2 * margin), height: bounds.height)
        }
    }
}

// MARK: - Section header

/// A section header on a page (`PageSectionHeader`): 20 pt bold in primary ink over the tiles and lists on the wallpaper, with an
/// optional trailing detail in secondary ink ("Page 1 of 5"). At accessibility sizes the detail moves under the title so neither is
/// squeezed.
@MainActor
final class UKPageSectionHeaderView: UIView, UKGridMeasuring {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let inSheet: Bool
    /// The size the containers above were last told about (``UIView/ukRemeasureContainers(ifSizeChangedFrom:atWidth:)``).
    private var measured = CGSize.zero

    init(_ title: String, detail: String? = nil, inSheet: Bool = false) {
        self.inSheet = inSheet
        super.init(frame: .zero)
        titleLabel.numberOfLines = 0
        titleLabel.text = title
        titleLabel.textColor = UKInk.primary
        titleLabel.accessibilityTraits = .header
        titleLabel.isAccessibilityElement = true
        detailLabel.numberOfLines = 0
        detailLabel.text = detail
        detailLabel.isHidden = detail == nil
        // Sits straight on the wallpaper, which is always dark-styled: the always-dark secondary at 85%.
        detailLabel.textColor = UKInk.onDarkSecondary
        detailLabel.isAccessibilityElement = true
        addSubview(titleLabel)
        addSubview(detailLabel)
        ukOnContentSizeChange { [weak self] in
            guard let self else { return }
            titleLabel.font = UKFont.sectionTitle(traitCollection)
            detailLabel.font = UKFont.preferred(.body, monospacedDigit: true, traits: traitCollection)
            setNeedsLayout()
            invalidateIntrinsicContentSize()
            ukRemeasureContainers(ifSizeChangedFrom: &measured, atWidth: bounds.width > 0 ? bounds.width : 10_000)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Replaces the texts.
    func configure(title: String, detail: String?) {
        titleLabel.text = title
        detailLabel.text = detail
        detailLabel.isHidden = detail == nil
        setNeedsLayout()
        invalidateIntrinsicContentSize()
        ukRemeasureContainers(ifSizeChangedFrom: &measured, atWidth: bounds.width > 0 ? bounds.width : 10_000)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { ukRemeasureContainers(ifSizeChangedFrom: &measured, atWidth: bounds.width > 0 ? bounds.width : 10_000) }
    }

    private func frames(width: CGFloat) -> (title: CGRect, detail: CGRect, height: CGFloat) {
        let top: CGFloat = inSheet ? HassTokens.Spacing.s : 0
        func size(_ label: UILabel, _ width: CGFloat) -> CGSize {
            label.sizeThatFits(CGSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude))
        }
        let hasDetail = detailLabel.text != nil
        if traitCollection.ukIsAccessibilitySize || !hasDetail {
            let titleSize = size(titleLabel, width)
            var y = top + ceil(titleSize.height)
            var detail = CGRect.zero
            if hasDetail {
                let detailSize = size(detailLabel, width)
                detail = CGRect(x: 0, y: y + HassTokens.Spacing.xs, width: width, height: ceil(detailSize.height))
                y = detail.maxY
            }
            return (CGRect(x: 0, y: top, width: width, height: ceil(titleSize.height)), detail, y)
        }
        // Side by side on the first text baseline; the title takes the room the detail leaves.
        let detailWidth = min(ceil(detailLabel.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).width), width / 2)
        let titleWidth = max(1, width - detailWidth - HassTokens.Spacing.s)
        let titleSize = size(titleLabel, titleWidth)
        let detailSize = size(detailLabel, detailWidth)
        let baseline = top + titleLabel.font.ascender
        let detailTop = baseline - detailLabel.font.ascender
        let titleFrame = CGRect(x: 0, y: top, width: titleWidth, height: ceil(titleSize.height))
        let detailFrame = CGRect(x: width - detailWidth, y: detailTop, width: detailWidth, height: ceil(detailSize.height))
        return (titleFrame, detailFrame, max(titleFrame.maxY, detailFrame.maxY))
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { frames(width: width).height }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: frames(width: size.width).height) }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: frames(width: max(bounds.width, 1)).height) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frames = frames(width: bounds.width)
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        func place(_ view: UIView, _ rect: CGRect) {
            view.frame = mirror ? CGRect(x: bounds.width - rect.maxX, y: rect.minY, width: rect.width, height: rect.height) : rect
        }
        place(titleLabel, frames.title)
        place(detailLabel, frames.detail)
        titleLabel.textAlignment = mirror ? .right : .left
        detailLabel.textAlignment = mirror ? .left : (traitCollection.ukIsAccessibilitySize ? .left : .right)
    }
}

// MARK: - Column

/// A vertical stack of views at their natural heights, laid out by hand: the page column of a gallery, and the SwiftUI
/// `VStack(alignment: .leading, spacing:)` inside a `ScrollView`. Children report their height from ``UKGridMeasuring`` or `sizeThatFits`.
@MainActor
final class UKColumnView: UIView, UKGridMeasuring {
    var spacing: CGFloat { didSet { setNeedsLayout() } }
    var insets: UIEdgeInsets { didSet { setNeedsLayout() } }
    private(set) var views: [UIView] = []

    init(spacing: CGFloat = 0, insets: UIEdgeInsets = .zero) {
        self.spacing = spacing
        self.insets = insets
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setViews(_ views: [UIView]) {
        self.views.forEach { $0.removeFromSuperview() }
        self.views = views
        views.forEach(addSubview)
        setNeedsLayout()
    }

    private func heights(width: CGFloat) -> [CGFloat] {
        views.map { view in
            if let measuring = view as? UKGridMeasuring { return measuring.gridHeight(forWidth: width) }
            return ceil(view.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height)
        }
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        let inner = max(0, width - insets.left - insets.right)
        let visible = zip(views, heights(width: inner)).filter { !$0.0.isHidden }.map(\.1)
        return insets.top + insets.bottom + visible.reduce(0, +) + spacing * CGFloat(max(visible.count - 1, 0))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inner = max(0, bounds.width - insets.left - insets.right)
        var y = insets.top
        for (view, height) in zip(views, heights(width: inner)) where !view.isHidden {
            view.frame = CGRect(x: insets.left, y: y, width: inner, height: height)
            y += height + spacing
        }
    }
}
#endif
