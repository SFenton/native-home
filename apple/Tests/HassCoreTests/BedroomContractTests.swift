import Foundation
import HassTestSupport
@preconcurrency import HAKit
@preconcurrency import HAKit_Mocks
@testable import HassCore
import Testing

// Pure parsing and formatting for the Master Bedroom devices, mirroring the web's wakeLightContract,
// bedAlarmProvisioning, householdAwayContract (bed scope) and sleepypod helper tests.

/// A UTC Gregorian calendar so dates don't depend on the machine.
let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

func wakeStatus(state: String = "scheduled", _ extra: [String: JSONValue] = [:]) -> EntityState {
    var attributes: [String: JSONValue] = [
        "contract_version": .number(6), "command_available": true, "profile_id": "master_bedroom", "revision": .number(7),
        "defaults": .object(["ramp_minutes": .number(15), "post_wake_hold_minutes": .number(10)]),
        "safety": .object(["vacation_state": "off"]),
        "alarms": .array([
            .object(["id": "a", "label": "Weekday", "kind": "weekly", "local_time": "06:45",
                     "weekdays": ["monday", "tuesday"], "enabled": true, "ramp_minutes": .number(30), "revision": .number(2)]),
            .object(["id": "b", "label": "Alex's Alarm", "kind": "weekly", "local_time": "06:30", "weekdays": ["monday"],
                     "source": "sleepypod", "source_ref": "sleepypod:left", "revision": .number(1)]),
        ]),
    ]
    for (key, value) in extra { attributes[key] = value }
    return EntityState(entityId: MasterBedroom.wakeLight.statusEntityId, state: state, attributes: attributes)
}

@Suite("Wake light contract", .demoHouse)
struct WakeLightContractTests {
    @Test func parsesTheStatusSensor() {
        let snapshot = WakeLight.snapshot(wakeStatus(), profileId: "fallback")
        #expect(snapshot.available)
        #expect(snapshot.compatible)
        #expect(snapshot.profileId == "master_bedroom")
        #expect(snapshot.revision == 7)
        #expect(snapshot.defaults == WakeLight.Defaults(rampMinutes: 15, postWakeHoldMinutes: 10))
        #expect(snapshot.alarms.map(\.id) == ["a", "b"])
        #expect(snapshot.alarms[0].weekdays == [.monday, .tuesday])
        #expect(snapshot.alarms[1].isNative == false)
        #expect(snapshot.alarms[1].sourceRef == "sleepypod:left")
        #expect(snapshot.phase == .scheduled)
    }

    @Test(arguments: [("ramping", true), ("holding", true), ("snoozed", true), ("scheduled", false), ("idle", false),
                      ("blocked_vacation", false), ("recovering", false), ("unavailable", false)])
    func theTileFillsOnlyWhileAWakeRuns(state: String, fills: Bool) {
        #expect(WakeLight.fillsTile(statusState: state) == fills)
        #expect(WakeLight.fillsTile(WakeLight.snapshot(wakeStatus(state: state), profileId: "x")) == fills)
    }

    @Test func theTileNeverFillsWithoutAStatusOrWhenUnavailable() {
        #expect(!WakeLight.fillsTile(statusState: nil))
        #expect(!WakeLight.fillsTile(statusState: "garbage"))
        #expect(!WakeLight.fillsTile(WakeLight.snapshot(wakeStatus(state: "ramping", ["command_available": false]), profileId: "x")))
    }

    @Test func isUnavailableWithoutCommandsOrSupportedContract() {
        #expect(!WakeLight.snapshot(wakeStatus(["command_available": false]), profileId: "x").available)
        let old = WakeLight.snapshot(wakeStatus(["contract_version": .number(3)]), profileId: "x")
        #expect(!old.available && !old.compatible)
        #expect(!WakeLight.snapshot(wakeStatus(state: "unavailable"), profileId: "x").available)
        #expect(!WakeLight.snapshot(nil, profileId: "x").available)
        #expect(WakeLight.snapshot(nil, profileId: "x").profileId == "x")
    }

