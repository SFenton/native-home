#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Shared list

/// The list under both chore tabs and the Expired Food tab: one diffable inset-grouped `UICollectionView` of reused cells with swipe
/// actions, on the sheet's ground (`List` with `groupedListStyle` in the SwiftUI tabs). Subclasses say which cell an id is, how to
/// configure it and which swipes it has.
@MainActor
class UKSummaryListViewController: UKPaneViewController, UKSheetFitting, UICollectionViewDelegate {
    private(set) var collectionView: UICollectionView!
    private(set) var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private(set) var updater: UKListUpdater<Int, String>!
    private(set) lazy var stateOverlay = UKStateMessageOverlay(host: view)
    var sheetFitScrollView: UIScrollView? { collectionView }

    override func viewDidLoad() {
        super.viewDidLoad()
        let layout = UICollectionViewCompositionalLayout { [weak self] _, environment in
            var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
            configuration.showsSeparators = false
            configuration.backgroundColor = .clear
            configuration.headerTopPadding = 0
            configuration.leadingSwipeActionsConfigurationProvider = { [weak self] path in self?.swipe(at: path, leading: true) }
            configuration.trailingSwipeActionsConfigurationProvider = { [weak self] path in self?.swipe(at: path, leading: false) }
            return NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
        collectionView = UKWidthAwareCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.allowsSelection = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        collectionView.ukPin(to: view)
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collectionView, path, id in
            self?.cell(collectionView, path, id)
        }
        updater = UKListUpdater(surface: "Summary", collectionView: collectionView, dataSource: dataSource) { [weak self] in self?.reapplyGeneration() }
    }

    /// `EntityStore.reapplyGeneration` for lists fed by the store; read inside `render()`'s observation so a reconnect applies while its
    /// window is open. nil: the list is not fed by it.
    func reapplyGeneration() -> Int? { nil }


    /// The cell for `id`.
    func cell(_ collectionView: UICollectionView, _ path: IndexPath, _ id: String) -> UICollectionViewCell? { nil }

    /// The swipe buttons for the row at `path` on an edge; nil for none.
    func swipe(at path: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? { nil }

    /// Applies `ids`, reconfiguring those in `changed`, through ``UKListUpdater`` (`cause`: `.reset` replaces, `.live` animates what is on screen).
    func apply(ids: [String], changed: [String], cause: ListUpdateCause = .live) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(ids)
        snapshot.reconfigureItems(changed.filter { ids.contains($0) && dataSource.snapshot().itemIdentifiers.contains($0) })
        updater.apply(snapshot, cause: cause)
    }
}

// MARK: - Chores tabs

/// The Summary sheet's Overdue Chores and Upcoming Chores tabs (`SummaryChoresTab`, web `DailyReportTodoTab` and
/// `DailyReportUpcomingTab`): the viewer's lists as module lists of the Chores page's own rows (``UKTodoItemRow``) with the same
/// swipe actions, menu and Delete confirmation. Upcoming has two sections, each hidden when empty; when nothing is left the tab says
/// so, and says "Enjoy vacation!" while Vacation Mode is on. Edit pushes the Donetick task form in the sheet's stack.
///
/// Never completes, edits or deletes anything by itself: every change is the reader's tap, swipe or button, and goes through the
/// shared ``TodoListController`` like the Chores page.
@MainActor
final class UKSummaryChoresViewController: UKSummaryListViewController {
    private struct ItemSpec: Equatable {
        var list: ChoresConfig.TodoList
        var item: TodoItem
        var due: String?
        var isFirst: Bool
        var isLast: Bool
        var density: ModuleDensity
        var offersUndo: Bool
        var canEdit: Bool
    }

    private enum RowSpec: Equatable {
        case title(String, leads: Bool)
        case error(entityId: String, message: String)
        case spinner(title: String)
        case item(ItemSpec)
    }

    private let summaryTab: SummaryTab
    private let lists: ProfileSummary.ResidentLists
    private let viewer: ChoresConfig.Resident
    private let store: EntityStore
    private let chores: ChoresModel
    private let connection: HassConnection?
    private let pushForm: (UIViewController) -> Void
    private let bag = UKObservationBag()
    private var specs: [String: RowSpec] = [:]
    private var emptySignature = ""
    private var loadKeys: [String: TodoReloadKey] = [:]
    private var reloadVersion = 0
    private var hadError = false

