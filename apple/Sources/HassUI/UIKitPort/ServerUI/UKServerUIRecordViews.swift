#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Keyed collection host

/// Native rows/cards are retained by provider key, including while a refresh fails.
///
/// A page whose body is one Todo, Inventory or Recipes collection hosts it as the page's scroller instead (``scrolling``): a
/// ``UKRecordCollectionController`` draws only the visible records from reused cells and reconfigures only the records that changed.
/// Every other collection, and a page that mixes a collection with other content, keeps the retained rows in the page's column.
@MainActor
final class UKServerUICollectionView: UIView, UKGridMeasuring {
    private let column = UKColumnView()
    private var gate: UKContentGateView?
    private var emptyKey: [String]?
    private var emptyView: UKServerUIRecordState?
    private let list = UKServerUIRecordList()
    private let grouped = UKColumnView(spacing: HassTokens.Spacing.m)
    private let alarmRows = UKColumnView(spacing: HassTokens.Spacing.m)
    private var sectionLists: [String: UKServerUIRecordList] = [:]
    private var sectionHeaders: [String: UIView] = [:]
    private let grid = UKDynamicGridView()
    private let message = UILabel.uk(.body, ink: UKDesignInk.secondary)
    private let summary = UILabel.uk(.subheadline, ink: UKDesignInk.secondary)
    /// The recipes footer while the next page loads; paging itself starts from the viewport, never from a button.
    private let loadingMore = UKArcSpinnerView(.compact, label: "Loading More Recipes")
    private let retry = UKPrimaryButton(AlertCopy.tryAgain) {}
    private let bag = UKObservationBag()
    private var provider: (any UKServerUICollectionSource)?
    private var definition: ServerUICompositionDocument.Collection?
    private weak var page: UKServerUIPage?
    private var loadingTask: Task<Void, Never>?
    private var nestedRows: [String: UIView] = [:]
    /// The record views by key: every retained row in a column, or the views of the visible cells when ``scrolling``.
    var rows: [String: UIView] { scroller?.visibleViews ?? nestedRows }
    /// Whether this collection is its page's scroller rather than a view in the page's column.
    private(set) var scrolling = false
    private var scroller: UKRecordCollectionController?
    private let scrollerBody = UIView()
    private var stateOverlay: UKStateMessageOverlay?
    private var headerViews: [String: (title: String, view: UIView)] = [:]
    private var recordsByKey: [String: UKServerUIRecord] = [:]
    /// The view the page installs as its scroller host (the gate over the collection), when ``scrolling``.
    var scrollerHost: UIView? { scrolling ? gate : nil }
    /// The scroll view the page names as its own, when ``scrolling``.
    var scrollerView: UIScrollView? { scrolling ? scroller?.collectionView : nil }
    /// The record controller, exposed to tests.
    var recordController: UKRecordCollectionController? { scroller }

    /// Whether `definition` may be hosted as a page scroller: a list of rows or a grid of cards, never a carousel or a row collection.
    static func hostsScroller(_ template: ServerUICompositionDocument.Collection.Template) -> Bool {
        switch template {
        case .todo, .inventory, .recipes: true
        case .rows, .carousel: false
        }
    }
    /// Whether the authored collection opted in to pull-to-refresh (off by default).
    var pullsToRefresh: Bool { definition?.pullsToRefresh == true }
    private var retainedRecords: [UKServerUIRecord] = []
    /// The records the retained rows were last built from, so an unchanged record keeps its row untouched.
    private var shownRecords: [String: UKServerUIRecord] = [:]
    private var builtDefinition: ServerUICompositionDocument.Collection?
    private var builtSurface: TileSurface?
    private var retainedSections: [UKServerUIRecordSection] = []
    private var carousel: UKSuggestedRecipesView?
    private var commandError: String?

