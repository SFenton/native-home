#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Configured room adapters

extension UKServerUIBindings {
    /// Visibility never removes a control while its canonical provider still owns a command.
    func roomVisible(_ component: D.Component) -> Bool {
        switch component {
        case .navigationTile(let tile):
            if let alarm = tile.alarm, alarms[alarm.sourceId]?.hasPendingIntent == true { return true }
            return roomVisible(tile.roomVisibility)
        case .roomCard(let card), .roomChip(let card):
            if let power = card.power, powers[power.sourceId]?.hasPendingIntent == true { return true }
            return roomVisible(card.visibility)
        case .roomSection(let section):
            if section.children.contains(where: roomHasPendingCommand) { return true }
            return roomVisible(section.visibility)
        default: return true
        }
    }

    func roomHasPendingCommand(_ component: D.Component) -> Bool {
        if component.ownActions.contains(where: {
            if case .domain(let action) = $0 { return powers[action.sourceId]?.hasPendingIntent == true }
            return false
        }) { return true }
        switch component {
        case .roomOverviewTile(let tile): return tile.powerSourceId.flatMap { lights[$0]?.hasPendingIntent } == true
        case .homeLightTile(let tile): return lights[tile.sourceId]?.hasPendingIntent == true
        case .alarmPanel(let panel): return alarms[panel.sourceId]?.hasPendingIntent == true
        case .doorTile(let tile): return doors[tile.sourceId]?.hasPendingIntent == true
        case .climate(let control): return climates[control.props.sourceId]?.hasPendingIntent == true
        case .roomCard(let card), .roomChip(let card): return card.power.map { powers[$0.sourceId]?.hasPendingIntent == true } ?? false
        case .navigationTile(let tile): return tile.alarm.map { alarms[$0.sourceId]?.hasPendingIntent == true } ?? false
        default: return component.childComponents.contains(where: roomHasPendingCommand)
        }
    }
}

@MainActor
enum UKServerUIRooms {
    typealias D = ServerUICompositionDocument

