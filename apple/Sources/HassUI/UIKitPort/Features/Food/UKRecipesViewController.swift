#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// All recipes: search, sort, filter and an endlessly loading grid (``RecipesScreen``; web `RecipesPage` + `RecipeFloatingActions`).
///
/// Search, Sort and Filter are the shared floating actions (`.agents/patterns/floating-actions.md`), as on the web. Where a split is
/// allowed (iPad and unfolded iPhone Duo landscape) an open recipe fills the trailing half; elsewhere it opens as a sheet.
final class UKRecipesViewController: UKPageViewController {
    private let models: FoodModels
    private let results: UKRecipeResultsController
    private let search = UKFloatingSearch(prompt: "Search recipes")
    private let bar: UKFloatingActionBar
    private let pinned: UKPinnedBarViewController
    private let paneHost = UIView()
    private var panes: UKHingedPanes?
    private var paneController: UKRecipeDetailPaneViewController?
    private var selected: RecipeCard?
    private var detail: RecipeDetailModel?
    private var presentedSheet = false
    private var closingForSplit = false
    private var lastAnnouncement = ""
    private var sortSheet: UKFilterSheet?
    private var sortDraft = RecipeSort.availability
    private var filterSheet: UKRecipeFilterSheetController?

    private var collection: RecipeCollectionModel { models.collection }

    /// - Parameter selected: A recipe to open at once (hosted tests).
    init(context: UKContext, models: FoodModels, selected: RecipeCard? = nil) {
        self.models = models
        results = UKRecipeResultsController(context: context, collection: models.collection)
        bar = UKFloatingActionBar(actions: [], search: search)
        pinned = UKPinnedBarViewController(content: results, bar: bar, scrollView: results.collectionView)
        super.init(context: context, title: "Recipes")
        if let selected {
            self.selected = selected
            detail = models.detailModel(for: selected)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        results.onOpen = { [weak self] recipe in self?.open(recipe) }
        results.selectedId = nil
        addChild(pinned)
        let panes = UKHingedPanes(leading: pinned.view, trailing: paneHost, showsTrailing: false, gutter: 0, shell: context.shell)
        panes.frame = contentView.bounds
        panes.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(panes)
        pinned.didMove(toParent: self)
        self.panes = panes
        paneHost.backgroundColor = .clear
        paneHost.clipsToBounds = true
        setPageScrollView(results.collectionView)

        if !collection.searchText.isEmpty {
            search.text = collection.searchText
            search.isExpanded = true
        }
        bar.actions = [
            UKFloatingAction(id: "sort", title: "Sort", symbol: "arrow.up.arrow.down", showsTitle: false, isActive: collection.sortActive) { [weak self] in self?.presentSort() },
            UKFloatingAction(id: "filter", title: "Filter", symbol: "line.3.horizontal.decrease", showsTitle: false, isActive: collection.filterActive) { [weak self] in self?.presentFilter() },
        ]
        bag.observe { [weak self] in
            guard let self else { return }
            let sortActive = self.collection.sortActive
            let filterActive = self.collection.filterActive
            self.bar.setActive(sortActive, forActionID: "sort")
            self.bar.setActive(filterActive, forActionID: "filter")
        }
        bag.observe { [weak self] in
            guard let self else { return }
            let text = self.search.text
            if self.collection.searchText != text { self.collection.searchText = text }
        }
        lastAnnouncement = collection.announcement
        bag.observe { [weak self] in
            guard let self else { return }
            let text = self.collection.announcement
            guard text != self.lastAnnouncement else { return }
            self.lastAnnouncement = text
            if !text.isEmpty { UIAccessibility.post(notification: .announcement, argument: text) }
        }
        collection.appear()
        #if DEBUG
        // FENTON_OPEN_RECIPE_SHEET=sort|filter opens that sheet a moment after launch (screenshots, crash repros).
        if let kind = ProcessInfo.processInfo.environment["FENTON_OPEN_RECIPE_SHEET"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                if kind == "filter" { self?.presentFilter() } else if kind == "sort" { self?.presentSort() }
            }
        }
        #endif
        if selected != nil { DispatchQueue.main.async { [weak self] in self?.showDetail(animated: false) } }
    }

    // MARK: Split

