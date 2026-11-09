#if DEBUG
import HassCore
import HassDesign
import Observation
import SwiftUI

// MARK: - Fixtures

/// One gallery entry: a device and its own synthetic state (not a copy of the live house).
struct RoomDeviceFixture: Identifiable {
    enum Kind: Equatable {
        case fan(BathroomFanConfig)
        case purifier(AirPurifierConfig)
        case humidifier
        case grill
    }

    var id: String
    var name: String
    var kind: Kind
    var store: EntityStore

    @MainActor
    init(id: String, name: String, kind: Kind, states: [EntityState]) {
        self.id = id
        self.name = name
        self.kind = kind
        store = EntityStore()
        store.replaceAll(states, freshness: .live)
    }

    @MainActor
    static func all(now: Date = Date()) -> [RoomDeviceFixture] {
        // The purifiers come from the house document, which may carry fewer than four: a missing one is left out, never indexed.
        let purifiers = AirPurifierConfig.all
        // The fans and humidifiers likewise come from the document by position: the first fan is off, the second locked with a timer.
        var fixtures: [RoomDeviceFixture] = []
        let fans = BathroomFanConfig.all
        if let fan = fans.first {
            fixtures.append(RoomDeviceFixture(id: "fan-guest", name: "First Bathroom Fan (off)", kind: .fan(fan),
                                              states: fanStates(fan, power: "off", locked: false, pending: false, now: now)))
        }
        if let fan = fans.dropFirst().first {
            fixtures.append(RoomDeviceFixture(id: "fan-master", name: "Second Bathroom Fan (locked, timer)", kind: .fan(fan),
                                              states: fanStates(fan, power: "on", locked: true, pending: true, now: now)))
        }
        if let auto = purifiers.dropFirst(3).first {
            fixtures.append(RoomDeviceFixture(id: "purifier-auto", name: "Office Air Quality (Auto)", kind: .purifier(auto), states: purifierStates(auto, mode: "Auto", percentage: 33)))
        }
        if let manual = purifiers.first {
            fixtures.append(RoomDeviceFixture(id: "purifier-manual", name: "Living Room Air Quality (Manual)", kind: .purifier(manual), states: purifierStates(manual, mode: "Manual", percentage: 66)))
        }
        if HumidifierConfig.all.first != nil {
            fixtures += [
                RoomDeviceFixture(id: "humidifier", name: "Humidifier", kind: .humidifier, states: humidifierStates(power: "on", tankRemoved: false)),
                RoomDeviceFixture(id: "humidifier-fault", name: "Humidifier (tank removed)", kind: .humidifier, states: humidifierStates(power: "on", tankRemoved: true)),
            ]
        }
        fixtures.append(RoomDeviceFixture(id: "grill", name: "Grill", kind: .grill, states: grillStates))
        return fixtures
    }

    private static func entity(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) -> EntityState {
        EntityState(entityId: id, state: state, attributes: attributes)
    }

    static func fanStates(_ fan: BathroomFanConfig, power: String, locked: Bool, pending: Bool, now: Date) -> [EntityState] {
        let deadline = now.addingTimeInterval(12 * 60 + 34)
        return [
            entity(fan.powerEntityId, power),
            entity(fan.lockEntityId, locked ? "on" : "off"),
            entity(fan.pendingEntityId, pending ? "on" : "off"),
            entity(fan.autoUnlockEntityId, pending && locked ? "on" : "off"),
            entity(fan.deadlineEntityId, "2026-10-11 12:00:00", ["timestamp": .number(deadline.timeIntervalSince1970)]),
            // The running timer was started for 15 minutes (the entity's `duration`), so the sheet's bar is mostly full.
            entity(fan.timerEntityId, pending ? "active" : "idle", ["duration": .string("0:15:00")]),
        ]
    }

