#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Keyed page body

/// A composed page keeps the canonical title, fade, insets and scrolling. It never uses the legacy section menu.
@MainActor
final class UKServerUIPage: UKPageViewController, UKSheetFitting, UKColumnExitRequesting, UIScrollViewDelegate {
    typealias D = ServerUICompositionDocument
    /// The id of the surface (page or modal) this controller shows.
    let surfaceID: String
    private(set) var definition: D.Surface
    /// The navigation root (a tab or the modal) whose stack holds this page.
    let root: ServerUINavigationState.Root
    /// The modal instance this page belongs to, or `nil` when it sits in a tab stack.
    let presentationID: UUID?
    /// How many pages sit below this one in its stack.
    let depth: Int
    weak var renderer: UKServerUIRenderer?
    private let column = UKColumnView()
    private(set) var body: UKPageScrollView?
    /// The one view the page's scroller sits in: the ``body`` column, or a record collection's own scroller.
    private let slot = UIView()
    /// The scroll view that drives the large title, the header fade and the pinned bar's inset: the ``body``, or the record
    /// collection's scroller when the body is a single Todo, Inventory or Recipes collection.
    private(set) var pageScroll: UIScrollView?
    /// The id of the collection hosted as the page's scroller, or nil while the column is.
    private var scrollerCollectionID: String?
    private(set) var nodes: [String: UKServerUINode] = [:]
    private var inheritedGroups: [D.ChromeGroup]
    private var closePolicy: D.Close?
    private lazy var chrome = UKServerUIChrome(page: self)
    private let layoutBag = UKObservationBag()
    /// Text shown in the empty detail column when the page lays out in columns, or `nil` for a single page.
    let columnPlaceholder: String?
    private(set) var columns: UKColumnsViewController?
    private var columnBar: UKColumnBar?
    private let columnAction = UIBarButtonItem()
    private var columnGroup: UIBarButtonItemGroup?
    private let bedroomVisitID = UUID().uuidString
    private(set) var bedroomDrafts: [String: ServerUIBedroomDraft] = [:]
    private var bedroomOwners: [String: ServerUIBedroomSession] = [:]
    private var bedroomErrors: [String: String] = [:]
    private var bedroomBack: UIBarButtonItem?

    deinit {
        let owners = bedroomOwners
        let owned = bedroomDrafts.compactMap { key, draft in owners[key].map { ($0, draft) } }
        Task { @MainActor in owned.forEach { owner, draft in owner.retire(draft) } }
    }

    /// Logical removal releases ownership even while UIKit retains a departed page for its transition.
    func retireBedroomDrafts() {
        for (sourceID, draft) in bedroomDrafts { bedroomOwners[sourceID]?.retire(draft) }
    }

    /// The page draws its own header buttons from the authored chrome, not the shared header.
    override var showsHeaderButtons: Bool { false }
    /// The scroller a sheet measures to fit this page.
    var sheetFitScrollView: UIScrollView? { pageScroll }
    /// The page's form, when it hosts one.
    var formView: UKServerUIFormView? { nodes.values.compactMap { $0.view as? UKServerUIFormView }.first }
    /// The authored pinned-actions bar, when the page declares one.
    var pinnedDefinition: D.PinnedActions? {
        definition.components.compactMap { if case .pinnedActions(let value) = $0 { value } else { nil } }.first
    }
    /// Whether popping this page in a column is allowed, needs a discard, or is blocked.
    var columnPopDecision: UKColumnPopDecision {
        if formView?.blocksExit == true || blocksRecordExit { return .block }
        if let gate = renderer?.nativeExitGate, gate.blocksExit(self) { return gate.canDiscard(self) ? .confirmDiscard : .block }
        return formView?.needsDiscard == true ? .confirmDiscard : .allow
    }
    /// Asks before leaving a column, running `completion` once the discard guards agree.
    /// - Parameters:
    ///   - leaving: The pages being left.
    ///   - completion: Runs when leaving is allowed.
    func requestColumnExit(leaving: [UIViewController] = [], completion: @escaping () -> Void) {
        renderer?.requestNativeExit(from: self,
            leaving: leaving.isEmpty ? [self] : leaving.compactMap { $0 as? UKServerUIPage }, completion: completion)
    }
    /// Whether a record collection or form on this page has an unsaved change that blocks leaving.
    var blocksRecordExit: Bool {
        guard let renderer else { return false }
        func pending(_ components: [D.Component]) -> Bool {
            components.contains {
                if case .recipePart(let value) = $0 { return renderer.records.recipes[value.providerId]?.hasPendingIntent == true }
                if case .collection(let value) = $0 { return renderer.recordCollection(value.providerId)?.hasPendingIntent == true }
                return pending($0.childComponents)
            }
        }
        return pending(definition.components)
    }

