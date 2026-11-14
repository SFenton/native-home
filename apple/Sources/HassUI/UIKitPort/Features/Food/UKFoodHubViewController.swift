#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// Food & Recipes hub (``FoodHubScreen``; web `FoodHubPage`; spec `.agents/pages/food/spec.md`).
///
/// Single column everywhere a split is not allowed; in iPad and unfolded iPhone Duo landscape the recipes sections take the
/// leading column and the inventory sections the trailing one, meeting at the hinge (``SplitPolicy/columnWidths(container:hinge:gutter:)``).
/// No page gate (owner, 2026-10-24): the tiles read the store and show at once; only the Suggested Recipes carousel waits, with its arc.
///
/// **Columns (owner, 2026-11-01).** Inside the shell the hub is the first column and a Food space (All Food, Fridge, Pantry ...) opens
/// beside it where the window splits (``ShellRoute/foodSpace(_:)``, pushed elsewhere), as Settings' topics do; "Select a food space to see
/// its items" fills the other column until one is chosen. The hub is then one column wide (recipes, then the spaces), not two panes.
/// Without a shell (the gallery) it keeps the two-pane form and pushes.
final class UKFoodHubViewController: UKPageViewController, UKColumnsHosting {
    private let models: FoodModels
    private let injectedInventory: InventoryModels?
    private let content = UKFoodHubContent()
    private let scroll: UKColumnScrollView
    private let carousel: UKSuggestedRecipesView
    private let allFoodGrid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true))
    private let spacesGrid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true))
    private var tiles: [UKGlassTileView] = []
    /// The hub (column one) and the Food space beside it.
    private(set) lazy var columns = UKColumnsViewController(rootView: scroll, shell: context.shell) {
        UKPanePlaceholderViewController(symbol: "refrigerator", text: "Select a food space to see its items", identifier: "food.pane.placeholder")
    }
    private var columnsPending = false
    /// The hub is a column of the shell's own routes (not the gallery's).
    private var inShell: Bool { context.navigator != nil && context.section != nil }

    /// - Parameter inventory: The inventory models the space tiles open (the gallery's fixture server); the signed-in connection's by default.
    init(context: UKContext, models: FoodModels, inventory: InventoryModels? = nil) {
        self.models = models
        injectedInventory = inventory
        carousel = UKSuggestedRecipesView(title: "Suggested Recipes", model: models.suggestions)
        scroll = UKColumnScrollView(content: content)
        super.init(context: context, title: "Food & Recipes")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var houseLayoutSkeleton: HouseSkeletonPlan.Kind? { .page }

    override func viewDidLoad() {
        super.viewDidLoad()
        scroll.accessibilityIdentifier = "food.scroll"
        buildColumns()
        carousel.onOpen = { [weak self] recipe in self?.open(recipe) }
        buildSections()
        content.shell = context.shell
        content.isStacked = inShell
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.context.shell?.windowHinge
            self.content.hingeChanged()
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (page: UKFoodHubViewController, _) in page.rescaleGrids() }
        rescaleGrids()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        models.suggestions.appear()
    }

    #if DEBUG
    private var debugOpened = false

    /// `FENTON_DEBUG_FOOD_SPACE=fridge|pantry|all-food...`: opens that space three seconds in, as a tap on its tile does. A probe, never in a release build.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !debugOpened, let raw = ProcessInfo.processInfo.environment["FENTON_DEBUG_FOOD_SPACE"], let space = InventorySpace(rawValue: raw) else { return }
        debugOpened = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.pushInventory(space) }
    }
    #endif

    // MARK: Sections

    /// Scales with the tiles' text, so accessibility sizes step down to fewer, wider tiles.
    private func rescaleGrids() {
        let minimum = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: DynamicGridMetrics.tileMinWidth, compatibleWith: traitCollection)
        for grid in [allFoodGrid, spacesGrid] {
            grid.configuration = UKGridConfiguration(minCellWidth: minimum, maxColumns: 4, equalRowHeights: true)
        }
    }

    /// - Parameter subtitle: The count line ("38 Items • 2 Expiring Soon", `FoodConfig.spaceSubtitle`), re-read from the store whenever
    ///   a space's count or the expiring sensor changes (the SwiftUI hub's `GlassTile(subtitle:)`).
    private func tile(_ model: UKGlassTileModel, subtitle: ((@escaping (String) -> EntityState?) -> String)? = nil,
                      action: @escaping () -> Void) -> UKGlassTileView {
        let environment = UKTileEnvironment(context: context)
        let tile = UKGlassTileView(model: model, environment: environment, action: action)
        tiles.append(tile)
        if let subtitle {
            let store = context.store
            structureBag.observe { [weak tile] in
                guard let tile else { return }
                var counted = model
                counted.subtitle = subtitle { store.entity($0).state }
                tile.configure(counted, environment: environment, action: action)
            }
        }
        return tile
    }

    /// Holds the observations of the tiles' count lines, which come from the house document's food spaces, so a rebuild ends the old ones.
    private let structureBag = UKObservationBag()

    override func houseLayoutDidChange() {
        structureBag.removeAll()
        tiles = []
        buildSections()
    }

    private func buildSections() {
        // The web's full-width blue tile with a navigation chevron (`FoodHubPage.tsx:46-54`).
        let allRecipes = tile(UKGlassTileModel(title: "All Recipes", symbol: SymbolMap.symbol(for: "mdi:book-open-page-variant"), family: .recipes,
                                               isActive: true, kind: .navigate, identifier: "food.allRecipes")) { [weak self] in self?.pushRecipes() }
        // One tile in the spaces' grid, so it is as wide as one space (web `singleTileGrid`).
        let allFood = tile(UKGlassTileModel(title: "All Food", symbol: SymbolMap.symbol(for: "mdi:food-variant"), family: .food, isActive: true,
                                            kind: .navigate, identifier: "food.allFood"),
                            subtitle: { FoodConfig.allFoodSubtitle(state: $0) }) { [weak self] in self?.pushInventory(.allFood) }
        allFoodGrid.setItems([UKGridItem(allFood)])

        var spaceItems: [UKGridItem] = []
        for space in FoodConfig.spaces {
            let family = FoodFamilies.family(forLocation: space.location)
            let identifier = "food.space.\(space.location)"
            let symbol = SymbolMap.symbol(for: space.icon)
            let spaceTile = tile(UKGlassTileModel(title: space.title, symbol: symbol, family: family, isActive: true, kind: .navigate, identifier: identifier),
                                  subtitle: { FoodConfig.spaceSubtitle(space, state: $0) }) { [weak self] in
                if let inventory = FoodInventoryScreen.space(forLocation: space.location) { self?.pushInventory(inventory) }
            }
            spaceItems.append(UKGridItem(spaceTile))
        }
        spacesGrid.setItems(spaceItems)
        allFoodGrid.followsFold = true
        spacesGrid.followsFold = true

        content.recipeColumn.setViews([carousel, allRecipes])
        content.inventoryColumn.setViews([
            UKFoodSectionView("All Food", content: allFoodGrid),
            UKFoodSectionView("Food Spaces", content: spacesGrid),
        ])
    }

    // MARK: Columns

    private func buildColumns() {
        addChild(columns)
        columns.view.frame = contentView.bounds
        columns.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(columns.view)
        columns.didMove(toParent: self)
        columns.onUserPop = { [weak self] _ in self?.trimSpaces() }
        setPageScrollView(scroll)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Under the shell the section's navigation controller decides; a hub shown alone (the gallery) keeps the two-pane form.
        guard !inShell, !(navigationController is UKSectionNavigationController), let window = view.window, !columnsPending else { return }
        let wanted = SplitPolicy.allowsSplit(size: window.bounds.size, isRegularWidth: window.traitCollection.horizontalSizeClass == .regular)
        guard wanted != columns.isWide else { return }
        columnsPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.columnsPending = false
            guard !self.inShell else { return }
            self.columns.setWide(wanted)
        }
    }

    func syncColumnRoutes(_ routes: [ShellRoute], animated: Bool) {
        guard columns.isWide else { return }
        columns.reconcile(tags: routes.map { AnyHashable($0) }, make: { [unowned self] in self.makeSpacePage($0.base as! ShellRoute) }, animated: animated)
    }

    /// A Food space in a column: no navigator of its own and no wallpaper (the section's bar and the hub's wallpaper are behind it).
    private func makeSpacePage(_ route: ShellRoute) -> UIViewController {
        let paneContext = context.with {
            $0.navigator = nil
            $0.isPane = true
        }
        guard case let .foodSpace(raw) = route, let space = InventorySpace(rawValue: raw) else { return UKPlaceholderViewController(title: "Food", symbol: "refrigerator") }
        return UKPageHost.wrapped(inventoryPage(space, context: paneContext), context: paneContext)
    }

    private func inventoryPage(_ space: InventorySpace, context: UKContext) -> UIViewController {
        let inventory = UKFoodNavigation.inventoryModels(context: context, injected: injectedInventory)
        return UKFoodNavigation.inventoryPage(space, context: context, models: inventory)
    }

    /// Closing a space (Close, Back, the edge pan) drops its route.
    private func trimSpaces() {
        guard let navigator = context.navigator, let section = context.section else { return }
        let routes = navigator.routes(in: section)
        guard let hub = routes.lastIndex(of: .home(.food)) else { return }
        navigator.trimPath(in: section, toDepth: hub + 1)
    }

    // MARK: Navigation

    private func pushRecipes() {
        UKFoodNavigation.push(UKRecipesViewController(context: context, models: models), from: self, context: context)
    }

    /// A Food space: a route of the hub's section (a column beside the hub, or a push), else a page the columns hold themselves.
    private func pushInventory(_ space: InventorySpace) {
        guard let navigator = context.navigator, let section = context.section else {
            UKFoodNavigation.push(inventoryPage(space, context: context), from: self, context: context)
            return
        }
        let routes = navigator.routes(in: section)
        guard let hub = routes.lastIndex(of: .home(.food)) else {
            // A hub opened some other way than a route (a launch probe): the page still opens beside it.
            let paneContext = context.with { $0.navigator = nil; $0.isPane = true }
            columns.open(UKPageHost.wrapped(inventoryPage(space, context: paneContext), context: paneContext), tag: nil, atDepth: 0)
            return
        }
        guard routes.last != .foodSpace(space.rawValue) || routes.count != hub + 2 else { return }
        navigator.trimPath(in: section, toDepth: hub + 1)
        navigator.append(.foodSpace(space.rawValue), in: section)
    }

    private func open(_ recipe: RecipeCard) {
        UKRecipeDetailPresenter.presentSheet(models.detailModel(for: recipe), from: self, context: context)
    }
}

