#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Group detail

/// A room's lights, temperatures and vents, presence sensors or doors and windows (`RoomGroupDetail`): shared by the overview detail
/// pages and the room pages' group sheets. Every run of tiles is one equal-height grid.
@MainActor
enum UKRoomsGroupDetail {
    static func make(kind: RoomOverviewKind, group: RoomGroup, showsHeadings: Bool = true, viewer: UKRoomsViewer, environment: UKTileEnvironment,
                     bag: UKObservationBag, read: @escaping @MainActor (String) -> EntityState?,
                     send: @escaping (LightControl.Command) -> Void) -> UIView {
        let sections = RoomOverview.detailSections(kind, group, showsHeadings: showsHeadings)
        let column = UKColumnView(spacing: HassTokens.Spacing.m)
        var views: [UIView] = []
        if kind == .lights {
            // "Lights", then the whole room at once, then each light (web `RoomLightDetailHeader`).
            if let title = sections.first?.title { views.append(UKPageSectionHeaderView(title, inSheet: true)) }
            if let groupLight = RoomOverview.groupLightEntityId(group) {
                views.append(UKRoomsBind.lightTile(title: RoomOverview.detailTitle(kind, group), entityId: groupLight,
                                                   identifier: "room.lightGroup.\(groupLight)", bag: bag, environment: environment,
                                                   read: { read(groupLight) }, send: send))
            }
        }
        let grid = UKRoomsGrid(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true)
        grid.avoidsHinge = false
        var items: [UKGridItem] = []
        for section in sections {
            if kind != .lights, let title = section.title { items.append(UKGridItem(UKPageSectionHeaderView(title, inSheet: true), isHeader: true)) }
            for item in section.items {
                items.append(UKGridItem(tile(kind: kind, item: item, viewer: viewer, environment: environment, bag: bag, read: read, send: send)))
            }
        }
        grid.setItems(items)
        views.append(grid)
        column.setViews(views)
        return column
    }

    private static func tile(kind: RoomOverviewKind, item: RoomGroupItem, viewer: UKRoomsViewer, environment: UKTileEnvironment,
                             bag: UKObservationBag, read: @escaping @MainActor (String) -> EntityState?,
                             send: @escaping (LightControl.Command) -> Void) -> UIView {
        let id = item.entityId
        switch kind {
        case .lights:
            return UKRoomsBind.lightTile(title: item.title(for: viewer.resident), entityId: id, identifier: "room.light.\(id)", bag: bag,
                                         environment: environment, read: { read(id) }, send: send)
        case .climate:
            let vent = id.hasPrefix("cover.")
            return sensor(item, symbol: vent ? "fan" : "thermometer.medium", family: vent ? .vents : .climate, environment: environment, bag: bag,
                          subtitle: { RoomOverview.climateText(read(id)) }, active: { vent && ClimateLogic.isVentOpen(read(id)) }, read: read)
        case .occupancy:
            return sensor(item, symbol: nil, family: .occupancy, environment: environment, bag: bag, redacts: true,
                          subtitle: { RoomFormat.occupancy(read(id)) }, active: { RoomFormat.isOccupied(read(id)) }, read: read,
                          dynamicSymbol: { SymbolMap.symbol(for: RoomFormat.isOccupied(read(id)) ? "mdi:motion-sensor" : "mdi:motion-sensor-off") })
        case .contacts:
            return sensor(item, symbol: nil, family: .contact, environment: environment, bag: bag,
                          subtitle: { RoomFormat.contactTileSubtitle(read(id)) }, active: { RoomFormat.isOpen(read(id)) }, read: read,
                          dynamicSymbol: { RoomOverviewStyle.contactSymbol(window: RoomFormat.isWindow(item), open: RoomFormat.isOpen(read(id))) })
        case .airQuality:
            return UIView()
        }
    }

    /// A read-only sensor tile (web `source-row` cards): filled with its family colour while active, else dark with the family glyph.
    private static func sensor(_ item: RoomGroupItem, symbol: String?, family: ColorFamily, environment: UKTileEnvironment, bag: UKObservationBag,
                               redacts: Bool = false, subtitle: @escaping @MainActor () -> String, active: @escaping @MainActor () -> Bool,
                               read: @escaping @MainActor (String) -> EntityState?, dynamicSymbol: (@MainActor () -> String)? = nil) -> UIView {
        func model() -> UKGlassTileModel {
            let redact = redacts && ScreenshotPrivacy.isRedacting
            return UKGlassTileModel(title: item.title, subtitle: redact ? "Hidden" : subtitle(), symbol: symbol ?? dynamicSymbol?() ?? "circle",
                                    family: family, isActive: active() && !redact, isUnavailable: RoomFormat.isUnavailable(read(item.entityId)),
                                    kind: .state, identifier: "room.entity.\(item.entityId)",
                                    spokenValue: family == .contact ? RoomFormat.contact(read(item.entityId)) : nil)
        }
        return UKRoomsBind.readOnly(bag: bag, environment: environment, model: model)
    }
}

