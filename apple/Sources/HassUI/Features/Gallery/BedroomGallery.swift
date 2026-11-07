#if DEBUG
import HassCore
import HassDesign
import Observation
import SwiftUI

// MARK: - Recorder

/// Records calls and answers like Home Assistant: wake-light and Solo Trip commands return `accepted` with a new
/// revision, and the fixture state follows each call after a short delay.
@MainActor
@Observable
final class BedroomGalleryRecorder: HassServiceResponding {
    private(set) var lastCall = "None"
    @ObservationIgnored private let store: EntityStore

    init(store: EntityStore) { self.store = store }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        lastCall = GalleryServiceRecorder.describe(domain, service, data)
        try? await Task.sleep(for: .milliseconds(300))
        echo(domain, service, JSONValue(any: data as [String: Any]))
    }

    func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        lastCall = GalleryServiceRecorder.describe(domain, service, data)
        try? await Task.sleep(for: .milliseconds(300))
        let value = JSONValue(any: data as [String: Any])
        if domain == "wake_light" { return .object(["response": .object(["outcome": "accepted", "revision": .number(Double(wakeCommand(value)))])]) }
        soloCommand(value)
        return .object(["response": .object(["outcome": "accepted"])])
    }

    // MARK: Echo

    private func update(_ id: String, _ change: (inout EntityState) -> Void) {
        var entity = store.value(id) ?? EntityState(entityId: id, state: "unknown")
        change(&entity)
        store.apply([entity])
    }

    private func set(_ id: String, _ state: String) { update(id) { $0.state = state } }

    private func echo(_ domain: String, _ service: String, _ data: JSONValue) {
        let entityId = data["entity_id"]?.string ?? ""
        switch (domain, service) {
        case ("input_number", "set_value"):
            if let value = data["value"]?.number { set(entityId, String(value)) }
        case ("mqtt", "publish"):
            guard let text = data["payload"]?.string, let payload = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else { return }
            mergeSchedule(payload)
        case ("button", "press"):
            guard let bed = MasterBedroom.beds.first(where: { $0.alarmSnoozeButtonEntityId == entityId || $0.alarmStopButtonEntityId == entityId }) else { return }
            alarm(bed, snooze: bed.alarmSnoozeButtonEntityId == entityId)
        case ("input_button", "press"):
            guard let bed = MasterBedroom.beds.first(where: { $0.hotFlashButtonEntityId == entityId || $0.hotFlashCancelButtonEntityId == entityId }) else { return }
            hotFlash(bed, on: bed.hotFlashButtonEntityId == entityId)
        case ("script", MasterBedroom.hotFlashBrokerScript):
            guard let side = data["side"]?.string.flatMap(BedSide.init(rawValue:)) else { return }
            set(MasterBedroom.bed(side).climateEntityId, data["action"]?.string == "power_off" ? "off" : "auto")
        case ("script", _):
            guard let bed = MasterBedroom.beds.first(where: { service == $0.tonightScript || service == $0.outsideScheduleScript }),
                  let level = data["level"]?.number else { return }
            set(bed.targetLevelEntityId, String(level))
        default: break
        }
    }

    private func alarm(_ bed: BedSideConfig, snooze: Bool) {
        update(bed.alarmStateEntityId) {
            $0.state = snooze ? "snoozed" : "idle"
            $0.attributes["snoozed_until"] = snooze ? .number(Date.now.timeIntervalSince1970 + 300) : nil
        }
    }

    private func hotFlash(_ bed: BedSideConfig, on: Bool) {
        set(bed.hotFlashActiveEntityId, on ? "on" : "off")
        update(bed.hotFlashTimerEntityId) {
            $0.state = on ? "active" : "idle"
            $0.attributes["finishes_at"] = on ? .string(ISO8601DateFormatter().string(from: .now.addingTimeInterval(900))) : nil
        }
        if on { set(bed.climateEntityId, "auto") }
    }

    private func mergeSchedule(_ payload: JSONValue) {
        update(MasterBedroom.scheduleEntityId) { entity in
            for side in BedSide.allCases {
                guard case let .object(days)? = payload[side.rawValue] else { continue }
                var sideValue: [String: JSONValue] = if case let .object(value)? = entity.attributes[side.rawValue] { value } else { [:] }
                for (day, value) in days {
                    var dayValue: [String: JSONValue] = if case let .object(existing)? = sideValue[day] { existing } else { [:] }
                    if case let .object(changes) = value { for (key, change) in changes { dayValue[key] = change } }
                    sideValue[day] = .object(dayValue)
                }
                entity.attributes[side.rawValue] = .object(sideValue)
            }
        }
    }

    /// Applies a `wake_light.command` to the status sensor and returns the new revision.
    private func wakeCommand(_ data: JSONValue) -> Int {
        var revision = 0
        update(MasterBedroom.wakeLight.statusEntityId) { entity in
            var attributes = entity.attributes
            revision = Int(attributes["revision"]?.number ?? 0) + 1
            attributes["revision"] = .number(Double(revision))
            var alarms = attributes["alarms"]?.array ?? []
            switch data["operation"]?.string {
            case "upsert_alarm":
                guard case var .object(alarm)? = data["alarm"] else { break }
                alarm["revision"] = .number((alarm["revision"]?.number ?? 0) + 1)
                if let index = alarms.firstIndex(where: { $0["id"] == alarm["id"] }) { alarms[index] = .object(alarm) } else { alarms.append(.object(alarm)) }
            case "delete_alarm":
                alarms.removeAll { $0["id"] == data["alarm_id"] }
            case "link_alarm":
                var links: [String: JSONValue] = if case let .object(value)? = attributes["alarm_links"] { value } else { [:] }
                for key in data["link_keys"]?.array ?? [] { if let key = key.string { links[key] = data["enabled"] ?? .bool(true) } }
                attributes["alarm_links"] = .object(links)
            case "update_defaults":
                if let defaults = data["defaults"] { attributes["defaults"] = defaults }
            case "end_episode":
                attributes["active_occurrences"] = .array([])
                attributes["episode_ref"] = .null
                attributes["commanded_brightness_pct"] = .number(0)
                entity.state = "idle"
            default: break
            }
            attributes["alarms"] = .array(alarms)
            entity.attributes = attributes
        }
        return revision
    }

    /// Applies a Household Away `sleepypod_command` to both sides.
    private func soloCommand(_ data: JSONValue) {
        let level = data["level"]?.number
        for bed in MasterBedroom.beds {
            switch data["action"]?.string {
            case "set_power": set(bed.climateEntityId, data["enabled"]?.bool == true ? "auto" : "off")
            case "set_outside_level", "set_tonight_level": if let level { set(bed.targetLevelEntityId, String(level)) }
            case "set_stage_level":
                if let level, let phase = data["phase"]?.string.flatMap(SchedulePhase.init(rawValue:)), let id = bed.stageLevelEntityIds[phase] { set(id, String(level)) }
            case "snooze_alarm": alarm(bed, snooze: true)
            case "stop_alarm": alarm(bed, snooze: false)
            case "replace_alarms":
                let rows = data["alarm_rows"]?.array ?? []
                var days: [String: JSONValue] = [:]
                for day in Weekday.allCases {
                    days[day.rawValue] = .object(["alarms": .array(rows.filter { $0["day"]?.string == day.rawValue }.map { row in
                        guard case var .object(fields) = row else { return row }
                        fields["day"] = nil
                        return .object(fields)
                    })])
                }
                mergeSchedule(.object([bed.side.rawValue: .object(days)]))
            default: break
            }
        }
    }
}