    private var split: Bool {
        guard let size = view.window?.bounds.size else { return false }
        return SplitPolicy.allowsSplit(size: size, isRegularWidth: traitCollection.horizontalSizeClass == .regular)
    }

    private var wasSplit = false

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let now = split
        if now != wasSplit {
            wasSplit = now
            // A fold or rotation moves an open recipe between the pane and the sheet.
            if detail != nil { DispatchQueue.main.async { [weak self] in self?.showDetail(animated: true) } }
        }
    }

    // MARK: Selection

    private func open(_ recipe: RecipeCard) {
        guard recipe.id != selected?.id else { return }
        selected = recipe
        detail = models.detailModel(for: recipe)
        showDetail(animated: true)
    }

    private func close() {
        selected = nil
        detail = nil
        results.selectedId = nil
        removePane(animated: true)
        if presentedSheet {
            presentedSheet = false
            presentedViewController?.dismiss(animated: true)
        }
    }

    /// Shows the open recipe where this window shows it: in the pane when it may split, else as a sheet.
    private func showDetail(animated: Bool) {
        guard let detail, let selected else { return }
        results.selectedId = split ? selected.id : nil
        if split {
            if presentedSheet {
                presentedSheet = false
                closingForSplit = true
                // UIKit presents from a child page on the window's root, so the sheet is found there, not on this page.
                let root: UIViewController = view.window?.rootViewController ?? self
                var top = root
                while let next = top.presentedViewController { top = next }
                if top === root { closingForSplit = false } else {
                    top.dismiss(animated: false) { [weak self] in self?.closingForSplit = false }
                }
            }
            showPane(for: detail, animated: animated)
        } else {
            removePane(animated: false)
            guard !presentedSheet else { return }
            presentedSheet = true
            UKRecipeDetailPresenter.presentSheet(detail, from: self, context: context) { [weak self] in
                guard let self else { return }
                self.presentedSheet = false
                if !self.closingForSplit, !self.split { self.close() }
            }
        }
    }

    private func showPane(for detail: RecipeDetailModel, animated: Bool) {
        if paneController?.view.tag == detail.recipe.id { return }
        let reveal = paneController == nil && panes?.showsTrailing != true
        paneController?.willMove(toParent: nil)
        paneController?.view.removeFromSuperview()
        paneController?.removeFromParent()
        let pane = UKRecipeDetailPaneViewController(model: detail, context: context) { [weak self] in self?.close() }
        addChild(pane)
        pane.view.tag = detail.recipe.id
        pane.view.frame = paneHost.bounds
        pane.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        paneHost.addSubview(pane.view)
        pane.didMove(toParent: self)
        paneController = pane
        guard reveal else { return }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        panes?.showsTrailing = true
        panes?.layoutIfNeeded()
        guard animated, view.window != nil else { return }
        // Reduce Motion: the pane fades in instead of sliding (HIG Motion).
        paneHost.alpha = reduceMotion ? 0 : 1
        paneHost.transform = reduceMotion ? .identity : CGAffineTransform(translationX: paneHost.bounds.width, y: 0)
        UKMotion.animate(.standard, reduced: .quick) {
            self.paneHost.alpha = 1
            self.paneHost.transform = .identity
        }
    }

    private func removePane(animated: Bool) {
        guard let pane = paneController else { return }
        paneController = nil
        pane.willMove(toParent: nil)
        pane.view.removeFromSuperview()
        pane.removeFromParent()
        panes?.showsTrailing = false
        paneHost.alpha = 1
        paneHost.transform = .identity
    }

    // MARK: Sort and filter

    private func presentSort() {
        sortDraft = collection.sort
        let sheet = UKFilterSheet(title: "Sort Recipes", canApply: false, canReset: collection.sort != .availability,
                                  onApply: { [weak self] in
                                      guard let self else { return }
                                      self.collection.apply(sort: self.sortDraft)
                                  },
                                  onReset: { [weak self] in
                                      self?.sortDraft = .availability
                                      self?.refreshSort()
                                  },
                                  sections: sortSections())
        sortSheet = sheet
        sheet.present(from: self)
    }

    private func sortSections() -> [UKFormSection] {
        [UKFormSection(id: "sort", header: "Sort By", rows: RecipeSort.allCases.map { option in
            UKFormRow(id: option.rawValue, identifier: "recipes.sort.\(option.rawValue)",
                      .option(title: option.title, subtitle: option.subtitle, swatch: [], isSelected: sortDraft == option) { [weak self] in
                          self?.sortDraft = option
                          self?.refreshSort()
                      })
        })]
    }

    private func refreshSort() {
        sortSheet?.update(subtitle: nil, canApply: sortDraft != collection.sort, canReset: sortDraft != .availability, sections: sortSections())
    }

    private func presentFilter() {
        let sheet = UKRecipeFilterSheetController(current: collection.filters, sortedAlphabetically: collection.sort == .alphabetical) { [weak self] filters in
            self?.collection.apply(filters: filters)
        }
        filterSheet = sheet
        sheet.present(from: self)
    }
}

