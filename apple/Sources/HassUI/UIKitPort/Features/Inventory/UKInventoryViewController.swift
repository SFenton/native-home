#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// An inventory page: All Food, Pantry, Fridge, Freezer, Spice Rack or Cabinet (``InventoryScreen``; web `EverShelfInventoryPanel`;
/// spec `.agents/pages/inventory/spec.md`).
///
/// Rows come from `evershelf.list_inventory`, on one dense module under the large title
/// (direction G mockup n6-inventory; no item-count line under the title, owner 2026-10-30). Search, Sort, Filter and Scan Item form the page's bottom bar. Rows open the item editor: as a
/// sheet, or in the trailing half where the window may split (iPad landscape, unfolded iPhone Duo landscape).
final class UKInventoryViewController: UKPageViewController {
    private let model: InventoryListModel
    private let models: InventoryModels
    private let launch: InventoryLaunch?
    private let presentation: InventoryPresentation
    private let list: UKInventoryListViewController
    private let search = UKFloatingSearch(prompt: "Search items")
    private let bar: UKFloatingActionBar
    private let pinned: UKPinnedBarViewController
    private let columns: UKColumnsViewController
    private let barHost = UKInventoryBarHost()
    private var toolbarSplit: Bool?
    private var toolbarSize: CGSize = .zero
    private var paneController: UKInventoryEditorPaneViewController?
    private var presentedKind: String?
    private let rowActions: UKInventoryRowActionsHost
    private var barHadControls: Bool?
    private var barHadSearch: Bool?
    private var opened = false
    private var loadTask: Task<Void, Never>?

    private var space: InventorySpace { model.space }