    /// Re-measures the body and the column bar after a layout pass.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        nodes.values.compactMap { $0.view as? UKServerUIPinnedActions }.forEach { $0.layoutChanged() }
        nodes.values.compactMap { $0.view as? UKServerUILocalTabs }.forEach { $0.layoutChanged() }
    }

    /// Whether the page lays out as a master and detail pair at the current width.
    var wantsColumns: Bool {
        columns != nil && !(parent is UKColumnsViewController)
            && SplitPolicy.allowsSplit(size: view.bounds.size, isRegularWidth: traitCollection.horizontalSizeClass == .regular)
    }

    init(surface: D.Surface, context: UKContext, root: ServerUINavigationState.Root,
         presentationID: UUID?, depth: Int, inheritedGroups: [D.ChromeGroup], close: D.Close?,
         renderer: UKServerUIRenderer, columnPlaceholder: String? = nil) {
        surfaceID = surface.id
        definition = surface
        self.root = root
        self.presentationID = presentationID
        self.depth = depth
        self.inheritedGroups = inheritedGroups
        closePolicy = close
        self.renderer = renderer
        self.columnPlaceholder = columnPlaceholder
        super.init(context: context.with { $0.inkDefault = TileInkDefault(renderer.publication.inkDefault) }, title: surface.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Builds the scroller, the optional column host and the first set of keyed nodes.
    override func viewDidLoad() {
        super.viewDidLoad()
        let body = UKPageScrollView(content: column)
        body.delegate = self
        self.body = body
        slot.backgroundColor = .clear
        slot.addSubview(body)
        body.ukPin(to: slot)
        pageScroll = body
        if let columnPlaceholder {
            let columns = UKColumnsViewController(rootView: slot, shell: context.shell) {
                UKPanePlaceholderViewController(symbol: "square.and.pencil", text: columnPlaceholder, identifier: "server-ui.column.placeholder")
            }
            self.columns = columns
            columns.pushesCollapsedPages = false
            columns.onUserPop = { [weak self] count in
                guard let self else { return }
                renderer?.columnPopped(from: self, kept: count)
            }
            columns.onSettled = { [weak self] in self?.renderer?.columnsSettled() }
            addChild(columns)
            contentView.addSubview(columns.view)
            columns.view.ukPin(to: contentView)
            columns.didMove(toParent: self)
            setPageScrollView(body)
        } else {
            slot.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(slot)
            slot.ukPin(to: contentView)
            setPageScrollView(body)
        }
        render()
        bag.observe { [weak self] in
            guard let self else { return }
            _ = self.context.shell?.chrome
            _ = self.context.shell?.inVerticalBar
            self.refreshTitle()
            self.refreshChrome()
            _ = self.bedroomDrafts.values.contains(where: \.blocksExit)
            self.renderer?.updateSettingsExitGuard()
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitLayoutDirection.self]) { (page: UKServerUIPage, _) in
            page.render()
        }
    }

    /// Updates values and keyed children in place; a publication is not a new page instance.
    func update(_ surface: D.Surface, inheritedGroups: [D.ChromeGroup], close: D.Close?) {
        definition = surface
        self.inheritedGroups = inheritedGroups
        closePolicy = close
        title = surface.title
        context.inkDefault = renderer.map { TileInkDefault($0.publication.inkDefault) } ?? .muted
        if isViewLoaded { render(); refreshTitle() }
    }

    private func refreshTitle() {
        guard let id = definition.titleSourceId else { return }
        guard let provider = bedroomProvider(id), case .draft(let draft) = provider else {
            renderer?.onError(.init(code: .unavailableSource, pointer: "/document/dataSources"))
            return
        }
        title = draft.presentationTitle
    }

    private var currentBedroomDrafts: [ServerUIBedroomDraft] {
        func sourceIDs(_ components: [D.Component]) -> [String] {
            components.flatMap { component -> [String] in
                if case .bedroom(let control) = component { return [control.sourceId] }
                return sourceIDs(component.childComponents)
            }
        }
        return Set(sourceIDs(definition.components)).compactMap { bedroomDrafts[$0] }
    }

    /// Rebuilds the bar items once the view is loaded; before that the first load builds them.
    func refreshNavigation() {
        if isViewLoaded { refreshChrome() }
    }

    /// Drives the large title, the header fade and the pinned bar from the scroll offset.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        nodes.values.compactMap { $0.view as? UKServerUICollectionView }.forEach { $0.viewportChanged() }
    }

    // A presented alert or sheet is part of the renderer's busy state; announce both edges.
    /// Presents a view controller and tells the renderer, so `isEnabled(_:from:)` sees the presentation begin and end.
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        super.present(viewControllerToPresent, animated: flag) { [weak self] in
            completion?()
            self?.renderer?.busyState.changed()
        }
        renderer?.busyState.changed()
    }

    /// Dismisses a presented view controller and tells the renderer, so `isEnabled(_:from:)` sees the dismissal begin and end.
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        super.dismiss(animated: flag) { [weak self] in
            completion?()
            self?.renderer?.busyState.changed()
        }
    }

    /// Opens the navigation flyout.
    override func openMenu() { renderer?.openMenu(from: self) }

    /// Re-opens a form that was parked while the page was away.
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        formView?.reopenIfNeeded()
    }

    /// Tells local tabs the page departed, so a reset-on-presentation tab can reset.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        nodes.values.compactMap { $0.view as? UKServerUILocalTabs }.forEach { $0.departed() }
    }

    /// Backs out or dismisses on the VoiceOver escape gesture.
    override func accessibilityPerformEscape() -> Bool {
        guard let renderer else { return false }
        if depth > 0 { renderer.activate(.back, from: self); return true }
        if presentationID != nil { renderer.activate(.dismiss(scope: .currentModal), from: self); return true }
        return false
    }

    /// Rebuilds the bar items from the authored chrome groups, keeping unchanged items in place.
    func refreshChrome() {
        let groups: [D.ChromeGroup]
        switch definition.toolbar {
        case .inherit: groups = inheritedGroups
        case .replace(let value): groups = value
        }
        chrome.apply(groups: groups, close: closePolicy)
        formView?.applyChrome()
        if formView == nil {
            let domainBlocked = renderer?.nativeExitGate?.blocksExit(self) == true
            UKDiscardGuard.apply(to: self, hasChanges: domainBlocked, isBusy: blocksRecordExit)
            let drafts = currentBedroomDrafts
            if depth > 0 && !drafts.isEmpty {
                navigationItem.hidesBackButton = true
                if bedroomBack == nil {
                    bedroomBack = UKSheetItems.back(identifier: "server-ui.alarm.back", hasChanges: false, presenter: self) { [weak self] in
                        guard let self else { return }
                        self.renderer?.activate(.back, from: self)
                    }
                }
                bedroomBack?.isEnabled = drafts.allSatisfy(\.canDiscard) && !blocksRecordExit
                navigationItem.leftBarButtonItems = bedroomBack.map { [$0] } ?? []
            } else if bedroomBack != nil {
                navigationItem.leftBarButtonItems = navigationItem.leftBarButtonItems?.filter { $0 !== bedroomBack }
                bedroomBack = nil
                navigationItem.hidesBackButton = false
            }
        }
        (parent as? UKColumnsViewController)?.pageStateChanged()
        if let pinnedDefinition {
            nodes.values.compactMap { $0.view as? UKServerUIPinnedActions }.first?.bind(pinnedDefinition, page: self)
        }
        if let columnGroup {
            navigationItem.leadingItemGroups = navigationItem.leadingItemGroups.filter { $0 !== columnGroup }
        }
        if let columnBar {
            columnAction.image = UIImage(systemName: columnBar.kind == .back ? "chevron.backward" : "xmark")
            columnAction.title = columnBar.kind == .back ? "Back" : "Close"
            columnAction.accessibilityLabel = columnAction.title
            columnAction.accessibilityIdentifier = columnBar.kind == .back ? "split.back" : "split.close"
            columnAction.isEnabled = columnBar.isEnabled
            columnAction.isHidden = columnBar.kind == .none
            columnAction.primaryAction = UIAction { _ in columnBar.perform() }
            let group = columnGroup ?? UIBarButtonItemGroup(barButtonItems: [], representativeItem: nil)
            group.barButtonItems = columnBar.items + [columnAction]
            columnGroup = group
            navigationItem.leadingItemGroups += [group]
        }
    }

    /// Installs or removes the column bar the page hosts.
    override func setColumnBar(_ bar: UKColumnBar?) {
        columnBar = bar
        if isViewLoaded { refreshChrome() }
    }

    /// Moves VoiceOver focus to the menu item.
    func focusMenu() { chrome.focusMenu() }

    /// Whether a focused field, a presented controller, a running tab swap or an active form, paged row or device interaction must keep a new publication from replacing the page.
    var blocksShellPublication: Bool {
        func hasFocus(_ view: UIView) -> Bool { view.isFirstResponder || view.subviews.contains(where: hasFocus) }
        return isViewLoaded && (hasFocus(view) || presentedViewController != nil || nodes.values.contains {
            ($0.view as? UKServerUILocalTabs)?.isTransitioning == true ||
            ($0.view as? UKServerUIPagedRow)?.blocksPublication == true ||
            ($0.view as? UKServerUIFormView)?.blocksPublication == true
                || ($0.view as? UKServerUIDeviceAtom)?.hasActiveInteraction == true
                || ($0.view as? UKGlassTileView)?.swipe?.isDragging == true
        })
    }

    private func render() {
        guard let renderer, let body else { return }
        let feedbackSources = Set(definition.components.compactMap { component -> String? in
            guard case .bedroom(let value) = component else { return nil }
            return value.kind == .wakeSummary || (value.kind == .feedback && value.parameter == "error") ? value.sourceId : nil
        })
        layoutBag.removeAll()
        let scrollerID = soleScrollingCollectionID(renderer)
        column.spacing = definition.layout.spacing.points
        body.padding = UKServerUIPreflight.padding(definition.layout.padding,
                                                   rightToLeft: view.effectiveUserInterfaceLayoutDirection == .rightToLeft)
        switch definition.layout.maxWidth {
        case .unbounded: body.maxWidth = .greatestFiniteMagnitude
        case .points(let value): body.maxWidth = value
        }
        var retained: [String: UKServerUINode] = [:]
        var containerChanges: [(clear: () -> Void, install: () -> Void)] = []
        var railChanges: [(UKChipRailView, [UIView])] = []
        var sectionChanges: [UKRoomSectionContent] = []
        var layoutBindings: [() -> Void] = []
        func node(_ component: D.Component) -> UIView {
            let id = component.node.id
            let entry = nodes[id].flatMap { $0.matches(component) ? $0 : nil } ?? UKServerUINode(component, surface: context.surface)
            retained[id] = entry
            entry.bag.removeAll()
            switch component {
            case .settingsControl(let control):
                if let view = entry.view as? UKServerUISettingsAtom, let provider = renderer.settingsProvider(for: control.sourceId) {
                    do { try view.bind(control, provider: provider, page: self) }
                    catch { renderer.onError(.init(code: .unavailableSource, pointer: "/document/dataSources")) }
                }
            case .statusRail(let rail):
                if let view = entry.view as? UKChipRailView {
                    view.hinge = context.shell?.windowHinge
                    view.edgeInset = UKChipRailView.edgeInset(pagePadding: min(body.padding.left, body.padding.right))
                    let children = rail.children.map(node)
                    if entry.childViews != children {
                        entry.childViews = children
                        railChanges.append((view, children))
                    }
                }
            case .statusChip(let chip):
                if let view = entry.view as? UKStatusChipView {
                    var shown: ServerUIResolvedAppearance?
                    entry.bag.observe { [weak self, weak view, weak renderer] in
                        guard let self, let view, let renderer, let value = renderer.bindings.status(chip.sourceId) else { return }
                        let action: (() -> Void)? = chip.action.map { intent in
                            { [weak self, weak view] in
                                guard let self else { return }
                                self.renderer?.activate(intent, from: self, source: view)
                            }
                        }
                        let (look, text) = UKServerUIHomeViews.appearance(chip, value: value, in: renderer.reader(), keeping: shown)
                        shown = look
                        UKServerUIHomeViews.configure(view, chip: chip, value: value, appearance: look, text: text, action: action)
                    }
                }
            case .roomOverviewTile(let tile):
                if let view = entry.view as? UKGlassTileView {
                    var shown: ServerUIResolvedAppearance?
                    entry.bag.observe { [weak self, weak view, weak renderer] in
                        guard let self, let view, let renderer, let value = renderer.bindings.status(tile.chip.sourceId, words: tile.words) else { return }
                        let (appearance, text) = UKServerUIHomeViews.appearance(tile.chip, value: value, in: renderer.reader(), keeping: shown)
                        shown = appearance
                        let hiddenSubtitle: Bool
                        let family: ColorFamily
                        if case .homeStatus(_, let config) = renderer.bindings.definitions[tile.chip.sourceId] {
                            hiddenSubtitle = tile.hidesContactSubtitle && config.projection == .contacts
                                && ["idle", "open-home", "open-away", "open-armed"].contains(value.state)
                            family = switch config.projection {
                            case .lights: .lights
                            case .climate: config.format == .item && config.entityIds.first?.hasPrefix("cover.") == true ? .vents : .climate
                            case .contacts: .contact
                            case .occupancy: .occupancy
                            case .airQuality: .air
                            case .entity: .neutral
                            }
                        } else { hiddenSubtitle = false; family = .neutral }
                        let fillPair = UKServerUIHomeViews.pair(appearance.fill)
                        let fill = fillPair?.light
                        let tint = family == .air ? value.color.map { UIColor.ukRGB($0.rgb) } : nil
                        let previousLabel = view.accessibilityLabel
                        let previousValue = view.accessibilityValue
                        var model = UKGlassTileModel(title: tile.chip.node.title, subtitle: hiddenSubtitle ? nil : text,
                                                     symbol: appearance.icon.drawn, tint: tint, family: family, fillRGB: fill,
                                                     isActive: value.active || fill != nil || tint != nil,
                                                     isUnavailable: value.unavailable, kind: tile.chip.action == nil ? .state : .navigate,
                                                     identifier: tile.chip.node.id, spokenValue: value.spoken)
                        model.fillDarkRGB = fillPair.flatMap { $0.isFixed ? nil : $0.dark }
                        model.stateCandidates = [text]
                        let power = tile.powerSourceId.flatMap { renderer.bindings.lights[$0] }
                        let powerSpec = power?.roomPower(title: tile.chip.node.title)
                        if var powerSpec {
                            powerSpec.isError = power?.isFailed == true
                            model.actions = [powerSpec].items
                            model.isError = powerSpec.isError
                        }
                        view.configure(model, environment: UKTileEnvironment(context: self.context), action: { [weak self, weak view] in
                            guard let self, let action = tile.chip.action else { return }
                            self.renderer?.activate(action, from: self, source: view)
                        }, perform: { [weak renderer] _ in
                            guard let renderer, let power, let powerSpec, let sourceID = tile.powerSourceId else { return }
                            do {
                                guard renderer.bindings.lights[sourceID] === power else { throw ServerUIHomeLightSource.Failure.invalidCommand }
                                try power.performRoomPower(title: tile.chip.node.title, expected: powerSpec)
                            } catch { renderer.onError(.init(code: .unavailableSource, pointer: "/document/dataSources")) }
                        })
                        UKServerUIHomeViews.announce(view, policy: tile.chip.announcement, previousLabel: previousLabel, previousValue: previousValue)
                        view.ukRemeasureContainers()
                    }
                }
            case .homeLightTile(let tile):
                if let view = entry.view as? UKServerUIHomeLightView {
                    view.bind(tile, bindings: renderer.bindings, context: context) { [weak renderer] error in renderer?.onError(error) }
                }
            case .weatherPanel(let panel):
                if let view = entry.view as? UKServerUIWeatherPanel, let source = renderer.bindings.weather[panel.sourceId] {
                    let action: (() -> Void)? = panel.action.map { intent in
                        { [weak self, weak view] in
                            guard let self else { return }
                            self.renderer?.activate(intent, from: self, source: view)
                        }
                    }
                    view.bind(panel, source: source, action: action)
                }
            case .alarmPanel(let panel):
                if let view = entry.view as? UKAlarmPanelControl {
                    UKServerUISecurityViews.bind(panel, view: view, bag: entry.bag, page: self, renderer: renderer)
                }
            case .stateTile(let tile):
                if let view = entry.view as? UKGlassTileView {
                    UKServerUIStateTileViews.bind(tile, view: view, bag: entry.bag, page: self, renderer: renderer, node: entry)
                }
            case .climate(let control):
                if let view = entry.view as? UKServerUIClimateControl,
                   let adapter = renderer.bindings.climates[control.props.sourceId] {
                    view.configure(control, adapter: adapter, context: context) { [weak self, weak view] action in
                        guard let self else { return }
                        self.renderer?.activate(action, from: self, source: view)
                    }
                }
            case .roomCard(let card): UKServerUIRooms.bind(card, entry: entry, page: self, chip: false)
            case .roomChip(let card): UKServerUIRooms.bind(card, entry: entry, page: self, chip: true)
            case .roomNavigationGrid(let grid):
                (entry.view as? UKServerUIRoomNavigationGrid)?.bind(grid, entry: entry, page: self)
            case .roomSection(let section):
                if let view = entry.view as? UKRoomSectionContent {
                    let children = section.children.map { ($0, node($0)) }
                    let items = children.filter { renderer.componentVisible($0.0) }.map { UKGridItem($0.1, span: $0.0.node.span) }
                    if view.itemViews != items.map(\.view) || view.itemSpans != items.map(\.span) { sectionChanges.append(view) }
                    var last: [UIView]?
                    layoutBindings.append { [weak view, weak renderer, weak self] in
                        entry.bag.observe { [weak view, weak renderer, weak self] in
                            guard let view, let renderer else { return }
                            let items = children.filter { renderer.componentVisible($0.0) }
                                .map { UKGridItem($0.1, span: $0.0.node.span) }
                            if last != items.map(\.view) {
                                view.configure(title: section.node.title, arrangement: section.layout,
                                               leadJoinsAtRegularWidth: section.leadJoinsAtRegularWidth, items: items)
                                last = items.map(\.view)
                                self?.body?.contentChanged(animated: false)
                            }
                        }
                    }
                }
            case .roomDeviceControl(let control):
                if let view = entry.view as? UKServerUIRoomDeviceAtom {
                    view.onNavigate = { [weak self] action, source in
                        guard let self else { return }
                        self.renderer?.activate(action, from: self, source: source)
                    }
                    view.update(control, source: renderer.bindings.devices[control.sourceId], context: context)
                }
            case .bedroom(let control):
                if let view = entry.view as? UKServerUIBedroomControl {
                    if let provider = bedroomProvider(control.sourceId) {
                        view.configure(control, provider: provider, presenter: { [weak self] in self },
                                   onError: { [weak renderer] in renderer?.onError($0) }, context: context,
                                   sharedFeedback: feedbackSources.contains(control.sourceId),
                                   navigate: { [weak self] action, source in
                                       guard let self else { return }
                                       self.renderer?.activate(action, from: self, source: source)
                                   }, completed: { [weak self] in
                                       guard let self else { return }
                                       self.renderer?.activate(self.depth > 0 ? .back : .dismiss(scope: .currentModal), from: self)
                                   })
                    } else {
                        view.showUnavailable(control, message: bedroomErrors[control.sourceId] ?? control.unavailableText)
                    }
                }
            case .deviceControl(let control):
                (entry.view as? UKServerUIDeviceAtom)?.bind(control, providers: renderer.deviceProviders, context: context,
                    presenter: { [weak self] in self }, navigate: { [weak self] action, source in
                        guard let self else { return }
                        self.renderer?.activate(action, from: self, source: source)
                    }, onError: { [weak renderer] in renderer?.onError($0) })
            case .vacuum(let control):
                (entry.view as? UKServerUIVacuumView)?.configure(control, source: renderer.bindings.vacuums[control.sourceId], page: self)
            case .accountHeader(let header):
                if let view = entry.view as? UKAccountHeaderView {
                    view.bindAvatar { [weak renderer] in
                        guard !ScreenshotPrivacy.isRedacting,
                              case .ready(_, _, let avatar) = renderer?.accountProvider?.account else { return nil }
                        return avatar
                    }
                    entry.bag.observe { [weak view, weak renderer] in
                        guard let view, let renderer else { return }
                        if ScreenshotPrivacy.isRedacting {
                            view.update(name: nil, server: "", fallbackName: header.fallbackName)
                        } else {
                            switch renderer.accountProvider?.account {
                            case .loading: view.update(name: nil, server: "", fallbackName: header.loadingText)
                            case .ready(let name, let server, _):
                                view.update(name: name, server: server, fallbackName: header.fallbackName)
                            case .unavailable, nil:
                                view.update(name: nil, server: "", fallbackName: header.unavailableText)
                            }
                        }
                        view.ukRemeasureContainers()
                    }
                }
            case .cameraTile(let camera):
                configureCamera(component, sourceID: camera.sourceId, entry: entry)
            case .cameraVideo(let camera):
                configureCamera(component, sourceID: camera.sourceId, entry: entry)
            case .cameraControls(let camera):
                configureCamera(component, sourceID: camera.sourceId, entry: entry)
            case .cameraViewer(let camera):
                configureCamera(component, sourceID: camera.sourceId, entry: entry)
            case .notificationBanner(let banner):
                if let view = entry.view as? UKNotificationPermissionPromptView {
                    entry.bag.observe { [weak view, weak renderer] in
                        guard let renderer else { return }
                        view?.apply(copy: .init(title: banner.node.title, message: banner.message,
                                               enable: banner.enableLabel, dismiss: banner.dismissLabel),
                                    busy: renderer.notificationSource.pendingNode != nil)
                        view?.isHidden = !renderer.notificationSource.visible
                    }
                    view.onEnable = { [weak renderer] in renderer?.notificationSource.enable(nodeID: banner.node.id) }
                    view.onDismiss = { [weak renderer] in renderer?.notificationSource.dismiss() }
                }
            case .bootstrapMessage(let message):
                (entry.view as? UKServerUIBootstrapMessage)?.apply(message)
            case .text(let text):
                if let view = entry.view as? UKServerUIText {
                    view.isSectionTitle = text.style == .sectionTitle
                    view.style = UKServerUIPreflight.textStyle(text.style)
                    view.look = text.look
                    entry.bag.observe { [weak view, weak renderer] in
                        guard let renderer else { return }
                        view?.apply(renderer.bindings.string(text.value), unavailable: text.unavailableText)
                    }
                }
            case .grid(let grid):
                if let view = entry.view as? UKDynamicGridView {
                    view.configuration = UKServerUIPreflight.grid(grid, traits: traitCollection)
                    view.followsFold = grid.fold == .page && !isSheet && !context.isPane
                    let children = grid.children.map { ($0, node($0)) }
                    // A grid grouped by state arranges its tiles under headings and moves one when its state changes (`sh.grid-state-groups@1`).
                    if grid.groups != entry.grouping?.groups {
                        entry.grouping?.detach()
                        entry.grouping = grid.groups.map { UKServerUIGridGrouping($0, gridID: grid.node.id, grid: view, surface: context.surface) }
                    }
                    entry.grouping?.reapplyGeneration = { [weak self] in self?.context.store.reapplyGeneration ?? 0 }
                    entry.grouping?.relayout = { [weak self] animated in self?.body?.contentChanged(animated: animated) }
                    let grouping = entry.grouping
                    func arranged() -> [UKGridItem] {
                        let shown = children.filter { renderer.componentVisible($0.0) }.map { (view: $0.1, span: $0.0.node.span) }
                        return grouping?.items(shown) ?? shown.map { UKGridItem($0.view, span: $0.span) }
                    }
                    let items = arranged()
                    if view.items.map(\.view) != items.map(\.view) || view.items.map(\.span) != items.map(\.span) {
                        containerChanges.append(({ view.setItems([]) }, { view.setItems(items) }))
                    }
                    layoutBindings.append { [weak view, weak renderer, weak self] in
                        entry.bag.observe { [weak view, weak renderer, weak self] in
                            guard let view, let renderer else { return }
                            let items = arranged()
                            if view.items.map(\.view) != items.map(\.view) || view.items.map(\.span) != items.map(\.span) {
                                view.setItems(items)
                                self?.body?.contentChanged(animated: false)
                            }
                        }
                    }
                }
            case .infoBox(let value):
                if let view = entry.view as? UKServerUIInfoBox {
                    entry.bag.observe { [weak view, weak renderer] in
                        guard let renderer else { return }
                        view?.apply(value, bindings: renderer.bindings)
                    }
                }
            case .statusPill(let value):
                if let view = entry.view as? UKStatusPillView {
                    entry.bag.observe { [weak view, weak renderer] in
                        guard let renderer, let view else { return }
                        let text: String
                        var pending = false
                        var tone = value.resolvedTone(in: renderer.reader()).native
                        switch renderer.bindings.string(value.value) {
                        case .ready(let value): text = value
                        case .loading: text = ""; pending = true
                        case .unavailable: text = value.unavailableText; tone = .unavailable
                        }
                        let detail: String?
                        if case .ready(let text) = renderer.bindings.string(value.detail), !text.isEmpty { detail = text }
                        else { detail = nil }
                        view.valuesPending = pending
                        view.configure(label: value.node.title, value: text, detail: detail, symbol: value.icon.drawn, tone: tone)
                    }
                }
            case .pagedRow(let value):
                if let view = entry.view as? UKServerUIPagedRow {
                    let children = value.children.map { ($0, node($0)) }
                    let reparent = view.needsReparent(children.filter { renderer.componentVisible($0.0) }.map(\.1))
                    containerChanges.append(({ if reparent { view.clear() } }, {
                        entry.bag.observe { [weak view, weak renderer, weak self] in
                            guard let view, let renderer else { return }
                            view.apply(value, children: children.filter { renderer.componentVisible($0.0) }.map(\.1))
                            self?.body?.contentChanged(animated: false)
                        }
                    }))
                }
            case .section(let section):
                if let view = entry.view as? UKServerUISection {
                    let children = section.children.map { ($0, node($0)) }
                    let views = children.filter { renderer.componentVisible($0.0) }.map(\.1)
                    let reparent = view.needsReparent(section, children: views)
                    containerChanges.append(({ if reparent { view.clear() } }, {
                        entry.bag.observe { [weak view, weak renderer, weak self] in
                            guard let view, let renderer, let self else { return }
                            let state = section.presentationProviderId.flatMap { renderer.records.sections[$0]?() } ?? .init()
                            view.apply(section, children: children.filter { renderer.componentVisible($0.0) }.map(\.1),
                                       surface: self.context.surface, state: state)
                            self.body?.contentChanged(animated: false)
                        }
                    }))
                }
            case .row(let row):
                if let view = entry.view as? UKServerUIRow {
                    entry.bag.observe { [weak self, weak view, weak renderer] in
                        guard let self, let renderer, let view else { return }
                        view.apply(row, bindings: renderer.bindings, surface: self.context.surface,
                                   enabled: row.action.map { renderer.isEnabled($0, from: self) && renderer.isEnabled(node: row.node) } ?? false) { [weak self, weak view] in
                            guard let self, let action = row.action else { return }
                            self.renderer?.activate(action, from: self, source: view, symbol: row.icon?.drawn ?? "")
                        }
                    }
                }
            case .overlay(let overlay):
                if let view = entry.view as? UKServerUIOverlayView {
                    let children = overlay.children.map { ($0, node($0)) }
                    let reparent = view.needsReparent(children.filter { renderer.componentVisible($0.0) }.map(\.1))
                    containerChanges.append(({ if reparent { view.clear() } }, {
                        entry.bag.observe { [weak view, weak renderer, weak self] in
                            guard let view, let renderer else { return }
                            let shown = children.filter { renderer.componentVisible($0.0) }
                            // The first child is the base; the rest are the controls on top.
                            let base = shown.first.flatMap { $0.0.node.id == overlay.children.first?.node.id ? $0.1 : nil }
                            view.apply(overlay, base: base, controls: shown.filter { $0.0.node.id != overlay.children.first?.node.id }
                                .map { ($0.0.node.id, $0.1) })
                            self?.body?.contentChanged(animated: false)
                        }
                    }))
                }
            case .stack(let stack):
                if let view = entry.view as? UKStackView {
                    let children = stack.children.map { ($0, node($0)) }
                    let reparent = view.needsReparent(children.filter { renderer.componentVisible($0.0) }.map(\.1))
                    containerChanges.append(({ if reparent { view.clear() } }, {
                        entry.bag.observe { [weak view, weak renderer, weak self] in
                            guard let view, let renderer, let self else { return }
                            UKServerUIStyleParts.apply(stack, to: view, children: children, page: self, renderer: renderer)
                            self.body?.contentChanged(animated: false)
                        }
                    }))
                }
            case .shape(let shape): (entry.view as? UKShapeView)?.apply(shape)
            case .symbol(let part):
                if let view = entry.view as? UKSymbolPartView { UKServerUIStyleParts.bind(part, view: view, entry: entry, renderer: renderer) }
            case .localTabs(let tabs):
                if let view = entry.view as? UKServerUILocalTabs {
                    let scope = tabs.scopeProviderId.flatMap { renderer.records.tabScopes[$0] }
                    var tabs = tabs
                    if let scope { tabs.tabs = tabs.tabs.filter { scope.allowedTabIDs.contains($0.id) } }
                    let children = tabs.tabs.map { $0.children.map { ($0, node($0)) } }
                    let areaChildren = tabs.areas.map { $0.children.map { ($0, node($0)) } }
                    let reparent = view.needsReparent(tabs, children: children.map { $0.map(\.1) }, areaChildren: areaChildren.map { $0.map(\.1) })
                    containerChanges.append(({ if reparent { view.clear() } }, {
                        if let scope {
                            do { try view.prepareScope(scope, stateID: tabs.stateId, state: renderer.localState) }
                            catch { renderer.onError(.init(code: .unavailableSource, pointer: "/document/localState")); return }
                        }
                        entry.bag.observe { [weak self, weak view, weak renderer, weak entry] in
                            guard let self, let view, let renderer, let entry,
                                  case .string(var selection)? = renderer.localState.values[tabs.stateId] else { return }
                            if !tabs.automatic.isEmpty {
                                // A rule that newly becomes the first match selects its panel once; the person's own choice then stands
                                // until the match changes again (it is not forced back while the rule keeps holding).
                                let reader = renderer.reader()
                                let match = tabs.automatic.first { $0.selectedWhen.evaluate(reader) == .yes }?.tabId
                                if match != entry.automaticMatch {
                                    entry.automaticMatch = match
                                    if let match, match != selection, (try? renderer.localState.set(.string(match), for: tabs.stateId)) != nil {
                                        selection = match
                                    }
                                }
                            }
                            let resolved: String
                            do { resolved = try view.resolveSelection(scope, stored: selection, value: tabs) }
                            catch { renderer.onError(.init(code: .unavailableSource, pointer: "/document/localState")); return }
                            if let title = scope?.title() { self.title = title }
                            // Tabs and areas hidden by their rules, the fallback tab and the areas that draw on the tab on show.
                            let layout = UKServerUITabLayout.resolve(tabs, requested: resolved, reader: renderer.reader(), memory: &entry.layoutMemory)
                            view.apply(layout.container, children: layout.keeping(children, parallelTo: tabs.tabs)
                                           .map { $0.filter { renderer.componentVisible($0.0) }.map(\.1) },
                                       areaChildren: areaChildren.map { $0.filter { renderer.componentVisible($0.0) }.map(\.1) },
                                       shownAreas: layout.shownAreas, selection: layout.selection, page: self,
                                       badges: scope?.badges() ?? [:]) { [weak self] value in
                                guard let self else { return }
                                self.view.endEditing(true)
                                self.renderer?.activate(.setLocal(stateId: tabs.stateId, value: .string(value)), from: self)
                            }
                            view.ukRemeasureContainers()
                        }
                    }))
                }
            case .localControl(let control):
                if let view = entry.view as? UKServerUILocalControl {
                    entry.bag.observe { [weak self, weak view, weak renderer] in
                        guard let self, let view, let renderer,
                              let field = renderer.publication.document.localState.first(where: { $0.id == control.stateId }),
                              let value = renderer.localState.values[control.stateId] else { return }
                        view.apply(control, field: field, value: value, surface: self.context.surface) { [weak self, weak view, weak renderer] value in
                            guard let self, let renderer else { return }
                            self.renderer?.activate(.setLocal(stateId: control.stateId, value: value), from: self)
                            if let accepted = renderer.localState.values[control.stateId] { view?.showAccepted(accepted) }
                        }
                    }
                }
            case .boundControl(let control):
                bindBoundControl(control, entry: entry, renderer: renderer)
            case .button(let button):
                if let wrapper = entry.view as? UKServerUIPrimaryButton {
                    entry.bag.observe { [weak self, weak wrapper, weak renderer] in
                        guard let self, let wrapper, let renderer else { return }
                        wrapper.button.title = button.node.title
                        wrapper.button.accessibilityIdentifier = button.node.id
                        wrapper.button.systemImage = button.icon?.drawn
                        wrapper.button.isEnabled = renderer.isEnabled(button.action, from: self) && renderer.isEnabled(node: button.node)
                        wrapper.button.action = { [weak self, weak wrapper] in
                            guard let self else { return }
                            self.renderer?.activate(button.action, from: self, source: wrapper?.button, symbol: button.icon?.drawn ?? "")
                        }
                    }
                }
            case .collection(let value):
                if let view = entry.view as? UKServerUICollectionView, let source = renderer.recordCollection(value.providerId) {
                    view.bind(value, provider: source, page: self, scrolling: value.node.id == scrollerID)
                }
            case .form(let value):
                if let view = entry.view as? UKServerUIFormView, let factory = renderer.records.forms[value.providerId] {
                    view.bind(value, factory: factory, page: self)
                }
            case .recipePart(let value):
                if let view = entry.view as? UKServerUIRecipePartView, let source = renderer.records.recipes[value.providerId] {
                    view.bind(value, source: source, page: self)
                }
            case .pinnedActions(let value):
                if let view = entry.view as? UKServerUIPinnedActions {
                    let children = value.children.map(node)
                    let reparent = entry.childViews != children
                    entry.childViews = children
                    containerChanges.append(({ if reparent { view.releaseControls() } }, { view.bind(value, page: self, controls: children) }))
                }
            case .rowCollection(let collection):
                if let view = entry.view as? UKServerUIRowCollection, let model = renderer.collections[collection.providerId] {
                    entry.bag.observe { [weak self, weak view, weak renderer] in
                        guard let self else { return }
                        var detail: String?
                        if let message = collection.emptyMessage, case .ready(let text) = renderer?.bindings.string(message) { detail = text }
                        var select: ((ServerUIRowItem) -> Void)?
                        if let action = collection.rowAction {
                            select = { [weak self, weak view] _ in
                                guard let self else { return }
                                self.renderer?.activate(action, from: self, source: view)
                            }
                        }
                        view?.apply(collection, model: model, surface: self.context.surface, emptyDetail: detail, onSelect: select)
                    }
                }
            case .navigationTile(let tile):
                if let view = entry.view as? UKGlassTileView {
                    var first = true
                    var shownFill: D.TileFill?
                    entry.bag.observe { [weak self, weak view, weak renderer] in
                        guard let self, let view, let renderer else { return }
                        let subtitle: String?
                        switch renderer.bindings.string(tile.subtitle) {
                        case .ready(let value): subtitle = value.isEmpty ? nil : value
                        case .loading: subtitle = nil
                        case .unavailable: subtitle = nil
                        }
                        var environment = UKTileEnvironment(context: self.context)
                        var fillRGB: UInt32?
                        var fillDarkRGB: UInt32?
                        if let presentation = tile.presentation {
                            environment.layout = presentation.layout == .anchoredBottom ? .anchoredBottom : .standard
                            environment.titleLines = presentation.titleLines
                            // A fill that follows a rule or an entity's color is read here, inside this observation.
                            let fill = presentation.resolvedFill(in: renderer.reader(), keeping: shownFill)
                            shownFill = fill
                            if let pair = UKServerUIHomeViews.pair(fill) {
                                fillRGB = pair.light
                                fillDarkRGB = pair.isFixed ? nil : pair.dark
                            }
                        }
                        let title = tile.titleProviderId.flatMap { renderer.recordCollection($0)?.navigationTitle }.flatMap { $0.isEmpty ? nil : $0 } ?? tile.node.title
                        var model = UKGlassTileModel(title: title, subtitle: subtitle, symbol: tile.icon.drawn,
                                                     family: UKServerUIPreflight.family(tile.family), fillRGB: fillRGB,
                                                     isActive: tile.selected == .navigationPath && renderer.isSelected(tile.action, from: self),
                                                     kind: .navigate, identifier: tile.node.id)
                        model.fillDarkRGB = fillDarkRGB
                        model.bodyHint = tile.presentation?.bodyHint
                        var alarmSpec: TileActionSpec?
                        if let alarm = tile.alarm, let provider = renderer.bindings.alarms[alarm.sourceId] {
                            let projection = provider.projection
                            let redacting = ScreenshotPrivacy.isRedacting
                            let appearance = redacting ? alarm.fallback
                                : alarm.states.first(where: { $0.state == projection.state })?.appearance ?? alarm.fallback
                            model.symbol = redacting ? tile.icon.drawn : appearance.icon.drawn
                            if case .solidRGB(let red, let green, let blue) = appearance.fill {
                                model.fillRGB = UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
                            }
                            model.subtitle = redacting ? alarm.hiddenText
                                : self.context.valuesPending ? alarm.loadingText
                                : projection.failed ? alarm.errorText
                                : EntityState.isUnavailable(projection.state) ? alarm.unavailableText : appearance.text
                            model.isError = !redacting && projection.failed
                            if !redacting, self.context.caller != nil {
                                alarmSpec = projection.spec
                                // The renderer owns the immutable ticket before showing the provider's question.
                                model.actions = [projection.spec.with(confirmation: nil)].items
                            }
                            model.stateCandidates = alarm.states.map(\.appearance.text)
                                + [alarm.fallback.text, alarm.loadingText, alarm.unavailableText, alarm.errorText, alarm.hiddenText]
                            model.reapplyGeneration = self.context.store.reapplyGeneration
                            let resolution = StateStyle.alarm.resolve(
                                EntityState(entityId: provider.entityID, state: projection.state ?? "unavailable"), entityId: provider.entityID)
                            let look = UKStateTileLooks.look(
                                resolution, request: .init(isInFlight: projection.spec.phase == .inFlight, failed: !redacting && projection.failed,
                                                           isUnknown: redacting || self.context.valuesPending || EntityState.isUnavailable(projection.state)),
                                icon: model.symbol, text: model.subtitle ?? "", isActive: model.isActive, hasDisc: !model.actions.isEmpty)
                            model.look = look
                            model.isWarning = look.stateClass == .warning
                        }
                        view.configure(model, environment: environment, animated: tile.alarm != nil && !first,
                                       action: { [weak self, weak view] in
                            guard let self else { return }
                            self.renderer?.activate(tile.action, from: self, source: view)
                        }, perform: { [weak self, weak view] id in
                            guard let self, let view, id == StateStyle.alarm.actionId, let alarmSpec else { return }
                            self.renderer?.activateAlarm(tile, expected: alarmSpec, from: self, source: view)
                        })
                        first = false
                        view.ukRemeasureContainers()
                    }
                }
            case .actionTile(let tile):
                if let view = entry.view as? UKGlassTileView {
                    var first = true
                    entry.bag.observe { [weak self, weak view, weak renderer] in
                        guard let self, let view, let renderer else { return }
                        let id = renderer.bindings.entityID(for: tile.binding.sourceId).value
                        let power = renderer.bindings.powers[tile.binding.sourceId]
                        let projection = power?.projection(entityID: id, symbol: tile.icon.drawn)
                        let specs = projection.map { [$0.spec] } ?? []
                        var model = UKGlassTileModel(title: tile.node.title,
                                                     subtitle: tile.powerText(spec: projection?.spec, failed: projection?.failed == true, fallback: projection?.text),
                                                    symbol: tile.icon.drawn, family: UKServerUIPreflight.family(tile.family),
                                                    isActive: specs.first?.isOn == true, isUnavailable: id == nil || specs.first?.phase == .unavailable,
                                                    isError: projection?.failed == true,
                                                    behavior: .perform(PowerToggleActions.actionId), actions: specs.items,
                                                    identifier: tile.node.id)
                        model.stateCandidates = (projection?.candidates ?? []) + (tile.powerLabels.map { [$0.on, $0.off] } ?? [])
                        model.reapplyGeneration = self.context.store.reapplyGeneration
                        view.configure(model, environment: UKTileEnvironment(context: self.context), animated: !first,
                                       perform: { [weak self, weak view] _ in
                            guard let self else { return }
                            self.renderer?.activate(.domain(tile.action), from: self, source: view, symbol: tile.icon.drawn)
                        })
                        first = false
                        view.ukRemeasureContainers()
                    }
                }
            case .settingsLink(let link):
                if let row = entry.view as? UKServerUISettingsLink {
                    let cell = row.cell
                    cell.reset()
                    cell.style = self.isSheet ? .sheet : .wallpaper
                    cell.kind = .link
                    cell.show(UKRowView.settingsLink(title: link.node.title, subtitle: link.subtitle,
                                                    symbol: link.icon.drawn, showsChevron: link.showsChevron))
                    cell.makeElement(label: UKRowView.accessibilityLabel(title: link.node.title, subtitle: link.subtitle),
                                     hint: link.hint, traits: .button, identifier: link.node.id)
                    cell.isEnabled = renderer.isEnabled(link.action, from: self)
                    cell.setAction { [weak self, weak cell] in
                        guard let self else { return }
                        self.renderer?.activate(link.action, from: self, source: cell)
                    }
                    row.setNeedsLayout()
                }
            case .remote(let remote):
                if let view = entry.view as? UKServerUIRemoteAtom, let session = renderer.bindings.remotes[remote.sourceId] {
                    view.configure(remote, session: session, context: context, artwork: { [weak renderer] key in
                        guard let renderer, case .mediaRemote(_, let providerID) = renderer.bindings.definitions[remote.sourceId] else { return nil }
                        return renderer.artworkURL(providerID: providerID, appID: key)
                    }, navigate: { [weak self] action, source in
                        guard let self else { return }
                        self.renderer?.activate(action, from: self, source: source)
                    }, residentId: renderer.roomResidentId, onError: { [weak renderer] in
                        renderer?.onError(.init(code: .unavailableSource, pointer: "/document/dataSources"))
                    })
                }
            }
            if let rule = component.node.visibleWhen { observeVisibility(of: entry, rule: rule, component: component) }
            UKServerUIBadgeViews.bind(component, entry: entry, renderer: renderer)
            return entry.view
        }
        let roots = definition.components.map { ($0, node($0)) }
        let views = roots.filter {
            if case .pinnedActions = $0.0 { return false }
            return $0.0.node.id != scrollerID && renderer.componentVisible($0.0)
        }.map(\.1)
        scrollerCollectionID = scrollerID
        hostScroller(scrollerID.flatMap { retained[$0]?.view as? UKServerUICollectionView })
        let rootChanged = column.views != views
        // Clear changed owners before reattaching: canonical setters remove their previous children,
        // including a keyed view another container might otherwise have already adopted.
        if rootChanged { column.setViews([]) }
        sectionChanges.forEach { $0.releaseItems() }
        for change in containerChanges { change.clear() }
        for (rail, _) in railChanges { rail.setChips([]) }
        for change in containerChanges { change.install() }
        for (rail, children) in railChanges { rail.setChips(children) }
        if rootChanged { column.setViews(views) }
        for (key, node) in nodes where retained[key]?.view !== node.view {
            (node.view as? UKServerUIFormView)?.detach()
            (node.view as? UKServerUILocalTabs)?.detach()
            if let bar = node.view as? UKServerUIPinnedActions {
                bar.detach()
                additionalSafeAreaInsets.bottom = 0
            }
        }
        nodes = retained
        let collections = nodes.values.compactMap { $0.view as? UKServerUICollectionView }.filter(\.pullsToRefresh)
        let rowLists = nodes.values.compactMap { $0.view as? UKServerUIRowCollection }.filter(\.pullsToRefresh)
        if !collections.isEmpty || !rowLists.isEmpty, let scroll = pageScroll {
            UKScrollFit.allowsPullToRefresh(scroll)
            let refresh = scroll.refreshControl ?? UIRefreshControl()
            let identifier = UIAction.Identifier("server-ui-refresh")
            refresh.removeAction(identifiedBy: identifier, for: .valueChanged)
            refresh.addAction(UIAction(identifier: identifier) { [weak refresh] _ in
                Task {
                    for collection in collections { await collection.refresh() }
                    for list in rowLists { await list.refresh() }
                    refresh?.endRefreshing()
                }
            }, for: .valueChanged)
            scroll.refreshControl = refresh
        } else { pageScroll?.refreshControl = nil }
        layoutBindings.forEach { $0() }
        layoutBag.observe { [weak self, weak renderer] in
            guard let self, let renderer else { return }
            if self.soleScrollingCollectionID(renderer) != self.scrollerCollectionID {
                // A visibility change moved the page between "one collection" and "mixed": host it the other way, outside this observation.
                DispatchQueue.main.async { [weak self] in self?.render() }
                return
            }
            let views = roots.filter {
                if case .pinnedActions = $0.0 { return false }
                return $0.0.node.id != scrollerID && renderer.componentVisible($0.0)
            }.map(\.1)
            if self.column.views != views {
                self.column.setViews(views)
                self.body?.contentChanged(animated: false)
            }
        }
        body.contentChanged(animated: false)
        refreshChrome()
    }

    /// The id of the collection that is the page's whole body (pinned actions aside), when it is a Todo, Inventory or Recipes
    /// collection: that page hosts the collection as its scroller, so only the visible records exist as views.
    private func soleScrollingCollectionID(_ renderer: UKServerUIRenderer) -> String? {
        let body = definition.components.filter {
            if case .pinnedActions = $0 { return false }
            return true
        }
        guard body.count == 1, case .collection(let value) = body[0], UKServerUICollectionView.hostsScroller(value.template),
              renderer.componentVisible(body[0]) else { return nil }
        return value.node.id
    }

    /// Puts the body column, or the record collection's own scroller, in the page's scroller slot, and names it the page's scroll view.
    ///
    /// - Parameter collection: The collection that is the page's whole body, or nil for the column.
    private func hostScroller(_ collection: UKServerUICollectionView?) {
        guard let body else { return }
        let host = collection?.scrollerHost ?? body
        let scroll: UIScrollView = collection?.scrollerView ?? body
        if slot.subviews.first !== host {
            slot.subviews.forEach { $0.removeFromSuperview() }
            slot.addSubview(host)
            host.ukPin(to: slot)
        }
        if pageScroll !== scroll {
            pageScroll = scroll
            setPageScrollView(scroll)
        }
        if let collection {
            collection.applyPageLayout(padding: body.padding, maxWidth: body.maxWidth)
        }
    }

    private func bedroomProvider(_ sourceID: String) -> UKServerUIBedroomProvider? {
        guard let renderer else { return nil }
        if let provider = renderer.bindings.bedroom(sourceID) { return provider }
        if let draft = bedroomDrafts[sourceID] { return .draft(draft) }
        guard case .bedroom(_, let id, _) = renderer.bindings.definitions[sourceID],
              let factory = renderer.bindings.bedroomRegistry?.editors[id] else { return nil }
        if bedroomErrors[sourceID] != nil { return nil }
        do {
            let draft = try factory.open(visitID: bedroomVisitID)
            bedroomDrafts[sourceID] = draft
            bedroomOwners[sourceID] = factory.source.session
            return .draft(draft)
        } catch {
            bedroomErrors[sourceID] = "This alarm is unavailable or changed. Return to the alarm list and open it again."
            renderer.onError(.init(code: .unavailableSource, pointer: "/document/dataSources"))
            return nil
        }
    }

    private func configureCamera(_ component: D.Component, sourceID: String, entry: UKServerUINode) {
        guard let renderer, let view = entry.view as? UKServerUICameraView,
              let source = renderer.bindings.cameras[sourceID] else {
            renderer?.onError(.init(code: .unavailableSource, pointer: "/document/dataSources"))
            return
        }
        view.apply(component, source: source, presenter: { [weak self] in self }, open: { [weak self] action, view in
            guard let self else { return }
            self.renderer?.activate(action, from: self, source: view)
        }, error: { [weak renderer] in renderer?.onError($0) })
    }

}