// MARK: - Results

/// The Recipes grid with infinite loading (``RecipeGrid``; web `RecipeGrid`), waiting for the first page like the web's page load gate
/// (spinner fades in, stays at least a second, fades out, then the grid fades in; later searches, sorts and filters use the quicker
/// results timings). The floating actions stay outside, so a search keeps its field and keyboard while its results reload.
///
/// A collection view with reused cards and image prefetching: 2+ columns of 160 pt cards (1+ at accessibility sizes, where a card is
/// a row), the order under the title ("Sorted by Ingredients Available"), and a footer for the next page.
final class UKRecipeResultsController: UKPaneViewController, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    enum Item: Hashable {
        case summary
        case card(String)
        case footer
    }

    private let context: UKContext
    private let collection: RecipeCollectionModel
    let collectionView: UICollectionView
    var onOpen: (RecipeCard) -> Void = { _ in }
    /// The card open beside the grid (a split): outlined and read as selected.
    var selectedId: Int? {
        didSet {
            guard selectedId != oldValue, dataSource != nil else { return }
            var snapshot = dataSource.snapshot()
            let changed = snapshot.itemIdentifiers.filter { item in
                guard case let .card(key) = item, let recipe = cards[key] else { return false }
                return recipe.id == selectedId || recipe.id == oldValue
            }
            snapshot.reconfigureItems(changed)
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }

    private var dataSource: UICollectionViewDiffableDataSource<Int, Item>!
    private var cards: [String: RecipeCard] = [:]
    private let body = UIView()
    private let gate: UKContentGateView
    private var stateOverlay: UKStateMessageOverlay?
    private var shownState = ""
    private var footerKey = ""
    private var sortShown: RecipeSort?
    private let bag = UKObservationBag()
    private var prefetching: [String: Task<Void, Never>] = [:]
    private var cardWidth: CGFloat = 160

    init(context: UKContext, collection: RecipeCollectionModel) {
        self.context = context
        self.collection = collection
        let layout = UICollectionViewCompositionalLayout { _, _ in UKRecipeResultsController.emptySection() }
        collectionView = UKWidthAwareCollectionView(frame: .zero, collectionViewLayout: layout)
        gate = UKContentGateView(page: "Recipes", isReady: collection.phase == .loaded || collection.phase == .failed, timing: .page,
                                 reloadTiming: .results, label: "Loading Recipes", content: body)
        super.init(nibName: nil, bundle: nil)
        collectionView.setCollectionViewLayout(UICollectionViewCompositionalLayout { [weak self] index, environment in
            self?.section(index, environment) ?? Self.emptySection()
        }, animated: false)
        NotificationCenter.default.addObserver(self, selector: #selector(foldChanged), name: UKHinge.didChange, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func emptySection() -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(1))
        return NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.accessibilityIdentifier = "recipes.grid"
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        body.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: body.topAnchor), collectionView.bottomAnchor.constraint(equalTo: body.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: body.leadingAnchor), collectionView.trailingAnchor.constraint(equalTo: body.trailingAnchor),
        ])
        stateOverlay = UKStateMessageOverlay(host: body)
        gate.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gate)
        NSLayoutConstraint.activate([
            gate.topAnchor.constraint(equalTo: view.topAnchor), gate.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gate.leadingAnchor.constraint(equalTo: view.leadingAnchor), gate.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let summary = UICollectionView.CellRegistration<UKRecipeSummaryCell, Item> { [weak self] cell, _, _ in
            cell.configure(text: RecipeGrid.sortSummary(self?.collection.sort ?? .availability))
        }
        let card = UICollectionView.CellRegistration<UKRecipeCardCell, Item> { [weak self] cell, _, item in
            guard let self, case let .card(key) = item, let recipe = self.cards[key] else { return }
            cell.configure(recipe: recipe, selected: recipe.id == self.selectedId) { [weak self] in self?.onOpen(recipe) }
        }
        let footer = UICollectionView.CellRegistration<UKRecipeFooterCell, Item> { [weak self] cell, _, _ in
            guard let self else { return }
            cell.configure(failed: self.collection.nextPageFailed, hydrating: self.collection.hydrating) { [weak self] in self?.collection.retryNextPage() }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .summary: collectionView.dequeueConfiguredReusableCell(using: summary, for: indexPath, item: item)
            case .card: collectionView.dequeueConfiguredReusableCell(using: card, for: indexPath, item: item)
            case .footer: collectionView.dequeueConfiguredReusableCell(using: footer, for: indexPath, item: item)
            }
        }
        bag.observe { [weak self] in
            guard let self else { return }
            self.apply(phase: self.collection.phase, items: self.collection.items, sort: self.collection.sort,
                       nextFailed: self.collection.nextPageFailed, nextLoading: self.collection.nextPageLoading,
                       hydrating: self.collection.hydrating, query: self.collection.appliedQuery)
        }
    }

    // MARK: Layout

    private func section(_ index: Int, _ environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let width = environment.container.effectiveContentSize.width
        let page = HassTokens.Spacing.l
        let spacing = HassTokens.Spacing.m
        switch index {
        case 0:
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(24))
            let section = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: page, bottom: 0, trailing: page)
            return section
        case 1:
            let accessibility = environment.traitCollection.ukIsAccessibilitySize
            if UKHinge.hasFold, let tracks = foldTracks(inner: width - 2 * page, leading: page, spacing: spacing, accessibility: accessibility) {
                return foldSection(tracks, spacing: spacing, page: page)
            }
            let columns = RecipeGrid.columnCount(width: width - 2 * page, accessibilitySize: accessibility)
            let each = max(1, (width - 2 * page - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            cardWidth = each
            let height = each / ImageCard.aspectRatio
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0 / CGFloat(columns)), heightDimension: .estimated(height)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height)),
                                                           repeatingSubitem: item, count: columns)
            group.interItemSpacing = .fixed(spacing)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = spacing
            section.contentInsets = NSDirectionalEdgeInsets(top: spacing + 8, leading: page, bottom: spacing, trailing: page)
            return section
        default:
            let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(60))
            let section = NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: page, bottom: 0, trailing: page)
            return section
        }
    }

    // MARK: Fold

    /// The card tracks on an iPhone Duo (either pose; owner 2026-11-01): an even number of equal tracks lying flat, so they are symmetric about the
    /// page's midpoint, and, partly folded, as many tracks on each side of the hinge band as fit, the gap between the two middle tracks being the
    /// band (``DynamicGridMetrics``, as the tile grids do). Nil for one track, which keeps the plain layout.
    private func foldTracks(inner: CGFloat, leading: CGFloat, spacing: CGFloat, accessibility: Bool) -> [DynamicGridMetrics.Track]? {
        guard inner > 0 else { return nil }
        let frame = collectionView.convert(collectionView.bounds, to: nil)
        let band = collectionView.window == nil ? nil : HingeAvoidance.band(
            in: CGRect(x: (frame.minX + leading).rounded(), y: 0, width: inner.rounded(), height: 0), hinge: UKHinge.frame)
        let metrics = DynamicGridMetrics(width: inner, minCellWidth: accessibility ? 320 : 160, maxColumns: 8, spacing: spacing, evenColumns: true, band: band)
        return metrics.tracks.count >= 2 ? metrics.tracks : nil
    }

    /// One row per group: each card an absolute track wide, with the space to the next track (the spacing, or the band) as its trailing edge
    /// spacing, so the hinge falls in a gap and a short last row keeps the tracks from the leading edge.
    private func foldSection(_ tracks: [DynamicGridMetrics.Track], spacing: CGFloat, page: CGFloat) -> NSCollectionLayoutSection {
        cardWidth = tracks[0].width
        let height = tracks[0].width / ImageCard.aspectRatio
        let items = tracks.indices.map { index -> NSCollectionLayoutItem in
            let track = tracks[index]
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(track.width), heightDimension: .estimated(height)))
            let gap = index + 1 < tracks.count ? tracks[index + 1].x - (track.x + track.width) : 0
            item.edgeSpacing = NSCollectionLayoutEdgeSpacing(leading: nil, top: nil, trailing: .fixed(gap), bottom: nil)
            return item
        }
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .estimated(height)),
                                                       subitems: items)
        group.interItemSpacing = .fixed(0)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        section.contentInsets = NSDirectionalEdgeInsets(top: spacing + 8, leading: page, bottom: spacing, trailing: page)
        return section
    }

    /// A change of fold re-tracks the cards one turn after it is published, so the reflow runs inside ``UKReflow``'s animation.
    @objc private func foldChanged() {
        DispatchQueue.main.async { [weak self] in self?.collectionView.collectionViewLayout.invalidateLayout() }
    }

    // MARK: State

    private func apply(phase: RecipeCollectionModel.Phase, items: [RecipeCard], sort: RecipeSort, nextFailed: Bool, nextLoading: Bool,
                       hydrating: Bool, query: String) {
        gate.isReady = phase == .loaded || phase == .failed
        cards = Dictionary(items.map { ($0.dedupeKey, $0) }, uniquingKeysWith: { first, _ in first })

        // What shows: the grid (also under the gate while it fades a reload out), a centred message, or nothing yet.
        var state = ""
        var grid = false
        switch phase {
        case .idle, .loading: grid = !items.isEmpty
        case .failed: state = "failed"
        case .loaded: if items.isEmpty { state = query.isEmpty ? "empty-filters" : "empty-search" } else { grid = true }
        }
        collectionView.isHidden = !grid
        if state != shownState {
            shownState = state
            switch state {
            case "failed":
                // The page's one primary action while nothing loaded (direction G, Controls: Primary buttons).
                stateOverlay?.show(UKStateMessageView(symbol: "exclamationmark.triangle", title: "Unable to Load Recipes", actionTitle: AlertCopy.tryAgain,
                                                      actionIdentifier: "recipes.retry", action: { [weak self] in self?.collection.reload() }, identifier: "recipes.error"))
            case "empty-filters", "empty-search":
                stateOverlay?.show(UKStateMessageView(symbol: "magnifyingglass", title: "No Recipes Found",
                                                      message: state == "empty-filters" ? "No recipes matched the current filters." : "Try a different search or loosen the recipe filters.",
                                                      identifier: "recipes.empty"))
            default:
                stateOverlay?.show(nil)
            }
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, Item>()
        snapshot.appendSections([0, 1, 2])
        if grid || !items.isEmpty { snapshot.appendItems([.summary], toSection: 0) }
        snapshot.appendItems(items.map { .card($0.dedupeKey) }, toSection: 1)
        let key = "\(nextFailed)|\(nextLoading || hydrating)|\(hydrating)"
        let showsFooter = nextFailed || nextLoading || hydrating
        if showsFooter { snapshot.appendItems([.footer], toSection: 2) }
        var reconfigured: [Item] = []
        if sortShown != sort, snapshot.itemIdentifiers.contains(.summary) { reconfigured.append(.summary) }
        if key != footerKey, showsFooter { reconfigured.append(.footer) }
        sortShown = sort
        footerKey = key
        snapshot.reconfigureItems(reconfigured.filter { snapshot.itemIdentifiers.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: Delegate

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool { false }
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool { false }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard case let .card(key)? = dataSource.itemIdentifier(for: indexPath), let recipe = cards[key] else { return }
        collection.itemAppeared(recipe)
    }

    // MARK: Prefetch

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let scale = collectionView.traitCollection.displayScale
        let pixels = Int(max(cardWidth, 1) * scale)
        for path in indexPaths {
            guard case let .card(key)? = dataSource.itemIdentifier(for: path), prefetching[key] == nil, let recipe = cards[key],
                  let url = recipe.cardImageURL ?? recipe.imageURL, ImagePipeline.shared.memoryImage(for: url) == nil else { continue }
            prefetching[key] = Task { @MainActor in
                for await _ in ImagePipeline.shared.images(for: url, maxPixel: pixels) {}
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        for path in indexPaths {
            guard case let .card(key)? = dataSource.itemIdentifier(for: path) else { continue }
            prefetching.removeValue(forKey: key)?.cancel()
        }
    }
}

/// The order under the large title (mockup n6 Recipes: "Sorted by Ingredients Available").
final class UKRecipeSummaryCell: UICollectionViewCell {
    private let label = UILabel.uk(.body, ink: UKDesignInk.secondary)

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.accessibilityIdentifier = "recipes.sortedBy"
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor), label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(text: String) { label.text = text }
}

/// One recipe card of the grid (``ImageCard`` in ``RecipeGrid``). Sizes itself from the card's own measure, so scrolling does no
/// Auto Layout work.
final class UKRecipeCardCell: UICollectionViewCell {
    private let card = UKImageCardView(title: " ", imageURL: nil, placeholderSymbol: "fork.knife", accessibilityHint: "Opens recipe details")

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.frame = contentView.bounds
        card.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(card)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(recipe: RecipeCard, selected: Bool, open: @escaping () -> Void) {
        card.configure(title: recipe.title, subtitle: recipe.coverageText, imageURL: recipe.cardImageURL, fallbackImageURL: recipe.imageURL, placeholderSymbol: "fork.knife")
        card.action = open
        card.isSelectionShown = selected
        card.accessibilityIdentifier = "recipes.card.\(recipe.id)"
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as? UICollectionViewLayoutAttributes ?? layoutAttributes
        attributes.size.height = ceil(card.gridHeight(forWidth: layoutAttributes.size.width))
        return attributes
    }
}

/// The grid's footer: "Unable to load more recipes." with Try Again, or the arc while the next page loads.
final class UKRecipeFooterCell: UICollectionViewCell {
    private let column = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        column.axis = .vertical
        column.alignment = .center
        column.spacing = HassTokens.Spacing.s
        column.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: contentView.topAnchor), column.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -HassTokens.Spacing.xl),
            column.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), column.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(failed: Bool, hydrating: Bool, retry: @escaping () -> Void) {
        for view in column.arrangedSubviews { column.removeArrangedSubview(view); view.removeFromSuperview() }
        if failed {
            let message = UILabel.uk(.body, ink: UKDesignInk.secondary, alignment: .center)
            message.text = "Unable to load more recipes."
            var configuration = UIButton.Configuration.bordered()
            configuration.title = AlertCopy.tryAgain
            configuration.baseForegroundColor = UKDesignInk.action
            let button = UIButton(configuration: configuration)
            button.accessibilityIdentifier = "recipes.nextPage.retry"
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: HassTokens.minTarget).isActive = true
            button.addAction(UIAction { _ in retry() }, for: .touchUpInside)
            column.addArrangedSubview(message)
            column.addArrangedSubview(button)
        } else {
            let arc = UKArcSpinnerView(.compact, label: hydrating ? "Finding more recipes" : "Loading more recipes")
            arc.color = .white
            arc.accessibilityIdentifier = "recipes.nextPage.loading"
            column.addArrangedSubview(arc)
        }
    }
}

