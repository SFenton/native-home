import Foundation

/// Everything a sprinkler controller shows, read from its entities in one pass.
///
/// Port of `ha-sfenton-react-dash@9ac2a46:src/components/hass/sprinklerState.ts` (`buildSprinklerSnapshot`),
/// rule for rule, so the native and web pages agree on availability, watering and program matching.
public struct SprinklerSnapshot: Equatable, Sendable {
    /// The controller's headline status, in the web's precedence: unavailable, fault, watering, ready.
    public enum Status: Equatable, Sendable { case unavailable, fault, watering, ready }

    /// A zone's program (a B-hyve program switch and its schedule attributes).
    public struct Program: Equatable, Sendable {
        public var available: Bool
        /// Watering budget in percent (100 when unreported).
        public var budget: Int
        /// Days the program runs, 0 = Sunday.
        public var days: [Int]
        public var enabled: Bool
        public var entityId: String
        public var name: String?
        /// The first run time in minutes, if any.
        public var runTimeMinutes: Int?
        /// Stations the program waters.
        public var stationIds: [Int]
        /// Start times as `HH:mm`.
        public var startTimes: [String]
    }

    /// A watering run from a history sensor.
    public struct LastRun: Equatable, Sendable {
        public var runTimeMinutes: Double?
        public var startTime: Date?

        static let none = LastRun(runTimeMinutes: nil, startTime: nil)
    }

    /// One zone.
    public struct Zone: Equatable, Sendable {
        public var available: Bool
        public var config: SprinklersConfig.Zone
        public var lastRun: LastRun
        public var name: String
        public var program: Program
        public var watering: Bool
    }

    public var activeValveEntityId: String?
    public var available: Bool
    public var batteryLow: Bool
    public var batteryPercent: Double?
    public var fault: Bool
    public var hubConnected: Bool
    /// The latest run across zones.
    public var lastRun: LastRun
    /// The device mode (`auto`, `manual`, `off`), or the controller state when the mode is unavailable.
    public var mode: String
    public var nextStart: Date?
    /// The next-watering sensor reports `unknown`.
    public var nextStartUnknown: Bool
    public var rainDelay: Bool
    public var smartWatering: Bool
    public var status: Status
    public var watering: Bool
    public var zones: [Zone]

    // MARK: - Building

    /// Reads a controller.
    /// - Parameters:
    ///   - config: The controller.
    ///   - entity: Looks up an entity's current state.
    public init(config: SprinklersConfig.Controller, entity: (String) -> EntityState?) {
        let state = entity(config.stateEntityId)
        let modeEntity = entity(config.modeEntityId)
        let battery = entity(config.batteryEntityId)
        let nextWatering = entity(config.nextWateringEntityId)
        var programIds: [String] = []
        for zone in config.zones where !programIds.contains(zone.programEntityId) { programIds.append(zone.programEntityId) }
        let programs = programIds.map { Self.program(entity($0), entityId: $0) }
        let zones = config.zones.map { Self.zone($0, entity: entity, programs: programs) }
        let available = Self.isAvailable(state) && zones.contains(where: \.available)
        let activeZone = zones.first(where: \.watering)
        let fault = available && entity(config.faultEntityId)?.state == "on"
        let batteryPercent = Self.isAvailable(battery) ? battery?.numericState : nil

        activeValveEntityId = activeZone?.config.valveEntityId
        self.available = available
        batteryLow = batteryPercent.map { $0 <= SprinklersConfig.lowBatteryPercent } ?? false
        self.batteryPercent = batteryPercent
        self.fault = fault
        hubConnected = entity(config.hubConnectedEntityId)?.state == "on"
        lastRun = zones.map(\.lastRun).reduce(LastRun.none) { latest, candidate in
            guard let start = candidate.startTime else { return latest }
            guard let latestStart = latest.startTime else { return candidate }
            return start > latestStart ? candidate : latest
        }
        mode = Self.isAvailable(modeEntity) ? modeEntity?.state ?? "unavailable" : state?.state ?? "unavailable"
        nextStart = Self.isAvailable(nextWatering) ? Self.date(nextWatering?.state) : nil
        nextStartUnknown = nextWatering?.state == "unknown"
        rainDelay = available && entity(config.rainDelayEntityId)?.state == "on"
        smartWatering = available && entity(config.smartWateringEntityId)?.state == "on"
        status = !available ? .unavailable : fault ? .fault : activeZone != nil ? .watering : .ready
        watering = activeZone != nil
        self.zones = zones
    }