/// One keyed native primitive and its observations, retained independently of its authored position.
@MainActor
final class UKServerUINode {
    private enum Kind: Equatable {
        case settingsControl(ServerUISettingsControl.Kind)
        case text, grid, navigationTile, actionTile, settingsLink, remote, accountHeader
        case section, row, localTabs, localControl, boundControl(ServerUICompositionDocument.BoundControl.Kind, ServerUICompositionDocument.BoundControl.Surface)
        case button, rowCollection
        case infoBox, statusPill, pagedRow
        case collection, form, recipePart, pinnedActions
        case statusChip, statusRail, roomOverviewTile, homeLightTile, weatherPanel
        case alarmPanel, stateTile, climate, roomCard, roomChip, roomSection, roomNavigationGrid
        case roomDeviceControl, deviceControl, bedroom, vacuum, cameraTile, cameraVideo, cameraControls, cameraViewer
        case bootstrapMessage, notificationBanner, overlay, stack, shape, symbol
    }

    /// The node's view, built once and kept for the node's lifetime.
    let view: UIView
    /// The observations tied to the node's lifetime.
    let bag = UKObservationBag()
    /// A grid's grouping by state, kept for the node's lifetime (`sh.grid-state-groups@1`).
    var grouping: UKServerUIGridGrouping?
    /// The views the node last placed inside itself, to detect a changed arrangement.
    var childViews: [UIView] = []
    /// Whether the node's `visibleWhen` last said it is shown; `nil` before its first answer (``ServerUIVisibility/WhenUnknown/keep``).
    var shown: Bool?
    /// The panel an authored `selectedWhen` last picked, so a rule selects once when it newly matches.
    var automaticMatch: String?
    /// What a tab container's tabs and areas and a state tile's discs last showed, so a rule that cannot be answered keeps its answer.
    var layoutMemory = UKServerUILayoutMemory()
    private let kind: Kind
    private let weatherKind: ServerUICompositionDocument.WeatherPanel.Panel?