// MARK: - Entity grid

/// A grid of read-only entity tiles (`RoomEntityGrid`), in the card's colour family.
@MainActor
enum UKRoomsEntityGrid {
    struct Item {
        var title: String
        var entityId: String
        var icon: String
    }

    static func make(title: String?, items: [Item], read: @escaping @MainActor (String) -> EntityState?, format: @escaping (EntityState?) -> String,
                     isActive: @escaping (EntityState?) -> Bool, family: ColorFamily, environment: UKTileEnvironment, bag: UKObservationBag) -> UIView {
        let column = UKColumnView(spacing: HassTokens.Spacing.m)
        let grid = UKRoomsGrid(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true)
        grid.avoidsHinge = false
        grid.setItems(items.map { item in
            let model: @MainActor () -> UKGlassTileModel = {
                let entity = read(item.entityId)
                let redact = ScreenshotPrivacy.isRedacting && family == .occupancy
                return UKGlassTileModel(title: item.title, subtitle: redact ? "Hidden" : format(entity), symbol: SymbolMap.symbol(for: item.icon), family: family,
                                        isActive: !redact && isActive(entity), isUnavailable: RoomFormat.isUnavailable(entity), kind: .state,
                                        identifier: "room.entity.\(item.entityId)")
            }
            return UKGridItem(UKRoomsBind.readOnly(bag: bag, environment: environment, model: model))
        })
        var views: [UIView] = []
        if let title { views.append(UKPageSectionHeaderView(title)) }
        views.append(grid)
        column.setViews(views)
        return column
    }
}

// MARK: - Overview grid (all contacts)

/// Every room's doors and windows, each room pushing its sensors (`RoomOverviewGrid`).
@MainActor
enum UKRoomsOverviewGrid {
    static func make(kind: RoomOverviewKind, store: EntityStore, environment: UKTileEnvironment, bag: UKObservationBag,
                     select: @escaping (RoomGroup) -> Void) -> UIView {
        let grid = UKRoomsGrid(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true)
        grid.avoidsHinge = false
        let read: RoomOverview.Read = { store.entity($0).state }
        var items: [UKGridItem] = []
        let sections: [RoomOverviewSection] = ScreenshotPrivacy.isRedacting && kind == .occupancy
            ? [RoomOverviewSection(title: "Rooms", groups: RoomOverview.groups(kind))] : RoomOverview.sections(kind, read: read)
        for section in sections {
            let header = UKPageSectionHeaderView(section.title, inSheet: true)
            header.accessibilityIdentifier = "overview.\(kind.rawValue).section.\(section.title)"
            items.append(UKGridItem(header, isHeader: true))
            for group in section.groups {
                items.append(UKGridItem(tile(kind: kind, group: group, read: read, environment: environment, bag: bag) { select(group) }))
            }
        }
        grid.setItems(items)
        return grid
    }

    private static func tile(kind: RoomOverviewKind, group: RoomGroup, read: @escaping RoomOverview.Read, environment: UKTileEnvironment,
                             bag: UKObservationBag, action: @escaping () -> Void) -> UIView {
        func model() -> UKGlassTileModel {
            let active = RoomOverview.isActive(kind, group, read: read)
            let redact = ScreenshotPrivacy.isRedacting && kind == .occupancy
            let symbol: String
            switch kind {
            case .lights: symbol = group.items.count > 1 ? "lightbulb.2" : "lightbulb"
            case .climate: symbol = SymbolMap.symbol(for: RoomOverview.roomIcon(group.room) ?? "mdi:thermometer")
            case .occupancy: symbol = SymbolMap.symbol(for: active && !redact ? "mdi:motion-sensor" : "mdi:motion-sensor-off")
            case .contacts: symbol = RoomOverviewStyle.contactSymbol(window: RoomOverview.isWindowGroup(group), open: active)
            case .airQuality: symbol = SymbolMap.symbol(for: "mdi:blur")
            }
            var model = UKGlassTileModel(title: group.room, subtitle: redact ? "Hidden" : RoomOverview.tileSubtitle(kind, group, read: read), symbol: symbol,
                                         family: RoomOverviewStyle.family(kind), isActive: RoomOverviewStyle.isFilled(kind, active: active && !redact),
                                         kind: .navigate, identifier: "overview.\(kind.rawValue).room.\(group.room)")
            model.spokenValue = redact ? "Hidden" : RoomOverview.spokenSubtitle(kind, group, read: read)
            return model
        }
        let view = UKGlassTileView(model: model(), environment: environment)
        view.accessibilityHint = "Opens \(RoomOverview.detailTitle(kind, group))"
        UKRoomsBind.tile(view, bag: bag, environment: environment, action: action, model: model)
        return view
    }
}

