import Foundation
import os

private let visitLog = Logger(subsystem: "com.sfenton.home", category: "Rooms")

// MARK: - Display values

/// How a room card shows right now (web `DefaultRoomSourceCard`, `DashboardViewPage.tsx:1154`).
public struct RoomCardDisplay: Equatable, Sendable {
    /// Personalized title.
    public var title: String
    public var subtitle: String?
    /// The entity is missing, unavailable or unknown.
    public var isUnavailable: Bool
    /// Drawn dimmed (unavailable, a disabled state, or an inactive light/fan/media/power card).
    public var isOff: Bool
    /// Tapping does something now.
    public var isEnabled: Bool
    /// What assistive technologies hear.
    public var semantics: RoomTileSemantics
    /// A state wash behind the tile.
    public var background: RoomColor?
}

/// A room tile's role (web `ControlSemantics` with `modal`).
public enum RoomTileSemantics: Equatable, Sendable {
    /// Opens a sheet: chevron, button.
    case modal
    /// Fires a command.
    case command
    /// An on/off switch.
    case toggle(isOn: Bool)
    /// One of a set; `.isSelected` when chosen.
    case selection(isSelected: Bool)
    /// Shows state only; not a button.
    case state
}

/// How a status chip shows (web `StatusRail` chip, `src/components/hass/StatusRail.tsx`).
public struct RoomChipDisplay: Equatable, Sendable {
    public var title: String
    public var summary: String
    /// MDI icon after state swaps (motion-sensor-off, door-open).
    public var icon: String
    public var isActive: Bool
    public var opensSheet: Bool
    /// A contact chip's house state (``ContactChipState``); nil on any other chip.
    public var contact: ContactChipState? = nil
    /// The colour Home Assistant gives a Climate or Air Quality chip (``ChipWebColor``); nil on any other chip.
    public var webColor: RoomColor? = nil
}

/// What a card's sheet shows (web `RoomSourceModal` + `renderRoomReusableSheet`, `DashboardViewPage.tsx:1272`).
///
/// Device-specific cases are hook points for their lanes; until a lane lands, the sheet draws generic entity tiles.
public enum RoomSheetContent: Hashable, Sendable {
    /// A media remote (`MediaRemoteSheet`).
    case mediaRemote(id: String)
    /// The room's lights.
    case lights(RoomGroup)
    /// The room's temperatures and vents.
    case climate(RoomGroup)
    /// The room's presence sensors.
    case occupancy(RoomGroup)
    /// The room's doors and windows.
    case contacts(RoomGroup)
    /// Every room's doors and windows (rooms without their own contact group).
    case allContacts
    /// A fixed list of entities (vents).
    case items([RoomModalItem])
    /// Device modals built in other lanes. Each falls back to ``RoomCard/fallbackEntityIds``.
    case device(RoomDeviceSheet)
    /// Nothing interactive (web `RoomSourceFallback`).
    case fallback
}

/// Device sheets owned by other lanes (web `DishwasherModalContent`, `AirQualityModalContent`, `HumidifierModal`,
/// `GrillModalContent`, `WakeLightModalWithBedAlarms`, `EightSleepBedModal`, `VacuumModal`, `BathroomFanModal`).
public enum RoomDeviceSheet: Hashable, Sendable {
    case dishwasher
    case airQuality(pm25EntityId: String)
    case humidifier(powerEntityId: String)
    case grill(entityId: String)
    case wakeLight(statusEntityId: String)
    /// An Eight Sleep side, by its sheet id (`alexs-bed`, `sams-bed`).
    case bed(sheet: String, climateEntityId: String)
    case vacuum(entityId: String)
    case bathroomFan(powerEntityId: String)
}

/// What tapping a card did.
public enum RoomTapResult: Equatable, Sendable {
    /// Present this card's sheet.
    case openSheet
    /// Ran its action.
    case ran
    /// Nothing (disabled, or no interaction).
    case none
}

// MARK: - Controller

/// One room page's reads and actions: card display, chip summaries, sheet routing and service calls.
///
/// Media cards and app launchers share a ``MediaRemoteController`` per remote, so the Music Room's source tiles and
/// its remote sheet show the same optimistic state.
@MainActor
public final class RoomController {
    public let page: RoomPage
    public let store: EntityStore
    public let caller: any HassServiceCalling
    private var remotes: [String: MediaRemoteController] = [:]
    private var inFlight: [Task<Void, Never>] = []
    /// Optimistic power for flip cards (`.agents/patterns/optimistic-actions.md`). Cleared by any live change, so a
    /// light that Presence Based Lighting turns back off shows the truth rather than the tap.
    private let flips: OptimisticActions