    init(_ component: ServerUICompositionDocument.Component, surface: TileSurface = .page) {
        kind = Self.kind(component)
        if case .weatherPanel(let panel) = component { weatherKind = panel.panel } else { weatherKind = nil }
        switch component {
        case .settingsControl: view = UKServerUISettingsAtom()
        case .statusChip: view = UKStatusChipView()
        case .statusRail: view = UKChipRailView()
        case .roomOverviewTile(let tile):
            view = UKGlassTileView(model: UKGlassTileModel(title: tile.chip.node.title, symbol: tile.chip.fallback.icon.drawn, isActive: false))
        case .homeLightTile: view = UKServerUIHomeLightView()
        case .weatherPanel(let panel): view = UKServerUIWeatherPanel(panel)
        case .alarmPanel(let panel):
            view = UKAlarmPanelControl(surface: surface, modes: UKServerUISecurityViews.modes(panel),
                                      headerIdentifier: panel.node.id + ".state", modeIdentifierPrefix: panel.node.id + ".mode",
                                      failureIdentifier: panel.node.id + ".failure")
        case .stateTile(let tile):
            view = UKGlassTileView(model: UKGlassTileModel(title: tile.node.title, symbol: tile.icon.drawn,
                                                          isActive: false, isUnavailable: true, kind: .state, identifier: tile.node.id))
        case .climate: view = UKServerUIClimateControl()
        case .roomCard(let card):
            view = UKGlassTileView(model: UKGlassTileModel(title: card.node.title, symbol: card.icon.drawn,
                                                          isActive: false, kind: .state, identifier: card.node.id))
        case .roomChip: view = UKRoomChipView()
        case .roomSection: view = UKRoomSectionContent()
        case .roomNavigationGrid: view = UKServerUIRoomNavigationGrid()
        case .roomDeviceControl: view = UKServerUIRoomDeviceAtom()
        case .deviceControl: view = UKServerUIDeviceAtom()
        case .bedroom: view = UKServerUIBedroomControl()
        case .vacuum: view = UKServerUIVacuumView()
        case .accountHeader: view = UKAccountHeaderView()
        case .cameraTile, .cameraVideo, .cameraControls, .cameraViewer: view = UKServerUICameraView()
        case .notificationBanner(let banner):
            view = UKNotificationPermissionPromptView(
                copy: .init(title: banner.node.title, message: banner.message, enable: banner.enableLabel, dismiss: banner.dismissLabel),
                onEnable: {}, onDismiss: {})
        case .bootstrapMessage: view = UKServerUIBootstrapMessage()
        case .overlay: view = UKServerUIOverlayView()
        case .stack: view = UKStackView()
        case .shape: view = UKShapeView()
        case .symbol: view = UKSymbolPartView()
        case .text: view = UKServerUIText()
        case .grid: view = UKDynamicGridView()
        case .section: view = UKServerUISection()
        case .infoBox: view = UKServerUIInfoBox()
        case .statusPill(let value):
            view = UKStatusPillView(label: value.node.title, value: "", symbol: value.icon.drawn, surface: surface == .sheet ? .groupedList : .page)
        case .pagedRow: view = UKServerUIPagedRow()
        case .row: view = UKServerUIRow()
        case .localTabs: view = UKServerUILocalTabs()
        case .localControl: view = UKServerUILocalControl()
        case .boundControl(let control):
            switch (control.kind, control.surface) {
            case (.button, _): view = UKServerUIPrimaryButton()
            case (.toggle, .tile):
                view = UKGlassTileView(model: UKGlassTileModel(title: control.node.title, symbol: control.icon?.drawn ?? "power",
                                                              isActive: false, isUnavailable: true, identifier: control.node.id))
            default: view = UKServerUILocalControl()
            }
        case .button: view = UKServerUIPrimaryButton()
        case .rowCollection: view = UKServerUIRowCollection()
        case .collection: view = UKServerUICollectionView()
        case .form: view = UKServerUIFormView()
        case .recipePart: view = UKServerUIRecipePartView()
        case .pinnedActions: view = UKServerUIPinnedActions()
        case .navigationTile(let tile):
            view = UKGlassTileView(model: UKGlassTileModel(title: tile.node.title, symbol: tile.icon.drawn,
                                                          isActive: false, kind: .navigate, identifier: tile.node.id))
        case .actionTile(let tile):
            view = UKGlassTileView(model: UKGlassTileModel(title: tile.node.title, symbol: tile.icon.drawn,
                                                          isActive: false, isUnavailable: true, identifier: tile.node.id))
        case .settingsLink: view = UKServerUISettingsLink()
        case .remote: view = UKServerUIRemoteAtom()
        }
        view.accessibilityIdentifier = component.node.id
    }

