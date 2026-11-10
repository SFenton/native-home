#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Layout helpers

/// One label with room around it, sized at its natural height.
@MainActor
final class UKLabelBox: UIView, UKGridMeasuring {
    let label: UILabel

    init(_ label: UILabel) {
        self.label = label
        super.init(frame: .zero)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }
}

/// A sheet page's content: padded `HassTokens.Spacing.l` all round, at most 960 pt wide and centred
/// (`.padding(.l).frame(maxWidth: 960).frame(maxWidth: .infinity)`).
@MainActor
final class UKCenteredColumn: UIView, UKGridMeasuring {
    let child: UIView & UKGridMeasuring
    static let maxWidth: CGFloat = 960

    init(_ child: UIView & UKGridMeasuring) {
        self.child = child
        super.init(frame: .zero)
        addSubview(child)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func innerWidth(_ width: CGFloat) -> CGFloat { max(0, min(width, Self.maxWidth) - 2 * HassTokens.Spacing.l) }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { child.gridHeight(forWidth: innerWidth(width)) + 2 * HassTokens.Spacing.l }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inner = innerWidth(bounds.width)
        let box = min(bounds.width, Self.maxWidth)
        child.frame = CGRect(x: (bounds.width - box) / 2 + HassTokens.Spacing.l, y: HassTokens.Spacing.l, width: inner,
                             height: child.gridHeight(forWidth: inner))
    }
}

// MARK: - Light tile

/// A brightness tile when the light dims, else a power tile (`LightGroupTile`). Both send explicit `turn_on` / `turn_off`
/// (``LightControl``), never `toggle`: Presence Based Lighting's Presence Lock reverts toggles.
@MainActor
final class UKLightGroupTileView: UIView, UKGridMeasuring {
    private let title: String
    private let entityId: String
    private let identifier: String
    private let environment: UKTileEnvironment
    private let send: (LightControl.Command) -> Void
    private let glass: UKGlassTileView
    private let brightness: UKBrightnessTileView

    init(title: String, entityId: String, identifier: String, environment: UKTileEnvironment, send: @escaping (LightControl.Command) -> Void) {
        self.title = title
        self.entityId = entityId
        self.identifier = identifier
        self.environment = environment
        self.send = send
        glass = UKGlassTileView(model: UKGlassTileModel(title: title, symbol: "lightbulb", family: .lights, isActive: false, identifier: identifier),
                                environment: environment)
        brightness = UKBrightnessTileView(title: title, tint: UIColor(HassTokens.RGB.Tint.light), percent: 0)
        super.init(frame: .zero)
        brightness.environment = environment
        brightness.identifier = identifier
        brightness.onPower = { [entityId, send] in send(LightControl.power(entityId, on: $0)) }
        brightness.onBrightness = { [entityId, send] in send(LightControl.brightness(entityId, percent: Double($0))) }
        brightness.isHidden = true
        addSubview(glass)
        addSubview(brightness)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var visibleTile: UIView & UKGridMeasuring { brightness.isHidden ? glass : brightness }

    /// Shows the light's state; call it from an observation of the light's box.
    func update(state: EntityState?) {
        let unavailable = state?.isUnavailable ?? true
        let dimmable = LightControl.isDimmable(state)
        if dimmable {
            let fill = LightControl.rgb(of: state).map { UIColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: 1) }
            brightness.update(fillTint: fill, percent: LightControl.percent(of: state), isUnavailable: unavailable)
        } else {
            let on = state?.state == "on"
            // An action tile with a `power` disc (`PowerToggleActions.entity`): explicit `turn_on` / `turn_off`, never `toggle`.
            let provider = PowerToggleActions.entity(entityId)
            let specs = provider.actions(for: state)
            var model = UKGlassTileModel(
                title: title, subtitle: state.map { $0.isUnavailable ? "Unavailable" : (on ? "On" : "Off") }, symbol: specs.first?.symbol ?? "power",
                family: .lights, isActive: on, isUnavailable: unavailable,
                behavior: TileBehavior(TileActionCatalog.classification(ofLightOpensDetails: false), primary: PowerToggleActions.actionId),
                actions: specs.items, identifier: identifier)
            model.stateCandidates = provider.stateTextCandidates
            glass.configure(model, environment: environment, action: {}, perform: { [entityId, send] _ in send(LightControl.flip(entityId, shownOn: on)) })
        }
        if brightness.isHidden != !dimmable {
            brightness.isHidden = !dimmable
            glass.isHidden = dimmable
            ukSetNeedsLayoutUpward()
        }
    }

