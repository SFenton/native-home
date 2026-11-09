#if os(iOS)
import HassDesign
import UIKit

// MARK: - Native paging

extension UIScrollView {
    /// Makes this horizontal scroll view page one viewport at a time (`pagesScrollViewByViewport`). In SwiftUI this reached into
    /// a `ScrollView` to turn `isPagingEnabled` on; here the scroll view is ours, so it is the one flag. Cells must be a whole
    /// fraction of the viewport wide so pages line up (``UKPagedRowView`` does this).
    func ukPagesByViewport() { isPagingEnabled = true }
}

// MARK: - Page indicator

/// The app's page indicator for every paging row and carousel (`PageIndicator`; `.agents/patterns/page-indicator.md`): a
/// resizing capsule and dots in the card's ink. The full-width 44 pt strip is two tap zones (the leading half goes back one
/// page, the trailing half forward) and one accessibility element with an adjustable action, a "Page 2 of 5" value and a
/// stable identifier. From ``PageIndicator/dotLimit`` + 1 pages up the dots give way to a "4 of 12" label.
///
/// ```swift
/// let dots = UKPageIndicator(page: 0, pageCount: 3, label: "Suggestion page", identifier: "food.suggestions.pages") { row.scroll(toPage: $0) }
/// dots.page = row.currentPage          // when the row settles
/// ```
public final class UKPageIndicator: UIView {
    public var page: Int { didSet { if page != oldValue { updateMarks(animated: true) } } }
    public var pageCount: Int { didSet { rebuildMarks() } }
    public let label: String
    /// The colour of the current dot and the count; the other dots are a fainter tone of it.
    public var ink: UIColor { didSet { updateMarks(animated: false) } }
    public var onSelect: (Int) -> Void

    private let dots = UIStackView()
    private let countLabel = UILabel()
    private var dotViews: [UIView] = []
    private var widthConstraints: [NSLayoutConstraint] = []

    public init(page: Int, pageCount: Int, label: String, identifier: String, ink: UIColor? = nil,
                onSelect: @escaping (Int) -> Void) {
        self.page = page
        self.pageCount = pageCount
        self.label = label
        self.ink = ink ?? UIColor(HassTokens.RGB.Ink.onDark)
        self.onSelect = onSelect
        super.init(frame: .zero)
        dots.axis = .horizontal
        dots.alignment = .center
        dots.spacing = HassTokens.Spacing.xs + 2
        dots.isUserInteractionEnabled = false
        countLabel.font = UKFont.preferred(.footnote, monospacedDigit: true)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.isUserInteractionEnabled = false
        [dots, countLabel].forEach { addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            dots.centerXAnchor.constraint(equalTo: centerXAnchor), dots.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.centerXAnchor.constraint(equalTo: centerXAnchor), countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget),
        ])
        for forward in [false, true] {
            let zone = UIControl()
            zone.addAction(UIAction { [weak self] _ in self?.select(forward: forward) }, for: .touchUpInside)
            addSubview(zone)
            zone.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                zone.topAnchor.constraint(equalTo: topAnchor), zone.bottomAnchor.constraint(equalTo: bottomAnchor),
                forward ? zone.trailingAnchor.constraint(equalTo: trailingAnchor) : zone.leadingAnchor.constraint(equalTo: leadingAnchor),
                zone.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5),
            ])
        }
        isAccessibilityElement = true
        accessibilityLabel = label
        accessibilityIdentifier = identifier
        accessibilityTraits = .adjustable
        rebuildMarks()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    private func rebuildMarks() {
        dotViews.forEach { $0.removeFromSuperview() }
        dotViews = []
        widthConstraints = []
        let showsCount = PageIndicator.showsCount(pageCount: pageCount)
        dots.isHidden = showsCount
        countLabel.isHidden = !showsCount
        if !showsCount {
            for _ in 0..<max(1, pageCount) {
                let dot = UIView()
                dot.layer.cornerRadius = 3.5
                dot.translatesAutoresizingMaskIntoConstraints = false
                let width = dot.widthAnchor.constraint(equalToConstant: 7)
                width.isActive = true
                dot.heightAnchor.constraint(equalToConstant: 7).isActive = true
                widthConstraints.append(width)
                dotViews.append(dot)
                dots.addArrangedSubview(dot)
            }
        }
        updateMarks(animated: false)
    }

    private func updateMarks(animated: Bool) {
        accessibilityValue = PageIndicator.valueDescription(page: page, pageCount: pageCount)
        countLabel.text = PageIndicator.countLabel(page: page, pageCount: pageCount)
        countLabel.textColor = ink
        let apply = { [self] in
            for (index, dot) in dotViews.enumerated() {
                let current = index == page
                widthConstraints[index].constant = current ? 18 : 7
                dot.backgroundColor = current ? ink : ink.withAlphaComponent(0.45)
            }
            layoutIfNeeded()
        }
        if animated, window != nil { UKMotion.animate(.quick, reduced: .quick, animations: apply) } else { apply() }
    }

    private func select(forward: Bool) {
        if let target = PageIndicator.target(from: page, forward: forward, pageCount: pageCount) { onSelect(target) }
    }

    public override func accessibilityIncrement() { select(forward: true) }
    public override func accessibilityDecrement() { select(forward: false) }
}