    /// Creates a controller.
    /// - Parameters:
    ///   - page: The room.
    ///   - store: Live state.
    ///   - caller: Where service calls go.
    ///   - scheduler: Revert timers for optimistic values (tests pass a manual one).
    public init(page: RoomPage, store: EntityStore, caller: any HassServiceCalling, scheduler: (any RevertScheduler)? = nil) {
        self.page = page
        self.store = store
        self.caller = caller
        var flipRules: [String: OptimisticOverlay.ClearRule] = [:]
        for card in page.allCards where card.action == .flip { flipRules[card.entityId] = .liveChange }
        flips = OptimisticActions(store: store, rules: flipRules, caller: caller, scheduler: scheduler ?? TaskRevertScheduler())
        for id in page.remoteIds {
            guard let config = MediaRemotes.config(id: id) else { continue }
            remotes[id] = scheduler.map { MediaRemoteController(config: config, store: store, caller: caller, scheduler: $0) }
                ?? MediaRemoteController(config: config, store: store, caller: caller)
        }
    }

    /// The shared controller for a remote this page uses.
    public func remote(_ id: String) -> MediaRemoteController? { remotes[id] }

    // MARK: Reading

    /// The optimistic value while one shows, else the live state.
    public func displayedState(_ entityId: String) -> String? {
        if let id = page.optimisticRemoteId, let remote = remotes[id] { return remote.displayedState(entityId) }
        return flips.shown(entityId)
    }

    /// Whether the last tap on `card` was rejected and the tile still shows its failed face (4 s).
    public func isFailed(_ card: RoomCard) -> Bool { flips.isFailed(card.entityId) }

    /// The entity with its displayed state.
    public func entity(_ entityId: String) -> EntityState? {
        guard var entity = store.entity(entityId).state else { return nil }
        if let shown = displayedState(entityId) { entity.state = shown }
        return entity
    }

    /// Whether the card shows its alternate entity now (the dishwasher's progress while it runs).
    public func usesAlternate(_ card: RoomCard) -> Bool {
        guard let alternate = card.alternate, let gate = entity(alternate.whenEntityId) else { return false }
        return alternate.whenStates.contains(gate.state)
    }

    /// The entity a card shows now: its alternate while that applies, else its own.
    public func displayEntity(_ card: RoomCard) -> EntityState? {
        entity(usesAlternate(card) ? card.alternate!.entityId : card.entityId)
    }

    /// How a card shows for `viewer`.
    public func display(_ card: RoomCard, viewer: HouseholdResident? = nil) -> RoomCardDisplay {
        let useAlternate = usesAlternate(card)
        let showState = useAlternate ? card.alternate!.showState : card.showState
        let subtitleIds = useAlternate ? card.alternate!.subtitleEntityIds : card.subtitleEntityIds
        let entity = displayEntity(card)

        let unavailable = RoomFormat.isUnavailable(entity)
        let disabledByState = entity.map { card.disabledStates.contains($0.state) } ?? false
        let subtitle: String? = !subtitleIds.isEmpty
            ? subtitleIds.map { RoomFormat.withUnit(self.entity($0)) }.joined(separator: " • ")
            : showState ? RoomFormat.cardState(card, entity) : nil
        let activeByState = entity.map { card.activeStates.contains($0.state) } ?? false
        let muted = !unavailable && !activeByState && !RoomFormat.isActive(entity) && RoomFormat.mutedWhenInactive.contains(card.kind)
        let interactionDisabled = unavailable || disabledByState
        return RoomCardDisplay(
            title: card.title(for: viewer),
            subtitle: subtitle,
            isUnavailable: unavailable,
            isOff: unavailable || disabledByState || muted,
            isEnabled: card.hasInteraction && !interactionDisabled,
            semantics: semantics(card, entity: entity, active: activeByState || RoomFormat.isActive(entity)),
            background: RoomFormat.background(card, entity, presence: nil)
        )
    }