    @Test func dropsMalformedAlarms() {
        let snapshot = WakeLight.snapshot(wakeStatus(["alarms": .array([
            .object(["id": "no-days", "label": "X", "kind": "weekly", "local_time": "06:00", "weekdays": []]),
            .object(["id": "bad-time", "label": "X", "kind": "once", "local_time": "25:00", "date": "2026-10-12"]),
            .object(["id": "no-date", "label": "X", "kind": "once", "local_time": "06:00"]),
            .object(["id": "", "label": "X", "kind": "weekly", "local_time": "06:00", "weekdays": ["monday"]]),
            .object(["id": "ok", "label": "X", "kind": "once", "local_time": "06:00", "date": "2026-10-12", "ramp_minutes": .number(99),
                     "bed_sides": ["right", "left", "middle"]]),
        ])]), profileId: "x")
        #expect(snapshot.alarms.map(\.id) == ["ok"])
        #expect(snapshot.alarms[0].rampMinutes == 60)
        #expect(snapshot.alarms[0].bedSides == [.left, .right])
    }

    @Test func readsOnlyFalseLinksAsUnlinked() {
        let snapshot = WakeLight.snapshot(wakeStatus(["alarm_links": .object(["k1": false, "k2": true, "k3": "no"])]), profileId: "x")
        #expect(snapshot.unlinkedKeys == ["k1"])
        #expect(!snapshot.isLinked("k1"))
        #expect(snapshot.isLinked("k2"))
        #expect(snapshot.isLinked(snapshot.alarms[1], calendar: utc))
    }

    @Test func linkKeysCoverMirroredDays() {
        let snapshot = WakeLight.snapshot(wakeStatus(), profileId: "x")
        #expect(snapshot.alarms[1].linkKeys(calendar: utc) == ["sleepypod:left#monday#06:30"])
        #expect(snapshot.alarms[0].linkKeys(calendar: utc).isEmpty)
        var once = snapshot.alarms[1]
        once.kind = .once
        once.date = "2026-10-11"
        #expect(once.linkDays(calendar: utc) == [.sunday])
    }