    var gridMinimumWidth: CGFloat { visibleTile.gridMinimumWidth }
    func gridHeight(forWidth width: CGFloat) -> CGFloat { visibleTile.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        brightness.frame = bounds
    }
}

// MARK: - Group detail

/// A room's lights, temperatures and vents, presence sensors or doors and windows, shared by Home's overview detail pages and the
/// room pages' group sheets (`RoomGroupDetail`). Every run of tiles is one equal-height grid. Lights send explicit `turn_on` /
/// `turn_off` through ``UKLightGroupTileView``; the sensor tiles are read-only.
@MainActor
final class UKRoomGroupDetailView: UIView, UKGridMeasuring {
    private let kind: RoomOverviewKind
    private let group: RoomGroup
    private let showsHeadings: Bool
    private let context: UKContext
    private let viewer: HouseholdResident?
    private let read: RoomOverview.Read
    private let send: (LightControl.Command) -> Void
    private let column = UKColumnView(spacing: HassTokens.Spacing.m)
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true))
    private let bag = UKObservationBag()
    private lazy var environment: UKTileEnvironment = {
        var environment = UKTileEnvironment(context: context)
        environment.surface = .sheet
        return environment
    }()

    /// - Parameters:
    ///   - showsHeadings: Room pages hide the occupancy and contact headings, where the sheet's title already names them.
    ///   - read: A light's pending power is shown in place of its state here (the page's optimistic overlay).
    init(kind: RoomOverviewKind, group: RoomGroup, showsHeadings: Bool = true, context: UKContext, viewer: HouseholdResident? = nil,
         read: @escaping RoomOverview.Read, send: @escaping (LightControl.Command) -> Void) {
        self.kind = kind
        self.group = group
        self.showsHeadings = showsHeadings
        self.context = context
        self.viewer = viewer
        self.read = read
        self.send = send
        super.init(frame: .zero)
        addSubview(column)
        build()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: UKRoomGroupDetailView, _) in
            view.grid.configuration.minCellWidth = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 140, compatibleWith: view.traitCollection)
        }
        grid.configuration.minCellWidth = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 140, compatibleWith: traitCollection)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func build() {
        let sections = RoomOverview.detailSections(kind, group, showsHeadings: showsHeadings)
        var views: [UIView] = []
        var items: [UKGridItem] = []
        if kind == .lights {
            // "Lights", then the whole room at once, then each light (web `RoomLightDetailHeader` with its group slider above the cards).
            if let title = sections.first?.title { views.append(UKPageSectionHeaderView(title, inSheet: true)) }
            if let groupLight = RoomOverview.groupLightEntityId(group) {
                let tile = lightTile(title: RoomOverview.detailTitle(kind, group), entityId: groupLight, identifier: "room.lightGroup.\(groupLight)")
                views.append(tile)
            }
        }
        for section in sections {
            if kind != .lights, let title = section.title { items.append(UKGridItem(UKPageSectionHeaderView(title, inSheet: true), isHeader: true)) }
            for item in section.items { items.append(UKGridItem(tile(item))) }
        }
        grid.setItems(items)
        views.append(grid)
        column.setViews(views)
    }

    private func lightTile(title: String, entityId: String, identifier: String) -> UKLightGroupTileView {
        let tile = UKLightGroupTileView(title: title, entityId: entityId, identifier: identifier, environment: environment, send: send)
        bag.observe { [weak tile, read] in tile?.update(state: read(entityId)) }
        return tile
    }

    private func tile(_ item: RoomGroupItem) -> UIView {
        switch kind {
        case .lights:
            return lightTile(title: item.title(for: viewer), entityId: item.entityId, identifier: "room.light.\(item.entityId)")
        case .climate:
            let vent = item.entityId.hasPrefix("cover.")
            return sensorTile(item, family: vent ? .vents : .climate) { entity in
                (RoomOverview.climateText(entity), vent ? "fan" : "thermometer.medium", vent && ClimateLogic.isVentOpen(entity))
            }
        case .occupancy:
            return sensorTile(item, family: .occupancy, redacts: true) { entity in
                let occupied = RoomFormat.isOccupied(entity)
                return (RoomFormat.occupancy(entity), SymbolMap.symbol(for: occupied ? "mdi:motion-sensor" : "mdi:motion-sensor-off"), occupied)
            }
        case .contacts:
            return sensorTile(item, family: .contact) { entity in
                let open = RoomFormat.isOpen(entity)
                return (RoomFormat.contactTileSubtitle(entity), RoomOverviewStyle.contactSymbol(window: RoomFormat.isWindow(item), open: open), open)
            }
        case .airQuality:
            return UIView()
        }
    }

    /// A read-only sensor tile (web `source-row` cards): filled with its family colour while active (occupied, open), else dark with
    /// the family glyph. Temperatures never fill; an open vent does.
    private func sensorTile(_ item: RoomGroupItem, family: ColorFamily, redacts: Bool = false,
                            state: @escaping (EntityState?) -> (subtitle: String, symbol: String, active: Bool)) -> UKGlassTileView {
        let redact = redacts && ScreenshotPrivacy.isRedacting
        // The tile is built from its real model, glyph included: a placeholder symbol replaced after the sheet is up would animate in.
        let model: @MainActor () -> UKGlassTileModel = { [read] in
            let entity = read(item.entityId)
            let shown = state(entity)
            return UKGlassTileModel(
                title: item.title, subtitle: redact ? "Hidden" : shown.subtitle, symbol: shown.symbol, family: family,
                isActive: shown.active && !redact, isUnavailable: RoomFormat.isUnavailable(entity), kind: .state,
                identifier: "room.entity.\(item.entityId)",
                spokenValue: family == .contact ? RoomFormat.contact(entity) : nil)
        }
        let tile = UKGlassTileView(model: model(), environment: environment)
        bag.observe { [weak tile, environment] in tile?.configure(model(), environment: environment) }
        return tile
    }

    func gridHeight(forWidth width: CGFloat) -> CGFloat { column.gridHeight(forWidth: width) }
    override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: gridHeight(forWidth: size.width)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        column.frame = bounds
        grid.hinge = nil
    }
}