    init(tab: SummaryTab, viewer: ChoresConfig.Resident, store: EntityStore, chores: ChoresModel, connection: HassConnection?,
         pushForm: @escaping (UIViewController) -> Void) {
        self.summaryTab = tab
        self.viewer = viewer
        self.store = store
        self.chores = chores
        self.connection = connection
        self.pushForm = pushForm
        lists = ProfileSummary.lists(for: viewer)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The lists this tab reads, in order: Overdue has one; Upcoming has due today, then no due date.
    private var tabLists: [ChoresConfig.TodoList] { summaryTab == .overdue ? [lists.overdue] : [lists.dueToday, lists.noDueDate] }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Registrations are made here, never inside the cell provider (UIKit traps on that).
        _ = itemCell
        _ = plainCell
        collectionView.accessibilityIdentifier = "summary.\(summaryTab.id)"
        bag.observe { [weak self] in self?.render() }
    }

    override func cell(_ collectionView: UICollectionView, _ path: IndexPath, _ id: String) -> UICollectionViewCell? {
        if case .item? = specs[id] {
            return collectionView.dequeueConfiguredReusableCell(using: itemCell, for: path, item: id)
        }
        return collectionView.dequeueConfiguredReusableCell(using: plainCell, for: path, item: id)
    }

    private lazy var itemCell = UICollectionView.CellRegistration<UKTodoRowCell, String> { [weak self] cell, _, id in
        guard let self, case let .item(spec)? = self.specs[id] else { return }
        let list = spec.list
        let item = spec.item
        let controller = self.chores.todos.controller(for: list.entityId)
        let actions = UKTodoItemRow.Actions(
            onToggle: { [weak self] in UKTodoListActions.toggle(item, in: list, controller: controller) { self?.expect($0, item: item, in: list) } },
            onEdit: spec.canEdit ? { [weak self] in self?.edit(list, item) } : nil,
            onUndo: spec.offersUndo ? { [weak self] in UKTodoListActions.undo(item, controller: controller) { self?.expect($0, item: item, in: list) } } : nil,
            onDelete: { [weak self, weak cell] in self?.confirmDelete(item, controller: controller, cell: cell) },
            menu: { [weak self, weak cell] in
                guard let self else { return nil }
                return UKTodoListActions.menu(UKTodoListActions.actions(for: item, canEdit: spec.canEdit, canDelete: true)) { action in
                    self.perform(action, spec, cell: cell)
                }
            })
        cell.configure(item: item, now: .now, density: spec.density, isFirst: spec.isFirst, isLast: spec.isLast, surface: .sheet, actions: actions)
    }

    private lazy var plainCell = UICollectionView.CellRegistration<UKTodoPlainCell, String> { [weak self] cell, _, id in
        guard let self else { return }
        switch self.specs[id] {
        case let .title(title, leads)?:
            cell.host(UKPageSectionHeaderView(title), top: leads ? TodoPageLayout.leadingRowTopInset : HassTokens.Spacing.xl, bottom: HassTokens.Spacing.s)
        case let .error(entityId, message)?:
            let alert = UKInlineAlertView(message)
            alert.accessibilityLabel = message
            alert.accessibilityIdentifier = "todo.error.\(entityId)"
            cell.host(alert, top: 0, bottom: HassTokens.Spacing.s)
        case let .spinner(title)?:
            cell.host(UKTodoSpinnerRow(label: "Loading \(title)"), top: 0, bottom: 0)
        default:
            break
        }
    }

    // MARK: Data