    @Test func subtitleFollowsTheWebOrder() {
        func subtitle(_ entity: EntityState, modal: Bool = false) -> String {
            WakeLight.subtitle(WakeLight.snapshot(entity, profileId: "x"), modal: modal, calendar: utc)
        }
        #expect(subtitle(wakeStatus(["command_available": false])) == "Setup · Unavailable")
        #expect(subtitle(wakeStatus(state: "recovering")) == "Waiting to Resume")
        #expect(subtitle(wakeStatus(state: "ramping", ["commanded_brightness_pct": .number(41.6)])) == "Active • 42%")
        #expect(subtitle(wakeStatus(["alarms": .array([])])) == "Alarms · None Enabled")
        #expect(subtitle(wakeStatus(["alarms": .array([])]), modal: true) == "No Active Wake-Light Alarms")
        #expect(subtitle(wakeStatus(["safety": .object(["vacation_state": "on"])])) == "Vacation Mode · Runs Blocked")
        #expect(subtitle(wakeStatus(["current_blockers": ["pbl_not_ready"]])) == "Execution Blocked")
        #expect(subtitle(wakeStatus(["next_wake_at": "2026-10-12T06:45:00Z", "next_ramp_minutes": .number(30)]))
            == "Next Alarm: 10/12 6:45 AM • 30 min ramp")
        #expect(subtitle(wakeStatus(["next_wake_at": "2026-10-12T06:45:00Z"])) == "Next Alarm: 10/12 6:45 AM")
        #expect(subtitle(wakeStatus()) == "Idle")
    }

    @Test func validatesDrafts() {
        let now = utc.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 12))!
        var alarm = WakeLight.Alarm.new(id: "n", now: now, calendar: utc)
        #expect(alarm.date == "2026-10-12")
        #expect(WakeLight.problems(alarm, now: now, calendar: utc).isEmpty)
        alarm.label = " "
        alarm.localTime = "7:00"
        alarm.rampMinutes = 7
        alarm.date = "2026-10-10"
        #expect(WakeLight.problems(alarm, now: now, calendar: utc) == [
            "Wake alarm name is required. Enter a name.", "Wake time is invalid. Choose a valid time.",
            "Choose a supported light ramp duration before saving.", "A one-time alarm requires a future date.",
        ])
        alarm = WakeLight.Alarm(id: "w", label: "W", kind: .weekly, localTime: "07:00")
        #expect(WakeLight.problems(alarm, now: now, calendar: utc) == ["A recurring alarm requires at least one weekday."])
    }

    @Test func buildsCommandData() {
        let snapshot = WakeLight.snapshot(wakeStatus(state: "ramping", ["episode_ref": "ep-1"]), profileId: "x")
        let upsert = WakeLight.serviceData(.upsert(snapshot.alarms[0]), snapshot: snapshot, requestId: "r1")
        #expect(upsert["operation"] as? String == "upsert_alarm")
        #expect(upsert["profile_id"] as? String == "master_bedroom")
        #expect(upsert["expected_revision"] as? Int == 7)
        #expect(upsert["request_id"] as? String == "r1")
        let alarm = upsert["alarm"] as? [String: any Sendable]
        #expect(alarm?["weekdays"] as? [String] == ["monday", "tuesday"])
        #expect(alarm?["date"] == nil)
        let link = WakeLight.serviceData(.link(keys: ["k"], enabled: false), snapshot: snapshot, requestId: "r2")
        #expect(link["link_keys"] as? [String] == ["k"])
        #expect(link["enabled"] as? Bool == false)
        let end = WakeLight.serviceData(.endEpisode, snapshot: snapshot, requestId: "r3")
        #expect(end["episode_ref"] as? String == "ep-1")
        let defaults = WakeLight.serviceData(.updateDefaults(.standard), snapshot: snapshot, requestId: "r4")
        #expect((defaults["defaults"] as? [String: any Sendable])?["ramp_minutes"] as? Int == 30)
        #expect(WakeLight.Command.delete(alarmId: "a").pendingKeys == ["alarm:a"])
        #expect(WakeLight.Command.link(keys: ["x", "y"], enabled: true).pendingKeys == ["link:x", "link:y"])
    }

    @Test func formatsSchedules() {
        let weekdays = WakeLight.Alarm(id: "a", label: "A", kind: .weekly, localTime: "06:05", weekdays: Weekday.workdays)
        #expect(WakeLight.scheduleLabel(weekdays) == "Weekdays")
        var other = weekdays
        other.weekdays = [.saturday, .sunday]
        #expect(WakeLight.scheduleLabel(other) == "Weekends")
        other.weekdays = Weekday.allCases
        #expect(WakeLight.scheduleLabel(other) == "Every Day")
        other.weekdays = [.wednesday, .monday]
        #expect(WakeLight.scheduleLabel(other) == "Mon, Wed")
        #expect(WakeLight.displayTime("18:30") == "6:30 PM")
        #expect(WakeLight.rampLabel(0) == "None")
        #expect(WakeLight.durationLabel(15) == "15 Minutes")
        #expect(WakeLight.errorMessage("transport").contains("did not confirm"))
        #expect(WakeLight.blockerMessage("vacation_not_off") == "Vacation Mode · Runs Blocked")
    }

    @Test func readsCommandOutcomes() {
        #expect(CommandOutcome(response: .object(["response": .object(["outcome": "accepted", "revision": .number(9)])]))
            == .accepted(noChange: false, revision: 9))
        #expect(CommandOutcome(response: .object(["status": "no_change"])) == .accepted(noChange: true, revision: nil))
        #expect(CommandOutcome(response: .object(["outcome": "rejected", "error_code": "revision_conflict", "conflict": "alarm_revision"]))
            == .rejected(code: "revision_conflict", alarmConflict: true, revision: nil))
        #expect(CommandOutcome(response: .object(["outcome": "rejected"])) == .rejected(code: "rejected", alarmConflict: false, revision: nil))
        #expect(CommandOutcome(response: .object([:])) == nil)
        #expect(CommandOutcome(response: nil) == nil)
        #expect(CommandOutcome(response: .object(["outcome": "accepted"]))?.isAccepted == true)
    }
}

