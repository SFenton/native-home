#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// Quick Links (`QuickLinksSheet`; web `GlobalQuickLinksAction`): Rooms and Security System open inside the sheet with Back; the other tiles
/// close it and open their page. The header button itself is the shell's (`UKShellHeaderItems`).
@MainActor
enum UKQuickLinks {
    /// The sheet as a navigation controller the shell presents full height (`hassSheet(.page, height: .full)`).
    /// - Parameters:
    ///   - choose: Called with the page a tile chose; the presenter pushes it once the sheet has gone.
    ///   - presenter: Set when the sheet is not the shell's header sheet (a gallery): it closes itself.
    static func make(context: UKContext, choose: @escaping (HomeRoute) -> Void, onDismissed: (() -> Void)? = nil) -> UKHassModalController {
        let sheetContext = context.with { $0.surface = .sheet }
        let box = ModalBox()
        var options = UKHassModalOptions(title: nil, fitKey: "QuickLinksSheet")
        options.closeIdentifier = "quickLinks.close"
        options.width = .page
        // Only as tall as the page on top (`hassSheet(.page, height: .fittedToTopPage)`).
        options.height = .fittedToTopPage
        options.onDismissed = onDismissed
        // Inside the shell the navigator owns the sheet: clearing it dismisses and runs the shell's dismissal work.
        options.onClose = { [weak box] in
            if let navigator = context.navigator, let section = context.section {
                navigator.sheet(in: section).wrappedValue = nil
            } else if let modal = box?.modal {
                modal.dismiss(animated: true) { onDismissed?() }
            }
        }
        let go: (HomeRoute) -> Void = { route in
            // One choice per opening: a second tap on a tile while the sheet is leaving does not choose (or close) again.
            guard !box.hasChosen else { return }
            box.hasChosen = true
            box.modal?.view.isUserInteractionEnabled = false
            choose(route)
            box.modal?.close()
        }
        let root = UKQuickLinksRootPage(context: sheetContext) { [weak box] link in
            switch link.action {
            case let .detail(detail):
                guard let modal = box?.modal else { return }
                // Security System is the Security lane's alarm card (`SecurityControls`); without a caller it shows the state alone.
                if detail == .securitySystem, let caller = sheetContext.caller {
                    let page = UKSecuritySystemViewController(context: sheetContext, caller: caller)
                    page.navigationItem.rightBarButtonItem = UKSheetItems.close(identifier: "quickLinks.close") { box?.modal?.close() }
                    modal.push(page)
                    return
                }
                modal.push(UKQuickLinksDetailPage(detail: detail, context: sheetContext, close: { box?.modal?.close() }, openRoom: { go(.room($0)) }))
            case let .navigate(path):
                if let route = HomeRoute(path: path) { go(route) }
            }
        }
        root.view.accessibilityIdentifier = "quickLinks.sheet"
        let modal = UKHassModalController(root: root, options: options)
        box.modal = modal
        #if DEBUG
        // `FENTON_DEBUG_QL_ROOMS=<seconds>`: pushes Rooms that long after the sheet is made (then `FENTON_DEBUG_QL_BACK` seconds later goes
        // back), so a host script can capture the sheet's resize without a tap. A probe, never in a release build.
        if let delay = ProcessInfo.processInfo.environment["FENTON_DEBUG_QL_ROOMS"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak box] in
                guard let modal = box?.modal else { return }
                modal.push(UKQuickLinksDetailPage(detail: .rooms, context: sheetContext, close: { box?.modal?.close() }, openRoom: { go(.room($0)) }))
                if let back = ProcessInfo.processInfo.environment["FENTON_DEBUG_QL_BACK"].flatMap(Double.init) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + back) { [weak box] in box?.modal?.popViewController(animated: true) }
                }
            }
        }
        #endif
        return modal
    }

    @MainActor
    private final class ModalBox {
        weak var modal: UKHassModalController?
        var hasChosen = false
    }
}

/// The Quick Links page body: its tiles, titled for the stack it sits in (`QuickLinksRoot`).
@MainActor
final class UKQuickLinksRootPage: UKRoomsSheetPage {
    private let onNavigate: (QuickLink) -> Void

    init(context: UKContext, onNavigate: @escaping (QuickLink) -> Void) {
        self.onNavigate = onNavigate
        super.init(title: QuickLinks.title, maxWidth: 560, context: context)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let store = context.store
        var environment = UKTileEnvironment(context: context)
        // The arrangement is the Rooms grid's, glyph top-leading and text on the bottom (owner, 2026-10-16).
        environment.layout = .anchoredBottom
        environment.titleLines = 2
        let grid = UKRoomsGrid(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true)
        grid.avoidsHinge = false
        grid.setItems(QuickLinks.visible { store.entity($0).state?.state }.map { link in
            UKGridItem(tile(link, store: store, environment: environment))
        })
        setContent([grid])
    }