    init() {
        super.init(frame: .zero)
        addSubview(column)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// - Parameter scrolling: Whether the page hosts this collection as its one scroller (``hostsScroller(_:)`` and nothing else in the body).
    func bind(_ definition: ServerUICompositionDocument.Collection, provider: any UKServerUICollectionSource, page: UKServerUIPage,
              scrolling: Bool = false) {
        let changed = self.provider !== provider || self.scrolling != scrolling
        if changed {
            loadingTask?.cancel()
            retainedRecords = []; retainedSections = []; nestedRows = [:]; shownRecords = [:]; recordsByKey = [:]
            sectionLists = [:]; sectionHeaders = [:]; headerViews = [:]; builtDefinition = nil; builtSurface = nil
            commandError = nil
        }
        self.definition = definition; self.provider = provider; self.page = page
        if changed {
            self.scrolling = scrolling
            column.removeFromSuperview()
            gate?.removeFromSuperview()
            let content: UIView = scrolling ? makeScrollerBody(for: definition) : column
            let gate = UKContentGateView(page: definition.node.id, isReady: definition.template == .carousel || !provider.loading || !provider.records.isEmpty,
                label: definition.loadingText, content: content)
            self.gate = gate
            if !scrolling { addSubview(gate) }
        }
        bag.removeAll()
        bag.observe { [weak self] in self?.render() }
        if changed {
            loadingTask = Task { [weak self] in
                do { try await provider.load() }
                catch {
                    if self?.provider === provider { self?.report(error) }
                }
            }
        }
    }

    /// The collection and its empty-state overlay, pinned together under the gate.
    private func makeScrollerBody(for definition: ServerUICompositionDocument.Collection) -> UIView {
        let controller = UKRecordCollectionController(shape: definition.template == .recipes ? .grid : .list)
        controller.owner = self
        scroller = controller
        let collection = controller.collectionView
        scrollerBody.subviews.forEach { $0.removeFromSuperview() }
        collection.accessibilityIdentifier = definition.node.id
        collection.translatesAutoresizingMaskIntoConstraints = false
        scrollerBody.addSubview(collection)
        collection.ukPin(to: scrollerBody)
        stateOverlay = UKStateMessageOverlay(host: scrollerBody)
        emptyKey = nil
        return scrollerBody
    }

    /// The page's body padding and widest measure, which the scroller's content follows exactly as a column does.
    func applyPageLayout(padding: UIEdgeInsets, maxWidth: CGFloat) {
        scroller?.padding = padding
        scroller?.maxWidth = maxWidth
    }

    private func render() {
        guard let definition, let provider, let page else { return }
        let incoming = provider.records
        guard Set(incoming.map(\.id)).count == incoming.count, incoming.allSatisfy({ !$0.id.isEmpty && $0.matches(definition.template) }) else {
            report(ServerUIRecordFailure.invalidValue); return
        }
        if provider.error == nil || !incoming.isEmpty {
            let sections = provider.sections
            guard Set(sections.map(\.id)).count == sections.count,
                  sections.flatMap(\.records).map(\.id) == incoming.map(\.id) else { report(ServerUIRecordFailure.invalidValue); return }
            retainedRecords = incoming
            retainedSections = sections
            recordsByKey = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        let records = retainedRecords
        gate?.isReady = definition.template == .carousel || !provider.loading || !records.isEmpty || provider.error != nil || commandError != nil
        let notice = commandError ?? provider.error ?? (!provider.loading && records.isEmpty ? definition.emptyText : nil)
        message.text = notice
        message.textColor = page.context.surface == .sheet ? UKDesignInk.secondary : UKInk.onDarkSecondary
        summary.text = provider.summary
        summary.textColor = message.textColor
        if scrolling {
            var changed = Set<String>()
            let rebuildAll = builtDefinition != definition || builtSurface != page.context.surface
            for record in records {
                if let before = shownRecords[record.id], !rebuildAll, record.isUnchanged(from: before) { continue }
                changed.insert(record.id)
            }
            shownRecords = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            builtDefinition = definition; builtSurface = page.context.surface
            applyScroller(changed: changed)
            return
        }
        if definition.template == .carousel {
            if carousel == nil { carousel = UKSuggestedRecipesView(title: definition.node.title, copy: .food) }
            if let carousel {
                carousel.configure(phase: provider.error != nil ? .failed : provider.loading ? .loading : .ready, items: records.compactMap {
                    if case .recipe(let item) = $0 { item } else { nil }
                })
                carousel.emptyMessage = definition.emptyText.isEmpty ? nil : definition.emptyText
                carousel.onOpen = { [weak self] item in self?.select(.recipe(item)) }
                retry.action = { [weak self] in self?.reload() }
                // The carousel draws its own failed and empty states ("Suggestions Unavailable"), so the provider's error line is not repeated
                // above it, and the authored empty text is the empty state's own message; only a failed command is.
                install((commandError == nil ? [] : [message]) + (provider.error == nil && commandError == nil ? [] : [retry]) + [carousel])
            }
        } else {
            var next: [String: UIView] = [:]
            var changed = Set<String>()
            let rebuildAll = builtDefinition != definition || builtSurface != page.context.surface
            for record in records {
                if !rebuildAll, let view = nestedRows[record.id], let before = shownRecords[record.id], record.isUnchanged(from: before) {
                    next[record.id] = view
                    continue
                }
                let view = make(record, old: nestedRows[record.id], page: page)
                view.accessibilityIdentifier = definition.node.id + "." + record.id
                next[record.id] = view
                changed.insert(record.id)
            }
            shownRecords = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            builtDefinition = definition; builtSurface = page.context.surface
            let views = records.compactMap { next[$0.id] }
            nestedRows = next
            let content: UIView
            if provider is UKServerUIBedroomCollection {
                if alarmRows.views != views { alarmRows.setViews(views) }
                content = alarmRows
            } else if definition.template == .recipes {
                if grid.items.map(\.view) != views { grid.setItems(views.map { UKGridItem($0) }) }
                content = grid
            } else {
                let groups = retainedSections
                var views: [UIView] = []
                for group in groups where !group.records.isEmpty {
                    let list = sectionLists[group.id] ?? UKServerUIRecordList()
                    sectionLists[group.id] = list
                    if let title = group.title {
                        let headerKey = group.id + ":" + title
                        let header = sectionHeaders[headerKey] ?? UKFormText.header(title, onWallpaper: page.context.surface != .sheet)
                        sectionHeaders[headerKey] = header
                        views.append(header)
                    }
                    let todos = group.records.compactMap { if case .todo(let item, _) = $0 { item } else { nil } }
                    let dense = definition.template == .inventory || TodoListSection.hasLateItem(todos, now: .now)
                    list.apply(keys: group.records.map(\.id), rows: next, changed: changed, surface: page.context.surface,
                               density: dense ? .dense : .thin, animates: definition.template == .todo)
                    list.swipe = { [weak self] key, leading in self?.swipe(key, leading: leading) }
                    list.menu = { [weak self] key in self?.menu(key) }
                    views.append(list)
                }
                if views.isEmpty, !records.isEmpty {
                    list.apply(keys: records.map(\.id), rows: next, changed: changed, surface: page.context.surface,
                               animates: definition.template == .todo)
                    views.append(list)
                }
                if grouped.views != views { grouped.setViews(views) }
                content = grouped
            }
            var empty: UIView?
            if records.isEmpty, !provider.loading, provider.error == nil, let state = provider.emptyState {
                let key = [state.symbol, state.title, state.message]
                if emptyKey != key {
                    emptyKey = key
                    emptyView = UKServerUIRecordState(UKStateMessageView(symbol: state.symbol, title: state.title, message: state.message)) { [weak self] in
                        self?.remainingHeight ?? 0
                    }
                }
                empty = emptyView
            }
            retry.action = { [weak self] in self?.reload() }
            install((notice == nil || empty != nil ? [] : [message])
                            + ((commandError ?? provider.error) == nil ? [] : [retry]) + (empty.map { [$0] } ?? [])
                            + (provider.summary == nil || records.isEmpty ? [] : [summary])
                            + (records.isEmpty ? [] : [content])
                            + (provider.loadingMore ? [loadingMore] : []))
        }
        ukRemeasureContainers(includingSelf: true)
        DispatchQueue.main.async { [weak self] in self?.viewportChanged() }
    }

    /// Shows the retained records in the scroller: the leading notices, each group under its title, and the footer, with only the
    /// records in `changed` reconfigured.
    private func applyScroller(changed: Set<String>) {
        guard scrolling, let definition, let provider, let page, let scroller else { return }
        let records = retainedRecords
        let isEmpty = records.isEmpty && !provider.loading && provider.error == nil && provider.emptyState != nil
        let failed = commandError ?? provider.error
        let notice = commandError ?? provider.error ?? (!provider.loading && records.isEmpty ? definition.emptyText : nil)
        var content = UKRecordCollectionContent()
        var signatures: [UKRecordCollectionItem: String] = [:]
        if notice != nil, !isEmpty { content.leading.append(.notice); signatures[.notice] = message.text ?? "" }
        if failed != nil { content.leading.append(.retry); signatures[.retry] = "retry" }
        if provider.summary != nil, !records.isEmpty { content.leading.append(.summary); signatures[.summary] = summary.text ?? "" }
        for group in retainedSections where !group.records.isEmpty {
            let todos = group.records.compactMap { if case .todo(let item, _) = $0 { item } else { nil } }
            let dense = definition.template == .inventory || TodoListSection.hasLateItem(todos, now: .now)
            if let title = group.title {
                if headerViews[group.id]?.title != title {
                    headerViews[group.id] = (title, UKFormText.header(title, onWallpaper: page.context.surface != .sheet))
                }
                signatures[.header(group.id)] = title
            }
            content.groups.append(.init(id: group.id, title: group.title, keys: group.records.map(\.id), dense: dense))
        }
        if content.groups.isEmpty, !records.isEmpty {
            content.groups = [.init(id: "records", title: nil, keys: records.map(\.id), dense: false)]
        }
        content.showsFooter = provider.loadingMore
        scroller.apply(content, changed: changed, signatures: signatures, surface: page.context.surface,
                       animated: definition.template == .todo)
        retry.action = { [weak self] in self?.reload() }
        if isEmpty, let state = provider.emptyState {
            let key = [state.symbol, state.title, state.message]
            if emptyKey != key {
                emptyKey = key
                stateOverlay?.show(UKStateMessageView(symbol: state.symbol, title: state.title, message: state.message))
            }
        } else if emptyKey != nil {
            emptyKey = nil
            stateOverlay?.show(nil)
        }
    }

    /// Only near-end visibility asks the canonical model to paginate; scrolling writes no observation state.
    func viewportChanged() {
        if scrolling { scroller?.reportVisible(); return }
        guard definition?.template == .recipes, let provider, provider.hasMore,
              let scroll = page?.pageScroll, let window, bounds.width > 0 else { return }
        let visible = scroll.convert(scroll.bounds, to: window).intersection(window.bounds)
        for record in retainedRecords.suffix(RecipeCollectionModel.prefetchDistance) {
            if let row = rows[record.id], row.convert(row.bounds, to: window).intersects(visible) {
                provider.displayed(record)
                return
            }
        }
    }

    private func install(_ views: [UIView]) {
        if column.views != views { column.setViews(views) }
    }

    func reload() {
        loadingTask = Task { [weak self] in await self?.refresh() }
    }

    func refresh() async {
        guard let provider else { return }
        commandError = nil
        do {
            guard !provider.hasPendingIntent else { throw ServerUIRecordFailure.busy }
            try await provider.load()
            guard self.provider === provider else { return }
            render()
        } catch {
            if self.provider === provider { report(error) }
        }
    }

    private func make(_ record: UKServerUIRecord, old: UIView?, page: UKServerUIPage) -> UIView {
        switch record {
        case .row(let item):
            let row = (old as? UKRowButton) ?? UKRowButton(UKRowView(.init(item.title)))
            row.row.update(.init(item.title, subtitle: item.subtitle, value: item.value, showsChevron: definition?.selection != nil))
            row.row.surface = page.context.surface
            row.onTap = { [weak self] in self?.select(record) }
            return row
        case .bedroom(let alarm, let source):
            let previous = (old as? UKBedroomRow) ?? (old as? UKServerUIMirroredAlarmRow)?.row
            let toggle = (previous?.accessory as? UISwitch) ?? UISwitch()
            let row = previous ?? UKBedroomRow(symbol: "alarm", title: "", lines: [],
                onOpen: definition?.selection == nil || alarm.linked != nil ? nil : {}, trailing: toggle)
            let title: String
            let lines: [String]
            switch alarm.alarm {
            case .bed(let value):
                title = ClockTime.display(value.time)
                lines = [value.enabled ? "Enabled" : "Disabled"]
            case .wake(let value):
                if value.isNative {
                    title = value.label
                    lines = ["\(WakeLight.scheduleLabel(value)) · \(WakeLight.displayTime(value.localTime))",
                             "Ramp: \(WakeLight.rampLabel(value.rampMinutes))"]
                } else {
                    title = value.sourceRef.flatMap(source.session.devices.wakeLight.config.source(id:))?.alarmLabel
                        ?? value.sourceLabel ?? value.label
                    lines = ["\(WakeLight.scheduleLabel(value)) · \(WakeLight.displayTime(value.localTime))"]
                }
            }
            let open: (() -> Void)? = alarm.editable && alarm.linked == nil && definition?.selection != nil
                ? { [weak self] in self?.select(record) } : nil
            row.configure(symbol: alarm.linked != nil ? "bed.double" : alarm.enabled ? "alarm" : "alarm.waves.left.and.right",
                          title: title, lines: lines, isMuted: !alarm.enabled || alarm.linked == false, onOpen: open)
            toggle.isOn = alarm.linked ?? alarm.enabled
            toggle.isEnabled = alarm.editable && !alarm.pending
            toggle.accessibilityLabel = alarm.linked == nil ? title : "Use room wake lights for the \(title) alarm"
            let actionID = UIAction.Identifier("server-ui.alarm.toggle")
            toggle.removeAction(identifiedBy: actionID, for: .valueChanged)
            toggle.addAction(UIAction(identifier: actionID) { [weak self, weak toggle] _ in
                guard let enabled = toggle?.isOn else { return }
                Task {
                    do {
                        guard try await source.alarms.toggle(alarm, enabled: enabled) else {
                            throw ServerUIRecordFailure.invalidValue
                        }
                    } catch { self?.report(error) }
                }
            }, for: .valueChanged)
            if case .wake(let value) = alarm.alarm, !value.isNative {
                let view = (old as? UKServerUIMirroredAlarmRow) ?? UKServerUIMirroredAlarmRow(row: row)
                let side = value.sourceRef.flatMap(source.session.devices.wakeLight.config.source(id:))?.side
                let link = definition?.bedroomLinks.first { $0.side == side }
                view.link.accessibilityIdentifier = (definition?.node.id ?? "alarms") + "." + record.id + ".linked-editor"
                view.link.configuration?.title = link?.label
                view.link.isHidden = link == nil
                view.open = link.map { link in { [weak self] in self?.select(record, action: link.action) } }
                return view
            }
            return row
        case .todo(let item, let source):
            let row = (old as? UKTodoItemRow) ?? UKTodoItemRow()
            UKServerUITodoRow.configure(row, item: item, provider: source, surface: page.context.surface,
                edit: definition?.selection == nil ? nil : { [weak self] in self?.select(record) },
                confirmDelete: { [weak self, weak row] item, ticket in
                    guard let self, let page = self.page else { return }
                    UKServerUIRecordPrompts.confirm(TodoListSection.deleteSpec(for: item), from: page, source: row ?? self,
                        cancel: { try source.cancelDelete(ticket) },
                        submit: { try await source.delete(confirmed: ticket) }, report: self.report)
                }, report: { [weak self] in self?.report($0) })
            return row
        case .inventory(let item, let source):
            let row = (old as? UKInventoryRowView) ?? UKInventoryRowView(surface: page.context.surface)
            row.configure(value: .init(item: item, model: source.model), actions: .init(
                onEdit: { [weak self] in self?.select(record) },
                onShop: { [weak self, weak row] in
                    guard let self, let page = self.page else { return }
                    do {
                        let selection = try source.select(item.id)
                        guard selection.item == item else { throw ServerUIRecordFailure.staleSelection }
                        UKServerUIRecordPrompts.quantity(title: "Add \(item.name) to Groceries", maximum: nil, from: page,
                            submit: { try await source.addToShopping(selection, quantity: $0) }, report: self.report)
                        _ = row
                    } catch { self.report(error) }
                }))
            return row
        case .recipe(let item):
            let value = RecipeCardPresentation(recipe: item, showCoverage: true, placeholderSymbol: "fork.knife", accessibilityHint: "Opens recipe details")
            let row = (old as? UKImageCardView) ?? UKImageCardView(title: value.title, imageURL: value.imageURL, accessibilityHint: value.accessibilityHint)
            row.configure(title: value.title, subtitle: value.subtitle, imageURL: value.imageURL, fallbackImageURL: value.fallbackImageURL, placeholderSymbol: value.placeholderSymbol)
            row.action = { [weak self] in self?.select(record) }
            return row
        }
    }

    private func select(_ record: UKServerUIRecord, action override: ServerUICompositionDocument.Action? = nil) {
        guard let page, let provider, let action = override ?? definition?.selection else { return }
        guard page.renderer?.isEnabled(action, from: page) == true else { report(ServerUIRecordFailure.busy); return }
        do {
            try provider.select(record)
            page.renderer?.activate(action, from: page, source: rows[record.id])
        } catch { report(error) }
    }

    private func todoAction(_ action: TodoRowActions.Action, record: UKServerUIRecord) {
        guard case .todo(let item, let source) = record, let page else { return }
        switch action {
        case .edit: select(record)
        case .delete:
            do {
                let ticket = try source.deleteTicket(expected: item)
                UKServerUIRecordPrompts.confirm(TodoListSection.deleteSpec(for: item), from: page,
                    source: rows[record.id] ?? self, cancel: { try source.cancelDelete(ticket) },
                    submit: { try await source.delete(confirmed: ticket) }, report: report)
            } catch { report(error) }
        case .complete, .reopen:
            Task { do { try await source.toggle(expected: item) } catch { report(error) } }
        }
    }

    private func swipe(_ key: String, leading: Bool) -> UISwipeActionsConfiguration? {
        guard let record = recordsByKey[key] else { return nil }
        switch record {
        case .todo(let item, let source):
            let actions = UKTodoListActions.actions(for: item, canEdit: definition?.selection != nil && UKServerUITodoRow.canEdit(item, provider: source),
                                                    canDelete: source.configuration.canDelete)
            return UKTodoListActions.swipeConfiguration(actions, item: item, leading: leading) { [weak self] in self?.todoAction($0, record: record) }
        case .inventory(let item, let source):
            if !leading, source.model.deletableRows(of: item) != nil, source.model.batches(for: item).count <= 1 {
                return UKSwipeAction.configuration([UKSwipeAction("Delete", systemImage: "trash", role: .destructive) { [weak self] done in
                    self?.deleteInventory(item, source: source); done(true)
                }])
            }
            if leading {
                return UKSwipeAction.configuration([UKSwipeAction("Add to Groceries", systemImage: "cart.badge.plus", tint: UKFloatingActionBar.tint) { [weak self] done in
                    self?.shopInventory(item, source: source); done(true)
                }])
            }
            return nil
        default: return nil
        }
    }

    private func menu(_ key: String) -> UIMenu? {
        guard let record = recordsByKey[key],
              case .todo(let item, let source) = record else { return nil }
        return UKTodoListActions.menu(UKTodoListActions.actions(for: item,
            canEdit: definition?.selection != nil && UKServerUITodoRow.canEdit(item, provider: source),
            canDelete: source.configuration.canDelete)) { [weak self] in self?.todoAction($0, record: record) }
    }

    private func shopInventory(_ item: InventoryDisplayItem, source: InventoryCompositionProvider) {
        guard let page else { return }
        do {
            let selection = try source.select(item.id)
            guard selection.item == item else { throw ServerUIRecordFailure.staleSelection }
            UKServerUIRecordPrompts.quantity(title: "Add \(item.name) to Groceries", maximum: nil, from: page,
                submit: { try await source.addToShopping(selection, quantity: $0) }, report: report)
        } catch { report(error) }
    }

    private func deleteInventory(_ item: InventoryDisplayItem, source: InventoryCompositionProvider) {
        guard let page else { return }
        do {
            let selection = try source.select(item.id)
            guard selection.item == item, let rows = source.model.deletableRows(of: item) else { throw ServerUIRecordFailure.staleSelection }
            let total = rows.reduce(0) { $0 + $1.quantity }
            if total > 1 {
                UKServerUIRecordPrompts.quantity(title: "Delete \(item.name)", maximum: total, from: page,
                    submit: { try await source.delete(selection, quantity: $0) }, report: report)
            } else {
                UKServerUIRecordPrompts.confirm(AlertCopy.delete("Item", named: item.name, detail: nil), from: page, source: self,
                    submit: { try await source.delete(selection) }, report: report)
            }
        } catch { report(error) }
    }

    private func report(_ error: any Error) {
        commandError = error.localizedDescription
        gate?.isReady = true
        message.text = commandError
        retry.action = { [weak self] in self?.reload() }
        if scrolling { applyScroller(changed: []) }
        else {
            install([message, retry] + column.views.filter { $0 !== message && $0 !== retry })
            ukRemeasureContainers(includingSelf: true)
        }
        page?.renderer?.onError(.init(code: .unavailableSource, pointer: "/document/collection"))
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        if definition?.template == .recipes, width > 0 {
            let count = RecipeGrid.columnCount(width: width, accessibilitySize: traitCollection.ukIsAccessibilitySize)
            var next = grid.configuration
            next.maxColumns = count
            next.minCellWidth = max(1, (width - next.spacing * CGFloat(count - 1)) / CGFloat(count))
            next.fill = .none
            if grid.configuration != next { grid.configuration = next }
        }
        let height = column.gridHeight(forWidth: width)
        return definition?.template != .carousel && provider?.loading == true && retainedRecords.isEmpty ? max(height, remainingHeight) : height
    }
    override func sizeThatFits(_ size: CGSize) -> CGSize { .init(width: size.width, height: gridHeight(forWidth: size.width)) }
    private var remainingHeight: CGFloat {
        guard let body = page?.pageScroll else { return 200 }
        return max(200, body.bounds.height - body.adjustedContentInset.top - body.adjustedContentInset.bottom - frame.minY)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let gate { gate.frame = bounds }
        else { column.frame = bounds }
    }
}

// MARK: - Scroller owner

extension UKServerUICollectionView: UKRecordCollectionOwner {
    func recordView(for key: String, reusing old: UIView?) -> UIView? {
        guard let record = recordsByKey[key], let page, let definition else { return nil }
        let view = make(record, old: old, page: page)
        view.accessibilityIdentifier = definition.node.id + "." + key
        return view
    }

    func recordSwipe(for key: String, leading: Bool) -> UISwipeActionsConfiguration? { swipe(key, leading: leading) }
    func recordMenu(for key: String) -> UIMenu? { menu(key) }

    func recordDisplayed(_ key: String) {
        guard let record = recordsByKey[key] else { return }
        provider?.displayed(record)
    }

    func recordImageURL(for key: String) -> URL? {
        if case .recipe(let item)? = recordsByKey[key] { item.cardImageURL ?? item.imageURL } else { nil }
    }

    func auxiliaryView(for item: UKRecordCollectionItem) -> UIView? {
        switch item {
        case .notice: message
        case .retry: retry
        case .summary: summary
        case .header(let id): headerViews[id]?.view
        case .footer: loadingMore
        case .record: nil
        }
    }
}

/// Retains the canonical card, switch and separate linked-device button through live updates.
@MainActor
private final class UKServerUIMirroredAlarmRow: UIStackView, UKGridMeasuring {
    let row: UKBedroomRow
    var open: (() -> Void)?
    lazy var link = UKBedroomRow.linkedEditorButton(label: "Open Linked-Device Alarm Editor", identifier: "") { [weak self] in
        self?.open?()
    }

    init(row: UKBedroomRow) {
        self.row = row
        super.init(frame: .zero)
        axis = .vertical
        spacing = HassTokens.Spacing.s
        addArrangedSubview(row)
        addArrangedSubview(link)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    }
}

/// Centers a canonical empty state in the remaining page without introducing another scroll view.
@MainActor
private final class UKServerUIRecordState: UIView, UKGridMeasuring {
    private let content: UKServerUIFittingView
    private let minimumHeight: () -> CGFloat
    init(_ view: UIView, minimumHeight: @escaping () -> CGFloat) {
        content = .wrapping(view); self.minimumHeight = minimumHeight
        super.init(frame: .zero)
        addSubview(content)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func gridHeight(forWidth width: CGFloat) -> CGFloat { max(minimumHeight(), content.gridHeight(forWidth: width)) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { .init(width: size.width, height: gridHeight(forWidth: size.width)) }
    override func layoutSubviews() {
        super.layoutSubviews()
        let height = content.gridHeight(forWidth: bounds.width)
        content.frame = .init(x: 0, y: max(0, (bounds.height - height) / 2), width: bounds.width, height: height)
    }
}

// MARK: - Generic confirmation and quantity boundaries

@MainActor
enum UKServerUIRecordPrompts {
    static func confirm(_ spec: AlertCopy.Spec, from page: UIViewController, source: UIView,
                        cancel: @escaping () throws -> Void = {},
                        submit: @escaping () async throws -> Void, report: @escaping (any Error) -> Void) {
        let alert = UIAlertController(title: spec.title, message: spec.message, preferredStyle: .actionSheet)
        alert.addAction(.init(title: spec.cancel.title, style: .cancel) { _ in
            do { try cancel() } catch { report(error) }
        })
        alert.addAction(.init(title: spec.confirm.title, style: .destructive) { _ in
            Task { do { try await submit() } catch { report(error) } }
        })
        UKPopoverSource.view(source).attach(to: alert.popoverPresentationController, fallback: page.view)
        page.present(alert, animated: true)
    }

    static func quantity(title: String, maximum: Double?, from page: UIViewController, cancel: @escaping () -> Void = {},
                         submit: @escaping (Double) async throws -> Void, report: @escaping (any Error) -> Void) {
        let alert = UIAlertController(title: title, message: maximum.map { "Quantity (1–\(InventoryFormat.quantity($0)))" }, preferredStyle: .alert)
        alert.addTextField {
            $0.text = "1"; $0.keyboardType = .decimalPad; $0.accessibilityLabel = "Quantity"
            $0.accessibilityIdentifier = "inventory.prompt.field"
        }
        alert.addAction(.init(title: "Cancel", style: .cancel) { _ in cancel() })
        alert.addAction(.init(title: "Confirm", style: .default) { [weak alert] _ in
            guard let text = alert?.textFields?.first?.text, let value = Double(text), value.isFinite,
                  value >= 1, maximum.map({ value <= $0 }) ?? true else { cancel(); report(ServerUIRecordFailure.invalidValue); return }
            Task { do { try await submit(value) } catch { report(error) } }
        })
        page.present(alert, animated: true)
    }
}

// MARK: - Recipe detail atoms

@MainActor
final class UKServerUIRecipePartView: UKServerUIFittingView {
    private let stack = UIStackView()
    private let bag = UKObservationBag()
    private var identity: Int?
    private var shown: RecipeDetail?
    private var shownPart: ServerUICompositionDocument.RecipePart.Part?
    /// What the page chrome last showed for this part, so an unchanged tick touches no bar state.
    private var shownChrome: Chrome?
    private var showsEmpty = false
    private struct Chrome: Equatable {
        var pending: Bool
        var title: String?
        var subtitle: String?
    }
    init() {
        super.init(frame: .zero)
        stack.axis = .vertical; stack.spacing = HassTokens.Spacing.l
        addSubview(stack); stack.ukPin(to: self)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func bind(_ value: ServerUICompositionDocument.RecipePart, source: RecipeBrowsingSource, page: UKServerUIPage) {
        bag.removeAll()
        bag.observe { [weak self, weak page] in
            guard let self else { return }
            let model = source.selected
            var chrome = Chrome(pending: source.hasPendingIntent)
            if let model, page?.presentationID != nil {
                chrome.title = model.detail?.title ?? model.recipe.title
                chrome.subtitle = model.recipe.requiredTotal > 0 ? model.recipe.coverageText : nil
            }
            if chrome != shownChrome {
                shownChrome = chrome
                if let title = chrome.title { page?.title = title }
                if chrome.title != nil, let item = page?.navigationItem { UKSheetSubtitle.apply(chrome.subtitle, to: item) }
                scheduleChrome(page)
            }
            guard let model else {
                if !showsEmpty {
                    showsEmpty = true; identity = nil; shown = nil
                    show([UKStateMessageView(symbol: "fork.knife", title: "No Recipe Selected", message: "Choose a recipe from the collection.")])
                }
                return
            }
            showsEmpty = false
            if let detail = model.detail {
                guard identity != model.id || shown != detail || shownPart != value.part else { return }
                identity = model.id; shown = detail; shownPart = value.part
                switch value.part {
                case .hero: show([UKRecipeHeroImage(url: detail.primaryImageURL, fallbackURL: detail.thumbnailURL)])
                case .general: show(UKRecipeTabs.general(detail, fallbackImageURL: model.recipe.imageURL))
                case .ingredients: show(UKRecipeTabs.ingredients(detail, model: model))
                case .instructions: show(UKRecipeTabs.instructions(detail))
                }
            } else if case .failed(let message, _) = model.phase {
                show([UKStateMessageView(symbol: "exclamationmark.triangle", title: "Recipe Unavailable", message: message,
                    actionTitle: AlertCopy.tryAgain, action: { model.load() })])
            } else { show([UKArcSpinnerView(.compact, label: "Loading Recipe")]) }
        }
    }
    /// Chrome is refreshed one turn later, outside the observation closure that noticed the change.
    private func scheduleChrome(_ page: UKServerUIPage?) {
        DispatchQueue.main.async { [weak page] in
            page?.refreshChrome()
            (page?.parent as? UKColumnsViewController)?.pageStateChanged()
        }
    }

    private func show(_ views: [UIView]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        views.forEach(stack.addArrangedSubview)
        ukRemeasureContainers(includingSelf: true)
    }
}
#endif