    private func semantics(_ card: RoomCard, entity: EntityState?, active: Bool) -> RoomTileSemantics {
        switch card.semantics {
        case .modal: return .modal
        case .command: return .command
        case let .rule(rule):
            switch rule.semantics(for: entity?.state) {
            case let .toggle(isOn): return .toggle(isOn: isOn)
            case let .selection(isSelected): return .selection(isSelected: isSelected)
            case .command: return .command
            case .state: return .state
            }
        case nil:
            switch card.action {
            case .flip: return .toggle(isOn: active)
            case .remote: return .command
            case nil: return card.sheet == nil ? .state : .modal
            }
        }
    }

    /// How an overview card shows as a status chip.
    public func chip(_ card: RoomCard) -> RoomChipDisplay {
        let entity = entity(card.entityId)
        var summary: String
        var icon = card.icon
        let active: Bool
        var contact: ContactChipState?
        var webColor: RoomColor?
        switch card.kind {
        case .occupancy:
            summary = RoomFormat.occupancy(entity)
            active = RoomFormat.isOccupied(entity)
            icon = active ? "mdi:motion-sensor" : "mdi:motion-sensor-off"
        case .contact:
            summary = RoomFormat.contact(entity)
            let open = RoomFormat.isOpen(entity)
            if !open && card.title.hasSuffix("s") { summary = "All Closed" }
            if open { icon = "mdi:door-open" }
            active = RoomFormat.isActive(entity)
            contact = ContactChipState.current(isOpen: RoomFormat.isUnavailable(entity) ? nil : open) { self.entity($0) }
        case .air:
            summary = RoomFormat.airSummary(aqi: self.entity(RoomFormat.aqiEntityId(forPM25: card.entityId)), pm25: entity)
            active = RoomFormat.isActive(entity)
            webColor = ChipWebColor.airColorEntityId(forPM25: card.entityId).map {
                ChipWebColor.airQuality(colorText: self.entity($0)?.state)
            }
        case .climate:
            summary = RoomFormat.compact(entity)
            active = RoomFormat.isActive(entity)
            // A room's range helper has a matching colour helper; other climate cards (beds) keep the family colour.
            if let colorId = ChipWebColor.climateColorEntityId(forRange: card.entityId) {
                webColor = ChipWebColor.climate(colorText: self.entity(colorId)?.state, rangeText: entity?.state)
            }
        default:
            summary = RoomFormat.compact(entity)
            active = RoomFormat.isActive(entity)
        }
        return RoomChipDisplay(title: card.title, summary: summary, icon: icon, isActive: active, opensSheet: card.sheet != nil,
                               contact: contact, webColor: webColor)
    }

    // MARK: Sheets

    /// What a card's sheet shows (resolution order follows the web's `RoomSourceModal`).
    public func sheet(for card: RoomCard) -> RoomSheetContent {
        guard let sheet = card.sheet else { return .fallback }
        let room = page.title
        if MasterBedroom.bed(id: sheet) != nil { return .device(.bed(sheet: sheet, climateEntityId: card.entityId)) }
        if card.kind == .media, MediaRemotes.config(id: sheet) != nil { return .mediaRemote(id: sheet) }
        if card.control == .bathroomFan { return .device(.bathroomFan(powerEntityId: card.entityId)) }
        if card.kind == .humidifier { return .device(.humidifier(powerEntityId: card.entityId)) }
        if card.kind == .vacuum { return .device(.vacuum(entityId: card.entityId)) }
        if card.kind == .wakeLight { return .device(.wakeLight(statusEntityId: card.entityId)) }
        if card.entityId == RoomsConfig.dishwasherProgramEntityId { return .device(.dishwasher) }
        if !card.modalItems.isEmpty { return .items(card.modalItems) }
        if card.kind == .light, let group = RoomGroups.lights(room: room) { return .lights(group) }
        if card.kind == .vent || (card.kind == .climate && card.title == "Climate"), let group = RoomGroups.climate(room: room) {
            return .climate(group)
        }
        if card.kind == .occupancy, let group = RoomGroups.occupancy(room: room) { return .occupancy(group) }
        if card.kind == .contact { return RoomGroups.contacts(room: room).map(RoomSheetContent.contacts) ?? .allContacts }
        if card.kind == .air { return .device(.airQuality(pm25EntityId: card.modalEntityId ?? card.entityId)) }
        if card.kind == .grill { return .device(.grill(entityId: card.entityId)) }
        return .fallback
    }

