#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Suggested recipes

/// Copy and accessibility values for the suggested-recipe carousel.
@MainActor
struct UKSuggestedRecipesCopy {
    let loading: String
    let accessibilityLabel: String
    let identifier: String
    let loadingIdentifier: String
    let errorTitle: String
    let errorMessage: String
    let errorIdentifier: String
    let emptyTitle: String
    let emptyMessage: String
    let emptyIdentifier: String
    let stateSymbol: String
    let pageLabel: String
    let pageIdentifier: String
    let cardPlaceholderSymbol: String
    let cardHint: String
    let cardIdentifierPrefix: String

    static let food = UKSuggestedRecipesCopy(
        loading: "Finding suggestions", accessibilityLabel: "Suggested recipes", identifier: "food.suggestions",
        loadingIdentifier: "food.suggestions.loading", errorTitle: "Suggestions Unavailable",
        errorMessage: "Suggested recipes are temporarily unavailable.", errorIdentifier: "food.suggestions.error",
        emptyTitle: "No Suggestions Yet", emptyMessage: "There's nothing to suggest right now. Check back later.",
        emptyIdentifier: "food.suggestions.empty", stateSymbol: "fork.knife", pageLabel: "Suggestion page",
        pageIdentifier: "food.suggestions.pages", cardPlaceholderSymbol: "fork.knife",
        cardHint: "Opens recipe details", cardIdentifierPrefix: "food.suggestion."
    )
}

/// The hub's Suggested Recipes: five swipeable pages of compact recipe cards (``SuggestedRecipesCarousel``; web
/// `SuggestedRecipeCarousel` + `CardCarousel`). Columns follow the width like the web (min 2, cards up to 220 pt, max 10); three rows on
/// narrow windows and two on wide ones. Empty slots keep their place while loading.
///
/// Direction G (mockup n6 Food & Recipes): page dots sit under the cards. Pages are built as they come near, not all at once.
/// The canonical Food wrapper binds it to ``SuggestedRecipesModel``; hosts may supply values directly.
@MainActor
final class UKSuggestedRecipesView: UIView, UKGridMeasuring, UIScrollViewDelegate {
    var onOpen: ((RecipeCard) -> Void)?
    /// Clip pages to the carousel's own width. Set it when the carousel shares a row with other content (the hub's split columns).
    var clipsPages = false { didSet { if clipsPages != oldValue { updateClipping() } } }

    private let copy: UKSuggestedRecipesCopy
    private let header: UKPageSectionHeaderView
    private let pages = UIScrollView()
    private let arc: UKArcSpinnerView
    private let bag = UKObservationBag()
    private var indicator: UKPageIndicator?
    private var state: UKStateMessageView?
    private var pageViews: [Int: UKSuggestionPageView] = [:]
    private var builtKey = ""
    private var page = 0
    private var placedWidth: CGFloat = 0
    private var needsOffset = true
    /// Neighbouring pages are in the view only while the carousel is moving (at rest only the page on screen is, so nothing off screen is laid out).
    private var showsNeighbours = false

    private var phase: SuggestedRecipesModel.Phase = .idle
    private var items: [RecipeCard] = []

    convenience init(title: String, model: SuggestedRecipesModel) {
        self.init(title: title, copy: .food)
        bag.observe { [weak self] in
            self?.configure(phase: model.phase, items: model.items)
        }
    }

