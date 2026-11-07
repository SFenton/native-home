#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The vacuum sheet (`VacuumSheet`; pattern: `.agents/patterns/vacuum-sheet.md`).
///
/// Map and status lead, the section's panel follows, and the sections sit in the bottom glass section bar (`UKModalTabBar`, symbols
/// only at five sections). Where a split is allowed (iPad and unfolded iPhone Duo in landscape) and the sheet is wide enough, the map
/// and status take a leading column and the tabs scroll in the trailing one; everywhere else it is one scrolling column. The area
/// editor and the cleaning report push onto the sheet's navigation stack.
@MainActor
final class UKVacuumSheetViewController: UKPageViewController {
    let controller: VacuumController
    let mapState: VacuumMapState
    let state: UKVacuumSheetState

    private let server: HassServer?
    private let catalog: (any HassServiceCatalog)?
    private let fixedServices: Set<String>?
    private let debugLine: UIView?
    private var mapPanel: UKVacuumMapPanel!
    private var swapView: UKSmoothContentSwapView<VacuumSheetContent.Key>!
    private let layoutRoot = UIView()
    private var twoColumns: Bool?
    private var tabScroll: UIScrollView?
    private var scrolls: [UIScrollView] = []
    private let barHost = UKVacuumBarHost()
    private let barSlot = UIView()
    private var tabBar: UIView?
    private var typedBar: UKModalTabBar<VacuumTab>?
    private var shownTabs: [VacuumTab] = []
    private var lastTab: VacuumTab
    private var pinnedBar: UKPagePinnedBar!