    /// Value/closure canonical tile and chip adapters. No feature IDs, global configs or alternate state path.
    static func bind(_ definition: D.RoomCard, entry: UKServerUINode, page: UKServerUIPage, chip: Bool) {
        guard let renderer = page.renderer else { return }
        var first = true
        entry.bag.observe { [weak page, weak renderer, weak view = entry.view] in
            guard let page, let renderer, let view else { return }
            let bindings = renderer.bindings
            let selected = ServerUIRooms.display(definition, read: bindings.roomEntity)
            let entity = bindings.roomEntity(selected.sourceId)
            let id = bindings.entityID(for: selected.sourceId).value ?? ""
            var card = ServerUIRooms.card(definition, entityId: id, in: renderer.reader())
            if let p = definition.personalization, let viewer = renderer.roomResidentId(), !ScreenshotPrivacy.isRedacting {
                card.title = viewer == p.residentId ? p.ownTitle : p.otherTitle
            }
            var subtitle: String?
            if !selected.subtitles.isEmpty {
                subtitle = selected.subtitles.map { RoomFormat.withUnit(bindings.roomEntity($0)) }.joined(separator: " • ")
            } else {
                subtitle = selected.showState ? RoomFormat.cardState(card, entity) : nil
            }
            if definition.kind == .vent, selected.subtitles.isEmpty, selected.showState,
               !definition.stateLabels.contains(where: { $0.state == entity?.state }) {
                subtitle = ClimateLogic.ventSubtitle(entity)
            }
            if definition.kind == .contact, definition.action == nil, definition.power == nil {
                subtitle = RoomFormat.contactTileSubtitle(entity)
            }
            let display = RoomCardDisplay.resolve(card, entity: entity, subtitle: subtitle)
            let face = RoomTileFace.resolve(card, entity: entity, display: display)
            let body: (() -> Void)? = definition.action.map { action in
                { [weak page, weak view] in
                    guard let page, let renderer = page.renderer,
                          let live = renderer.bindings.roomEntity(ServerUIRooms.display(definition, read: renderer.bindings.roomEntity).sourceId), !live.isUnavailable,
                          !definition.disabledStates.contains(live.state) else { return }
                    renderer.activate(action, from: page, source: view)
                }
            }
            if chip, let view = view as? UKRoomChipView {
                var summary = subtitle ?? RoomFormat.compact(entity)
                var symbol = definition.icon.drawn, tint: ChipTint?, active = face.isActive
                let sources = definition.chipSources
                if definition.subtitleSourceIds.isEmpty, !definition.stateLabels.contains(where: { $0.state == entity?.state }) {
                    if definition.kind == .occupancy { summary = RoomFormat.occupancy(entity) }
                    if definition.kind == .contact { summary = RoomFormat.contact(entity) }
                }
                if definition.kind == .occupancy {
                    active = RoomFormat.isOccupied(entity)
                    symbol = SymbolMap.symbol(for: active ? "mdi:motion-sensor" : "mdi:motion-sensor-off")
                }
                if definition.kind == .contact {
                    let open = RoomFormat.isOpen(entity)
                    if open { symbol = SymbolMap.symbol(for: "mdi:door-open") }
                    else if sources?.pluralContacts == true, entity?.isUnavailable == false { summary = "All Closed" }
                    if let sources {
                        let contact = ContactChipState.resolve(isOpen: entity?.isUnavailable == false ? open : nil,
                            alarmState: sources.alarmSourceId.flatMap { bindings.roomEntity($0)?.state },
                            isAway: ServerUIRooms.isAway(sources, read: bindings.roomEntity))
                        switch contact {
                        case .unavailable: tint = nil
                        case .allClosed: tint = .contactClosed
                        case .openHome: tint = .contactOpenHome
                        case .openAway: tint = .contactOpenAway
                        case .openArmed: tint = .contactOpenArmed
                        }
                        active = contact != .unavailable
                    }
                }
                if definition.kind == .air, let sources {
                    summary = RoomFormat.airSummary(aqi: sources.aqiSourceId.flatMap(bindings.roomEntity), pm25: entity)
                    tint = .fromWeb(ChipWebColor.airQuality(colorText: sources.colorSourceId.flatMap { bindings.roomEntity($0)?.state }).rgb)
                    active = entity?.isUnavailable == false || sources.aqiSourceId.flatMap(bindings.roomEntity)?.isUnavailable == false
                }
                if definition.kind == .climate,
                   let color = ChipWebColor.climate(colorText: sources?.colorSourceId.flatMap { bindings.roomEntity($0)?.state }, rangeText: entity?.state) {
                    tint = .fromWeb(color.rgb)
                    active = entity?.isUnavailable == false
                }
                if ScreenshotPrivacy.isRedacting, definition.kind == .occupancy {
                    summary = "Hidden"
                    symbol = definition.icon.drawn
                    active = false
                    tint = nil
                }
                view.configure(title: card.title, summary: summary, symbol: symbol,
                               family: face.family, isActive: active, tint: tint,
                               action: display.isEnabled ? body : nil, animated: !first)
            } else if let view = view as? UKGlassTileView {
                let powerId = definition.power.flatMap { bindings.entityID(for: $0.sourceId).value }
                let power = definition.power.flatMap { bindings.powers[$0.sourceId] }
                let projection = power?.projection(entityID: powerId, symbol: definition.icon.drawn)
                let specs = projection.map { [$0.spec] } ?? []
                let behavior: TileBehavior = body != nil ? .navigate
                    : definition.power != nil ? .perform(PowerToggleActions.actionId) : .inert
                var model = UKGlassTileModel(title: card.title,
                                             subtitle: projection?.failed == true ? "Didn't Respond" : subtitle,
                                             symbol: definition.icon.drawn, family: face.family,
                                             isActive: projection?.spec.isOn ?? face.isActive,
                                             isUnavailable: display.isUnavailable || (body != nil && !display.isEnabled),
                                             isError: projection?.failed == true, behavior: behavior,
                                             actions: specs.items, identifier: definition.node.id)
                model.stateCandidates = projection?.candidates ?? definition.stateLabels.map(\.label)
                if let color = RoomFormat.background(card, entity, presence: nil) {
                    model.fillRGB = UInt32((color.red * 255).rounded()) << 16
                        | UInt32((color.green * 255).rounded()) << 8 | UInt32((color.blue * 255).rounded())
                }
                if definition.kind == .occupancy, ScreenshotPrivacy.isRedacting {
                    model.subtitle = "Hidden"
                    model.isActive = false
                    model.fillRGB = nil
                }
                if definition.kind == .contact, body == nil, definition.power == nil {
                    model.symbol = RoomOverviewStyle.contactSymbol(window: definition.icon.drawn.contains("window"), open: RoomFormat.isOpen(entity))
                    model.spokenValue = RoomFormat.contact(entity)
                }
                if body != nil { model.bodyHint = "Opens \(definition.node.title)" }
                model.reapplyGeneration = page.context.store.reapplyGeneration
                view.configure(model, environment: UKTileEnvironment(context: page.context), animated: !first, action: body,
                               perform: { [weak page, weak view] _ in
                    guard let page, let action = definition.power else { return }
                    page.renderer?.activate(.domain(action), from: page, source: view, symbol: definition.icon.drawn)
                })
                view.ukRemeasureContainers()
            }
            first = false
        }
    }
}