// MARK: - Filter sheet

/// Filter Recipes (``RecipeFilterSheet``; web `RecipeFilterSheet`), in direction G's sheet form (mockup n5 Filter Recipes): inset
/// sections under 15 Semibold secondary headers, the expiry horizon as a segmented control under its toggle, and footers that explain
/// each section. The draft is applied with the check and dropped by Cancel.
@MainActor
final class UKRecipeFilterSheetController {
    private var draft: RecipeFilters
    private let current: RecipeFilters
    private let sortedAlphabetically: Bool
    private let sheet: UKFilterSheet
    private let coverage: UKPercentSliderRow
    private let expiringToggle: UKLabeledSwitchRow
    private let horizon: UKSegmentedChoice<Int>
    private let availability: UKPercentSliderRow
    private let expiry: UKPercentSliderRow

    init(current: RecipeFilters, sortedAlphabetically: Bool, onApply: @escaping (RecipeFilters) -> Void) {
        draft = current
        self.current = current
        self.sortedAlphabetically = sortedAlphabetically
        // The rows are made once and kept: a slider being dragged must not be replaced by a reload of the form.
        let box = Box()
        coverage = UKPercentSliderRow("Minimum Ingredients Available", value: current.minimumCoverage, identifier: "recipes.filter.coverage") { box.controller?.draft.minimumCoverage = $0; box.controller?.sync() }
        expiringToggle = UKLabeledSwitchRow(title: "Expiring Ingredients Only", symbol: "clock", identifier: "recipes.filter.expiringOnly", isOn: current.expiringOnly) {
            box.controller?.draft.expiringOnly = $0
            box.controller?.sync()
        }
        horizon = UKSegmentedChoice(label: "Expiring Within", options: RecipeFilters.horizons, title: { RecipeFilters.horizon($0).title },
                                    selection: current.expiringWithinDays, identifier: "recipes.filter.horizon") { box.controller?.draft.expiringWithinDays = $0; box.controller?.sync() }
        availability = UKPercentSliderRow("Availability Weight", value: current.availabilityWeight, identifier: "recipes.filter.availabilityWeight") { box.controller?.draft.availabilityWeight = $0; box.controller?.sync() }
        expiry = UKPercentSliderRow("Expiry Weight", value: current.expiryWeight, identifier: "recipes.filter.expiryWeight") { box.controller?.draft.expiryWeight = $0; box.controller?.sync() }
        sheet = UKFilterSheet(title: "Filter Recipes", subtitle: current.activeSummary, canApply: false, canReset: current != .defaults,
                              onApply: { if let controller = box.controller { onApply(controller.draft) } }, onReset: { box.controller?.reset() }, sections: [])
        box.controller = self
        self.box = box
        sync()
    }

