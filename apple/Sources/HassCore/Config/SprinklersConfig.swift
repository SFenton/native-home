import Foundation

/// The Sprinklers page (web route `/at-a-glance/sprinklers`): the two Orbit B-hyve faucet controllers.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/sprinklers.ts`; copy from
/// `src/i18n/locales/en/pages/sprinklers.json`. State reading is in ``SprinklerSnapshot``.
public enum SprinklersConfig {
    /// One watering zone (a valve, its program switch and its history sensor).
    public struct Zone: Hashable, Sendable, Codable {
        public var historyEntityId: String
        public var programEntityId: String
        public var valveEntityId: String
    }

    /// One B-hyve controller.
    public struct Controller: Hashable, Sendable, Identifiable, Codable {
        public var id: String
        public var title: String
        public var batteryEntityId: String
        public var faultEntityId: String
        public var hubConnectedEntityId: String
        public var modeEntityId: String
        public var nextWateringEntityId: String
        public var rainDelayEntityId: String
        public var smartWateringEntityId: String
        public var stateEntityId: String
        public var zones: [Zone]
    }

    /// Shows the Sprinklers link on Home (web Quick Access `visibilityEntityId`): the server's document, else empty.
    public static var visibilityEntityId: String { HouseConfigSource.active.read { $0.sprinklers.visibilityEntityId } ?? "" }
    /// At or below this battery percent the controller warns.
    public static var lowBatteryPercent: Double { HouseConfigSource.active.read { $0.sprinklers.lowBatteryPercent } ?? 0 }
    /// Manual run time stepper (minutes).
    public static let manualRunTime = (default: 15, min: 1, max: 60)
    /// One-tap run times beside the stepper (minutes; owner, 2026-10-24), so the usual values do not take up to 45 taps.
    public static let manualRunPresets = [5, 10, 15, 30, 60]
    /// Watering budget stepper (percent).
    public static let budgetRange = (min: 0, max: 200, step: 5)
    /// A new start time's default.
    public static var defaultStartTime: String { HouseConfigSource.active.read { $0.sprinklers.defaultStartTime } ?? "" }
    /// Optimistic values give way after this long (SprinklerController.tsx `OPTIMISTIC_REVERT_MS`).
    public static let optimisticRevert: Duration = .seconds(10)



    /// Every controller, in page order (SprinklersPage.tsx): the server's document.
    public static var controllers: [Controller] { HouseConfigSource.active.read { $0.sprinklers.controllers } ?? [] }

    // MARK: - Service calls (SprinklerController.tsx)

    /// Waters a zone for `minutes`.
    public static func startWatering(valve: String, minutes: Int) -> ServiceCall {
        ServiceCall("bhyve", "start_watering", data: ["entity_id": .string(valve), "minutes": .number(Double(minutes))])
    }

    /// Stops watering on a valve.
    public static func stopWatering(valve: String) -> ServiceCall {
        ServiceCall("bhyve", "stop_watering", data: ["entity_id": .string(valve)])
    }

    /// Runs a program now.
    public static func startProgram(_ program: String) -> ServiceCall {
        ServiceCall("bhyve", "start_program", data: ["entity_id": .string(program)])
    }

    /// Turns a switch (rain delay, smart watering or a program) on or off.
    public static func setSwitch(_ entityId: String, on: Bool) -> ServiceCall {
        ServiceCall("switch", on ? "turn_on" : "turn_off", target: entityId)
    }

    /// Saves a program's days (0 = Sunday), start times (`HH:mm`) and budget.
    public static func updateProgram(_ program: String, days: [Int], startTimes: [String], budget: Int) -> ServiceCall {
        ServiceCall("bhyve", "update_program", data: [
            "budget": .number(Double(budget)),
            "entity_id": .string(program),
            "frequency": .object(["days": .array(days.map { .number(Double($0)) }), "type": .string("days")]),
            "start_times": .array(startTimes.map(JSONValue.string)),
        ])
    }
}