// MARK: - Detail page

/// A room pushed from an overview sheet: the group's title, its live summary and its tiles (`RoomGroupDetailPage`).
@MainActor
final class UKRoomGroupDetailPageViewController: UKPageViewController {
    private let kind: RoomOverviewKind
    private let group: RoomGroup
    private let onDone: () -> Void
    private let subtitle = UILabel.uk(.subheadline, ink: UIColor(HassTokens.RGB.Ink.secondary))
    private var scroll: UKColumnScrollView!
    /// Optimistic light power: a tap shows at once, a rejected call rolls back, and any live change wins (Presence Based Lighting may
    /// revert a light), so lights clear on `.liveChange` (`.agents/patterns/optimistic-actions.md`).
    private var lights: OptimisticActions?

    init(context: UKContext, kind: RoomOverviewKind, group: RoomGroup, onDone: @escaping () -> Void) {
        self.kind = kind
        self.group = group
        self.onDone = onDone
        super.init(context: context.with { $0.surface = .sheet }, title: RoomOverview.detailTitle(kind, group))
        navigationItem.title = RoomOverview.detailTitle(kind, group)
        if kind == .lights, let caller = context.caller ?? context.connection {
            let ids = group.items.map(\.entityId) + [group.entityId].compactMap { $0 }
            lights = OptimisticActions(store: context.store, rules: Dictionary(ids.map { ($0, .liveChange) }) { first, _ in first }, caller: caller)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The live entity, with a pending light power shown in place of its state.
    private func read(_ id: String) -> EntityState? {
        guard var entity = context.store.entity(id).state else { return nil }
        if let shown = lights?.shown(id) { entity.state = shown }
        return entity
    }

    private func send(_ command: LightControl.Command) {
        // Brightness above 0 and turn_on both show the light on; turn_off shows it off.
        let shown = command.service == "turn_off" ? "off" : "on"
        lights?.perform(command.domain, command.service, data: command.serviceData, showing: [OptimisticIntent(command.entityId, value: shown)])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "overview.detail.\(group.room)"
        subtitle.accessibilityIdentifier = "overview.detail.subtitle"
        let detail = UKRoomGroupDetailView(kind: kind, group: group, context: context, read: { [weak self] in self?.read($0) }, send: { [weak self] in self?.send($0) })
        let column = UKColumnView(spacing: HassTokens.Spacing.l)
        column.setViews([UKLabelBox(subtitle), detail])
        scroll = UKColumnScrollView(content: UKCenteredColumn(column))
        install(scrollView: scroll)
        navigationItem.rightBarButtonItem = UKSheetItems.close(action: onDone)
        bag.observe { [weak self] in
            guard let self else { return }
            let redact = ScreenshotPrivacy.isRedacting && kind == .occupancy
            let text = redact ? "Hidden" : RoomOverview.detailSubtitle(kind, group, read: { self.read($0) })
            if subtitle.text != text {
                subtitle.text = text
                scroll.setNeedsLayout()
                scroll.content.setNeedsLayout()
            }
        }
    }
}

// MARK: - Overview sheet

/// A room-by-room overview sheet that pushes a room's detail page (`RoomOverviewSheet`, web `LightsSheet` … `AirQualitySheet`;
/// pattern: `.agents/patterns/room-overview-sheet.md`). Home opens it from five status chips and the Security page from its Contact
/// Sensors chip. A room tap pushes the room inside the sheet's own navigation stack with Back, as the web's in-sheet back button
/// does.
@MainActor
enum UKRoomOverviewSheet {
    /// The sheet as a modal: full height, page width.
    static func controller(context: UKContext, kind: RoomOverviewKind) -> UKHassModalController {
        let read: RoomOverview.Read = { context.store.entity($0).state }
        var options = UKHassModalOptions(title: UKRoomOverviewViewController.title(kind, read: read))
        options.height = .full
        options.width = .page
        options.reveal = .gate(.sheet)
        let sheetContext = context.with { $0.surface = .sheet }
        return UKHassModalController(root: UKRoomOverviewViewController(context: sheetContext, kind: kind), options: options)
    }
}

/// The overview's room cards in one equal-height grid, sections headed inside it (`RoomOverviewGrid`).
@MainActor
final class UKRoomOverviewViewController: UKPageViewController {
    override var houseLayoutSkeleton: HouseSkeletonPlan.Kind? { .page }

    private let kind: RoomOverviewKind
    private let structureBag = UKObservationBag()
    private let tileBag = UKObservationBag()
    private let grid = UKDynamicGridView(configuration: UKGridConfiguration(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true))
    private var scroll: UKColumnScrollView!
    private var structureKey: [String] = []
    private lazy var environment: UKTileEnvironment = {
        var environment = UKTileEnvironment(context: context)
        environment.surface = .sheet
        return environment
    }()

    init(context: UKContext, kind: RoomOverviewKind) {
        self.kind = kind
        super.init(context: context.with { $0.surface = .sheet }, title: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The sheet's title: its name where the subtitle carries the state, else the web's title with its count.
    static func title(_ kind: RoomOverviewKind, read: RoomOverview.Read) -> String { RoomOverviewSheet.title(kind, read: read) }

    /// Optimistic room power (`.agents/patterns/optimistic-actions.md`), made on the first tap of a Lights card's disc. Any live change wins
    /// (Presence Based Lighting may revert a light), so every light clears on `.liveChange`.
    private var lights: OptimisticActions?

    /// The live entity, with a pending room power shown in place of its state.
    private var read: RoomOverview.Read {
        { [context, weak self] id in
            guard var entity = context.store.entity(id).state else { return nil }
            if let shown = self?.lights?.shown(id) { entity.state = shown }
            return entity
        }
    }

    /// Runs the room power disc through the optimistic path; nothing without a connection or caller.
    private func run(_ spec: TileActionSpec, _ provider: RoomLightsPowerActions) {
        guard let target = context.caller ?? context.connection else { return }
        let actions = lights ?? OptimisticActions(
            store: context.store, rules: Dictionary(provider.entityIds.map { ($0, .liveChange) }) { first, _ in first }, caller: target)
        lights = actions
        actions.perform(spec)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "overview.\(kind.rawValue)"
        scroll = UKColumnScrollView(content: UKCenteredColumn(grid))
        install(scrollView: scroll)
        grid.configuration.minCellWidth = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 140, compatibleWith: traitCollection)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (controller: UKRoomOverviewViewController, _) in
            controller.grid.configuration.minCellWidth = UIFontMetrics(forTextStyle: .subheadline).scaledValue(for: 140, compatibleWith: controller.traitCollection)
        }
        structureBag.observe { [weak self] in
            guard let self else { return }
            let read = self.read
            navigationItem.title = Self.title(kind, read: read)
            UKSheetSubtitle.apply(RoomOverview.sheetSubtitle(kind, read: read), to: navigationItem)
            let sections = self.sections(read: read)
            let key = sections.map { $0.title + ":" + $0.groups.map(\.room).joined(separator: ",") }
            guard key != structureKey else { return }
            structureKey = key
            rebuild(sections)
        }
    }

    /// Shared screenshots hide who is home, so redacted occupancy lists every room under one heading.
    private func sections(read: RoomOverview.Read) -> [RoomOverviewSection] {
        if ScreenshotPrivacy.isRedacting, kind == .occupancy {
            return [RoomOverviewSection(title: "Rooms", groups: RoomOverview.groups(kind))]
        }
        return RoomOverview.sections(kind, read: read)
    }

    private func rebuild(_ sections: [RoomOverviewSection]) {
        tileBag.removeAll()
        var items: [UKGridItem] = []
        if kind == .airQuality {
            items.append(UKGridItem(UKPageSectionHeaderView("Rooms", inSheet: true), isHeader: true))
            for room in RoomOverview.airQualityRooms { items.append(UKGridItem(airQualityTile(room))) }
        } else {
            for section in sections {
                let header = UKPageSectionHeaderView(section.title, inSheet: true)
                header.accessibilityIdentifier = "overview.\(kind.rawValue).section.\(section.title)"
                items.append(UKGridItem(header, isHeader: true))
                for group in section.groups { items.append(UKGridItem(roomTile(group))) }
            }
        }
        grid.setItems(items)
        scroll.setNeedsLayout()
    }

    // MARK: Tiles

    /// One room card (`RoomOverviewTile`): the room's state, opening its detail page.
    private func roomTile(_ group: RoomGroup) -> UKGlassTileView {
        let kind = kind
        // The tile is built from its real model, glyph included (`roomModel`), then follows live changes.
        let first = roomModel(group, read: read, kind: kind)
        let tile = UKGlassTileView(model: first.model, environment: environment)
        tileBag.observe { [weak tile, weak self] in
            guard let self, let tile else { return }
            let (model, specs, provider) = self.roomModel(group, read: self.read, kind: kind)
            tile.configure(model, environment: environment, action: { [weak self] in self?.open(group) }, perform: { [weak self] id in
                if let spec = specs.first(where: { $0.id == id }), let provider { self?.run(spec, provider) }
            })
        }
        return tile
    }

    /// One room card's model from the live state: the glyph, subtitle, fill and (Lights) the room power disc.
    private func roomModel(_ group: RoomGroup, read: RoomOverview.Read, kind: RoomOverviewKind)
        -> (model: UKGlassTileModel, specs: [TileActionSpec], provider: RoomLightsPowerActions?) {
        let active = RoomOverview.isActive(kind, group, read: read)
        let redact = ScreenshotPrivacy.isRedacting && kind == .occupancy
        let symbol: String = switch kind {
        case .lights: group.items.count > 1 ? "lightbulb.2" : "lightbulb"
        case .climate: SymbolMap.symbol(for: RoomOverview.roomIcon(group.room) ?? "mdi:thermometer")
        case .occupancy: SymbolMap.symbol(for: active && !redact ? "mdi:motion-sensor" : "mdi:motion-sensor-off")
        case .contacts: RoomOverviewStyle.contactSymbol(window: RoomOverview.isWindowGroup(group), open: active)
        case .airQuality: SymbolMap.symbol(for: "mdi:blur")
        }
        // A **Lights** card is a navigation tile with a room power disc left of its chevron (`RoomLightsPowerActions`, audit item 12).
        let provider = kind == .lights ? RoomLightsPowerActions(group) : nil
        let specs = provider?.actions(read: read) ?? []
        var model = UKGlassTileModel(
            title: group.room, subtitle: redact ? "Hidden" : RoomOverview.tileSubtitle(kind, group, read: read), symbol: symbol,
            family: RoomOverviewStyle.family(kind), isActive: RoomOverviewStyle.isFilled(kind, active: active && !redact), behavior: .navigate,
            actions: specs.items, identifier: "overview.\(kind.rawValue).room.\(group.room)",
            spokenValue: redact ? "Hidden" : RoomOverview.spokenSubtitle(kind, group, read: read))
        model.stateCandidates = provider?.stateTextCandidates ?? []
        // On the body only: a hint set from outside would also be read on the lights disc.
        model.bodyHint = "Opens \(RoomOverview.detailTitle(kind, group))"
        return (model, specs, provider)
    }

    /// One room in the Air Quality sheet (`AirQualityRoomTile`): AQI and PM2.5, its glyph and rim in the room's AQI colour; read-only.
    private func airQualityTile(_ room: AirQualityRoom) -> UKGlassTileView {
        let tile = UKGlassTileView(model: airQualityModel(room, read: read), environment: environment)
        tileBag.observe { [weak tile, weak self] in
            guard let self, let tile else { return }
            tile.configure(self.airQualityModel(room, read: self.read), environment: environment)
        }
        return tile
    }

    /// One Air Quality room's model from the live state.
    private func airQualityModel(_ room: AirQualityRoom, read: RoomOverview.Read) -> UKGlassTileModel {
        // Both sensors dead: the neutral dark face and "Unavailable", not the teal fallback with a reading.
        let offline = (read(room.aqiEntityId)?.isUnavailable ?? true) && (read(room.pm25EntityId)?.isUnavailable ?? true)
        return UKGlassTileModel(
            title: room.title, subtitle: RoomFormat.airSummary(aqi: read(room.aqiEntityId), pm25: read(room.pm25EntityId)),
            symbol: SymbolMap.symbol(for: "mdi:blur"), tint: UIColor(RoomOverview.airQualityColor(room, read: read).token), isActive: !offline, kind: .state,
            identifier: "overview.airQuality.room.\(room.title)")
    }

    private func open(_ group: RoomGroup) {
        guard let modal = navigationController as? UKHassModalController else { return }
        let page = UKRoomGroupDetailPageViewController(context: context, kind: kind, group: group) { [weak modal] in modal?.close() }
        modal.push(page)
    }
}
#endif