@Suite("Bed alarm provisioning")
struct BedAlarmProvisioningTests {
    let alarms = [BedAlarm.new(day: .monday, time: "07:00", id: "m"), BedAlarm.new(day: .tuesday, time: "07:00", id: "t")]

    @Test func createsMissingAlarmsAndLinksWhenOn() {
        let snapshot = WakeLight.snapshot(wakeStatus(["alarm_links": .object(["sleepypod:left#tuesday#07:00": false])]), profileId: "x")
        let plan = BedAlarmProvisioning.plan(snapshot: snapshot, days: [.wednesday, .monday, .tuesday], linked: true,
                                             alarms: alarms, source: "sleepypod:left", time: "7:00")
        #expect(plan?.createDays == [.wednesday])
        #expect(plan?.linkKeysOn == ["sleepypod:left#tuesday#07:00"])
        #expect(plan?.linkKeysOff == [])
    }

    @Test func unlinksExistingAlarmsWhenOff() {
        let snapshot = WakeLight.snapshot(wakeStatus(), profileId: "x")
        let plan = BedAlarmProvisioning.plan(snapshot: snapshot, days: [.monday, .friday], linked: false,
                                             alarms: alarms, source: "sleepypod:left", time: "07:00")
        #expect(plan?.createDays == [])
        #expect(plan?.linkKeysOff == ["sleepypod:left#monday#07:00"])
        #expect(BedAlarmProvisioning.plan(snapshot: snapshot, days: [.monday], linked: true, alarms: alarms, source: "", time: "07:00") == nil)
        #expect(BedAlarmProvisioning.plan(snapshot: snapshot, days: [.monday], linked: true, alarms: alarms, source: "s", time: "bad") == nil)
        #expect(BedAlarmProvisioning.Plan().isEmpty)
        #expect(BedAlarmProvisioning.days(of: alarms, at: "07:00") == [.monday, .tuesday])
    }
}

@Suite("Solo Trip bed scope", .demoHouse)
struct HouseholdAwayBedScopeTests {
    func away(_ state: String, effects: Bool = true, home: String = "alex") -> EntityState {
        EntityState(entityId: MasterBedroom.householdAwayEntityId, state: state, attributes: [
            "mode": "solo_trip", "traveler": "sam", "home_resident": .string(home), "revision": .number(5),
            "effects": .object(["wake_light_source": .bool(effects), "sleepypod_schedule": true, "sleepypod_live_follow": true]),
        ])
    }

    @Test func homeResidentControlsTheWholeBed() {
        let scope = HouseholdAwayBedScope(entity: away("active"), owner: .resident1)
        #expect(scope.engaged && scope.controlsWholeBed && scope.interactive && !scope.readOnly)
        #expect(scope.revision == 5)
        #expect(scope.notice?.title == "Sam Away")
        let data = scope.commandData(action: "set_power", side: .left, extra: ["enabled": true], requestId: "r")
        #expect(data["operation"] as? String == "sleepypod_command")
        #expect(data["expected_revision"] as? Int == 5)
        #expect(data["enabled"] as? Bool == true)
    }

    @Test func travelerSideIsReadOnly() {
        let scope = HouseholdAwayBedScope(entity: away("active"), owner: .resident2)
        #expect(scope.readOnly && !scope.interactive)
        #expect(scope.notice?.message.contains("Alex's bed side") == true)
    }

    @Test func unconfirmedEffectsAreReadOnlyForBoth() {
        let scope = HouseholdAwayBedScope(entity: away("activating", effects: false), owner: .resident1)
        #expect(scope.engaged && scope.readOnly)
    }

    @Test func noTripWhenIdleScheduledOrOtherMode() {
        #expect(!HouseholdAwayBedScope(entity: away("scheduled"), owner: .resident1).engaged)
        #expect(!HouseholdAwayBedScope(entity: nil, owner: .resident1).engaged)
        let vacation = EntityState(entityId: "x", state: "active", attributes: ["mode": "vacation"])
        #expect(!HouseholdAwayBedScope(entity: vacation, owner: .resident1).engaged)
        #expect(HouseholdAwayBedScope.noTrip.interactive)
        #expect(HouseholdAwayBedScope.noTrip.notice == nil)
    }
}