// MARK: - Paged row

/// A horizontally paging row of equal-width cells (`PagedRow`; the hourly weather): a paging `UIScrollView`, so a swipe writes
/// nothing into the page around it. ``firstVisible`` is the first cell on screen, always the first cell of a page; setting it
/// moves the row to that page, swiping reports it through ``onFirstVisibleChange`` once per page, not once per frame.
///
/// VoiceOver reads the cells on the page on screen (the other pages' cells are left out of the accessibility elements), pages
/// with a three-finger swipe and announces "Page 2 of 3" when it settles.
///
/// ```swift
/// let row = UKPagedRowView(itemCount: hours.count, perPage: 6) { index in HourCell(hours[index]) }
/// row.onFirstVisibleChange = { dots.page = row.currentPage }
/// dots.onSelect = { row.firstVisible = row.firstIndex(ofPage: $0) }
/// ```
public final class UKPagedRowView: UIScrollView, UIScrollViewDelegate {
    public private(set) var itemCount: Int
    public private(set) var perPage: Int
    public var animatesPaging: Bool
    private let cellProvider: (Int) -> UIView
    private var cells: [UIView] = []
    private var measuredHeight: CGFloat = 0
    private var measuredWidth: CGFloat = 0
    private var isMovingToPage = false
    private var announcedPage: Int? = 0
    /// Called once per page the row settles on or passes, with ``firstVisible`` already updated.
    public var onFirstVisibleChange: () -> Void = {}

    /// The first cell on screen (nil is the first page). Set it to page the row.
    public var firstVisible: Int? {
        didSet { followBinding() }
    }