    /// Creates the sheet on an existing controller.
    /// - Parameters:
    ///   - loader: Supplies the map; a gallery loader holds a fixture map and no `server`.
    ///   - server: Resolves the map camera's picture; nil keeps the loader's map.
    ///   - catalog: Reads Home Assistant's services; `services` sets them directly instead.
    ///   - debugLine: A gallery's debug line under the section bar.
    init(controller: VacuumController, loader: ValetudoMapLoader, server: HassServer?, catalog: (any HassServiceCatalog)?, services: Set<String>?,
         initialTab: VacuumTab = .controls, context: UKContext, debugLine: UIView? = nil) {
        self.controller = controller
        self.server = server
        self.catalog = catalog
        fixedServices = services
        self.debugLine = debugLine
        mapState = VacuumMapState(vacuum: controller.vacuum, loader: loader)
        state = UKVacuumSheetState(tab: initialTab, controller: controller)
        lastTab = state.displayed.tab
        super.init(context: context.with { $0.surface = .sheet }, title: nil)
        title = "\(controller.vacuum.title) Robot Vacuum"
        navigationItem.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The tiles in the sheet draw on the sheet's surface.
    private var tileEnvironment: UKTileEnvironment { UKTileEnvironment(context: context) }

    private var pictureURL: URL? {
        guard let server else { return nil }
        return ValetudoMapLoader.pictureURL(controller.store.entity(controller.vacuum.mapCameraEntityId).state, server: server)
    }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        mapPanel = UKVacuumMapPanel(controller: controller, mapState: mapState, state: state, environment: tileEnvironment, pictureURL: { [weak self] in self?.pictureURL }) { [weak self] contract in
            self?.openReport(contract)
        }
        swapView = UKSmoothContentSwapView(initial: state.displayed) { [weak self] key in
            guard let self else { return UIView() }
            self.state.displayed = key
            self.mapPanel.frameView.setMode(key.mode)
            return self.makePanel(key)
        }
        swapView.timing.fadeOut = 0.13
        swapView.timing.fadeIn = 0.17
        swapView.animatesLayout = { $0.mode != $1.mode }
        swapView.didSwap = { [weak self] key in self?.didSwap(key) }
        swapView.accessibilityIdentifier = "vacuum.tabContent"
        layoutRoot.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(layoutRoot)
        NSLayoutConstraint.activate([
            layoutRoot.topAnchor.constraint(equalTo: contentView.topAnchor), layoutRoot.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            layoutRoot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor), layoutRoot.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
        buildBar()
        bag.observe { [weak self] in self?.sync() }
        Task { await loadServices() }
    }

    private func loadServices() async {
        if let fixedServices { controller.services = fixedServices; return }
        guard let catalog, controller.services == nil else { return }
        controller.services = try? await catalog.serviceNames()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyColumns()
        pinnedBar?.layoutChanged()
    }

    // MARK: Chrome

    private func buildBar() {
        barHost.axis = .vertical
        barHost.alignment = .fill
        barHost.translatesAutoresizingMaskIntoConstraints = false
        barHost.addArrangedSubview(barSlot)
        if let debugLine {
            let backing = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
            backing.contentView.addSubview(debugLine)
            debugLine.ukPin(to: backing.contentView, insets: UIEdgeInsets(top: 4, left: HassTokens.Spacing.l, bottom: 4, right: HassTokens.Spacing.l))
            barHost.addArrangedSubview(backing)
        }
        // The standard pinned bar (modal-sheet, "Modal standard"): the content scrolls under it, with the soft bottom edge, and clears it.
        pinnedBar = UKPagePinnedBar(bar: barHost)
        pinnedBar.install(in: self)
    }

    /// Follows the controller: the target tab, the section bar and the subtitle.
    private func sync() {
        let target = VacuumSheetContent.key(requested: state.requestedTab, controller: controller)
        if target.tab != state.requestedTab { state.requestedTab = target.tab }
        swapView.show(target)
        let tabs = controller.tabs(in: state.displayed.mode)
        let selection = state.selection(in: tabs)
        if tabs != shownTabs || typedBar == nil {
            shownTabs = tabs
            tabBar?.removeFromSuperview()
            let bar = UKModalTabBar(tabs: tabs, label: "\(controller.vacuum.title) sections", title: { $0.title },
                                    symbol: { VacuumTabSymbols.symbol(for: $0) }, selection: selection, identifier: "vacuum.tabs") { [state] in
                state.requestedTab = $0
            }
            let wrapped = bar.inset()
            barSlot.addSubview(wrapped)
            wrapped.ukPin(to: barSlot)
            tabBar = wrapped
            barHost.passThrough = [barSlot, wrapped]
            typedBar = bar
        } else {
            typedBar?.selection = selection
        }
        UKSheetSubtitle.apply(VacuumSheetChrome.subtitle(state: controller.statusState, battery: controller.batteryLabel), to: navigationItem)
    }

    // MARK: Panels

    private func makePanel(_ key: VacuumSheetContent.Key) -> UIView {
        switch key.tab {
        case .controls:
            return UKVacuumControlsTab(controller: controller, environment: tileEnvironment, mapState: mapState, mode: key.mode,
                                       onOpenRooms: { [weak self] in self?.openRooms() }, onEditArea: { [weak self] in self?.openAreaEditor() })
        case .zones: return ukVacuumRoomsTab(controller: controller, environment: tileEnvironment)
        case .autoClean: return ukVacuumAutoCleanTab(controller: controller, environment: tileEnvironment)
        case .more: return UKVacuumActionsTab(controller: controller, environment: tileEnvironment)
        case .info: return UKVacuumInfoTab(controller: controller, environment: tileEnvironment)
        }
    }

    private func openRooms() {
        if controller.tabs.contains(.zones) { state.requestedTab = .zones }
    }

    private func openAreaEditor() {
        (navigationController as? UKHassModalController)?.push(UKVacuumAreaEditorViewController(controller: controller, mapState: mapState))
    }

    private func openReport(_ contract: VacuumOutcomeContract) {
        (navigationController as? UKHassModalController)?.push(UKVacuumOutcomeDetailViewController(vacuum: controller.vacuum, contract: contract))
    }

    /// A new section brings the tab control back to the top of the column, but only when the panel's top has scrolled under the bar or
    /// off the top, so a new section would open mid-content.
    private func didSwap(_ key: VacuumSheetContent.Key) {
        defer { lastTab = key.tab }
        guard key.tab != lastTab, let scroll = tabScroll else { return }
        let top = swapView.convert(CGPoint.zero, to: scroll).y
        let panelTop = top - scroll.contentOffset.y
        if panelTop < scroll.adjustedContentInset.top {
            scroll.setContentOffset(CGPoint(x: 0, y: top - scroll.adjustedContentInset.top), animated: false)
        }
    }

    // MARK: Columns

    private func applyColumns() {
        let window = view.window
        let windowSize = window?.bounds.size ?? view.bounds.size
        let regular = window?.traitCollection.horizontalSizeClass == .regular
        let two = MediaRemoteLayout.usesTwoColumns(window: windowSize, isRegularWidth: regular, container: contentView.bounds.size)
        guard two != twoColumns else { return }
        twoColumns = two
        layoutRoot.subviews.forEach { $0.removeFromSuperview() }
        mapPanel.removeFromSuperview()
        swapView.removeFromSuperview()
        scrolls = []
        layoutRoot.accessibilityIdentifier = two ? "vacuum.layout.twoColumn" : "vacuum.layout.singleColumn"
        if two {
            // The map ends at the hinge and the tabs start after it on the unfolded Duo, else halves.
            let left = column([mapPanel], width: nil)
            let right = column([swapView], width: nil)
            let panes = UKHingedPanes(leading: left, trailing: right, shell: context.shell)
            layoutRoot.addSubview(panes)
            panes.ukPin(to: layoutRoot)
            scrolls = [left, right]
            tabScroll = right
        } else {
            let scroll = column([mapPanel, swapView], width: 640)
            layoutRoot.addSubview(scroll)
            scroll.ukPin(to: layoutRoot)
            scrolls = [scroll]
            tabScroll = scroll
        }
        // The header fade, scroll to top and the bar's soft edge follow the tabs column; both columns scroll under the header and the bar.
        for scroll in scrolls {
            scroll.backgroundColor = .clear
            UKScrollFit.apply(to: scroll)
            UKHeaderEdgeFade.applySoftEdge(to: scroll)
        }
        setPageScrollView(tabScroll)
        pinnedBar.follow(tabScroll)
        view.setNeedsLayout()
    }

    /// A scroll view holding `views` in a padded column, no wider than `width` when given and centred.
    private func column(_ views: [UIView], width: CGFloat?) -> UIScrollView {
        let scroll = UKVacuumScrollView()
        scroll.alwaysBounceVertical = false
        let stack = ukVStack(views, spacing: HassTokens.Spacing.xl)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        let fill = stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -2 * HassTokens.Spacing.l)
        fill.priority = UILayoutPriority(999)
        var constraints = [
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: HassTokens.Spacing.l),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -HassTokens.Spacing.l),
            stack.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor), fill,
        ]
        if let width { constraints.append(stack.widthAnchor.constraint(lessThanOrEqualToConstant: width)) }
        NSLayoutConstraint.activate(constraints)
        return scroll
    }
}

/// The section bar's host: only the bar itself takes touches, so a drag in the gaps around it scrolls the sheet.
final class UKVacuumBarHost: UIStackView {
    var passThrough: [UIView] = []

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if let hit, hit === self || passThrough.contains(where: { $0 === hit }) { return nil }
        return hit
    }
}

/// A scroll view that scrolls even when a drag starts on a control: a segmented control would otherwise keep the touch (SwiftUI's
/// `ScrollView` scrolls over a picker).
final class UKVacuumScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}

/// Presents vacuum sheets.
@MainActor
enum UKVacuumSheet {
    /// The sheet as a modal: full height, page width on iPad, titled "<vacuum> Robot Vacuum".
    static func modal(for sheet: UKVacuumSheetViewController, onDismissed: (() -> Void)? = nil) -> UKHassModalController {
        var options = UKHassModalOptions(title: sheet.title)
        options.width = .page
        options.height = .full
        options.onDismissed = onDismissed
        return UKHassModalController(root: sheet, options: options)
    }
}
#endif