// MARK: - Layout

/// The hub's scrolled content: the recipes column and the inventory column, stacked, or side by side where a split is allowed
/// (`HingedPanes`), inside the page margins (16 pt sides, 12 pt top and bottom).
@MainActor
final class UKFoodHubContent: UIView, UKGridMeasuring {
    let recipeColumn = UKColumnView(spacing: HassTokens.Spacing.xl)
    let inventoryColumn = UKColumnView(spacing: HassTokens.Spacing.xl)
    var shell: UKShellEnvironment?
    /// One column always: the hub is itself a column beside a Food space (``UKFoodHubViewController``).
    var isStacked = false
    private var hinge: CGRect?

    init() {
        super.init(frame: .zero)
        addSubview(recipeColumn)
        addSubview(inventoryColumn)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func hingeChanged() {
        hinge = shell?.windowHinge
        setNeedsLayout()
    }

    private var isSplit: Bool {
        guard !isStacked, let size = window?.bounds.size else { return false }
        return SplitPolicy.allowsSplit(size: size, isRegularWidth: traitCollection.horizontalSizeClass == .regular)
    }

    private struct Arrangement {
        var split: SplitGeometry?
        var recipes: CGRect
        var inventory: CGRect
        var height: CGFloat
    }

    private func arrange(width: CGFloat) -> Arrangement {
        let inner = max(0, width - 2 * HassTokens.Spacing.l)
        let x = HassTokens.Spacing.l
        let top = HassTokens.Spacing.m
        if isSplit {
            // The columns meet at the hinge on the unfolded Duo, else share the width.
            let originX = convert(CGPoint(x: x, y: 0), to: nil).x
            let geometry = SplitPolicy.columnWidths(container: CGRect(x: originX, y: 0, width: inner, height: 0), hinge: hinge, gutter: HassTokens.Spacing.xl)
            let leftHeight = recipeColumn.gridHeight(forWidth: geometry.leadingWidth)
            let rightHeight = inventoryColumn.gridHeight(forWidth: geometry.trailingWidth)
            return Arrangement(
                split: geometry,
                recipes: CGRect(x: x, y: top, width: geometry.leadingWidth, height: leftHeight),
                inventory: CGRect(x: x + geometry.leadingWidth + geometry.bandWidth, y: top, width: geometry.trailingWidth, height: rightHeight),
                height: top + max(leftHeight, rightHeight) + top)
        }
        let first = recipeColumn.gridHeight(forWidth: inner)
        let second = inventoryColumn.gridHeight(forWidth: inner)
        return Arrangement(
            split: nil,
            recipes: CGRect(x: x, y: top, width: inner, height: first),
            inventory: CGRect(x: x, y: top + first + HassTokens.Spacing.xl, width: inner, height: second),
            height: top + first + HassTokens.Spacing.xl + second + top)
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { arrange(width: width).height }

    override func layoutSubviews() {
        super.layoutSubviews()
        let arrangement = arrange(width: bounds.width)
        recipeColumn.frame = arrangement.recipes
        inventoryColumn.frame = arrangement.inventory
        // The carousel clips its pages to its own width where it shares a row with the other column.
        if let carousel = recipeColumn.views.first as? UKSuggestedRecipesView { carousel.clipsPages = arrangement.split != nil }
    }
}

/// A titled section on the Food pages (``FoodSection``): a section header over its content, 12 pt apart.
@MainActor
final class UKFoodSectionView: UIView, UKGridMeasuring {
    private let header: UKPageSectionHeaderView
    private let body: UIView & UKGridMeasuring

    init(_ title: String, detail: String? = nil, content: UIView & UKGridMeasuring) {
        header = UKPageSectionHeaderView(title, detail: detail)
        body = content
        super.init(frame: .zero)
        addSubview(header)
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        header.gridHeight(forWidth: width) + HassTokens.Spacing.m + body.gridHeight(forWidth: width)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let headerHeight = header.gridHeight(forWidth: bounds.width)
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        let y = headerHeight + HassTokens.Spacing.m
        body.frame = CGRect(x: 0, y: y, width: bounds.width, height: max(0, bounds.height - y))
    }
}

// MARK: - Suggested recipes

/// The hub's Suggested Recipes: five swipeable pages of compact recipe cards (``SuggestedRecipesCarousel``; web
/// `SuggestedRecipeCarousel` + `CardCarousel`). Columns follow the width like the web (min 2, cards up to 220 pt, max 10); three rows on
/// narrow windows and two on wide ones. Empty slots keep their place while loading.
///
/// Direction G (mockup n6 Food & Recipes): page dots sit under the cards. Pages are built as they come near, not all at once.
@MainActor
final class UKSuggestedRecipesView: UIView, UKGridMeasuring, UIScrollViewDelegate {
    var onOpen: ((RecipeCard) -> Void)?
    /// Clip pages to the carousel's own width. Set it when the carousel shares a row with other content (the hub's split columns).
    var clipsPages = false { didSet { if clipsPages != oldValue { updateClipping() } } }

    private let title: String
    private let model: SuggestedRecipesModel
    private let header: UKPageSectionHeaderView
    private let pages = UIScrollView()
    private let arc = UKArcSpinnerView(.compact, label: "Finding suggestions")
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

    init(title: String, model: SuggestedRecipesModel) {
        self.title = title
        self.model = model
        header = UKPageSectionHeaderView(title, detail: nil)
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
        arc.accessibilityIdentifier = "food.suggestions.loading"
        addSubview(header)
        addSubview(pages)
        addSubview(arc)
        accessibilityContainerType = .semanticGroup
        accessibilityLabel = "Suggested recipes"
        accessibilityIdentifier = "food.suggestions"
        bag.observe { [weak self] in
            guard let self else { return }
            self.phase = self.model.phase
            self.items = self.model.items
            self.builtKey = ""
            self.setNeedsLayout()
            self.superview?.setNeedsLayout()
            self.invalidateHost()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

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
        let view = UKSuggestionPageView(slots: pageSlots(index, plan: plan), columns: plan.columns) { [weak self] recipe in self?.onOpen?(recipe) }
        pageViews[index] = view
        return view
    }

    private func stateView(_ plan: Plan) -> UKStateMessageView? {
        if plan.showsFailure {
            return UKStateMessageView(symbol: "fork.knife", title: "Suggestions Unavailable", message: "Suggested recipes are temporarily unavailable.",
                                      identifier: "food.suggestions.error")
        }
        if plan.showsEmpty {
            return UKStateMessageView(symbol: "fork.knife", title: "No Suggestions Yet", message: "There's nothing to suggest right now. Check back later.",
                                      identifier: "food.suggestions.empty")
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
            let dots = UKPageIndicator(page: min(page, plan.pageCount - 1), pageCount: plan.pageCount, label: "Suggestion page",
                                       identifier: "food.suggestions.pages", ink: UKInk.primary) { [weak self] target in self?.scroll(toPage: target) }
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
    init(slots: [RecipeCard?], columns: Int, onOpen: @escaping (RecipeCard) -> Void) {
        self.columns = max(columns, 1)
        super.init(frame: .zero)
        for slot in slots {
            if let recipe = slot {
                let card = UKImageCardView(title: recipe.title, imageURL: recipe.cardImageURL, fallbackImageURL: recipe.imageURL,
                                           placeholderSymbol: "fork.knife", accessibilityHint: "Opens recipe details") { onOpen(recipe) }
                card.accessibilityIdentifier = "food.suggestion.\(recipe.id)"
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
