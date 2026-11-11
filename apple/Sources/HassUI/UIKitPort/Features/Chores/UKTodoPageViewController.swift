#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// A page of todo lists: Chores, Groceries, each resident's chores, Home Improvement and the admin To-Do (``TodoPageView``, web
/// `TodoPageContent`).
///
/// Lists with nothing open are hidden; when every list is, the page shows its empty state. DoneTick rows open the task form to edit
/// and the admin To-Do's rows open a rename sheet. The floating Add button opens the page's create sheet. Each list is a 20 pt bold
/// header over an inset module card on the wallpaper.
///
/// **Built for the long house.** The page is one diffable `UICollectionView` list: every row is a reused, self-sizing cell
/// (``UKTodoRowCell``), a live change reconfigures the rows that differ and nothing else, and nothing draws per frame while it
/// scrolls. The list model is the SwiftUI page's own (``TodoPageLayout/sections(for:viewerUserId:store:todos:)``).
///
/// In a window that splits (iPad landscape, the unfolded Duo landscape: ``SplitPolicy``) the form for a row, the Add button or a
/// rename opens in a column beside the list; elsewhere it is a sheet. The two share the form and its draft
/// (``TodoDraftStore``), so a fold or a rotation keeps what was typed. The form is a column page like any other: its title is content
/// at the top of its list, and Close (Back) and its Save are the section bar's column group (``UKColumnsViewController``); Close asks
/// before it drops edits and waits for a save (``UKColumnPopGuarding``).
///
/// **Columns.** The Chores tab's root page hosts the sub-pages its quick links open (``ShellRoute/chores(_:)``): Your Chores, Groceries
/// ... open beside the list in a window that splits and are pushed elsewhere, as Settings' topics are. A todo page that is itself a column
/// (the quick-link pages, the admin To-Do in Settings) has no columns of its own: its forms are sheets, as the Inventory pages' editors
/// are in a half-width column.
@MainActor
final class UKTodoPageViewController: UKPageViewController, UICollectionViewDelegate, UKColumnsHosting {
    override var houseLayoutSkeleton: HouseSkeletonPlan.Kind? { .page }

    let chorePage: ChoresConfig.Page
    let model: ChoresModel
    private let headerView: (UIView & UKGridMeasuring)?

    // MARK: Rows

    /// Space above the list's first row. None: the SwiftUI page's 35 pt is its inset-grouped `List`'s own top margin, which UIKit's list
    /// does not add; here the scroll view already starts under the bar, so 35 pt more read as dead space between the title and Quick Links
    /// that no other page has (owner, 2026-11-01). The first row's own `leadingRowTopInset` is the page's standard gap.
    private static let listTopInset: CGFloat = 0

    private enum RowID: Hashable {
        case header
        case title(String)
        case error(String)
        case spinner(String)
        case item(list: String, id: String)
    }

    private struct ItemSpec: Equatable {
        var list: ChoresConfig.TodoList
        var item: TodoItem
        var due: String?
        var tone: TodoItem.DueTone?
        var isFirst: Bool
        var isLast: Bool
        var density: ModuleDensity
        var offersUndo: Bool
        var canEdit: Bool
        var canDelete: Bool
    }

    private enum RowSpec: Equatable {
        case header
        case title(String, leads: Bool)
        case error(entityId: String, message: String)
        case spinner(title: String)
        case item(ItemSpec)
    }

    /// The page's own observation (the base class's ``bag`` holds the chrome's).
    private let dataBag = UKObservationBag()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, RowID>!
    private var updater: UKListUpdater<Int, RowID>!
    private var specs: [RowID: RowSpec] = [:]

    // MARK: Chrome