// MARK: - Frozen-order, live-visibility room grid

/// Reuses the production grid and tile metrics; accepted publications keep tile instances and the visible order.
@MainActor
final class UKServerUIRoomNavigationGrid: UKRoomsGrid {
    private var order = ServerUIRooms.ServerUIRoomOrder()
    private var tiles: [String: UKGlassTileView] = [:]
    private var hasChosen = false

    init() {
        super.init(minCellWidth: DynamicGridMetrics.tileMinWidth, maxColumns: 4, equalRowHeights: true)
        avoidsHinge = false
        accessibilityContainerType = .semanticGroup
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func bind(_ definition: ServerUICompositionDocument.RoomNavigationGrid, entry: UKServerUINode, page: UKServerUIPage) {
        guard let renderer = page.renderer,
              case .roomNavigation(_, let configuration) = renderer.bindings.definitions[definition.sourceId] else { return }
        accessibilityLabel = definition.node.title
        var environment = UKTileEnvironment(context: page.context)
        environment.layout = .anchoredBottom
        environment.titleLines = 2
        var next: [String: UKGlassTileView] = [:]
        for item in configuration.items {
            var fill: UInt32?
            if case .solidRGB(let red, let green, let blue) = item.fill {
                fill = UInt32(red) << 16 | UInt32(green) << 8 | UInt32(blue)
            }
            var model = UKGlassTileModel(title: item.title, symbol: item.icon.drawn, family: .neutral,
                                        fillRGB: fill, isActive: false, kind: .navigate, identifier: "\(definition.node.id).\(item.id)")
            model.bodyHint = item.bodyHint
            let tile = tiles[item.id] ?? UKGlassTileView(model: model, environment: environment)
            tile.configure(model, environment: environment, animated: false, action: { [weak self, weak page, weak tile] in
                guard let self, !self.hasChosen, let page, let renderer = page.renderer, let tile else { return }
                do {
                    try renderer.activateRoom(item, sourceId: definition.sourceId, from: page, source: tile)
                    if case .dismissThenPush = item.action { self.hasChosen = true }
                } catch let error as UKServerUIRendererError { renderer.onError(error) }
                catch { renderer.onError(.init(code: .interactionBlocked, pointer: "/document/dataSources")) }
            })
            next[item.id] = tile
        }
        tiles = next
        entry.bag.observe { [weak self, weak renderer] in
            guard let self, let renderer else { return }
            let ordered = self.order.items(configuration) { renderer.bindings.context.store.entity($0).state?.state }
            let visible = ordered.compactMap { item -> UKGridItem? in
                guard renderer.bindings.roomVisible(item.visibility), let tile = self.tiles[item.id] else { return nil }
                return UKGridItem(tile)
            }
            if self.items.map(\.view) != visible.map(\.view) {
                self.setItems(visible)
                self.remeasure()
            }
        }
    }
}
#endif