    /// - Parameters:
    ///   - launch: A sheet or editor to open once rows load (debug gallery and journeys).
    ///   - presentation: What the page starts out presenting (tests).
    init(context: UKContext, model: InventoryListModel, models: InventoryModels, launch: InventoryLaunch? = nil,
         presentation: InventoryPresentation = InventoryPresentation()) {
        self.model = model
        self.models = models
        self.launch = launch
        self.presentation = presentation
        list = UKInventoryListViewController(context: context, model: model, presentation: presentation)
        rowActions = UKInventoryRowActionsHost(presentation: presentation, model: model, context: context)
        bar = UKFloatingActionBar(actions: [], search: nil)
        // The list is the first column; the item editor opens in the second, and "Select an item to see its details" fills it until one is.
        // The editor is a sheet where the window does not split, so nothing is carried into a push (``UKColumnsViewController/pushesCollapsedPages``).
        columns = UKColumnsViewController(rootController: list, shell: context.shell) {
            UKPanePlaceholderViewController(symbol: "square.and.pencil", text: "Select an item to see its details", identifier: "inventory.pane.placeholder")
        }
        columns.pushesCollapsedPages = false
        barHost.install(bar)
        pinned = UKPinnedBarViewController(content: columns, bar: barHost, scrollView: list.collectionView)
        super.init(context: context, title: model.space.title)
        // Close (or Back) in the column bar ends the edit, as the pane's own close did.
        columns.onUserPop = { [weak self] _ in self?.presentation.editing = nil }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        list.onEdit = { [weak self] item in
            guard let self else { return }
            self.presentation.open(item, in: self.model)
        }
        list.onShop = { [weak self] item in self?.presentation.ask(.shopping(item)) }
        list.onDelete = { [weak self] item in
            guard let self else { return }
            self.presentation.requestDelete(item, in: self.model)
        }
        addChild(pinned)
        pinned.view.frame = contentView.bounds
        pinned.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(pinned.view)
        pinned.didMove(toParent: self)
        setPageScrollView(list.collectionView)
        list.enablePullToRefresh()
        // The page identifier belongs to the list column: on the whole row it replaced the editor pane's identifiers.
        list.view.accessibilityContainerType = .semanticGroup
        list.view.accessibilityIdentifier = "inventory.\(space.rawValue)"

        if !model.searchQuery.isEmpty {
            search.text = model.searchQuery
            search.isExpanded = true
        }
        bag.observe { [weak self] in self?.syncBar() }
        bag.observe { [weak self] in
            guard let self else { return }
            let text = self.search.text
            if self.model.searchQuery != text { self.model.searchQuery = text }
        }
        rowActions.presenter = self
        rowActions.start()
        bag.observe { [weak self] in self?.syncPresentation() }
        bag.observe { [weak self] in self?.syncToolbarSplit() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.model.load()
            guard !self.opened else { return }
            self.opened = true
            self.presentation.open(self.launch, in: self.model)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        syncPresentation()
        syncToolbarSplit()
        rowActions.sync()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        presentation.updateSplit(contentView.bounds.size, isRegularWidth: traitCollection.horizontalSizeClass == .regular)
    }

    // MARK: Bar

    /// Sort and Filter (filled while applied) once there is something to sort, then Scan Item: a titled glass capsule on an empty page
    /// (mockup n6-inventory-empty), a glass circle beside the others (web `EverShelfInventoryFloatingActions` + the scan FAB).
    private func syncBar() {
        let hasControls = !model.items.isEmpty || model.searchActive
        let sortActive = model.sortActive
        let filterActive = model.filterActive
        let showsSearch = model.phase == .content && hasControls
        if barHadControls != hasControls {
            barHadControls = hasControls
            var actions: [UKFloatingAction] = []
            if hasControls {
                actions.append(UKFloatingAction(id: "inventory.sort", title: "Sort", symbol: "arrow.up.arrow.down", showsTitle: false, isActive: sortActive) { [weak self] in self?.presentation.sheet = .sort })
                actions.append(UKFloatingAction(id: "inventory.filter", title: "Filter", symbol: "line.3.horizontal.decrease", showsTitle: false, isActive: filterActive) { [weak self] in self?.presentation.sheet = .filter })
            }
            actions.append(UKFloatingAction(id: "inventory.scan", title: "Scan Item", symbol: "barcode.viewfinder", showsTitle: !hasControls, isProminent: false) { [weak self] in self?.presentation.sheet = .scan })
            bar.actions = actions
        } else if hasControls {
            bar.setActive(sortActive, forActionID: "inventory.sort")
            bar.setActive(filterActive, forActionID: "inventory.filter")
        }
        if barHadSearch != showsSearch {
            barHadSearch = showsSearch
            bar.setSearch(showsSearch ? search : nil)
        }
    }

    /// The bar over a partly folded split window (owner, 2026-11-01): the page divides on the hinge, so the search stays over the list (left
    /// of the hinge) and Sort, Filter and Scan Item sit on the right, over the detail pane, with their titles. Lying flat it keeps the
    /// bar in the list's half, as before; portrait and folded, the bar is the page's. Changes animate with the fold's own reflow.
    private func syncToolbarSplit() {
        // Read first: the observation records what this reads, and the page may not be on screen yet.
        let canSplit = presentation.canSplit
        let hinge = context.shell?.windowHinge
        guard isViewLoaded, view.window != nil else { return }
        let size = pinned.view.bounds.size
        let geometry = SplitPolicy.columnWidths(container: pinned.view.convert(pinned.view.bounds, to: nil), hinge: hinge, gutter: 0)
        // The band: a vertical hinge inside the page (nil while lying flat, when the page divides at the midpoint).
        let band = hinge.flatMap { $0.height >= $0.width && $0.width > 0 ? $0 : nil }
        let global = pinned.view.convert(pinned.view.bounds, to: nil)
        let split = canSplit && band.map { $0.midX > global.minX && $0.midX < global.maxX } == true
        let column = band.map { $0.minX - global.minX } ?? geometry.leadingWidth
        defer { toolbarSize = size }
        // A rotation is not a posture change: its new shape lands with it, unanimated.
        let animated = toolbarSplit != nil && toolbarSplit != split && size == toolbarSize
        toolbarSplit = split
        let change = {
            // Half of the page while a split shows the detail pane beside the list, else the whole page.
            self.barHost.confinesToLeadingHalf = canSplit && !split
            self.barHost.layoutIfNeeded()
        }
        if animated { UKMotion.animate(.standard, reduced: .quick, animations: change) } else { change() }
        bar.setSplit(leadingColumn: split ? column : nil, expandsActions: split, animated: animated)
    }

    // MARK: Presentation

    private func syncPresentation() {
        let sheet = presentation.sheet
        let editing = presentation.editing
        let canSplit = presentation.canSplit
        guard isViewLoaded, view.window != nil else { return }

        // The editor in the trailing pane while the window may split (as a sheet otherwise, which the row actions present).
        if canSplit {
            showPane(for: editing)
        } else {
            removePane()
        }

        if presentedKind == nil, presentedViewController == nil {
            if let sheet { presentSheet(sheet) }
        } else if let kind = presentedKind, sheet?.rawValue != kind, presentedViewController?.isBeingDismissed == false {
            // The model cleared what is up: take it down.
            presentedKind = nil
            presentedViewController?.dismiss(animated: true)
        }
    }

    private func presentSheet(_ sheet: InventorySheet) {
        presentedKind = sheet.rawValue
        switch sheet {
        case .sort:
            let controller = UKInventorySheets.sort(model: model) { [weak self] in self?.sheetGone() }
            controller.present(from: self)
        case .filter:
            let controller = UKInventorySheets.filter(model: model) { [weak self] in self?.sheetGone() }
            controller.present(from: self)
        case .scan:
            let scan = ScanItemModel(space: model.space, client: models.everShelf)
            UKScanItemSheet.present(model: scan, from: self, context: context, onAdded: { [models] in Task { await models.refreshLoaded() } }) { [weak self] in
                self?.sheetGone()
            }
        }
    }

    private func sheetGone() {
        presentedKind = nil
        if presentation.sheet != nil { presentation.sheet = nil }
    }

    // MARK: Pane

    /// The detail column beside the list: the editor of the open item, or the prompt to pick one. Wherever the window may split the column
    /// is always there (the prompt keeps it from being an empty wallpaper); elsewhere it is not, and the editor is a sheet.
    private func showPane(for editor: InventoryEditorModel?) {
        columns.setWide(true)
        guard let editor else {
            paneController = nil
            columns.setDetail(nil, animated: view.window != nil)
            return
        }
        if paneController?.model === editor { return }
        let pane = UKInventoryEditorPaneViewController(model: editor, context: context) { [weak self] in
            self?.presentation.editing = nil
        }
        paneController = pane
        // The editor draws its own title and Close, so the columns add no header; another item dissolves in over the open one.
        columns.setDetail(pane, animated: view.window != nil)
    }

    /// No second column at all (the window may not split): the editor is a sheet there.
    private func removePane() {
        paneController = nil
        columns.setWide(false)
    }
}

// MARK: - Bar host

/// The page's bottom bar, full width so it can reach across a split window: the bar fills it, or only its leading half while the detail
/// pane sits beside the list and the bar belongs to the list. Touches in the empty part go through to the pane.
final class UKInventoryBarHost: UIView {
    private var fullWidth: NSLayoutConstraint?
    private var half: NSLayoutConstraint?