@Suite("SleepyPod schedule")
struct SleepypodScheduleTests {
    static let attributes: [String: JSONValue] = [
        "left": .object([
            "monday": .object([
                "alarms": .array([
                    .object(["time": "07:30", "enabled": true]),
                    .object(["time": "06:00", "enabled": false, "vibrationPattern": "double"]),
                    .object(["time": "nope"]),
                ]),
                "power": .object(["on": "22:00", "off": "08:00", "enabled": true]),
                "temperatures": .object(["23:00": .number(90), "04:00": .number(80)]),
            ]),
            "tuesday": .object(["alarm": .object(["time": "06:15", "enabled": true])]),
        ]),
    ]

    @Test func parsesAlarmsInDisplayOrder() throws {
        let schedule = try #require(SleepypodSchedule(attributes: Self.attributes))
        #expect(schedule.has(.left) && !schedule.has(.right))
        let alarms = schedule.alarms(.left)
        #expect(alarms.map(\.time) == ["06:00", "07:30", "06:15"])
        #expect(alarms[0].vibrationPattern == "double")
        #expect(!alarms[0].enabled)
        #expect(SleepypodSchedule(attributes: [:]) == nil)
        #expect(SleepypodSchedule(attributes: nil) == nil)
    }

    @Test func buildsAlarmPayloadForEveryDay() {
        let payload = SleepypodSchedule.alarmPayload([BedAlarm.new(day: .friday, time: "07:00", id: "f")], side: .right)
        #expect(payload["right"]?["friday"]?["alarms"]?.array?.count == 1)
        #expect(payload["right"]?["monday"]?["alarms"]?.array?.isEmpty == true)
        #expect(payload["right"]?["friday"]?["alarms"]?.array?.first?["vibrationPattern"] == "rise")
    }

    @Test func buildsStagePayloadKeepingTimes() throws {
        let schedule = try #require(SleepypodSchedule(attributes: Self.attributes))
        let payload = schedule.stagePayload(side: .left, levels: [.bedtime: 4, .asleep: 2, .dawn: -2])
        let monday = payload["left"]?["monday"]
        #expect(monday?["power"]?["on"] == "22:00")
        #expect(monday?["power"]?["onTemperature"] == .number(94))
        #expect(monday?["temperatures"]?["23:00"] == .number(88))
        #expect(monday?["temperatures"]?["04:00"] == .number(77))
        #expect(monday?["alarms"]?.array?.count == 2)
        let wednesday = payload["left"]?["wednesday"]
        #expect(wednesday?["power"]?["on"] == "21:30")
        #expect(wednesday?["temperatures"]?["01:00"] == .number(88))
    }

    @Test func groupsByDay() {
        let alarms = [BedAlarm.new(day: .monday, time: "07:00", id: "a"), BedAlarm.new(day: .monday, time: "08:00", enabled: false, id: "b"),
                      BedAlarm.new(day: .friday, time: "07:00", id: "c")]
        let groups = BedAlarmDayGroup.groups(alarms)
        #expect(groups.map(\.day) == [.monday, .friday])
        #expect(groups[0].title == "Monday Alarms")
        #expect(groups[0].summary == "1 Enabled • 1 Disabled")
        #expect(groups[1].title == "Friday Alarm")
        #expect(groups[1].summary == "Enabled")
        let normalized = (alarms.reversed() as [BedAlarm]).normalizedIndexes()
        #expect(normalized.map(\.index) == [0, 1, 0])
        #expect(alarms.contentKey == normalized.contentKey)
    }
}