    /// Reads a controller from a store.
    @MainActor
    public init(config: SprinklersConfig.Controller, store: EntityStore) {
        self.init(config: config) { store.entity($0).state }
    }

    /// Every entity a controller reads, so a view can observe them.
    public static func entityIds(_ config: SprinklersConfig.Controller) -> [String] {
        [config.stateEntityId, config.modeEntityId, config.batteryEntityId, config.faultEntityId, config.nextWateringEntityId,
         config.hubConnectedEntityId, config.rainDelayEntityId, config.smartWateringEntityId]
            + config.zones.flatMap { [$0.valveEntityId, $0.programEntityId, $0.historyEntityId] }
    }

    // MARK: - Pieces

    static func isAvailable(_ entity: EntityState?) -> Bool {
        guard let entity else { return false }
        return !entity.isUnavailable
    }

    static func number(_ value: JSONValue?) -> Double? { value?.finiteNumber }

    static func program(_ entity: EntityState?, entityId: String) -> Program {
        let runTimes = entity?.attributes["run_times"]?.array ?? []
        let stations = runTimes.compactMap { number($0["station"]) }.map { Int($0) }
        return Program(
            available: isAvailable(entity),
            budget: number(entity?.attributes["budget"]).map { Int($0) } ?? 100,
            days: entity?.attributes["frequency"]?["days"]?.array?.compactMap { number($0) }.map { Int($0) } ?? [],
            enabled: entity?.state == "on",
            entityId: entityId,
            name: entity?.attributes["friendly_name"]?.string.flatMap { $0.isEmpty ? nil : $0 },
            runTimeMinutes: runTimes.lazy.compactMap { number($0["run_time"]) }.first.map { Int($0) },
            stationIds: stations,
            startTimes: entity?.attributes["start_times"]?.array?.compactMap(\.string).filter { !$0.isEmpty } ?? []
        )
    }

    static func lastRun(_ entity: EntityState?) -> LastRun {
        LastRun(
            runTimeMinutes: number(entity?.attributes["run_time"]),
            startTime: date(entity?.attributes["start_time"]?.string ?? entity?.state)
        )
    }

    static func zone(_ config: SprinklersConfig.Zone, entity: (String) -> EntityState?, programs: [Program]) -> Zone {
        let valve = entity(config.valveEntityId)
        let available = isAvailable(valve)
        let valveState = valve?.state ?? "unavailable"
        let station = number(valve?.attributes["station"]).map { Int($0) }
        let configured = programs.first { $0.entityId == config.programEntityId }
        let byStation = station.flatMap { station in programs.first { $0.stationIds.contains(station) } }
        let name = valve?.attributes["zone_name"]?.string.flatMap { $0.isEmpty ? nil : $0 }
            ?? valve?.attributes["friendly_name"]?.string.flatMap { $0.isEmpty ? nil : $0 }
            ?? valve?.entityId
            ?? ""
        return Zone(
            available: available,
            config: config,
            lastRun: lastRun(entity(config.historyEntityId)),
            name: name,
            program: byStation ?? configured ?? program(nil, entityId: config.programEntityId),
            watering: available && (valveState == "open" || valveState == "opening")
        )
    }

    /// Parses Home Assistant timestamps (ISO 8601, with or without fractional seconds).
    static func date(_ text: String?) -> Date? { HassDates.iso8601(text) }
}