    static func purifierStates(_ purifier: AirPurifierConfig, mode: String, percentage: Double) -> [EntityState] {
        [
            entity(purifier.pm25EntityId, "3", ["unit_of_measurement": .string("µg/m³")]),
            entity(purifier.aqiEntityId, "12"),
            entity(purifier.modeEntityId, mode, ["options": .array(["Manual", "Sleep", "Auto"].map(JSONValue.string))]),
            entity(purifier.autoModeEntityId, "Default", ["options": .array(["Default", "Quiet", "Efficient"].map(JSONValue.string))]),
            entity(purifier.fanEntityId, "on", ["percentage": .number(percentage)]),
        ]
    }

    static func humidifierStates(power: String, tankRemoved: Bool) -> [EntityState] {
        guard let h = HumidifierConfig.all.first else { return [] }
        return [
            entity(h.powerEntityId, power),
            entity(h.modeEntityId, "Target Humidity"),
            entity(h.mistLevelEntityId, "5.0"),
            entity(h.targetHumidityEntityId, "50.0"),
            entity(h.warmLevelEntityId, "1.0"),
            entity(h.timerMinutesEntityId, "60.0"),
            entity(h.timerRemainingEntityId, "3000"),
            entity(h.displayEntityId, "on"),
            entity(h.currentHumidityEntityId, "41", ["unit_of_measurement": .string("%")]),
            entity(h.currentTemperatureEntityId, "70.2", ["unit_of_measurement": .string("°F")]),
            entity(h.humidifyingEntityId, tankRemoved ? "off" : "on"),
            entity(h.waterLowEntityId, "off"),
            entity(h.tankRemovedEntityId, tankRemoved ? "on" : "off"),
            entity(h.scheduleEnabledEntityId, "on"),
            entity(h.scheduleEntityId, "off"),
            entity(h.vacationModeEntityId, "off"),
        ]
    }

    static var grillStates: [EntityState] {
        let g = GrillConfig.bearGrills
        // One reading per detail, in the document's order; a shorter list gets fewer states.
        let readings: [(String, [String: JSONValue])] = [
            ("165", ["unit_of_measurement": .string("°F")]), ("72", ["unit_of_measurement": .string("%")]), ("off", [:]), ("on", [:]),
        ]
        return [entity(g.stateEntityId, "cooking")]
            + zip(g.details, readings).map { entity($0.entityId, $1.0, $1.1) }
    }
}

// MARK: - Recording caller

/// Records service calls and echoes them into the fixture's store after a short delay, like Home Assistant.
@MainActor
@Observable
final class RoomDeviceGalleryRecorder {
    private(set) var lastCall = "None"

    /// A caller bound to one fixture's store.
    func caller(for store: EntityStore) -> any HassServiceCalling { Caller(recorder: self, store: store) }

    @MainActor
    private final class Caller: HassServiceCalling {
        let recorder: RoomDeviceGalleryRecorder
        let store: EntityStore

        init(recorder: RoomDeviceGalleryRecorder, store: EntityStore) {
            self.recorder = recorder
            self.store = store
        }

        func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
            recorder.lastCall = GalleryServiceRecorder.describe(domain, service, data)
            try? await Task.sleep(for: .milliseconds(400))
            RoomDeviceGalleryEcho.apply(domain, service, data, to: store)
        }
    }
}