    private func render() {
        let sections = tabLists.compactMap {
            TodoPageLayout.section(for: $0, viewerUserId: viewer.haUserId, store: store, todos: chores.todos)
        }
        let shown = sections.filter(\.isShown)
        let vacation = store.entity(ChoresConfig.vacationModeEntityId).state?.state == "on"
        // Every list loads, drawn or not, so a hidden one reappears when its entity says it has items again.
        for list in tabLists {
            let key = TodoReloadKey(entity: store.entity(list.entityId).state, version: reloadVersion)
            if loadKeys[list.entityId] != key {
                loadKeys[list.entityId] = key
                let controller = chores.todos.controller(for: list.entityId)
                Task { await controller.load() }
            }
        }
        let anyError = tabLists.contains { chores.todos.controller(for: $0.entityId).error != nil }
        if anyError, !hadError { UKTapFeedback.failure() }
        hadError = anyError

        let now = Date.now
        var ids: [String] = []
        var new: [String: RowSpec] = [:]
        func add(_ id: String, _ spec: RowSpec) {
            guard new[id] == nil else { return }
            ids.append(id)
            new[id] = spec
        }
        for section in shown {
            let list = section.list
            let controller = section.controller
            add("title:\(list.entityId)", .title(list.title, leads: section.id == shown.first?.id))
            if let error = controller.error { add("error:\(list.entityId)", .error(entityId: list.entityId, message: error)) }
            if controller.items == nil {
                add("spinner:\(list.entityId)", .spinner(title: list.title))
                continue
            }
            let items = controller.visibleItems(hideCompleted: list.hideCompleted)
            // Overdue spans are orange and red text, which needs the dense module over the lit windows (direction G, Layers).
            let density: ModuleDensity = TodoListSection.hasLateItem(items, now: now) ? .dense : .thin
            var unique: [TodoItem] = []
            var seen = Set<String>()
            for item in items where seen.insert(item.id).inserted { unique.append(item) }
            for (index, item) in unique.enumerated() {
                let due = item.status == .completed ? nil : item.dueLabel(now: now)
                add("item:\(list.entityId):\(item.id)", .item(ItemSpec(
                    list: list, item: item, due: due?.text, isFirst: index == 0, isLast: index == unique.count - 1, density: density,
                    offersUndo: controller.offersUndo(item), canEdit: DonetickEditTarget(item: item, listEntityId: list.entityId) != nil)))
            }
        }
        let old = specs
        specs = new
        apply(ids: ids, changed: ids.filter { old[$0] != new[$0] })

        let empty = TodoPageLayout.showsEmptyState(sections)
        let emptyKey = empty ? "\(summaryTab.id)|\(vacation)" : ""
        if emptyKey != emptySignature {
            emptySignature = emptyKey
            if empty {
                let copy = ProfileSummary.choresEmpty(summaryTab, vacationMode: vacation)
                stateOverlay.show(UKStateMessageView(symbol: vacation ? "airplane" : (summaryTab == .overdue ? "checkmark.circle" : "checklist"), title: copy.title,
                                                     message: copy.description, identifier: "summary.empty.\(summaryTab.id)"))
            } else {
                stateOverlay.show(nil)
            }
        }
    }

    // MARK: Actions

    private func edit(_ list: ChoresConfig.TodoList, _ item: TodoItem) {
        guard let target = DonetickEditTarget(item: item, listEntityId: list.entityId) else { return }
        // Edit Task is a page pushed in Your Summary's stack, not a second sheet over it (HIG: Sheets; owner, 2026-10-24).
        let form = UKDonetickTaskViewController(model: chores, mode: .edit(target), connection: connection, onSaved: { [weak self] in self?.reload() }, isPushed: true)
        // Back and Save return to the Summary; they do not close its sheet.
        form.closeForm = { [weak form] in form?.navigationController?.popViewController(animated: true) }
        pushForm(form)
    }

    private func reload() {
        reloadVersion += 1
        render()
    }

    private func confirmDelete(_ item: TodoItem, controller: TodoListController, cell: UIView?) {
        guard let list = tabLists.first(where: { $0.entityId == controller.entityId }) else { return }
        UKTodoListActions.confirmDelete(item, controller: controller, from: self, source: cell.map(UKPopoverSource.view) ?? UKPopoverSource.none) { [weak self] in
            self?.expect($0, item: item, in: list)
        }
    }

    /// A person is about to remove or bring back `item`: the change is theirs, so it is announced and focused.
    private func expect(_ expectation: UKTodoListActions.Expectation, item: TodoItem, in list: ChoresConfig.TodoList) {
        let id = "item:\(list.entityId):\(item.id)"
        switch expectation {
        case let .removal(title): updater.expectRemoval(of: [id], title: title)
        case .insertion: updater.expectInsertion(of: [id])
        }
    }

    override func reapplyGeneration() -> Int? { store.reapplyGeneration }

    private func perform(_ action: TodoRowActions.Action, _ spec: ItemSpec, cell: UIView?) {
        let controller = chores.todos.controller(for: spec.list.entityId)
        switch action {
        case .complete, .reopen:
            UKTodoListActions.toggle(spec.item, in: spec.list, controller: controller) { [weak self] in self?.expect($0, item: spec.item, in: spec.list) }
        case .edit: edit(spec.list, spec.item)
        case .delete: confirmDelete(spec.item, controller: controller, cell: cell)
        }
    }