    /// The bar takes the list's half of the window (the midpoint split), not the window.
    var confinesToLeadingHalf = false {
        didSet {
            guard confinesToLeadingHalf != oldValue else { return }
            fullWidth?.isActive = !confinesToLeadingHalf
            half?.isActive = confinesToLeadingHalf
        }
    }

    func install(_ bar: UIView) {
        addSubview(bar)
        bar.translatesAutoresizingMaskIntoConstraints = false
        let full = bar.trailingAnchor.constraint(equalTo: trailingAnchor)
        let halved = bar.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.5)
        fullWidth = full
        half = halved
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor), bar.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor), full,
        ])
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

// MARK: - Alerts

/// Confirmation dialogs whose buttons carry identifiers (UIKit has none for alert actions; the label's view gets one once the dialog is up).
@MainActor
enum UKInventoryAlerts {
    /// "Delete Honey?" with the place in the message: a destructive confirm and Cancel (``AlertCopy``), as an action sheet (a popover on iPad).
    static func confirmDelete(_ spec: AlertCopy.Spec, from controller: UIViewController, source: UKPopoverSource = .none, confirmID: String,
                              onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        let dialog = UIAlertController(title: spec.title, message: spec.message, preferredStyle: .actionSheet)
        dialog.addAction(UIAlertAction(title: spec.confirm.title, style: spec.confirm.role == .destructive ? .destructive : .default) { _ in onConfirm() })
        dialog.addAction(UIAlertAction(title: spec.cancel.title, style: .cancel) { _ in onCancel() })
        source.attach(to: dialog.popoverPresentationController, fallback: controller.view)
        (controller.presentedViewController ?? controller).present(dialog, animated: true) {
            tag(spec.confirm.title, as: confirmID, in: dialog.view)
        }
    }