    /// One Quick Links tile (`QuickLinkTile`): a solid colour per link with a filled white glyph and white text; Security System follows the
    /// alarm mode.
    ///
    /// Every tile is a navigation tile with the chevron (owner, 2026-10-27). Security System also carries one disc left of it
    /// (`AlarmModeActions`, audit item 17): **Arm Home** while disarmed, **Disarm** (confirmed with today's alert) while armed, an arc
    /// spinner while the panel is disarming. A tap on the disc goes through `OptimisticActions` like every call, so a rejected call shows
    /// "Didn't Respond". While screenshots are redacted, or without a caller, the disc is not drawn: its verb and glyph would give the
    /// alarm mode away.
    private func tile(_ link: QuickLink, store: EntityStore, environment: UKTileEnvironment) -> UIView {
        let caller = context.caller
        var actions: OptimisticActions?
        func specs() -> [TileActionSpec] {
            QuickLinkTile.specs(link, alarm: store.entity(QuickLinks.securityEntityId).state, canSend: caller != nil, isRedacting: ScreenshotPrivacy.isRedacting)
        }
        func model() -> UKGlassTileModel {
            let state = link.entityId.flatMap { store.entity($0).state }
            let security = link.id == "security-system" ? QuickLinks.securityAppearance(state?.state) : nil
            let subtitle: String?
            switch link.status {
            case .entityState: subtitle = ScreenshotPrivacy.isRedacting ? "Hidden" : RoomFormat.compact(state)
            case .allFood: subtitle = QuickLinks.allFoodSubtitle { store.entity($0).state?.state }
            case nil: subtitle = nil
            }
            let specs = specs()
            let failed = actions?.isFailed(QuickLinks.securityEntityId) ?? false
            // A navigation tile is never "on": a solid fill with a filled white glyph, like a room (owner, 2026-10-16).
            var model = UKGlassTileModel(title: link.title,
                                    subtitle: failed ? "Didn't Respond" : subtitle,
                                    // Redacted screenshots keep the plain shield, so the glyph can't give the alarm mode away.
                                    symbol: SymbolMap.symbol(for: ScreenshotPrivacy.isRedacting ? link.icon : security?.icon ?? link.icon),
                                    family: .neutral, fillRGB: QuickLinkTile.fill(link, alarmState: state?.state), isActive: false, isError: failed,
                                    behavior: .navigate, actions: specs.items, identifier: QuickLinkTile.identifier(link))
            model.stateCandidates = specs.isEmpty ? [] : AlarmModeActions().stateTextCandidates + ["Didn't Respond"]
            // On the body only: a hint set from outside would also be read on the Security System disc.
            let isDetail: Bool = { if case .detail = link.action { return true } else { return false } }()
            model.bodyHint = isDetail ? "Opens \(link.title) in Quick Links" : "Opens the \(link.title) page"
            return model
        }
        let view = UKGlassTileView(model: model(), environment: environment)
        UKRoomsBind.tile(view, bag: bag, environment: environment, action: { [onNavigate] in onNavigate(link) }, perform: { id in
            guard let spec = specs().first(where: { $0.id == id }), let caller else { return }
            let run = actions ?? OptimisticActions(store: store, rules: [QuickLinks.securityEntityId: .liveChange], caller: caller)
            actions = run
            run.perform(spec, failing: QuickLinks.securityEntityId)
        }, model: model)
        return view
    }
}

/// Rooms or Security System, opened from a Quick Links tile (`QuickLinksDetailView`).
@MainActor
final class UKQuickLinksDetailPage: UKRoomsSheetPage {
    private let detail: QuickLink.Detail
    private let openRoom: (String) -> Void

    init(detail: QuickLink.Detail, context: UKContext, close: @escaping () -> Void, openRoom: @escaping (String) -> Void) {
        self.detail = detail
        self.openRoom = openRoom
        super.init(title: detail == .rooms ? "Rooms" : "Security System", maxWidth: detail == .rooms ? .greatestFiniteMagnitude : 720, context: context)
        // Close at every depth, so a pushed page is not left by Back or a swipe alone (HIG: Sheets; owner, 2026-10-24, `sheet-stacking-close`).
        navigationItem.rightBarButtonItem = UKSheetItems.close(identifier: "quickLinks.close", action: close)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        switch detail {
        case .rooms:
            setContent([UKRoomNavigationGrid(context: context, bag: bag, onOpen: openRoom)])
        case .securitySystem:
            // TODO(uikit-port): Security lane's alarm controls (`SecurityControls`); the state alone until they land.
            let state = context.store.entity(QuickLinks.securityEntityId).state
            setContent([UKRoomsMeasured(UKStateMessageView(symbol: SymbolMap.symbol(for: QuickLinks.securityAppearance(state?.state).icon), title: "Security System",
                                                           message: ScreenshotPrivacy.isRedacting ? "Hidden" : RoomFormat.compact(state)))])
        }
    }
}

/// Every room as a coloured tile (`RoomNavigationGrid`), most-visited first. Opening a room counts the visit. The ranking is taken once, so a
/// counter that changes never reorders the tiles under the reader.
@MainActor
final class UKRoomNavigationGrid: UKRoomsGrid {
    init(context: UKContext, bag: UKObservationBag, onOpen: @escaping (String) -> Void) {
        super.init(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true)
        avoidsHinge = false
        var environment = UKTileEnvironment(context: context)
        environment.layout = .anchoredBottom
        environment.titleLines = 2
        let store = context.store
        let caller = context.caller
        let order = RoomNavigation.ranked { store.entity($0).state?.state }
        setItems(order.map { item in
            // A solid fill per room with a filled white glyph (direction G, Colour: Room tiles; owner, 2026-10-16).
            let model = UKGlassTileModel(title: item.title, symbol: SymbolMap.symbol(for: item.icon), family: .neutral,
                                         fillRGB: RoomPalette.fill(at: RoomNavigation.paletteIndex(forPath: item.path)), isActive: false, kind: .navigate, identifier: "rooms.\(item.path)")
            let tile = UKGlassTileView(model: model, environment: environment) {
                if let caller { RoomController.recordVisit(item, caller: caller) }
                onOpen(item.path)
            }
            tile.accessibilityHint = "Opens the \(item.title) page"
            return UKGridItem(tile)
        })
        accessibilityContainerType = .semanticGroup
        accessibilityLabel = "Rooms"
    }
}
#endif