    /// - Parameters:
    ///   - clipsToBounds: Whether the row clips to its own width; unclipped, the next page peeks into the margin beside it.
    public init(itemCount: Int, perPage: Int, animatesPaging: Bool = true, clipsToBounds: Bool = true, cell: @escaping (Int) -> UIView) {
        self.itemCount = itemCount
        self.perPage = max(1, perPage)
        self.animatesPaging = animatesPaging
        self.cellProvider = cell
        super.init(frame: .zero)
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        alwaysBounceHorizontal = true
        alwaysBounceVertical = false
        isDirectionalLockEnabled = true
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        self.clipsToBounds = clipsToBounds
        ukPagesByViewport()
        delegate = self
        reload()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    public var pageCount: Int { PagedRowMetrics.pageCount(itemCount: itemCount, perPage: perPage) }

    /// The page on screen.
    public var currentPage: Int {
        PagedRowMetrics.page(forOffset: contentOffset.x, viewport: bounds.width, contentWidth: contentSize.width, pageCount: pageCount)
    }

    /// The first cell of a page.
    public func firstIndex(ofPage page: Int) -> Int { PagedRowMetrics.firstIndex(ofPage: page, itemCount: itemCount, perPage: perPage) }

    /// Rebuilds the cells (the content changed).
    public func reload(itemCount newCount: Int? = nil, perPage newPerPage: Int? = nil) {
        if let newCount { itemCount = newCount }
        if let newPerPage { perPage = max(1, newPerPage) }
        cells.forEach { $0.removeFromSuperview() }
        cells = (0..<max(0, itemCount)).map(cellProvider)
        cells.forEach(addSubview)
        measuredWidth = 0
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    // MARK: Layout

    private func measure(width: CGFloat) -> CGFloat {
        let cellWidth = max(1, width / CGFloat(perPage))
        return cells.map {
            $0.systemLayoutSizeFitting(CGSize(width: cellWidth, height: UIView.layoutFittingCompressedSize.height),
                                       withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        }.max() ?? 0
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: measuredHeight > 0 ? measuredHeight : measure(width: bounds.width > 0 ? bounds.width : 320))
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let cellWidth = bounds.width / CGFloat(perPage)
        if measuredWidth != bounds.width {
            measuredWidth = bounds.width
            let height = measure(width: bounds.width)
            if height != measuredHeight {
                measuredHeight = height
                invalidateIntrinsicContentSize()
            }
        }
        for (index, cell) in cells.enumerated() {
            cell.frame = CGRect(x: CGFloat(index) * cellWidth, y: 0, width: cellWidth, height: measuredHeight)
        }
        let size = CGSize(width: cellWidth * CGFloat(cells.count), height: measuredHeight)
        if contentSize != size {
            contentSize = size
            followBinding()
        }
    }

    // MARK: Paging

    /// Moves to the page the binding names when it is not the page on screen.
    private func followBinding() {
        guard bounds.width > 0, contentSize.width > 0, !isTracking, !isDecelerating, !isMovingToPage else { return }
        let wanted = PagedRowMetrics.page(containing: firstVisible, perPage: perPage, pageCount: pageCount)
        guard wanted != currentPage else { return }
        let target = CGPoint(x: PagedRowMetrics.offset(ofPage: wanted, viewport: bounds.width, contentWidth: contentSize.width), y: 0)
        let animated = animatesPaging && window != nil && !UIAccessibility.isReduceMotionEnabled
        isMovingToPage = animated
        setContentOffset(target, animated: animated)
    }

    /// Writes the page on screen into ``firstVisible``, once per page.
    private func reportPage() {
        guard bounds.width > 0, !isMovingToPage else { return }
        let first = PagedRowMetrics.firstIndex(ofPage: currentPage, itemCount: itemCount, perPage: perPage)
        if firstVisible != first {
            firstVisible = first
            onFirstVisibleChange()
        }
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) { reportPage() }
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { isMovingToPage = false }
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { announcePage() }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { announcePage() }
    }

    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        isMovingToPage = false
        followBinding()
        if !isMovingToPage {
            reportPage()
            announcePage()
        }
    }

    // MARK: Accessibility

    /// What VoiceOver reads: only the cells on the page on screen.
    public override var accessibilityElements: [Any]? {
        get {
            let viewport = UIAccessibility.convertToScreenCoordinates(bounds, in: self)
            let frames = cells.map { UIAccessibility.convertToScreenCoordinates($0.bounds, in: $0) }
            return PagedRowMetrics.indexes(ofFrames: frames, overlapping: viewport).map { cells[$0] }
        }
        set { super.accessibilityElements = newValue }
    }

    /// A three-finger swipe moves by a page, as a paging scroll view does.
    public override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        let step: Int
        switch direction {
        case .left, .next: step = 1
        case .right, .previous: step = -1
        default: return super.accessibilityScroll(direction)
        }
        guard let target = PagedRowMetrics.page(from: currentPage, step: step, pageCount: pageCount) else { return false }
        // An animated move reports when it ends (`scrollViewDidEndScrollingAnimation`); without a window or with Reduce Motion the
        // offset jumps and no end callback comes, so the page is reported here.
        let animated = animatesPaging && window != nil && !UIAccessibility.isReduceMotionEnabled
        isMovingToPage = animated
        setContentOffset(CGPoint(x: PagedRowMetrics.offset(ofPage: target, viewport: bounds.width, contentWidth: contentSize.width), y: 0), animated: animated)
        if !animated { reportPage() }
        return true
    }

    /// Tells VoiceOver which page the row settled on ("Page 2 of 3"), once per page.
    private func announcePage() {
        guard bounds.width > 0 else { return }
        let page = currentPage
        defer { announcedPage = page }
        guard let announcedPage, announcedPage != page, UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .pageScrolled, argument: PagedRowMetrics.pageDescription(page, pageCount: pageCount))
    }
}
#endif