    /// Lets the rows' closures reach the controller they are built before.
    private final class Box { weak var controller: UKRecipeFilterSheetController? }
    private var box: Box?

    func present(from presenter: UIViewController) { sheet.present(from: presenter) }

    private func reset() {
        draft = .defaults
        sync()
    }

    private func sections() -> [UKFormSection] {
        [
            UKFormSection(id: "coverage", header: "Ingredient Coverage",
                          footer: "Only show recipes where at least this percentage of required ingredients is available.", headerStyle: .subheadline,
                          rows: [UKFormRow(id: "coverage", .custom { [coverage] in coverage })]),
            UKFormSection(id: "expiring", header: "Expiring Ingredients", footer: RecipeFilters.horizon(draft.expiringWithinDays).subtitle, headerStyle: .subheadline,
                          rows: [UKFormRow(id: "expiringOnly", .custom { [expiringToggle] in expiringToggle }), UKFormRow(id: "horizon", .custom { [horizon] in horizon })]),
            UKFormSection(id: "ranking", header: "Ranking Strength",
                          footer: sortedAlphabetically
                              ? "Weights are unavailable while recipes are sorted alphabetically."
                              : "Tune how strongly available and expiring ingredients influence ranked recipe results.",
                          headerStyle: .subheadline,
                          rows: [UKFormRow(id: "availability", .custom { [availability] in availability }), UKFormRow(id: "expiry", .custom { [expiry] in expiry })]),
        ]
    }