/// What Home Assistant would do for each gallery call.
enum RoomDeviceGalleryEcho {
    @MainActor
    static func apply(_ domain: String, _ service: String, _ data: [String: any Sendable], to store: EntityStore) {
        let target = data["entity_id"] as? String
        func set(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) {
            var entity = store.value(id) ?? EntityState(entityId: id, state: state)
            entity.state = state
            entity.attributes.merge(attributes) { _, new in new }
            store.apply([entity])
        }
        func number(_ key: String) -> Double? {
            (data[key] as? Int).map(Double.init) ?? data[key] as? Double
        }
        switch (domain, service) {
        case ("switch", "turn_on"), ("input_boolean", "turn_on"): if let target { set(target, "on") }
        case ("switch", "turn_off"), ("input_boolean", "turn_off"): if let target { set(target, "off") }
        case ("select", "select_option"): if let target, let option = data["option"] as? String { set(target, option) }
        case ("number", "set_value"): if let target, let value = number("value") { set(target, String(value)) }
        case ("fan", "set_percentage"):
            if let target, let value = number("percentage") { set(target, value > 0 ? "on" : "off", ["percentage": .number(value)]) }
        case ("script", let script):
            if let fan = BathroomFanConfig.all.first(where: { $0.scriptService == script }) {
                echoFan(fan, data, set: set, number: number)
            } else if let h = HumidifierConfig.all.first(where: { $0.setLevelScriptService == script }), let level = number("level") {
                set(h.powerEntityId, level > 0 ? "on" : "off")
                if level > 0 { set(h.mistLevelEntityId, String(level)) }
            } else if let h = HumidifierConfig.all.first(where: { $0.applyProfileScriptService == script }) {
                set(h.powerEntityId, "on")
                if let mode = data["mode"] as? String { set(h.modeEntityId, mode) }
            }
        default: break
        }
    }

    @MainActor
    private static func echoFan(_ fan: BathroomFanConfig, _ data: [String: any Sendable],
                                set: (String, String, [String: JSONValue]) -> Void, number: (String) -> Double?) {
        switch data["command"] as? String {
        case "power":
            set(fan.powerEntityId, data["target_power"] as? String ?? "off", [:])
            for id in [fan.pendingEntityId, fan.lockEntityId, fan.autoUnlockEntityId] { set(id, "off", [:]) }
        case "lock":
            let locked = data["locked"] as? Bool ?? false
            set(fan.lockEntityId, locked ? "on" : "off", [:])
        case "timer_start":
            let deadline = Date().addingTimeInterval((number("minutes") ?? 30) * 60)
            set(fan.deadlineEntityId, "2026-10-11 12:00:00", ["timestamp": .number(deadline.timeIntervalSince1970)])
            set(fan.pendingEntityId, "on", [:])
            // The script ends with switch.turn_on, so a timer started on an off fan turns it on.
            set(fan.powerEntityId, "on", [:])
            set(fan.timerEntityId, "active", ["duration": .string(String(format: "0:%02d:00", Int(number("minutes") ?? 30)))])
            set(fan.autoUnlockEntityId, data["auto_unlock"] as? Bool == true ? "on" : "off", [:])
        case "timer_cancel":
            set(fan.pendingEntityId, "off", [:])
            set(fan.autoUnlockEntityId, "off", [:])
        default: break
        }
    }
}

// MARK: - Schedules

/// An in-memory `schedule` helper with two activities.
@MainActor
final class GalleryScheduleStore: HassScheduleStoring {
    private var schedule: HassSchedule

    init(rules: [HumidifierScheduleRule] = GalleryScheduleStore.rules) {
        schedule = HassSchedule(id: HumidifierConfig.all.first?.scheduleId ?? "schedule", name: "Humidifier",
                                icon: "mdi:calendar-clock", days: HumidifierSchedule.days(from: rules))
    }

    static let rules = [
        HumidifierScheduleRule(id: "night", label: "Night", days: [.sunday, .monday, .tuesday, .wednesday, .thursday],
                               start: "22:00", end: "07:00", mode: .sleep, mistLevel: 4, targetHumidity: 50, warmLevel: 0, display: false),
        HumidifierScheduleRule(id: "evening", label: "Evening", days: Weekday.allCases, start: "18:00", end: "21:30",
                               mode: .targetHumidity, mistLevel: 6, targetHumidity: 45, warmLevel: 1, display: true),
    ]

    func listSchedules() async throws -> [HassSchedule] { [schedule] }

    func updateSchedule(_ message: [String: JSONValue]) async throws -> HassSchedule {
        try? await Task.sleep(for: .milliseconds(300))
        var saved = message
        saved["id"] = message["schedule_id"]
        schedule = HassSchedule(json: .object(saved)) ?? schedule
        return schedule
    }

    func userIsAdmin() async throws -> Bool { true }
}
#endif