// MARK: - Fixtures

/// Synthetic Master Bedroom state for the gallery and hosted tests (not a copy of the live house).
enum BedroomFixtures {
    enum Scenario: String, CaseIterable {
        case `default`, ringing, unavailable, waking
        case soloTrip = "solo-trip"
        case hotFlash = "hot-flash"
    }

    static func states(_ scenario: Scenario, now: Date = .now) -> [EntityState] {
        func entity(_ id: String, _ state: String, _ attributes: [String: JSONValue] = [:]) -> EntityState {
            EntityState(entityId: id, state: state, attributes: attributes)
        }
        let levelRange: [String: JSONValue] = ["min": .number(-10), "max": .number(10), "step": .number(1)]
        var states: [EntityState] = []
        for bed in MasterBedroom.beds {
            let left = bed.side == .left
            let available = scenario != .unavailable
            states += [
                entity(bed.climateEntityId, available ? "auto" : "unavailable", ["current_temperature": .number(left ? 86.5 : 79.0), "temperature": .number(left ? 90.75 : 74.25)]),
                entity(bed.targetLevelEntityId, available ? (left ? "3.0" : "-3.0") : "unavailable", levelRange),
                entity(bed.schedulePhaseEntityId, left ? "asleep" : "outside"),
                entity(bed.stageLevelEntityIds[.bedtime]!, left ? "4.0" : "-2.0", levelRange),
                entity(bed.stageLevelEntityIds[.asleep]!, left ? "3.0" : "-3.0", levelRange),
                entity(bed.stageLevelEntityIds[.dawn]!, left ? "1.0" : "-1.0", levelRange),
                entity(bed.alarmStateEntityId, scenario == .ringing && left ? "ringing" : "idle"),
                entity(bed.hotFlashActiveEntityId, scenario == .hotFlash && !left ? "on" : "off"),
                entity(bed.hotFlashTimerEntityId, scenario == .hotFlash && !left ? "active" : "idle",
                       scenario == .hotFlash && !left ? ["finishes_at": .string(ISO8601DateFormatter().string(from: now.addingTimeInterval(612)))] : [:]),
                entity(bed.hotFlashRestoreAtEntityId, "unknown"),
                entity(bed.heartRateEntityId, left ? "58" : "62", ["unit_of_measurement": "bpm"]),
                entity(bed.breathingRateEntityId, left ? "14" : "15", ["unit_of_measurement": "br/min"]),
                entity(bed.hrvEntityId, left ? "48" : "52", ["unit_of_measurement": "ms"]),
                entity(bed.pumpLoopTemperatureEntityId, left ? "91.2" : "73.8", ["unit_of_measurement": "°F"]),
                entity(bed.pumpRpmEntityId, left ? "2140" : "1980", ["unit_of_measurement": "rpm"]),
                entity(bed.pumpClogEntityId, "off"),
                entity(bed.pumpStallEntityId, "off"),
            ]
        }
        states.append(entity(MasterBedroom.scheduleEntityId, "ok", schedule))
        states.append(entity(MasterBedroom.householdAwayEntityId, scenario == .soloTrip ? "active" : "idle", scenario == .soloTrip ? [
            "contract_version": .number(1), "mode": "solo_trip", "traveler": "sam", "home_resident": "alex", "revision": .number(4),
            "command_available": true,
            "effects": .object(["wake_light_source": true, "sleepypod_schedule": true, "sleepypod_live_follow": true]),
        ] : ["contract_version": .number(1), "mode": "none", "revision": .number(3), "command_available": true]))
        states.append(wakeLight(scenario, now: now))
        return states
    }