    /// Shows the draft: the row views follow it, and the sheet's check, reset row and footers.
    private func sync() {
        coverage.value = draft.minimumCoverage
        expiringToggle.show(draft.expiringOnly)
        horizon.selection = draft.expiringWithinDays
        horizon.isEnabled = draft.expiringOnly
        availability.value = draft.availabilityWeight
        expiry.value = draft.expiryWeight
        availability.isEnabled = !sortedAlphabetically
        expiry.isEnabled = !sortedAlphabetically
        sheet.update(subtitle: draft.activeSummary, canApply: draft != current, canReset: draft != .defaults, sections: sections())
    }
}

/// A switch row with a leading glyph (`Toggle { Label(title, systemImage:) }`): the canonical row (grouped metrics) with the switch in
/// its accessory slot, 44 pt at least.
final class UKLabeledSwitchRow: UKRowView {
    private let toggle = UISwitch()

    init(title: String, symbol: String?, identifier: String, isOn: Bool, onChange: @escaping (Bool) -> Void) {
        super.init(.init(title, symbol: symbol, glyph: UKDesignInk.primary, style: .form))
        toggle.isOn = isOn
        toggle.accessibilityLabel = title
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.addAction(UIAction { [weak toggle] _ in onChange(toggle?.isOn ?? false) }, for: .valueChanged)
        setAccessory(toggle)
        isTextAccessible = false
        accessibilityContainerType = .semanticGroup
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the draft's value.
    func show(_ on: Bool) {
        if toggle.isOn != on { toggle.setOn(on, animated: window != nil) }
    }
}
#endif