// MARK: - Sheet pages

/// A sheet page: a scroll view around a column up to `maxWidth` wide with the page padding (the `ScrollView` + `.padding(l)` +
/// `.frame(maxWidth:)` every room sheet uses). Names its scroller for the sheet-fit measurement.
@MainActor
class UKRoomsSheetPage: UKPageViewController, UKSheetFitting {
    private let column = UKColumnView(spacing: HassTokens.Spacing.l)
    private var scroll: UKPageScrollView!
    private let maxWidth: CGFloat

    init(title: String?, maxWidth: CGFloat, context: UKContext = .sheetPlaceholder) {
        self.maxWidth = maxWidth
        super.init(context: context.with { $0.surface = .sheet }, title: nil)
        navigationItem.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var sheetFitScrollView: UIScrollView? { scroll }

    /// The views of the column, top to bottom.
    func setContent(_ views: [UIView]) {
        column.setViews(views)
        scroll?.contentChanged(animated: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        scroll = UKPageScrollView(content: column, maxWidth: maxWidth, padding: UIEdgeInsets(top: HassTokens.Spacing.l, left: HassTokens.Spacing.l,
                                                                                            bottom: HassTokens.Spacing.l, right: HassTokens.Spacing.l))
        install(scrollView: scroll)
    }
}

/// A secondary line of a sheet (`.font(.subheadline)` in the secondary ink).
@MainActor
func ukRoomsSecondaryLabel(_ text: String, style: UIFont.TextStyle = .subheadline, identifier: String) -> UILabel {
    let label = UILabel.uk(style, ink: UKDesignInk.secondary)
    label.text = text
    label.numberOfLines = 0
    label.accessibilityIdentifier = identifier
    return label
}

/// The sheet a room card opens (`RoomCardSheet`).
@MainActor
final class UKRoomCardSheetPage: UKRoomsSheetPage {
    private let controller: RoomController
    private let card: RoomCard
    private let viewer: UKRoomsViewer

    /// The modal for a card, as `RoomCardSheet(...).hassSheet(.page, height: .full)` presents it.
    static func make(controller: RoomController, card: RoomCard, viewer: UKRoomsViewer, context: UKContext,
                     onDismissed: (() -> Void)? = nil) -> UKHassModalController {
        let page = UKRoomCardSheetPage(controller: controller, card: card, viewer: viewer, context: context)
        var options = UKHassModalOptions(title: controller.sheetTitle(for: card), fitKey: "RoomPageContent.cardSheet")
        options.width = .page
        options.height = .full
        options.onDismissed = onDismissed
        return UKHassModalController(root: page, options: options)
    }

    init(controller: RoomController, card: RoomCard, viewer: UKRoomsViewer, context: UKContext) {
        self.controller = controller
        self.card = card
        self.viewer = viewer
        super.init(title: controller.sheetTitle(for: card), maxWidth: 720, context: context)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "room.sheet.\(card.sheet ?? card.title)"
        var views: [UIView] = []
        if let subtitle = controller.sheetSubtitle(for: card) {
            views.append(ukRoomsSecondaryLabel(subtitle, identifier: "room.sheet.subtitle"))
        }
        views.append(body(controller.sheet(for: card)))
        setContent(views)
    }

    private var environment: UKTileEnvironment { UKTileEnvironment(context: context) }

    private func body(_ content: RoomSheetContent) -> UIView {
        let controller = self.controller
        switch content {
        case let .lights(group): return groupDetail(.lights, group)
        case let .climate(group): return groupDetail(.climate, group)
        case let .occupancy(group): return groupDetail(.occupancy, group)
        case let .contacts(group): return groupDetail(.contacts, group)
        case .allContacts:
            return UKRoomsOverviewGrid.make(kind: .contacts, store: controller.store, environment: environment, bag: bag) { [weak self] group in
                self?.pushGroup(group)
            }
        case let .items(items):
            // A vents card draws the Vents face with the one rule Advanced Controls uses.
            let isVent = card.kind == .vent
            return UKRoomsEntityGrid.make(
                title: nil, items: items.map { .init(title: $0.title, entityId: $0.entityId, icon: $0.icon) }, read: { controller.entity($0) },
                format: { isVent ? ClimateLogic.ventSubtitle($0) : RoomFormat.compact($0) },
                isActive: { isVent ? ClimateLogic.isVentOpen($0) : RoomFormat.isActive($0) },
                family: RoomTileFace.family(card.kind, icon: card.icon), environment: environment, bag: bag)
        case .device:
            return deviceFallback()
        case .mediaRemote, .fallback:
            return UKRoomsMeasured(UKStateMessageView(symbol: SymbolMap.symbol(for: card.icon), title: card.title,
                                                      message: "\(card.title) has no controls in the app yet. Use Home Assistant to change it."))
        }
    }

    private func groupDetail(_ kind: RoomOverviewKind, _ group: RoomGroup) -> UIView {
        let controller = self.controller
        return UKRoomsGroupDetail.make(kind: kind, group: group, showsHeadings: false, viewer: viewer, environment: environment, bag: bag,
                                       read: { controller.entity($0) }, send: { controller.send($0) })
    }

    /// Generic tiles for a device sheet whose lane has not landed: the card's entities, read-only.
    private func deviceFallback() -> UIView {
        let controller = self.controller
        let card = self.card
        let grid = UKRoomsEntityGrid.make(
            title: nil,
            items: controller.fallbackEntityIds(for: card).map { id in
                .init(title: RoomDeviceFallback.title(friendlyName: controller.entity(id)?.friendlyName, entityId: id), entityId: id, icon: card.icon)
            }, read: { controller.entity($0) }, format: RoomFormat.withUnit, isActive: { !RoomFormat.isUnavailable($0) },
            family: RoomTileFace.family(card.kind, icon: card.icon), environment: environment, bag: bag)
        let note = UILabel.uk(.footnote, ink: UKDesignInk.secondary)
        note.text = "More controls for this device are coming."
        note.numberOfLines = 0
        let column = UKColumnView(spacing: HassTokens.Spacing.m)
        column.setViews([grid, note])
        return column
    }

    private func pushGroup(_ group: RoomGroup) {
        let page = UKRoomsGroupDetailPage(kind: .contacts, group: group, store: controller.store, viewer: viewer, context: context)
        (navigationController as? UKHassModalController)?.push(page)
    }
}

/// A room pushed from an overview sheet (`RoomGroupDetailPage`): the group's title, its live summary and its tiles. Close stays in the
/// bar at every depth.
@MainActor
final class UKRoomsGroupDetailPage: UKRoomsSheetPage {
    private let kind: RoomOverviewKind
    private let group: RoomGroup
    private let store: EntityStore
    private let viewer: UKRoomsViewer

    init(kind: RoomOverviewKind, group: RoomGroup, store: EntityStore, viewer: UKRoomsViewer, context: UKContext) {
        self.kind = kind
        self.group = group
        self.store = store
        self.viewer = viewer
        super.init(title: RoomOverview.detailTitle(kind, group), maxWidth: 960, context: context)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "overview.detail.\(group.room)"
        navigationItem.rightBarButtonItem = UKSheetItems.close { [weak self] in (self?.navigationController as? UKHassModalController)?.close() }
        let store = self.store
        let read: RoomOverview.Read = { store.entity($0).state }
        let subtitle = ukRoomsSecondaryLabel(ScreenshotPrivacy.isRedacting && kind == .occupancy ? "Hidden" : RoomOverview.detailSubtitle(kind, group, read: read),
                                             identifier: "overview.detail.subtitle")
        bag.observe { [weak subtitle, kind, group] in
            subtitle?.text = ScreenshotPrivacy.isRedacting && kind == .occupancy ? "Hidden" : RoomOverview.detailSubtitle(kind, group, read: read)
        }
        let detail = UKRoomsGroupDetail.make(kind: kind, group: group, viewer: viewer, environment: UKTileEnvironment(context: context), bag: bag,
                                             read: { store.entity($0).state }, send: { _ in })
        setContent([subtitle, detail])
    }
}
#endif