    init(title: String, copy: UKSuggestedRecipesCopy) {
        self.copy = copy
        header = UKPageSectionHeaderView(title, detail: nil)
        arc = UKArcSpinnerView(.compact, label: copy.loading)
        super.init(frame: .zero)
        pages.isPagingEnabled = true
        pages.showsHorizontalScrollIndicator = false
        pages.showsVerticalScrollIndicator = false
        pages.alwaysBounceHorizontal = false
        pages.alwaysBounceVertical = false
        pages.contentInsetAdjustmentBehavior = .never
        pages.isDirectionalLockEnabled = true
        pages.delegate = self
        pages.backgroundColor = .clear
        arc.color = UKInk.secondary
        arc.accessibilityIdentifier = copy.loadingIdentifier
        addSubview(header)
        addSubview(pages)
        addSubview(arc)
        accessibilityContainerType = .semanticGroup
        accessibilityLabel = copy.accessibilityLabel
        accessibilityIdentifier = copy.identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Applies provider values without replacing the carousel or resetting its visible page.
    func configure(phase: SuggestedRecipesModel.Phase, items: [RecipeCard]) {
        guard phase != self.phase || items != self.items else { return }
        self.phase = phase
        self.items = items
        builtKey = ""
        setNeedsLayout()
        superview?.setNeedsLayout()
        invalidateHost()
    }

    /// The scroll content above this view re-measures it: walk up to the scroll view's content and ask for a layout.
    private func invalidateHost() {
        var view: UIView? = superview
        while let current = view {
            current.setNeedsLayout()
            if current is UIScrollView { break }
            view = current.superview
        }
    }

    /// Web `RECOMMENDATION_PAGE_COUNT`.
    private var isAccessibilitySize: Bool { traitCollection.ukIsAccessibilitySize }

    // MARK: Measuring

    private struct Plan {
        var columns: Int
        var rows: Int
        var pageCount: Int
        var showsFailure: Bool
        var showsEmpty: Bool
    }

    private func plan(width: CGFloat) -> Plan {
        let layout = SuggestedRecipesCarousel.layout(width: width, accessibilitySize: isAccessibilitySize)
        let size = max(layout.columns * layout.rows, 1)
        let count = phase == .ready
            ? max(1, min(SuggestedRecipesCarousel.pageCount, Int((Double(items.count) / Double(size)).rounded(.up))))
            : SuggestedRecipesCarousel.pageCount
        return Plan(columns: layout.columns, rows: layout.rows, pageCount: count, showsFailure: phase == .failed, showsEmpty: phase == .ready && items.isEmpty)
    }

    private func pageSlots(_ index: Int, plan: Plan) -> [RecipeCard?] {
        let size = plan.columns * plan.rows
        var result: [RecipeCard?] = []
        for slot in 0..<size {
            let position = index * size + slot
            if phase == .ready {
                if position < items.count { result.append(items[position]) }
            } else {
                result.append(nil)
            }
        }
        return result
    }

    private func page(at index: Int, plan: Plan, width: CGFloat) -> UKSuggestionPageView {
        if let existing = pageViews[index] { return existing }
        let view = UKSuggestionPageView(slots: pageSlots(index, plan: plan), columns: plan.columns, copy: copy) { [weak self] recipe in self?.onOpen?(recipe) }
        pageViews[index] = view
        return view
    }

    private func stateView(_ plan: Plan) -> UKStateMessageView? {
        if plan.showsFailure {
            return UKStateMessageView(symbol: copy.stateSymbol, title: copy.errorTitle, message: copy.errorMessage,
                                      identifier: copy.errorIdentifier)
        }
        if plan.showsEmpty {
            return UKStateMessageView(symbol: copy.stateSymbol, title: copy.emptyTitle, message: copy.emptyMessage,
                                      identifier: copy.emptyIdentifier)
        }
        return nil
    }

    private func layoutHeights(width: CGFloat) -> (header: CGFloat, state: CGFloat, pages: CGFloat, plan: Plan) {
        let plan = plan(width: width)
        let headerHeight = header.gridHeight(forWidth: width)
        if plan.showsFailure || plan.showsEmpty {
            let probe = state ?? stateView(plan)
            let height = probe?.systemLayoutSizeFitting(CGSize(width: width, height: 0), withHorizontalFittingPriority: .required,
                                                        verticalFittingPriority: .fittingSizeLevel).height ?? 0
            return (headerHeight, ceil(height), 0, plan)
        }
        let first = page(at: 0, plan: plan, width: width)
        return (headerHeight, 0, first.gridHeight(forWidth: width), plan)
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        syncStructure(width: width)
        let heights = layoutHeights(width: width)
        let indicatorHeight: CGFloat = heights.plan.pageCount > 1 ? HassTokens.minTarget : 0
        if heights.state > 0 { return heights.header + HassTokens.Spacing.m + heights.state }
        return heights.header + HassTokens.Spacing.m + heights.pages
            + (indicatorHeight > 0 ? HassTokens.Spacing.s + indicatorHeight : 0)
    }

    // MARK: Structure

    /// Rebuilds the pages, indicator and state message when what they show has changed (phase, items, columns, rows, text size).
    private func syncStructure(width: CGFloat) {
        let plan = plan(width: width)
        let key = "\(phase)|\(items.count)|\(plan.columns)|\(plan.rows)|\(plan.pageCount)|\(isAccessibilitySize)|\(Int(width))"
        guard key != builtKey else { return }
        builtKey = key
        needsOffset = true
        pageViews.values.forEach { $0.removeFromSuperview() }
        pageViews = [:]
        state?.removeFromSuperview()
        state = nil
        indicator?.removeFromSuperview()
        indicator = nil
        if let message = stateView(plan) {
            state = message
            addSubview(message)
        } else if plan.pageCount > 1 {
            // The shared page indicator: tap either side of the dots, or adjust with VoiceOver.
            let dots = UKPageIndicator(page: min(page, plan.pageCount - 1), pageCount: plan.pageCount, label: copy.pageLabel,
                                       identifier: copy.pageIdentifier, ink: UKInk.primary) { [weak self] target in self?.scroll(toPage: target) }
            indicator = dots
            addSubview(dots)
        }
        page = min(page, plan.pageCount - 1)
        arc.isHidden = !(phase == .idle || phase == .loading)
        updateClipping()
    }

    private func updateClipping() {
        // The next page peeks into the page margin at standard sizes; at accessibility sizes the sliver is unreadable, so pages clip.
        pages.clipsToBounds = true
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        syncStructure(width: width)
        let heights = layoutHeights(width: width)
        header.frame = CGRect(x: 0, y: 0, width: width, height: heights.header)
        var y = heights.header + HassTokens.Spacing.m
        if let state {
            state.frame = CGRect(x: 0, y: y, width: width, height: heights.state)
            pages.isHidden = true
            arc.isHidden = true
            return
        }
        pages.isHidden = false
        pages.frame = CGRect(x: 0, y: y, width: width, height: heights.pages)
        pages.contentSize = CGSize(width: width * CGFloat(heights.plan.pageCount), height: heights.pages)
        // The offset follows the page only when the width changes (a rotation) or the pages were rebuilt, never during a drag.
        if placedWidth != width || needsOffset {
            needsOffset = false
            pages.contentOffset = CGPoint(x: width * CGFloat(page), y: 0)
        }
        placedWidth = width
        arc.frame = CGRect(x: (width - arc.intrinsicContentSize.width) / 2, y: y + (heights.pages - arc.intrinsicContentSize.height) / 2,
                           width: arc.intrinsicContentSize.width, height: arc.intrinsicContentSize.height)
        y += heights.pages + HassTokens.Spacing.s
        indicator?.frame = CGRect(x: 0, y: y, width: width, height: HassTokens.minTarget)
        ensurePages(around: page, plan: heights.plan, width: width, height: heights.pages)
    }

    /// Builds the page on screen and its neighbours.
    private func ensurePages(around center: Int, plan: Plan, width: CGFloat, height: CGFloat) {
        let low = showsNeighbours ? max(0, center - 1) : center
        let high = showsNeighbours ? min(plan.pageCount - 1, center + 1) : center
        for (index, other) in pageViews where index < low || index > high { other.removeFromSuperview() }
        for index in low...high {
            let view = page(at: index, plan: plan, width: width)
            if view.superview == nil { pages.addSubview(view) }
            // VoiceOver reads the page on screen only.
            view.accessibilityElementsHidden = index != center
            view.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: height)
        }
    }