    static var schedule: [String: JSONValue] {
        func alarm(_ time: String, enabled: Bool = true) -> JSONValue {
            .object(["time": .string(time), "enabled": .bool(enabled), "alarmTemperature": .number(82), "duration": .number(300),
                     "vibrationIntensity": .number(100), "vibrationPattern": "rise"])
        }
        func side(_ times: [Weekday: [JSONValue]]) -> JSONValue {
            .object(Dictionary(Weekday.allCases.map { day in
                (day.rawValue, JSONValue.object([
                    "power": .object(["on": "21:30", "off": "09:00", "enabled": true, "onTemperature": .number(93)]),
                    "temperatures": .object(["01:00": .number(91), "05:00": .number(86)]),
                    "alarms": .array(times[day] ?? []),
                ]))
            }, uniquingKeysWith: { first, _ in first }))
        }
        var left: [Weekday: [JSONValue]] = [:]
        for day in Weekday.workdays { left[day] = [alarm("06:30")] }
        left[.saturday] = [alarm("08:00", enabled: false), alarm("09:15")]
        var right: [Weekday: [JSONValue]] = [:]
        for day in [Weekday.monday, .wednesday, .friday] { right[day] = [alarm("07:15")] }
        return ["left": side(left), "right": side(right)]
    }

    static func wakeLight(_ scenario: Scenario, now: Date) -> EntityState {
        let waking = scenario == .waking
        let iso = ISO8601DateFormatter()
        var attributes: [String: JSONValue] = [
            "contract_version": .number(6), "command_available": true, "profile_id": "master_bedroom", "revision": .number(12),
            "defaults": .object(["ramp_minutes": .number(30), "post_wake_hold_minutes": .number(10)]),
            "safety": .object(["vacation_state": "off"]),
            "alarm_links": .object(["sleepypod:right#monday#07:15": false]),
            "current_blockers": .array([]),
            "next_wake_at": .string(iso.string(from: now.addingTimeInterval(9 * 3600))),
            "next_ramp_minutes": .number(30),
            "alarms": .array([
                .object(["id": "weekday", "label": "Weekday Wake", "kind": "weekly", "local_time": "06:45",
                         "weekdays": .array(Weekday.workdays.map { .string($0.rawValue) }), "enabled": true, "ramp_minutes": .number(30),
                         "revision": .number(2), "source": "native", "bed_sides": .array([])]),
                .object(["id": "weekend", "label": "Weekend Sleep-In", "kind": "weekly", "local_time": "08:30",
                         "weekdays": .array([.string("saturday"), .string("sunday")]), "enabled": false, "ramp_minutes": .number(15),
                         "revision": .number(1), "source": "native", "bed_sides": .array([])]),
                .object(["id": "sleepypod-left", "label": "Alex's Alarm", "kind": "weekly", "local_time": "06:30",
                         "weekdays": .array(Weekday.workdays.map { .string($0.rawValue) }), "enabled": true, "ramp_minutes": .number(30),
                         "revision": .number(1), "source": "sleepypod", "source_ref": "sleepypod:left", "bed_sides": .array([])]),
                .object(["id": "sleepypod-right", "label": "Sam's Alarm", "kind": "weekly", "local_time": "07:15",
                         "weekdays": .array([.string("monday"), .string("wednesday"), .string("friday")]), "enabled": true,
                         "ramp_minutes": .number(30), "revision": .number(1), "source": "sleepypod", "source_ref": "sleepypod:right",
                         "bed_sides": .array([])]),
            ]),
        ]
        if waking {
            attributes["active_occurrences"] = .array([.object(["occurrence_id": "occ-1", "alarm_id": "weekday", "phase": "ramping",
                                                                "progress": .number(42), "wake_at": .string(iso.string(from: now.addingTimeInterval(17 * 60)))])])
            attributes["episode_ref"] = "episode-1"
            attributes["commanded_brightness_pct"] = .number(42)
        }
        return EntityState(entityId: MasterBedroom.wakeLight.statusEntityId, state: waking ? "ramping" : "scheduled", attributes: attributes)
    }
}
#endif