    /// Whether `component` is the same kind of node, so its view can be kept across a publication.
    /// - Parameter component: The candidate component.
    func matches(_ component: ServerUICompositionDocument.Component) -> Bool {
        guard kind == Self.kind(component) else { return false }
        if case .weatherPanel(let panel) = component { return panel.panel == weatherKind }
        return true
    }

    private static func kind(_ component: ServerUICompositionDocument.Component) -> Kind {
        switch component {
        case .settingsControl(let control): .settingsControl(control.kind)
        case .climate: .climate
        case .roomDeviceControl: .roomDeviceControl
        case .deviceControl: .deviceControl
        case .bedroom: .bedroom
        case .vacuum: .vacuum
        case .notificationBanner: .notificationBanner
        case .overlay: .overlay
        case .stack: .stack
        case .shape: .shape
        case .symbol: .symbol
        case .bootstrapMessage: .bootstrapMessage
        case .text: .text
        case .grid: .grid
        case .navigationTile: .navigationTile
        case .actionTile: .actionTile
        case .section: .section
        case .infoBox: .infoBox
        case .statusPill: .statusPill
        case .pagedRow: .pagedRow
        case .row: .row
        case .localTabs: .localTabs
        case .localControl: .localControl
        case .boundControl(let control): .boundControl(control.kind, control.surface)
        case .button: .button
        case .rowCollection: .rowCollection
        case .collection: .collection
        case .form: .form
        case .recipePart: .recipePart
        case .pinnedActions: .pinnedActions
        case .statusChip: .statusChip
        case .statusRail: .statusRail
        case .roomOverviewTile: .roomOverviewTile
        case .homeLightTile: .homeLightTile
        case .weatherPanel: .weatherPanel
        case .alarmPanel: .alarmPanel
        case .stateTile: .stateTile
        case .settingsLink: .settingsLink
        case .roomCard: .roomCard
        case .roomChip: .roomChip
        case .roomSection: .roomSection
        case .roomNavigationGrid: .roomNavigationGrid
        case .remote: .remote
        case .accountHeader: .accountHeader
        case .cameraTile: .cameraTile
        case .cameraVideo: .cameraVideo
        case .cameraControls: .cameraControls
        case .cameraViewer: .cameraViewer
        }
    }
}