    /// Sets `identifier` on the accessibility element that reads `title` inside `view`.
    static func tag(_ title: String, as identifier: String, in view: UIView) {
        if view.accessibilityLabel == title, view.isAccessibilityElement { view.accessibilityIdentifier = identifier }
        for child in view.subviews { tag(title, as: identifier, in: child) }
    }
}

// MARK: - List

/// The inventory rows under the large title: a list on dense module cards (a `List` of ``ModuleRowBackground`` rows) with swipe actions
/// (delete for single-batch items, add to groceries), status headers when sorted by expiration, a loading arc and the empty and error
/// states. Rows keep to a readable measure on wide windows.
final class UKInventoryListViewController: UKPaneViewController, UICollectionViewDelegate {
    enum Item: Hashable {
        case row(String)
    }

    var onEdit: (InventoryDisplayItem) -> Void = { _ in }
    var onShop: (InventoryDisplayItem) -> Void = { _ in }
    var onDelete: (InventoryDisplayItem) -> Void = { _ in }

    private let context: UKContext
    private let model: InventoryListModel
    private let presentation: InventoryPresentation
    private(set) lazy var collectionView: UICollectionView = UKWidthAwareCollectionView(frame: .zero, collectionViewLayout: makeLayout())
    private var dataSource: UICollectionViewDiffableDataSource<String, Item>!
    private let bag = UKObservationBag()
    private let loading: UKArcSpinnerView
    private let searching = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private var stateView: UKCenteredStateMessageView?
    private var shownState = ""
    private var sections: [InventorySection] = []
    private var rows: [String: InventoryDisplayItem] = [:]
    private var positions: [String: (isFirst: Bool, isLast: Bool)] = [:]

    /// The widest the rows run (HIG Layout: readable content width).
    private func margin(forWidth width: CGFloat) -> CGFloat { InventoryScreen.sideMargin(forWidth: width) }