    private let leadingHost = UIView()
    /// The list (column one) and what opens beside it. A page that is itself a column builds none (``context`` `isPane`).
    private(set) lazy var columns: UKColumnsViewController = {
        let page = chorePage
        let columns = UKColumnsViewController(rootView: leadingHost, shell: context.shell) {
            UKPanePlaceholderViewController(symbol: TodoPageLayout.editsItems(page) ? "square.and.pencil" : "plus.circle",
                                            text: TodoPageLayout.panePrompt(page), identifier: "todo.pane.placeholder")
        }
        columns.trailingIdentifier = "todo.pane"
        columns.onWideChange = { [weak self] wide in self?.split = wide }
        columns.onUserPop = { [weak self] depth in
            guard let self, let navigator = self.context.navigator, let section = self.context.section, self.isSectionRoot else { return }
            navigator.trimPath(in: section, toDepth: depth)
        }
        return columns
    }()
    /// Whether this page's columns exist: the page is not itself a column.
    private var hasOwnColumns: Bool { !context.isPane }
    private var bar: UKFloatingActionBar!
    /// A quick-link page open in a column of the Chores root: the root draws the one Add button for both columns, so this page keeps its
    /// own bar only as the hidden spacer that clears its last row (owner, 2026-11-02).
    var addButtonIsShared = false {
        didSet { if isViewLoaded { refreshAddButton() } }
    }
    /// The quick-link page the root's Add button belongs to while one is open beside the list.
    private weak var openSubpage: UKTodoPageViewController?
    private var addTargetKey: String?
    private var barHeight: CGFloat = 0
    private var emptyOverlay: UKCenteredStateMessageView?
    private var emptyKey: String?
    private var emptyTop: NSLayoutConstraint?
    private var emptyBottom: NSLayoutConstraint?
    private var showsEmpty = false

    // MARK: Forms

    private var sheet: TodoSheet? {
        didSet {
            guard sheet != oldValue else { return }
            // A form that is closed, saved or replaced after the discard confirmation drops its draft; a fold or rotation keeps it.
            if let oldValue { drafts.clear(oldValue.id) }
            applyPresentation()
        }
    }
    private var split = false {
        didSet {
            guard split != oldValue else { return }
            if hasOwnColumns, columns.isWide != split, !isControlledBySection { columns.setWide(split) }
            applyPresentation()
            refreshAddButton()
        }
    }
    /// Where a form opened by this page goes: nowhere beside the list when the page is a column (a sheet), else the page's own columns.
    private weak var detailPage: UIViewController?
    private var paneHasEdits = false
    private let drafts = TodoDraftStore()
    private var presentedSheetID: String?
    private var paneSheetID: String??
    private var reloadVersion = 0
    private var loadKeys: [String: TodoReloadKey] = [:]
    private var failedLists: Set<String> = []