/// Bridges the canonical Auto Layout cell into the composition column's width-driven measurement.
@MainActor
final class UKServerUISettingsLink: UIView, UKGridMeasuring {
    /// The settings cell this link draws.
    let cell = UKSettingsStackCell(frame: .zero)

    init() {
        super.init(frame: .zero)
        addSubview(cell)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The height the node needs at `width`.
    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        cell.frame = CGRect(x: 0, y: 0, width: width, height: max(cell.bounds.height, 2_000))
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        return ceil(cell.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height)
    }

    /// Keeps the settings cell and the pending bar at the measured size.
    override func layoutSubviews() {
        super.layoutSubviews()
        cell.frame = bounds
    }
}

// MARK: - Text adapter

/// Natural Dynamic Type text with the existing pending bar; no downloaded formatter or loading animation.
@MainActor
final class UKServerUIText: UIView, UKGridMeasuring {
    private let label = UILabel.uk(.body, ink: UKDesignInk.primary)
    private let pending = UKPendingValueBar()
    /// The text style; changing it restyles the label.
    var style: UIFont.TextStyle = .body {
        didSet { restyle() }
    }
    /// Whether this is the document's `section-title` (title3, bold, a heading), not its plain `title3`.
    var isSectionTitle = false {
        didSet {
            restyle()
            accessibilityTraits = isSectionTitle ? .header : .staticText
        }
    }
    /// The weight, digits, scaled size, ink, lines, alignment and overflow over the style (`sh.text-style@1`).
    var look = ServerUITextLook() { didSet { if look != oldValue { restyle() } } }
    /// The sliding line of a ticker, present only while the look asks for one.
    private(set) var ticker: UKTickerLabel?
    /// The ink and the font the text is drawn with now, for tests of the look.
    var drawnInk: UIColor { label.textColor }
    var drawnFont: UIFont { label.font }
    var lineBreak: NSLineBreakMode { label.lineBreakMode }