@Suite("Bed levels and times", .demoHouse)
struct BedLevelTests {
    @Test func formatsAndSnapsLevels() {
        #expect(BedLevel.format(3) == "+3")
        #expect(BedLevel.format(0) == "0")
        #expect(BedLevel.format(-2.5) == "-2.5")
        #expect(BedLevel.format(nil) == "--")
        #expect(BedLevel.snap(3.4, range: -10...10, step: 1) == 3)
        #expect(BedLevel.snap(12, range: -10...10, step: 1) == 10)
        #expect(BedLevel.snap(1.26, range: -10...10, step: 0.5) == 1.5)
        #expect(BedLevel.fahrenheit(level: 10) == 110)
        #expect(BedLevel.fahrenheit(level: -10) == 55)
        #expect(BedLevel.level(fahrenheit: 82.5, range: -10...10) == 0)
        #expect(BedLevel.level(fahrenheit: 200, range: -10...10) == 10)
        #expect(BedLevel.currentLevel(current: 90.5, range: -10...10, targetLevel: 3, targetTemperature: 90.75) == 3)
        #expect(BedLevel.action(targetLevel: 1, isOn: true) == "heating")
        #expect(BedLevel.action(targetLevel: -1, isOn: true) == "cooling")
        #expect(BedLevel.action(targetLevel: 0.5, isOn: true) == "idle")
        #expect(BedLevel.action(targetLevel: nil, isOn: true) == "idle")
        #expect(BedLevel.action(targetLevel: 5, isOn: false) == "off")
    }

    @Test func parsesClockTimes() {
        #expect(ClockTime.parse("2026-10-11 06:45:00") == "06:45")
        #expect(ClockTime.parse(nil, fallback: "07:00") == "07:00")
        #expect(ClockTime.isValid("23:59") && !ClockTime.isValid("7:00"))
        #expect(ClockTime.display("00:05") == "12:05 AM")
        #expect(ClockTime.display("12:30") == "12:30 PM")
        #expect(ClockTime.minutes("01:30") == 90)
        #expect(ClockTime.normalized("7:05:00") == "07:05")
        #expect(ClockTime.normalized("24:00") == nil)
    }

    @Test func readsAlarmAndPhaseStates() {
        #expect(BedAlarmState(state: "ringing").isActive)
        #expect(BedAlarmState(state: "bogus") == .unavailable)
        #expect(!BedAlarmState(state: "idle").isActive)
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(BedAlarmState.snoozeRemainingText(snoozedUntil: 1_299.2, now: now) == "5:00 Remaining")
        #expect(BedAlarmState.snoozeRemainingText(snoozedUntil: 900, now: now) == "0:00 Remaining")
        #expect(BedAlarmState.snoozeRemainingText(snoozedUntil: nil, now: now) == nil)
        #expect(SchedulePhase(state: " Asleep ") == .asleep)
        #expect(SchedulePhase(state: "outside") == nil)
        #expect(SchedulePhase.isAvailable("outside"))
        #expect(!SchedulePhase.isAvailable("unknown"))
        #expect(BedFormat.temperature(71.5) == "71.5°F")
        #expect(BedFormat.countdown(65) == "1:05")
        #expect(BedFormat.metric(EntityState(entityId: "s", state: "58.0", attributes: ["unit_of_measurement": "bpm"])) == "58 bpm")
        #expect(BedFormat.metric(EntityState(entityId: "s", state: "91.25", attributes: ["unit_of_measurement": "°F"])) == "91.3°F")
        #expect(BedFormat.metric(nil) == "Unavailable")
        #expect(Weekday(date: Date(timeIntervalSince1970: 0), calendar: utc) == .thursday)
        #expect(Weekday.ordered([.friday, .monday, .friday]) == [.monday, .friday])
        #expect(MasterBedroom.bed(id: "sams-bed")?.side == .right)
        #expect(MasterBedroom.wakeLight.source(for: .left)?.id == "sleepypod:left")
    }
}

// MARK: - Service responses and remaining copy

@Suite("Bedroom service responses")
@MainActor
struct BedroomServiceResponseTests {
    private func makeConnection() -> (HassConnection, HAMockConnection) {
        let mock = HAMockConnection()
        let cache = EntitySnapshotCache(fileURL: FileManager.default.temporaryDirectory.appending(path: "bedroom-\(UUID()).json"))
        return (HassConnection(server: .example, store: EntityStore(), snapshotCache: cache, connection: mock), mock)
    }