    override func swipe(at path: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? {
        guard let id = dataSource.itemIdentifier(for: path), case let .item(spec)? = specs[id] else { return nil }
        let actions = UKTodoListActions.actions(for: spec.item, canEdit: spec.canEdit, canDelete: true)
        let cell = collectionView.cellForItem(at: path)
        return UKTodoListActions.swipeConfiguration(actions, item: spec.item, leading: leading) { [weak self] action in self?.perform(action, spec, cell: cell) }
    }
}

// MARK: - Expired Food tab

/// The Summary sheet's Expired Food tab (`SummaryExpiredFoodTab`, web `DailyReportExpiredFoodTab`).
///
/// The sensor the expired-items sensor decides whether there is anything to show. The rows are the Food page's All Food
/// model's expired items, soonest expiry first, drawn by the Food page's own row (``UKInventoryRowCell``) with the same swipe
/// actions, editor, quantity prompt and delete confirmation (``UKInventoryRowActionsHost``). Vacation Mode hides the list
/// ("Expired Food Hidden", or "No Expired Food" when the count is a confirmed zero, with "Enjoy vacation!").
@MainActor
final class UKSummaryExpiredFoodViewController: UKSummaryListViewController {
    private let context: UKContext
    private let store: EntityStore
    private let models: InventoryModels?
    private let presentation = InventoryPresentation()
    private var rowActions: UKInventoryRowActionsHost?
    private let bag = UKObservationBag()
    private var signature = ""
    private var lastSensor: EntityState?
    private var didLoad = false
    private var rows: [String: InventoryDisplayItem] = [:]
    private var positions: [String: (isFirst: Bool, isLast: Bool)] = [:]
    private weak var currentModel: InventoryListModel?
    /// Cards whose removal ticket is registered (``InventoryListModel/pendingRemoval``).
    private var ticketed: Set<String> = []