    init(context: UKContext, model: InventoryListModel, presentation: InventoryPresentation) {
        self.context = context
        self.model = model
        self.presentation = presentation
        loading = UKArcSpinnerView(.compact, label: "Loading \(model.space.title)")
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func enablePullToRefresh() {
        guard collectionView.refreshControl == nil else { return }
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self, weak refresh] _ in
            Task { @MainActor in
                _ = try? await self?.model.refresh()
                refresh?.endRefreshing()
            }
        }, for: .valueChanged)
        collectionView.refreshControl = refresh
        UKScrollFit.allowsPullToRefresh(collectionView)
    }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor), collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor), collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        loading.color = UKInk.secondary
        loading.accessibilityIdentifier = "inventory.loading"
        loading.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loading)
        NSLayoutConstraint.activate([
            loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loading.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: HassTokens.Spacing.xl),
        ])
        let searchArc = UKArcSpinnerView(.compact, label: "Searching inventory")
        searchArc.translatesAutoresizingMaskIntoConstraints = false
        searching.contentView.addSubview(searchArc)
        searching.accessibilityIdentifier = "inventory.searching"
        searching.layer.cornerRadius = 20
        searching.clipsToBounds = true
        searching.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searching)
        NSLayoutConstraint.activate([
            searchArc.topAnchor.constraint(equalTo: searching.contentView.topAnchor, constant: HassTokens.Spacing.s),
            searchArc.bottomAnchor.constraint(equalTo: searching.contentView.bottomAnchor, constant: -HassTokens.Spacing.s),
            searchArc.leadingAnchor.constraint(equalTo: searching.contentView.leadingAnchor, constant: HassTokens.Spacing.m),
            searchArc.trailingAnchor.constraint(equalTo: searching.contentView.trailingAnchor, constant: -HassTokens.Spacing.m),
            searching.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            searching.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: HassTokens.Spacing.s * 2),
        ])
        searching.isHidden = true

        let rowCell = UICollectionView.CellRegistration<UKInventoryRowCell, Item> { [weak self] cell, _, item in
            guard let self, case let .row(id) = item, let row = self.rows[id] else { return }
            let position = self.positions[id] ?? (true, true)
            let selected = self.presentation.canSplit && self.presentation.editing?.itemId == id
            cell.configure(item: row, model: self.model, isFirst: position.isFirst, isLast: position.isLast, selected: selected, surface: .page,
                           actions: UKInventoryRowActions(onEdit: { [weak self] in self?.onEdit(row) }, onShop: { [weak self] in self?.onShop(row) }))
        }
        let header = UICollectionView.SupplementaryRegistration<UKInventoryHeaderView>(elementKind: UICollectionView.elementKindSectionHeader) { [weak self] view, _, path in
            guard let self, let section = self.dataSource.snapshot().sectionIdentifiers[safe: path.section],
                  let model = self.sections.first(where: { $0.id == section }), let title = model.title else { return }
            view.configure(title: title, count: model.items.count, id: model.id)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, item in
            switch item {
            case .row: collectionView.dequeueConfiguredReusableCell(using: rowCell, for: indexPath, item: item)
            }
        }
        dataSource.supplementaryViewProvider = { collectionView, _, path in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: path)
        }
        bag.observe { [weak self] in self?.refresh() }
        bag.observe { [weak self] in
            guard let self else { return }
            // The row that is open beside the list is washed.
            _ = self.presentation.canSplit
            _ = self.presentation.editing?.itemId
            self.reconfigureSelection()
        }
    }


    // MARK: Layout

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let self else { return Self.emptySection() }
            let identifiers = self.dataSource?.snapshot().sectionIdentifiers ?? []
            let id = identifiers[safe: index]
            var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
            configuration.showsSeparators = false
            configuration.backgroundColor = .clear
            let hasHeader = id.flatMap { id in self.sections.first { $0.id == id }?.title } != nil
            configuration.headerMode = hasHeader ? .supplementary : .none
            configuration.leadingSwipeActionsConfigurationProvider = { [weak self] path in self?.leadingSwipe(at: path) }
            configuration.trailingSwipeActionsConfigurationProvider = { [weak self] path in self?.trailingSwipe(at: path) }
            let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
            let side = self.margin(forWidth: environment.container.effectiveContentSize.width)
            // The section headers carry their own space.
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: side, bottom: HassTokens.Spacing.m, trailing: side)
            return section
        }
    }

    private static func emptySection() -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(1))
        return NSCollectionLayoutSection(group: .vertical(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)]))
    }

    // MARK: Swipe

    private func item(at path: IndexPath) -> InventoryDisplayItem? {
        guard case let .row(id)? = dataSource.itemIdentifier(for: path) else { return nil }
        return rows[id]
    }

    func trailingSwipe(at path: IndexPath) -> UISwipeActionsConfiguration? {
        guard let item = item(at: path), model.deletableRows(of: item) != nil, model.batches(for: item).count <= 1 else { return nil }
        return UKSwipeAction.configuration([UKSwipeAction("Delete", systemImage: "trash", role: .destructive) { [weak self] done in
            self?.onDelete(item)
            done(true)
        }])
    }

    func leadingSwipe(at path: IndexPath) -> UISwipeActionsConfiguration? {
        guard let item = item(at: path) else { return nil }
        return UKSwipeAction.configuration([UKSwipeAction("Add to Groceries", systemImage: "cart.badge.plus", tint: UKFloatingActionBar.tint) { [weak self] done in
            self?.onShop(item)
            done(true)
        }])
    }

    // MARK: State

    private func refresh() {
        let phase = model.phase
        let empty = model.emptyState
        let isError = model.loadError != nil
        let visible = model.visibleItems
        let sort = model.sortMode
        let isSearching = model.isSearching
        let built = InventorySections.make(visible, sort: sort, calendar: model.calendar)

        loading.isHidden = phase != .loading
        searching.isHidden = !(isSearching && phase != .loading && empty == nil)

        var state = ""
        if phase != .loading, let empty { state = "\(isError ? "error" : "empty")|\(empty.title)|\(empty.description)" }
        collectionView.isHidden = phase == .loading || !state.isEmpty
        if state != shownState {
            shownState = state
            stateView?.removeFromSuperview()
            stateView = nil
            if let empty, !state.isEmpty {
                // Centred on the page (mockup n6-inventory-empty), and still scrolling once AX sizes make it taller.
                let message = UKStateMessageView(symbol: isError ? "exclamationmark.triangle" : "basket", title: empty.title, message: empty.description,
                                                 actionTitle: isError ? AlertCopy.tryAgain : nil,
                                                 action: isError ? { [weak self] in Task { _ = try? await self?.model.refresh() } } : nil, identifier: "inventory.empty")
                let centred = UKCenteredStateMessageView(message)
                centred.translatesAutoresizingMaskIntoConstraints = false
                view.insertSubview(centred, belowSubview: loading)
                NSLayoutConstraint.activate([
                    centred.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), centred.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
                    centred.leadingAnchor.constraint(equalTo: view.leadingAnchor), centred.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                ])
                UKScrollFit.allowsPullToRefresh(centred)
                let refresh = UIRefreshControl()
                refresh.addAction(UIAction { [weak self, weak refresh] _ in
                    Task { @MainActor in
                        _ = try? await self?.model.refresh()
                        refresh?.endRefreshing()
                    }
                }, for: .valueChanged)
                centred.refreshControl = refresh
                stateView = centred
            }
        }

        sections = built
        var items: [String: InventoryDisplayItem] = [:]
        var places: [String: (isFirst: Bool, isLast: Bool)] = [:]
        for section in built {
            for (index, item) in section.items.enumerated() {
                items[item.id] = item
                places[item.id] = (index == 0, index == section.items.count - 1)
            }
        }
        var snapshot = NSDiffableDataSourceSnapshot<String, Item>()
        for section in built {
            snapshot.appendSections([section.id])
            snapshot.appendItems(section.items.map { .row($0.id) }, toSection: section.id)
        }
        // A row whose card changed (a quantity, its place on the module) is redrawn in place; the rest are not touched.
        var changed: [Item] = []
        for (id, item) in items where rows[id] != item || positions[id]?.isFirst != places[id]?.isFirst || positions[id]?.isLast != places[id]?.isLast {
            if rows[id] != nil { changed.append(.row(id)) }
        }
        rows = items
        positions = places
        snapshot.reconfigureItems(changed.filter { snapshot.itemIdentifiers.contains($0) })
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func reconfigureSelection() {
        guard dataSource != nil else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { if case .row = $0 { return true } else { return false } })
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: Delegate

    // Rows open the editor with their own tap recognizer (``UKInventoryRowView``), so the list selects nothing.
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool { false }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool { false }
}

/// One group's status header with its count (``PageSectionHeader``), identifier `inventory.section.<id>`.
final class UKInventoryHeaderView: UICollectionReusableView {
    private let header = UKPageSectionHeaderView("", detail: nil)

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(header)
        accessibilityContainerType = .semanticGroup
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(title: String, count: Int, id: String) {
        header.configure(title: title, detail: String(count))
        accessibilityIdentifier = "inventory.section.\(id)"
        accessibilityLabel = title
        setNeedsLayout()
    }

    private var inset: CGFloat { HassTokens.Spacing.l }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = max(0, bounds.width - 2 * inset)
        header.frame = CGRect(x: inset, y: HassTokens.Spacing.s, width: width, height: header.gridHeight(forWidth: width))
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as? UICollectionViewLayoutAttributes ?? layoutAttributes
        let width = max(0, layoutAttributes.size.width - 2 * inset)
        attributes.size.height = ceil(header.gridHeight(forWidth: width)) + HassTokens.Spacing.s * 2
        return attributes
    }
}
#endif