    private func pending(_ mock: HAMockConnection) async throws -> HAMockConnection.PendingRequest {
        for _ in 0..<1_000 where mock.pendingRequests.isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        return try #require(mock.pendingRequests.first)
    }

    @Test func sendsReturnResponseOnceAndReadsTheResponseObject() async throws {
        let (connection, mock) = makeConnection()
        let task = Task { try await connection.callServiceWithResponse("wake_light", "command", data: ["operation": "upsert_alarm"]) }
        let request = try await pending(mock)
        #expect(request.request.type == .webSocket("call_service"))
        #expect(request.request.shouldRetry == false)
        let data = request.request.data
        #expect(data["domain"] as? String == "wake_light")
        #expect(data["service"] as? String == "command")
        #expect(data["return_response"] as? Bool == true)
        #expect((data["service_data"] as? [String: any Sendable])?["operation"] as? String == "upsert_alarm")
        request.completion(.success(HAData(value: ["response": ["outcome": "accepted", "revision": 9]])))
        let value = try await task.value
        #expect(CommandOutcome(response: value) == .accepted(noChange: false, revision: 9))
    }

    @Test func throwsTheTransportError() async throws {
        let (connection, mock) = makeConnection()
        let task = Task { try await connection.callServiceWithResponse("script", "x", data: [:]) }
        let request = try await pending(mock)
        request.completion(.failure(.internal(debugDescription: "offline")))
        await #expect(throws: HAError.self) { try await task.value }
    }

    @Test func convertsEveryHADataShape() {
        #expect(JSONValue(haData: .empty) == .null)
        #expect(JSONValue(haData: .primitive("x")) == .string("x"))
        #expect(JSONValue(haData: .primitive(true)) == .bool(true))
        #expect(JSONValue(haData: .dictionary(["a": 1])) == .object(["a": .number(1)]))
        #expect(JSONValue(haData: .array([.primitive("a"), .empty, .dictionary(["k": "v"])])) == .array(["a", .null, .object(["k": "v"])]))
    }

    @Test func commandResponseUnwrapsOnlyObjects() {
        #expect(JSONValue.object(["response": .object(["outcome": "accepted"])]).commandResponse == .object(["outcome": "accepted"]))
        #expect(JSONValue.object(["outcome": "accepted"]).commandResponse == .object(["outcome": "accepted"]))
        #expect(JSONValue.object(["response": "text"]).commandResponse == .object(["response": "text"]))
        #expect(JSONValue.array([]).commandResponse == nil)
        #expect(JSONValue.string("x").commandResponse == nil)
        #expect(CommandOutcome(response: .array([])) == nil)
    }

    @Test func copyForSourceBlockersOnceAlarmsAndStates() {
        #expect(WakeLight.blockerMessage("source_unavailable").contains("linked alarm schedule"))
        #expect(WakeLight.blockerMessage("source_ref_missing") == WakeLight.blockerMessage("source_unavailable"))
        var once = WakeLight.Alarm(id: "o", label: "O", kind: .once, localTime: "06:00", date: "2030-03-04")
        #expect(WakeLight.scheduleLabel(once, calendar: utc) == "Mar 4, 2030")
        once.date = nil
        #expect(WakeLight.scheduleLabel(once, calendar: utc) == "—")
        once.date = "nope"
        #expect(WakeLight.scheduleLabel(once, calendar: utc) == "—")
        #expect(BedAlarmState.ringing.label == "Ringing")
        #expect(BedAlarmState.snoozed.label == "Snoozed")
        #expect(Weekday.monday < Weekday.friday)
        #expect(!(Weekday.friday < Weekday.monday))
        #expect(BedFormat.metric(EntityState(entityId: "sensor.demo_x", state: "restless")) == "Restless")
        #expect(BedFormat.metric(EntityState(entityId: "sensor.demo_x", state: "62", attributes: ["unit_of_measurement": "bpm"])) == "62 bpm")
        #expect(BedFormat.metric(EntityState(entityId: "sensor.demo_x", state: "91.25", attributes: ["unit_of_measurement": "°F"])) == "91.3°F")
        #expect(BedFormat.metric(nil) == "Unavailable")
    }
}