    init(context: UKContext, models: InventoryModels?) {
        self.context = context
        store = context.store
        self.models = models
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        _ = headerCell
        _ = statusCell
        _ = rowCell
        collectionView.accessibilityIdentifier = "summary.expired-food"
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self, weak refresh] _ in
            Task {
                _ = try? await self?.models?.model(for: .allFood).refresh()
                refresh?.endRefreshing()
            }
        }, for: .valueChanged)
        collectionView.refreshControl = refresh
        if let model = models?.model(for: .allFood) {
            let host = UKInventoryRowActionsHost(presentation: presentation, model: model, context: context)
            host.presenter = self
            host.start()
            rowActions = host
        }
        bag.observe { [weak self] in self?.render() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        rowActions?.sync()
    }

    private lazy var headerCell = UICollectionView.CellRegistration<UKTodoPlainCell, String> { cell, _, _ in
        cell.host(UKPageSectionHeaderView(SummaryTab.expiredFood.title), top: TodoPageLayout.leadingRowTopInset, bottom: HassTokens.Spacing.s)
    }

    private lazy var statusCell = UICollectionView.CellRegistration<UKTodoPlainCell, String> { [weak self] cell, _, id in
        if id == "spinner" {
            cell.host(UKTodoSpinnerRow(label: "Loading Expired Food"), top: 0, bottom: 0)
        } else {
            let alert = UKInlineAlertView(self?.currentModel?.loadError ?? "")
            alert.accessibilityIdentifier = "summary.expired-food.error"
            cell.host(alert, top: 0, bottom: 0)
        }
    }

    private lazy var rowCell = UICollectionView.CellRegistration<UKInventoryRowCell, String> { [weak self] cell, _, id in
        guard let self, let model = self.currentModel, let row = self.rows[id] else { return }
        let position = self.positions[id] ?? (true, true)
        cell.configure(item: row, model: model, isFirst: position.isFirst, isLast: position.isLast, selected: false, surface: .sheet,
                       actions: UKInventoryRowActions(onEdit: { [weak self] in self?.presentation.open(row, in: model) },
                                                      onShop: { [weak self] in self?.presentation.ask(.shopping(row)) },
                                                      onDelete: { [weak self] in self?.presentation.requestDelete(row, in: model) }),
                       animatedCorners: self.updater?.isAnimating ?? false)
    }

    override func reapplyGeneration() -> Int? { store.reapplyGeneration }

    override func cell(_ collectionView: UICollectionView, _ path: IndexPath, _ id: String) -> UICollectionViewCell? {
        switch id {
        case "header": collectionView.dequeueConfiguredReusableCell(using: headerCell, for: path, item: id)
        case "spinner", "error": collectionView.dequeueConfiguredReusableCell(using: statusCell, for: path, item: id)
        default: collectionView.dequeueConfiguredReusableCell(using: rowCell, for: path, item: id)
        }
    }

    private func render() {
        let vacation = store.entity(ChoresConfig.vacationModeEntityId).state?.state == "on"
        let sensor = store.entity(ProfileSummary.expiredFoodEntityId).state
        let count = ProfileSummary.expiredFoodCount(sensor)
        if let empty = ProfileSummary.expiredFoodEmpty(count: count, vacationMode: vacation) {
            apply(ids: [], changed: [], cause: .reset)
            stateOverlay.show(UKStateMessageView(symbol: vacation ? "airplane" : "checkmark.circle", title: empty.title, message: empty.description,
                                                 identifier: "summary.empty.expired-food"))
            return
        }
        guard let model = models?.model(for: .allFood) else {
            apply(ids: [], changed: [], cause: .reset)
            stateOverlay.show(nil)
            return
        }
        currentModel = model
        // The rows reload when the house says something expired or was cleared.
        if !didLoad || sensor != lastSensor {
            didLoad = true
            lastSensor = sensor
            Task { await model.load() }
        }
        // Expired cards, soonest expiry first (the web locks the shared controls to this filter and sort).
        let items = InventoryCatalog.visible(model.displayItems, sort: .expiry, direction: .ascending, filter: .expired, calendar: model.calendar)
            .filter { model.pendingRemoval[$0.id] == nil }
        for (id, name) in model.takeRemovals() {
            ticketed.insert(id)
            updater.expectRemoval(of: [id], title: name)
        }
        let showsEmpty = model.phase != .loading && model.loadError == nil && items.isEmpty
        var ids = ["header"]
        var places: [String: (isFirst: Bool, isLast: Bool)] = [:]
        var newRows: [String: InventoryDisplayItem] = [:]
        if model.phase == .loading {
            ids.append("spinner")
        } else if model.loadError != nil {
            ids.append("error")
        } else {
            for (index, item) in items.enumerated() {
                ids.append(item.id)
                newRows[item.id] = item
                places[item.id] = (index == 0, index == items.count - 1)
            }
        }
        let key = "\(model.phase)|\(model.loadError ?? "")|" + items.map { "\($0.id)|\($0.name)|\(model.batches(for: $0).count)|\($0.shownQuantity ?? 0)" }.joined(separator: ";")
        let changed = key != signature
        signature = key
        rows = newRows
        positions = places
        apply(ids: ids, changed: changed ? ids : [])
        for id in ticketed where model.pendingRemoval[id] == nil {
            // A delete that failed brought its card back: drop the ticket so a later removal is not announced for it.
            ticketed.remove(id)
            updater.cancelExpectation(of: [id])
        }
        let empty = ProfileSummary.noExpiredFood
        stateOverlay.show(showsEmpty ? UKStateMessageView(symbol: "checkmark.circle", title: empty.title, message: empty.description,
                                                          identifier: "summary.empty.expired-food") : nil)
    }

    override func swipe(at path: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? {
        guard let id = dataSource.itemIdentifier(for: path), let item = rows[id], let model = currentModel else { return nil }
        if leading {
            return UKSwipeAction.configuration([UKSwipeAction("Add to Groceries", systemImage: "cart.badge.plus", tint: UKFloatingActionBar.tint) { [weak self] done in
                self?.presentation.ask(.shopping(item))
                done(true)
            }])
        }
        guard model.deletableRows(of: item) != nil, model.batches(for: item).count <= 1 else { return nil }
        return UKSwipeAction.configuration([UKSwipeAction("Delete", systemImage: "trash", role: .destructive) { [weak self] done in
            guard let self else { done(false); return }
            UKInventoryRowActionsHost.swipeDelete(item, in: model, presentation: self.presentation, done: done)
        }])
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool { false }
}
#endif