    // MARK: Paging

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { setNeighbours(true) }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { setNeighbours(false) }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { setNeighbours(false) }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { setNeighbours(false) } }

    private func setNeighbours(_ on: Bool) {
        guard showsNeighbours != on else { return }
        showsNeighbours = on
        setNeedsLayout()
        if on { layoutIfNeeded() }
    }

    private func scroll(toPage target: Int) {
        setNeighbours(true)
        let reduce = UIAccessibility.isReduceMotionEnabled
        // Reduce Motion: jump to the page rather than scrolling the carousel across.
        pages.setContentOffset(CGPoint(x: pages.bounds.width * CGFloat(target), y: 0), animated: !reduce)
        if reduce {
            pageChanged(to: target)
            setNeighbours(false)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.bounds.width > 0 else { return }
        let target = Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded())
        pageChanged(to: target)
    }

    private func pageChanged(to target: Int) {
        let plan = plan(width: bounds.width)
        let clamped = max(0, min(plan.pageCount - 1, target))
        guard clamped != page else { return }
        page = clamped
        indicator?.page = clamped
        setNeedsLayout()
    }
}

/// One page of the carousel: a grid of cards, 10 pt apart, with the page's trailing 10 pt padding (`SuggestionSlot`).
@MainActor
final class UKSuggestionPageView: UIView, UKGridMeasuring {
    private let columns: Int
    private var cells: [UIView] = []