    /// The sheet's title: the remote's title, "Kitchen Lights", or "Living Room: Robot Vacuum" (web `RoomSourceModal`).
    public func sheetTitle(for card: RoomCard) -> String {
        if card.kind == .media, let sheet = card.sheet, let config = MediaRemotes.config(id: sheet) { return config.remoteTitle }
        if card.entityId == RoomsConfig.dishwasherProgramEntityId { return card.modalTitle ?? card.title }
        let plain: Set<RoomCardKind> = [.air, .climate, .contact, .humidifier, .light, .occupancy]
        return "\(page.title)\(plain.contains(card.kind) ? " " : ": ")\(card.modalTitle ?? card.title)"
    }

    /// The sheet's subtitle (web `roomSourceModalSubtitle`): Occupied/Clear, the air summary, the humidifier summary or
    /// the card's state. Lights and contacts have none.
    public func sheetSubtitle(for card: RoomCard) -> String? {
        let plain: Set<RoomCardKind> = [.air, .climate, .humidifier, .occupancy]
        guard plain.contains(card.kind), card.showState || card.kind == .air else { return nil }
        switch card.kind {
        case .occupancy:
            guard let group = RoomGroups.occupancy(room: page.title) else { return nil }
            return group.items.contains { RoomFormat.isOccupied(entity($0.entityId)) } ? "Occupied" : "Clear"
        case .air:
            let pm25 = card.modalEntityId ?? card.entityId
            return RoomFormat.airSummary(aqi: entity(RoomFormat.aqiEntityId(forPM25: pm25)), pm25: entity(pm25))
        default:
            return RoomFormat.cardState(card, entity(card.entityId))
        }
    }

    /// Entities a device sheet's generic fallback lists until its lane lands: the card's entity, its subtitle
    /// entities and its sheet entity, without duplicates.
    public func fallbackEntityIds(for card: RoomCard) -> [String] {
        var ids: [String] = []
        func add(_ id: String?) { if let id, !ids.contains(id) { ids.append(id) } }
        add(card.modalEntityId)
        if card.kind == .air { add(RoomFormat.aqiEntityId(forPM25: card.modalEntityId ?? card.entityId)) }
        add(card.entityId)
        card.subtitleEntityIds.forEach { add($0) }
        if let alternate = card.alternate { add(alternate.entityId) }
        return ids
    }

    // MARK: Actions

    /// Taps a card: opens its sheet or runs its action, unless it is disabled.
    @discardableResult
    public func tap(_ card: RoomCard) -> RoomTapResult {
        guard display(card).isEnabled else { return .none }
        guard let action = card.action else { return card.sheet == nil ? .none : .openSheet }
        run(action, on: card)
        return .ran
    }

    private func run(_ action: RoomCardAction, on card: RoomCard) {
        switch action {
        case .flip:
            let shownOn = RoomFormat.isActive(entity(card.entityId))
            let command = LightControl.flip(card.entityId, shownOn: shownOn)
            inFlight.append(flips.perform(command.domain, command.service, data: command.serviceData,
                                          showing: [.init(card.entityId, value: shownOn ? "off" : "on")]))
        case let .remote(remoteAction):
            if let id = page.optimisticRemoteId, let remote = remotes[id] {
                remote.run(remoteAction, entityId: card.entityId)
                return
            }
            if case let .service(call, _) = remoteAction.resolve(entityId: card.entityId, displayedState: displayedState) {
                send(call.domain, call.service, call.serviceData.mapValues(\.foundationValue))
            }
        }
    }

    /// Calls a light or switch command from a sheet tile.
    public func send(_ command: LightControl.Command) {
        send(command.domain, command.service, command.serviceData)
    }

    /// Counts a visit to a room opened from the Rooms grid.
    public static func recordVisit(_ item: RoomNavigationItem, caller: any HassServiceCalling) {
        let call = RoomNavigation.accessIncrementCall(for: item)
        Task {
            do { try await caller.call(call) } catch {
                // A missed visit count only reorders the grid; nothing to show, but the log says why.
                visitLog.error("room visit count failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func send(_ domain: String, _ service: String, _ data: [String: any Sendable]) {
        let caller = caller
        inFlight.append(Task {
            do { try await caller.callService(domain, service, data: data) } catch {
                // A command with no optimistic value has no tile to turn red; the log says why it did nothing.
                visitLog.error("room command \(domain, privacy: .public).\(service, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        })
    }

    /// Waits for every call started so far, including the shared remotes'. Tests use it.
    public func waitForCalls() async {
        let tasks = inFlight
        inFlight.removeAll()
        for task in tasks { await task.value }
        for remote in remotes.values { await remote.waitForCalls() }
    }
}