    init() {
        super.init(frame: .zero)
        addSubview(label)
        addSubview(pending)
        pending.isHidden = true
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        label.isAccessibilityElement = false
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKServerUIText, _) in
            guard view.look.isDeclared else { return }
            view.restyle()
            view.ukRemeasureContainers(includingSelf: true)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows a value, or `unavailable` while it has none.
    /// - Parameters:
    ///   - value: The bound text value.
    ///   - unavailable: The text shown while the value is unavailable.
    func apply(_ value: UKServerUIValue<String>, unavailable: String) {
        switch value {
        case .ready(let text): label.text = text; pending.isHidden = true
        case .unavailable: label.text = unavailable; pending.isHidden = true
        case .loading: label.text = "Loading"; pending.isHidden = false
        }
        label.alpha = pending.isHidden ? 1 : 0
        ticker?.text = label.text ?? ""
        accessibilityLabel = label.text
        ukRemeasureContainers(includingSelf: true)
    }

    /// The height the settings cell needs at `width`.
    func gridHeight(forWidth width: CGFloat) -> CGFloat {
        if let ticker { return ceil(ticker.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height) }
        return ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }

    /// Draws the style, then the look over it.
    private func restyle() {
        let styled: UIFont = isSectionTitle ? .ukFont(.title3, weight: .bold) : UIFont.preferredFont(forTextStyle: style, compatibleWith: traitCollection)
        let base: UIFont.Weight? = isSectionTitle ? .bold : nil
        let font = UKStyledText.font(style: style, look: look, traits: traitCollection, baseWeight: base) ?? styled
        let ink = look.ink.map(UKStyledText.color) ?? ([.subheadline, .footnote].contains(style) ? UKDesignInk.secondary : UKDesignInk.primary)
        label.font = font
        label.textColor = ink
        label.numberOfLines = look.lines ?? 0
        label.lineBreakMode = look.shrinks || (look.lines ?? 0) > 0 ? .byTruncatingTail : .byWordWrapping
        label.textAlignment = UKStyledText.alignment(look.align, rightToLeft: effectiveUserInterfaceLayoutDirection == .rightToLeft)
        if look.isTicker {
            let ticker = self.ticker ?? UKTickerLabel(label.text ?? "", truncatesWhenStill: true)
            if self.ticker == nil { self.ticker = ticker; insertSubview(ticker, belowSubview: pending) }
            ticker.fontProvider = { [style, look, base] traits in UKStyledText.font(style: style, look: look, traits: traits, baseWeight: base) ?? font }
            ticker.textColor = ink
            ticker.textAlignment = label.textAlignment
            ticker.text = label.text ?? ""
            label.isHidden = true
        } else {
            ticker?.removeFromSuperview()
            ticker = nil
            label.isHidden = false
        }
        setNeedsLayout()
    }

    /// Lays out the label above its pending bar.
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        ticker?.frame = bounds
        let size = pending.sizeThatFits(bounds.size)
        pending.frame = CGRect(x: effectiveUserInterfaceLayoutDirection == .rightToLeft ? max(0, bounds.width - size.width) : 0,
                               y: max(0, (bounds.height - size.height) / 2), width: min(size.width, bounds.width), height: size.height)
    }
}

// MARK: - Measuring for a stack

extension UKServerUIText: UKStackMeasuring {
    var stackNaturalWidth: CGFloat { ceil(label.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).width) }
    var stackFillsWidth: Bool { true }
    var stackShrinks: Bool { look.shrinks }
}
#endif