    /// - Parameter slots: A recipe, or nil for the loading placeholder in its place. Slots past the recipes are not passed.
    init(slots: [RecipeCard?], columns: Int, copy: UKSuggestedRecipesCopy = .food, onOpen: @escaping (RecipeCard) -> Void) {
        self.columns = max(columns, 1)
        super.init(frame: .zero)
        for slot in slots {
            if let recipe = slot {
                let values = RecipeCardPresentation(recipe: recipe, showCoverage: false, placeholderSymbol: copy.cardPlaceholderSymbol,
                                                    accessibilityHint: copy.cardHint)
                let card = UKImageCardView(title: values.title, subtitle: values.subtitle, imageURL: values.imageURL,
                                           fallbackImageURL: values.fallbackImageURL, placeholderSymbol: values.placeholderSymbol,
                                           accessibilityHint: values.accessibilityHint) { onOpen(recipe) }
                card.accessibilityIdentifier = "\(copy.cardIdentifierPrefix)\(recipe.id)"
                cells.append(card)
            } else {
                // An empty module in the card's place, so the page keeps its height while loading.
                let placeholder = UIView()
                placeholder.backgroundColor = UKInk.moduleThin
                placeholder.layer.cornerRadius = ImageCard.cornerRadius
                placeholder.layer.cornerCurve = .continuous
                placeholder.isAccessibilityElement = false
                cells.append(placeholder)
            }
            addSubview(cells[cells.count - 1])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static let spacing = SuggestedRecipesCarousel.spacing

    private func cardWidth(_ width: CGFloat) -> CGFloat {
        let grid = max(0, width - Self.spacing)
        return max(1, (grid - Self.spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    private func height(of view: UIView, width: CGFloat) -> CGFloat {
        if let card = view as? UKGridMeasuring { return card.gridHeight(forWidth: width) }
        return width / ImageCard.aspectRatio
    }

    private func rowHeights(width: CGFloat) -> [CGFloat] {
        let cardWidth = cardWidth(width)
        var rows: [CGFloat] = []
        for (index, cell) in cells.enumerated() {
            let row = index / columns
            if row >= rows.count { rows.append(0) }
            rows[row] = max(rows[row], height(of: cell, width: cardWidth))
        }
        return rows
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        let rows = rowHeights(width: width)
        return rows.reduce(0, +) + Self.spacing * CGFloat(max(rows.count - 1, 0))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rows = rowHeights(width: bounds.width)
        let cardWidth = cardWidth(bounds.width)
        let mirror = effectiveUserInterfaceLayoutDirection == .rightToLeft
        var tops: [CGFloat] = []
        var y: CGFloat = 0
        for row in rows {
            tops.append(y)
            y += row + Self.spacing
        }
        for (index, cell) in cells.enumerated() {
            let column = index % columns
            let row = index / columns
            let x = CGFloat(column) * (cardWidth + Self.spacing)
            cell.frame = CGRect(x: mirror ? bounds.width - x - cardWidth : x, y: tops[row], width: cardWidth, height: rows[row])
        }
    }
}
#endif