    init(context: UKContext, page: ChoresConfig.Page, model: ChoresModel, header: (UIView & UKGridMeasuring)? = nil, title: String? = nil) {
        chorePage = page
        self.model = model
        headerView = header
        super.init(context: context, title: title ?? page.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        buildCollection()
        buildPanes()
        buildBar()
        refreshAddButton()
        setPageScrollView(collectionView)
        (headerView as? UKChoreQuickLinksView)?.onHeightChange = { [weak self] in self?.reconfigureHeader() }
        dataBag.observe { [weak self] in self?.refresh() }
    }

    #if DEBUG
    private var debugOpened = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // `FENTON_GALLERY_OPEN=edit-task|new-task`, as the SwiftUI page does.
        if sheet == nil, let next = TodoPageLayout.galleryLaunchSheet(page: chorePage) { sheet = next }
        // `FENTON_DEBUG_CHORES_OPEN=<page id>`: opens that quick-link page three seconds in, as a tap on its tile does.
        if isSectionRoot, !debugOpened, let id = ProcessInfo.processInfo.environment["FENTON_DEBUG_CHORES_OPEN"], let page = ChoresConfig.page(id) {
            debugOpened = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.openQuickLink(page) }
        }
    }
    #endif

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSplit()
        updateBarInsets()
        if let overlay = emptyOverlay, overlay.superview != nil { updateEmptyTop() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        FrameMonitor.shared.endScroll(page: "Chores · \(chorePage.id)")
    }

    /// The Chores root under a section's navigation controller: that controller decides (it is on screen whichever page shows).
    private var isControlledBySection: Bool { isSectionRoot && navigationController is UKSectionNavigationController }

    private func updateSplit() {
        // A page that is a column has no room for a pane of its own: a form there is a sheet.
        guard hasOwnColumns, !isControlledBySection, let window = view.window else { return }
        split = SplitPolicy.allowsSplit(size: window.bounds.size, isRegularWidth: window.traitCollection.horizontalSizeClass == .regular)
    }

    // MARK: Hosting

    var hostsColumnRoutes: Bool { isSectionRoot }

    func syncColumnRoutes(_ routes: [ShellRoute], animated: Bool) {
        guard hasOwnColumns, columns.isWide else { return }
        columns.reconcile(tags: routes.map { AnyHashable($0) }, make: { [unowned self] in self.makeSubpage($0.base as! ShellRoute) }, animated: animated)
        if routes.isEmpty { openSubpage = nil }
        refreshAddButton()
    }

    // MARK: Add button

    private func addAction(for page: ChoresConfig.Page) -> UKFloatingAction {
        UKFloatingAction(id: "add", title: TodoPageLayout.addTitle(page.addAction), symbol: "plus") { [weak self] in
            // Resolved at the tap: the open quick-link page when one is beside the list, else this page.
            if let shared = self?.sharedTarget { shared.open(.create) } else { self?.open(.create) }
        }
    }

    /// The quick-link page the shared Add button adds to: the one open beside the list, in a window showing columns.
    private var sharedTarget: UKTodoPageViewController? {
        guard hasOwnColumns, columns.isWide, let page = openSubpage else { return nil }
        return page
    }

    /// One Add button per window (owner, 2026-11-02: "Add task should always be overlaid in bottom right unless we're editing a chore").
    ///
    /// Where columns show, the Chores root's button floats over both, adds to the page the person is looking at (the open quick-link
    /// page, with that page's list and assignee defaults; otherwise the root's) and hides while a chore form is open. A quick-link page in
    /// a column draws none. Narrow windows keep each page's own button.
    private func refreshAddButton() {
        let target = sharedTarget
        let page = target?.chorePage ?? chorePage
        // Rebuilt only when the button's owner changes: a rebuild on every call would churn the bar's views.
        if addTargetKey != page.id {
            addTargetKey = page.id
            bar.actions = [addAction(for: page)]
        }
        let wide = hasOwnColumns && columns.isWide
        let editing = wide && sheet != nil
        bar.isHidden = UKPerfSwitches.isOff(.ukFab) || addButtonIsShared || editing
    }

    /// A quick-link page in a column: it pushes nothing on the section's stack, and shows no header buttons (the bar above carries them).
    private func makeSubpage(_ route: ShellRoute) -> UIViewController {
        let paneContext = context.with {
            $0.navigator = nil
            $0.isPane = true
        }
        guard case let .chores(id) = route, let page = ChoresConfig.page(id) else { return UKPlaceholderViewController(title: "Chores", symbol: "checklist") }
        let todo = UKChoresPages.page(page, context: paneContext, model: model)
        todo.addButtonIsShared = true
        openSubpage = todo
        return UKPageHost.wrapped(todo, context: paneContext)
    }

    /// A quick link: the page opens in a column beside the list, or is pushed where the window does not split. The navigator keeps the
    /// route either way (the section's navigation controller shows it as one or the other).
    func openQuickLink(_ page: ChoresConfig.Page) {
        guard let navigator = context.navigator, let section = context.section else {
            // No shell (the gallery): a plain push.
            navigationController?.pushViewController(UKChoresPages.page(page, context: context, model: model), animated: true)
            return
        }
        if sheet != nil { sheet = nil }
        guard navigator.routes(in: section) != [.chores(page.id)] else { return }
        navigator.trimPath(in: section, toDepth: 0)
        navigator.append(.chores(page.id), in: section)
    }

    // MARK: Building

    private func buildCollection() {
        let layout = UICollectionViewCompositionalLayout { [weak self] _, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.showsSeparators = false
            configuration.backgroundColor = .clear
            configuration.headerTopPadding = 0
            configuration.leadingSwipeActionsConfigurationProvider = { [weak self] path in self?.swipe(at: path, leading: true) }
            configuration.trailingSwipeActionsConfigurationProvider = { [weak self] path in self?.swipe(at: path, leading: false) }
            let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
            // The inset-grouped list's own space above its first section (the SwiftUI page's first row sits this far down).
            section.contentInsets.top = Self.listTopInset
            return section
        }
        collectionView = UKWidthAwareCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.allowsSelection = false
        // The page identifier goes on the list: the empty state keeps its own.
        collectionView.accessibilityIdentifier = "todo.page.\(chorePage.id)"

        let itemCell = UICollectionView.CellRegistration<UKTodoRowCell, RowID> { [weak self] cell, _, id in self?.configureItem(cell, id) }
        let plainCell = UICollectionView.CellRegistration<UKTodoPlainCell, RowID> { [weak self] cell, _, id in self?.configurePlain(cell, id) }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, id in
            if case .item = id { return collectionView.dequeueConfiguredReusableCell(using: itemCell, for: indexPath, item: id) }
            return collectionView.dequeueConfiguredReusableCell(using: plainCell, for: indexPath, item: id)
        }
        // The reapply counter is read inside `refresh()`'s observation, so a reconnect re-runs it and applies while its window is open.
        updater = UKListUpdater(surface: "Chores", collectionView: collectionView, dataSource: dataSource) { [weak self] in self?.context.store.reapplyGeneration ?? 0 }
    }

    private func buildPanes() {
        leadingHost.backgroundColor = .clear
        leadingHost.frame = contentView.bounds
        collectionView.frame = leadingHost.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        leadingHost.addSubview(collectionView)

        // The list is the first column; the form for a row opens in the second, "pick a row" fills it until one does. The form is a sheet
        // where the window does not split, so nothing is carried into a push (``UKColumnEntry/pushesWhenNarrow``).
        guard hasOwnColumns else {
            leadingHost.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.addSubview(leadingHost)
            return
        }
        addChild(columns)
        columns.view.frame = contentView.bounds
        columns.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(columns.view)
        columns.didMove(toParent: self)
    }

    private func buildBar() {
        bar = UKFloatingActionBar(actions: [addAction(for: chorePage)])
        bar.translatesAutoresizingMaskIntoConstraints = false
        // On the page itself, not in its first column: where the window shows columns the one Add button floats over all of them,
        // at the content area's bottom-right (owner, 2026-11-02; ``refreshAddButton()``).
        contentView.addSubview(bar)
        let guide = contentView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            bar.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: guide.leadingAnchor), bar.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
        ])
        if #available(iOS 26, *), !UKPerfSwitches.isOff(.ukEdgeInteraction) {
            let interaction = UIScrollEdgeElementContainerInteraction()
            interaction.scrollView = collectionView
            interaction.edge = .bottom
            bar.addInteraction(interaction)
            collectionView.bottomEdgeEffect.style = .soft
            if UKPerfSwitches.isOff(.ukBottomEdgeHard) { collectionView.bottomEdgeEffect.style = .hard }
            if UKPerfSwitches.isOff(.ukBottomEdgeHidden) { collectionView.bottomEdgeEffect.isHidden = true }
        }
    }

    /// The bar's height keeps the last row clear of it (the page's `floatingActionBar` safe-area inset).
    private func updateBarInsets() {
        let height = bar.bounds.height
        guard abs(height - barHeight) > 0.5 else { return }
        barHeight = height
        collectionView.contentInset.bottom = height
        collectionView.verticalScrollIndicatorInsets.bottom = height
        emptyBottom?.constant = -height
    }

    // MARK: Data

    /// Reads everything the page shows (inside the page's observation, so any change re-runs it) and applies the difference.
    private func refresh() {
        let store = context.store
        let sections = TodoPageLayout.sections(for: chorePage, viewerUserId: model.viewerUserId, store: store, todos: model.todos)
        let shown = sections.filter(\.isShown)
        showsEmpty = TodoPageLayout.showsEmptyState(sections)
        let now = Date.now
        let hasHeader = headerView != nil
        let deletion = TodoPageLayout.deletion(for: chorePage)

        var ids: [RowID] = []
        var specs: [RowID: RowSpec] = [:]
        func add(_ id: RowID, _ spec: RowSpec) {
            guard specs[id] == nil else { return }
            ids.append(id)
            specs[id] = spec
        }
        if hasHeader { add(.header, .header) }
        for section in shown {
            let list = section.list
            let controller = section.controller
            if !chorePage.hideListHeaders {
                add(.title(list.entityId), .title(list.title, leads: section.id == shown.first?.id && !hasHeader))
            }
            if let error = controller.error { add(.error(list.entityId), .error(entityId: list.entityId, message: error)) }
            if controller.items == nil {
                add(.spinner(list.entityId), .spinner(title: list.title))
            } else {
                let items = controller.visibleItems(hideCompleted: list.hideCompleted)
                guard !items.isEmpty else { continue }
                // Overdue spans are orange and red text, which needs the dense module over the lit windows (direction G, Layers).
                let density: ModuleDensity = TodoListSection.hasLateItem(items, now: now) ? .dense : .thin
                var unique: [TodoItem] = []
                var seen = Set<String>()
                for item in items where seen.insert(item.id).inserted { unique.append(item) }
                for (index, item) in unique.enumerated() {
                    let due = item.status == .completed ? nil : item.dueLabel(now: now)
                    add(.item(list: list.entityId, id: item.id), .item(ItemSpec(
                        list: list, item: item, due: due?.text, tone: due?.tone, isFirst: index == 0, isLast: index == unique.count - 1,
                        density: density, offersUndo: controller.offersUndo(item), canEdit: canEdit(list, item), canDelete: deletion != .unavailable)))
                }
            }
        }
        syncLoads(store)
        let vacation = store.entity(ChoresConfig.vacationModeEntityId).state?.state == "on"
        let emptyMessage = chorePage.emptyDescription(viewer: model.viewer, vacationModeOn: vacation)
        apply(ids: ids, specs: specs)
        updateEmpty(message: emptyMessage)
    }

    private func apply(ids: [RowID], specs new: [RowID: RowSpec]) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, RowID>()
        snapshot.appendSections([0])
        snapshot.appendItems(ids)
        snapshot.reconfigureItems(ids.filter { id in specs[id].map { $0 != new[id] } ?? false })
        specs = new
        // Chores animate away when completed and back in if the call fails; under Reduce Motion they fade. A reconnect, a reapply and the
        // first apply never move (``ListUpdateTransition``).
        updater.apply(snapshot)
    }

    /// A person is about to remove or bring back `item`: the change is theirs, so it is announced and focused.
    private func expect(_ expectation: UKTodoListActions.Expectation, item: TodoItem, in list: ChoresConfig.TodoList) {
        let id = RowID.item(list: list.entityId, id: item.id)
        switch expectation {
        case let .removal(title): updater.expectRemoval(of: [id], title: title)
        case .insertion: updater.expectInsertion(of: [id])
        }
    }

    private func reconfigureHeader() {
        guard dataSource != nil, specs[.header] != nil, dataSource.snapshot().itemIdentifiers.contains(.header) else { return }
        updater.redraw(where: { $0 == .header })
    }

    /// Every visible list loads, drawn or not, so a hidden list reappears when its entity says it has items again; a save or delete
    /// reloads them all (web `todoReloadVersion`).
    private func syncLoads(_ store: EntityStore) {
        for list in chorePage.lists where list.isVisible(to: model.viewerUserId, openItems: store.entity(list.entityId).state) {
            let controller = model.todos.controller(for: list.entityId)
            let key = TodoReloadKey(entity: store.entity(list.entityId).state, version: reloadVersion)
            if loadKeys[list.entityId] != key {
                loadKeys[list.entityId] = key
                Task { await controller.load() }
            }
            // The inline error says what failed; the haptic says it at once (a check-off that rolled back).
            if controller.error != nil {
                if failedLists.insert(list.entityId).inserted { UKTapFeedback.failure() }
            } else {
                failedLists.remove(list.entityId)
            }
        }
    }

    private func reload() {
        reloadVersion += 1
        loadKeys = [:]
        dataBag.removeAll()
        dataBag.observe { [weak self] in self?.refresh() }
    }

    // MARK: Cells

    private func configureItem(_ cell: UKTodoRowCell, _ id: RowID) {
        guard case let .item(spec)? = specs[id] else { return }
        let list = spec.list
        let item = spec.item
        let controller = model.todos.controller(for: list.entityId)
        let actions = UKTodoItemRow.Actions(
            onToggle: { [weak self] in self?.toggle(item, in: list) },
            onEdit: spec.canEdit ? { [weak self] in self?.edit(list, item) } : nil,
            onUndo: spec.offersUndo ? { [weak self] in UKTodoListActions.undo(item, controller: controller) { self?.expect($0, item: item, in: list) } } : nil,
            onDelete: spec.canDelete ? { [weak self] in self?.delete(item, in: list, from: cell) } : nil,
            menu: { [weak self, weak cell] in
                guard let self else { return nil }
                let rowActions = UKTodoListActions.actions(for: item, canEdit: spec.canEdit, canDelete: spec.canDelete)
                return UKTodoListActions.menu(rowActions) { action in self.perform(action, spec, cell: cell) }
            })
        cell.configure(item: item, now: .now, density: spec.density, isFirst: spec.isFirst, isLast: spec.isLast, surface: .page, actions: actions)
    }

    private func configurePlain(_ cell: UKTodoPlainCell, _ id: RowID) {
        switch specs[id] {
        case .header?:
            guard let headerView else { return }
            // A plain row, like the others, so the tiles share the modules' edges through the list's own insets.
            headerView.isHidden = UKPerfSwitches.isOff(.ukHeaderTiles)
            cell.host(headerView, top: TodoPageLayout.leadingRowTopInset, bottom: 0)
        case let .title(title, leads)?:
            cell.host(UKPageSectionHeaderView(title), top: leads ? TodoPageLayout.leadingRowTopInset : HassTokens.Spacing.xl, bottom: HassTokens.Spacing.s)
        case let .error(entityId, message)?:
            let alert = UKInlineAlertView(message)
            // The journeys find the message itself among the static texts.
            alert.accessibilityLabel = message
            alert.accessibilityIdentifier = "todo.error.\(entityId)"
            cell.host(alert, top: 0, bottom: HassTokens.Spacing.s)
        case let .spinner(title)?:
            cell.host(UKTodoSpinnerRow(label: "Loading \(title)"), top: 0, bottom: 0)
        default:
            break
        }
    }

    // MARK: Actions

    /// DoneTick rows edit through the task form (only rows whose uid carries a task id); admin To-Do rows rename.
    private func canEdit(_ list: ChoresConfig.TodoList, _ item: TodoItem) -> Bool {
        if chorePage.hasTaskForm { return DonetickEditTarget(item: item, listEntityId: list.entityId) != nil }
        return chorePage.editsAdminTodo
    }

    private func edit(_ list: ChoresConfig.TodoList, _ item: TodoItem) {
        if chorePage.hasTaskForm {
            guard let target = DonetickEditTarget(item: item, listEntityId: list.entityId) else { return }
            open(.editTask(target))
        } else if chorePage.editsAdminTodo {
            open(.renameTodo(AdminTodoEditTarget(itemUid: item.uid, originalTitle: item.summary ?? "", todoEntityId: list.entityId)))
        }
    }

    private func toggle(_ item: TodoItem, in list: ChoresConfig.TodoList) {
        UKTodoListActions.toggle(item, in: list, controller: model.todos.controller(for: list.entityId)) { [weak self] in self?.expect($0, item: item, in: list) }
    }

    /// Asks first, or deletes at once on a page that doesn't confirm.
    private func delete(_ item: TodoItem, in list: ChoresConfig.TodoList, from cell: UIView? = nil) {
        let controller = model.todos.controller(for: list.entityId)
        switch TodoPageLayout.deletion(for: chorePage) {
        case .unavailable: break
        case .confirm:
            UKTodoListActions.confirmDelete(item, controller: controller, from: self, source: cell.map(UKPopoverSource.view) ?? UKPopoverSource.none) { [weak self] in
                self?.expect($0, item: item, in: list)
            }
        case .immediate:
            expect(.removal(title: item.displayTitle), item: item, in: list)
            Task { await controller.remove(item) }
        }
    }

    private func perform(_ action: TodoRowActions.Action, _ spec: ItemSpec, cell: UIView?) {
        switch action {
        case .complete, .reopen: toggle(spec.item, in: spec.list)
        case .edit: edit(spec.list, spec.item)
        case .delete: delete(spec.item, in: spec.list, from: cell)
        }
    }

    private func itemSpec(at path: IndexPath) -> ItemSpec? {
        guard let id = dataSource.itemIdentifier(for: path), case let .item(spec)? = specs[id] else { return nil }
        return spec
    }

    private func swipe(at path: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? {
        guard let spec = itemSpec(at: path) else { return nil }
        let cell = collectionView.cellForItem(at: path)
        let actions = UKTodoListActions.actions(for: spec.item, canEdit: spec.canEdit, canDelete: spec.canDelete)
        return UKTodoListActions.swipeConfiguration(actions, item: spec.item, leading: leading) { [weak self] action in self?.perform(action, spec, cell: cell) }
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool { false }
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool { false }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let spec = itemSpec(at: indexPath) else { return nil }
        let cell = collectionView.cellForItem(at: indexPath)
        let actions = UKTodoListActions.actions(for: spec.item, canEdit: spec.canEdit, canDelete: spec.canDelete)
        return UIContextMenuConfiguration(identifier: spec.item.id as NSString, previewProvider: nil) { [weak self] _ in
            UKTodoListActions.menu(actions) { action in self?.perform(action, spec, cell: cell) }
        }
    }

    // MARK: Scroll telemetry

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { FrameMonitor.shared.beginScroll(page: "Chores · \(chorePage.id)") }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { FrameMonitor.shared.endScroll(page: "Chores · \(chorePage.id)") }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { FrameMonitor.shared.endScroll(page: "Chores · \(chorePage.id)") }

    // MARK: Empty state

    /// Centred in what the list leaves, below the quick links and above the Add button, not a row at the top of its content.
    private func updateEmpty(message: String) {
        let key = showsEmpty ? "\(chorePage.emptyTitle)|\(message)" : nil
        guard key != emptyKey else { return }
        emptyKey = key
        emptyOverlay?.removeFromSuperview()
        emptyOverlay = nil
        emptyTop = nil
        emptyBottom = nil
        guard showsEmpty else { return }
        // The checklist glyph on the wallpaper.
        let state = UKStateMessageView(symbol: "checklist", title: chorePage.emptyTitle, message: message, identifier: "todo.empty")
        let overlay = UKCenteredStateMessageView(state)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        leadingHost.addSubview(overlay)
        let top = overlay.topAnchor.constraint(equalTo: leadingHost.safeAreaLayoutGuide.topAnchor)
        let bottom = overlay.bottomAnchor.constraint(equalTo: leadingHost.safeAreaLayoutGuide.bottomAnchor, constant: -barHeight)
        NSLayoutConstraint.activate([top, bottom, overlay.leadingAnchor.constraint(equalTo: leadingHost.leadingAnchor),
                                     overlay.trailingAnchor.constraint(equalTo: leadingHost.trailingAnchor)])
        emptyTop = top
        emptyBottom = bottom
        emptyOverlay = overlay
        updateEmptyTop()
    }

    /// Where the quick links end, so the message centres below them.
    private func updateEmptyTop() {
        guard let emptyTop, headerView != nil else { return }
        let path = IndexPath(item: 0, section: 0)
        guard let attributes = collectionView.layoutAttributesForItem(at: path) else { return }
        let bottom = collectionView.convert(attributes.frame, to: leadingHost).maxY
        let safeTop = leadingHost.safeAreaInsets.top
        let constant = max(0, bottom - safeTop)
        if abs(emptyTop.constant - constant) > 0.5 { emptyTop.constant = constant }
    }

    // MARK: Forms

    /// Opens a form: a sheet, or in the trailing pane, where an edited form is replaced only after the discard confirmation.
    fileprivate func open(_ next: TodoSheet) {
        switch TodoPageLayout.switchDecision(current: split ? sheet : nil, next: next, hasEdits: paneHasEdits) {
        case .switchNow: sheet = next
        case .confirm: UKDiscardGuard.confirm(from: self, source: .none) { [weak self] in self?.sheet = next }
        }
    }

    private func makeForm(_ sheet: TodoSheet) -> UKTodoFormController {
        let reload = { [weak self] in self?.reload() }
        let form: UKTodoFormController
        switch sheet {
        case .create:
            switch chorePage.addAction {
            case let .assignedTask(defaultAssignee):
                form = UKDonetickTaskViewController(model: model, mode: .create(defaultAssignee: defaultAssignee), connection: context.connection, onSaved: { reload() })
            case let .groceryItem(entityId):
                form = UKAddGroceryItemController(model: model, entityId: entityId)
            case let .adminTodo(entityId):
                form = UKAddAdminTodoController(model: model, entityId: entityId)
            }
        case let .editTask(target):
            form = UKDonetickTaskViewController(model: model, mode: .edit(target), connection: context.connection, onSaved: { reload() })
        case let .renameTodo(target):
            form = UKRenameTodoItemController(model: model, target: target, onSaved: { reload() })
        }
        form.drafts = TodoDraftHandle(store: drafts, key: sheet.id)
        form.closeForm = { [weak self] in self?.sheet = nil }
        return form
    }

    /// The hand-over rule: a splitting window shows the open form in the pane, a single-page one as a sheet.
    private func applyPresentation() {
        guard isViewLoaded else { return }
        defer { refreshAddButton() }
        let presentation = TodoPageLayout.presentation(open: sheet, split: split)
        if let next = presentation.sheet {
            if presentedSheetID != next.id { presentSheet(next) }
        } else if presentedSheetID != nil {
            presentedSheetID = nil
            presentedViewController?.dismiss(animated: true)
        }
        updatePane(presentation.pane)
    }

    private func presentSheet(_ next: TodoSheet) {
        if let existing = presentedViewController, presentedSheetID != nil { existing.dismiss(animated: false) }
        guard view.window != nil else { return }
        let form = makeForm(next)
        var options = UKHassModalOptions(title: form.title, fitKey: "todo.\(next.id)")
        options.showsClose = false
        options.height = TodoPageLayout.sheetHeight(next, addAction: chorePage.addAction)
        options.onDismissed = { [weak self] in
            guard let self else { return }
            self.presentedSheetID = nil
            if self.sheet?.id == next.id { self.sheet = nil }
        }
        presentedSheetID = next.id
        UKHassModalController(root: form, options: options).present(from: self)
    }

    private func updatePane(_ target: TodoSheet?) {
        if let paneSheetID, paneSheetID == target?.id { return }
        paneSheetID = .some(target?.id)
        paneHasEdits = false
        guard hasOwnColumns else { return }
        if let detail = detailPage {
            columns.remove(detail, animated: view.window != nil)
            detailPage = nil
        }
        guard let target else { return }
        let form = makeForm(target)
        form.onEditsChange = { [weak self] edits in self?.paneHasEdits = edits }
        // The form is a column page: its title is content, Close is in the section bar's column group, and its Save rides there with it.
        // It replaces whatever is open beside the list, quick-link pages included (the left column replaces the right).
        columns.open(form, tag: nil, atDepth: 0, ground: .systemBackground, hairline: true, animated: view.window != nil, pushesWhenNarrow: false) { [weak self] in
            // Close or Back ended it: the page forgets the form and drops its draft, as Cancel did.
            guard let self, self.detailPage === form else { return }
            self.detailPage = nil
            self.paneSheetID = .some(nil)
            self.sheet = nil
        }
        detailPage = form
        if isControlledBySection, let navigator = context.navigator, let section = context.section, !navigator.routes(in: section).isEmpty {
            navigator.trimPath(in: section, toDepth: 0)
        }
    }
}
#endif
