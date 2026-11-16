import Foundation

// MARK: - Value-only status projection

/// Native domain formatting over injected entity reads. Missing members never imply all-clear.
public enum ServerUIHomeStatus {
    /// The authored value.
    public struct Value: Equatable, Sendable {
        public let state: String
        public let text: String
        public let spoken: String
        public let active: Bool
        public let unavailable: Bool
        public let color: RoomColor?
        /// How many members are active (lit, occupied, open); `nil` when that cannot be said (loading, redacted, every member
        /// missing, or a projection with no notion of active). Read as `count` (`sh.home-status-counts@1`).
        public var count: Int?
        /// How many members the status names. Read as `total`.
        public var total = 0
        /// How many members are unavailable or missing. Read as `unavailableCount`.
        public var unavailableCount = 0
    }

    /// Projects the authored status onto the current entity values, with the counts of its members.
    public static func project(_ configuration: ServerUICompositionDocument.HomeStatus, pending: Bool = false,
                               redacted: Bool = false, read: @escaping (String) -> EntityState?) -> Value {
        var value = projectState(configuration, pending: pending, redacted: redacted, read: read)
        let entities = configuration.entityIds.map(read)
        value.total = entities.count
        value.unavailableCount = entities.count { $0?.isUnavailable ?? true }
        guard !["loading", "hidden", "unavailable"].contains(value.state) else { return value }
        let isMember: ((EntityState) -> Bool)? = switch configuration.projection {
        case .lights: { RoomFormat.isActive($0) }
        case .occupancy: { RoomFormat.isOccupied($0) }
        case .contacts: { RoomFormat.isOpen($0) }
        default: nil
        }
        if let isMember { value.count = entities.compactMap { $0 }.count(where: isMember) }
        return value
    }

    private static func projectState(_ configuration: ServerUICompositionDocument.HomeStatus, pending: Bool,
                                     redacted: Bool, read: @escaping (String) -> EntityState?) -> Value {
        let c = configuration
        func value(_ state: String, _ text: String, active: Bool = false, unavailable: Bool = false,
                   spoken: String? = nil) -> Value {
            let color: RoomColor?
            if unavailable || ["loading", "empty", "hidden"].contains(state) { color = nil }
            else if c.projection == .climate && c.format != .item {
                color = ChipWebColor.climate(colorText: c.colorEntityId.flatMap(read)?.state, rangeText: text)
            } else if c.projection == .airQuality, c.colorEntityId != nil {
                color = ChipWebColor.airQuality(colorText: c.colorEntityId.flatMap(read)?.state)
            } else { color = nil }
            return Value(state: state, text: text, spoken: spoken ?? text, active: active, unavailable: unavailable, color: color)
        }
        if redacted { return value("hidden", c.labels.hidden) }
        if pending { return value("loading", c.labels.loading) }
        if c.entityIds.isEmpty { return value("empty", c.labels.empty) }
        let entities = c.entityIds.map(read)
        let missing = entities.count { $0?.isUnavailable ?? true }
        let hasSecondaryAir = c.projection == .airQuality && c.secondaryEntityId.flatMap(read)?.isUnavailable == false
        let hasClimateRange = c.projection == .climate && c.rangeEntityId.flatMap(read)?.isUnavailable == false
        guard missing < entities.count || hasSecondaryAir || hasClimateRange else {
            return value("unavailable", c.labels.unavailable, unavailable: true)
        }
        // A partial sensor set cannot vouch for a closed/unoccupied/off house.
        let group = RoomGroup("", entityId: c.rangeEntityId, c.entityIds.map { id in
            guard let member = c.members.first(where: { $0.entityId == id }) else { return RoomGroupItem("", id) }
            return RoomGroupItem(member.title, id, contactCount: member.contactCount, contactKind: member.contactKind)
        })
        let safeRead: RoomOverview.Read = { id in
            guard let entity = read(id), !entity.isUnavailable else { return nil }
            return entity
        }
        let active: Bool
        let text: String
        var state = "idle"
        switch c.projection {
        case .entity:
            guard let entity = entities.first ?? nil else { return value("unavailable", c.labels.unavailable, unavailable: true) }
            return value(entity.state, entity.state)
        case .lights, .occupancy, .contacts:
            let count = entities.compactMap { $0 }.count {
                switch c.projection {
                case .lights: RoomFormat.isActive($0)
                case .occupancy: RoomFormat.isOccupied($0)
                default: RoomFormat.isOpen($0)
                }
            }
            active = c.projection == .lights && c.format != .summary
                ? RoomOverview.isActive(.lights, group, read: safeRead) : count > 0
            if missing > 0, !active { return value("unavailable", c.labels.unavailable, unavailable: true) }
            if c.format == .item {
                text = switch c.projection {
                case .contacts: RoomFormat.contact(entities.first ?? nil)
                case .occupancy: RoomFormat.occupancy(entities.first ?? nil)
                default: RoomFormat.compact(entities.first ?? nil)
                }
            } else if c.format == .room || c.format == .detail {
                let kind: RoomOverviewKind = c.projection == .lights ? .lights : c.projection == .contacts ? .contacts : .occupancy
                text = c.format == .detail ? RoomOverview.detailSubtitle(kind, group, read: safeRead)
                    : RoomOverview.cardSubtitle(kind, group, read: safeRead)
            } else {
                text = active ? (c.projection == .occupancy ? c.labels.active : "\(count)\(c.labels.countSuffix)") : c.labels.idle
            }
            if c.projection == .contacts {
                let contact = ContactChipState.resolve(isOpen: active, alarmState: c.alarmEntityId.flatMap(read)?.state,
                                                       isAway: c.awayEntityIds.contains { read($0)?.state == "on" })
                state = switch contact {
                case .allClosed: "idle"
                case .openHome: "open-home"
                case .openAway: "open-away"
                case .openArmed: "open-armed"
                case .unavailable: "unavailable"
                }
            } else { state = active ? "active" : "idle" }
        case .climate:
            active = c.format == .item && entities.first.flatMap { $0 }?.domain == "cover"
                && ClimateLogic.isVentOpen(entities.first ?? nil)
            if c.format == .item {
                text = RoomOverview.climateText(entities.first ?? nil)
                state = active ? "active" : "idle"
            } else if c.format == .summary {
                guard let id = c.rangeEntityId ?? c.entityIds.first, let state = safeRead(id)?.state else {
                    return value("unavailable", c.labels.unavailable, unavailable: true)
                }
                text = state
            } else if let range = c.rangeEntityId.flatMap({ safeRead($0)?.state }).flatMap(RoomOverview.normalizedRange) {
                text = range
            } else {
                let sensors = c.entityIds.compactMap(safeRead).filter { $0.attributes["unit_of_measurement"]?.string != nil && Double($0.state)?.isFinite == true }
                guard !sensors.isEmpty else { return value("unavailable", c.labels.unavailable, unavailable: true) }
                text = RoomOverview.climateSubtitle(group, read: safeRead)
            }
        case .airQuality:
            active = false
            let aqi = c.entityIds.first.flatMap(safeRead), pm25 = c.secondaryEntityId.flatMap(safeRead)
            text = c.format == .summary ? RoomOverview.airQualityChipSummary(aqi: aqi, pm25: pm25)
                : RoomFormat.airSummary(aqi: aqi, pm25: pm25)
        }
        let spoken = missing > 0 && c.projection != .airQuality ? "\(text), \(missing) \(c.labels.unavailable)" : text
        return value(state, text, active: active, spoken: spoken)
    }
}
