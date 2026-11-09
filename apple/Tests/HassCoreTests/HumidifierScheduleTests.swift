import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Schedule rules ⇄ Home Assistant blocks (web `humidifierSchedule.test.ts`) and the Schedules tab controller.
@Suite(.demoHouse)
struct HumidifierScheduleTests {
    func rule(_ id: String = "rule-1", days: [Weekday] = [.monday], start: String = "22:00", end: String = "07:00",
              mode: HumidifierMode = .sleep, label: String = "Night") -> HumidifierScheduleRule {
        var rule = HumidifierScheduleRule.new(id: id)
        rule.days = days
        rule.start = start
        rule.end = end
        rule.mode = mode
        rule.label = label
        return rule
    }

    @Test func newRulesDefaultToWeekdayNights() {
        let rule = HumidifierScheduleRule.new(id: "x")
        #expect(rule.days == [.monday, .tuesday, .wednesday, .thursday, .friday])
        #expect(rule.start == "22:00" && rule.end == "07:00" && rule.mode == .sleep && rule.label == "Night")
        #expect(rule.isComplete)
    }

    @Test func serializesActivitiesWithTheirProfileData() {
        var morning = rule("morning", days: [.monday, .wednesday], start: "06:00", end: "07:30", mode: .targetHumidity, label: "Morning")
        morning.mistLevel = 3
        morning.targetHumidity = 45
        var evening = rule("evening", days: [.monday, .wednesday], start: "20:00", end: "22:30", mode: .manual, label: "Evening")
        evening.display = true
        evening.mistLevel = 6
        evening.warmLevel = 2
        let days = HumidifierSchedule.days(from: [evening, morning])
        #expect(days[.monday]?.count == 2)
        let first = days[.monday]![0]
        #expect(first.from == "06:00" && first.to == "07:30")
        #expect(first.data["label"] == .string("Morning"))
        #expect(first.data["mist_level"] == .number(3))
        #expect(first.data["mode"] == .string("Target Humidity"))
        #expect(first.data["target_humidity"] == .number(45))
        #expect(first.data["rule_days"] == .string("monday,wednesday"))
        #expect(days[.monday]![1].data["warm_level"] == .number(2))
        #expect(days[.monday]![1].data["display"] == .bool(true))
        #expect(days[.tuesday] == [])
        #expect(HumidifierSchedule.conflicts(in: [morning, evening]).isEmpty)
    }

    @Test func overnightActivitiesSplitAndRoundTripAsOneRule() {
        let overnight = rule("overnight", days: [.monday, .tuesday], label: "Overnight")
        let days = HumidifierSchedule.days(from: [overnight])
        #expect(days[.monday]?.map { "\($0.from)-\($0.to)" } == ["22:00-24:00"])
        #expect(days[.tuesday]?.map { "\($0.from)-\($0.to)" } == ["00:00-07:00", "22:00-24:00"])
        #expect(days[.wednesday]?.map { "\($0.from)-\($0.to)" } == ["00:00-07:00"])
        let schedule = HassSchedule(id: "master_bedroom_humidifier", name: "Demo Humidifier Schedule", days: days)
        #expect(HumidifierSchedule.rules(from: schedule) == [overnight])
        #expect(HumidifierSchedule.rules(from: nil).isEmpty)
    }

    @Test func saturdayOvernightWrapsToSunday() {
        let days = HumidifierSchedule.days(from: [rule(days: [.saturday])])
        #expect(days[.sunday]?.first?.to == "07:00")
        #expect(Weekday.saturday.next == .sunday)
    }

    @Test func endingAtMidnightAddsNoNextDayBlock() {
        let evening = rule("evening", start: "22:00", end: "00:00")
        let days = HumidifierSchedule.days(from: [evening])
        #expect(days[.monday]?.map(\.to) == ["24:00"])
        #expect(days[.tuesday] == [])
        #expect(HumidifierSchedule.conflicts(in: [evening]).isEmpty)
    }

    @Test func touchingRulesAreFineButOverlapsAreReported() {
        let first = rule("first", days: [.friday], start: "08:00", end: "10:00")
        let touching = rule("touching", days: [.friday], start: "10:00", end: "12:00")
        let overlapping = rule("overlap", days: [.friday], start: "09:30", end: "11:00")
        #expect(HumidifierSchedule.conflicts(in: [first, touching]).isEmpty)
        let conflicts = HumidifierSchedule.conflicts(in: [first, overlapping])
        #expect(conflicts == [ScheduleConflict(day: .friday, firstRuleId: "first", secondRuleId: "overlap")])
        #expect(conflicts[0].message == "This activity overlaps another activity on Friday.")
    }

    @Test func buildsACompleteUpdateMessage() {
        let schedule = HassSchedule(id: "master_bedroom_humidifier", name: "Demo Humidifier Schedule")
        let message = HumidifierSchedule.updateMessage(schedule, rules: [rule("weekend", days: [.saturday, .sunday], start: "07:00", end: "09:00")])
        #expect(message["type"] == .string("schedule/update"))
        #expect(message["schedule_id"] == .string("master_bedroom_humidifier"))
        #expect(message["name"] == .string("Demo Humidifier Schedule"))
        #expect(message["icon"] == .string("mdi:calendar-clock"))
        #expect(message["saturday"]?.array?.count == 1)
        #expect(message["monday"] == .array([]))
        #expect(message["sunday"]?.array?.first?["from"] == .string("07:00"))
    }

    @Test func parsesScheduleListItemsAndToleratesBadData() throws {
        let json = JSONValue.object([
            "id": .string("master_bedroom_humidifier"),
            "name": .string("Humidifier"),
            "monday": .array([
                .object(["from": .string("22:00:00"), "to": .string("24:00:00"), "data": .object([
                    "rule_id": .string("a"), "label": .string("  "), "mode": .string("Bogus"), "mist_level": .string("12"),
                    "target_humidity": .number(10), "warm_level": .number(2), "display": .bool(false),
                    "rule_days": .string("monday,funday"),
                ])]),
                .object(["from": .string("01:00:00"), "to": .string("02:00:00")]),
                .object(["from": .number(1)]),
            ]),
        ])
        let schedule = try #require(HassSchedule(json: json))
        #expect(schedule.days[.monday]?.count == 2)
        let rules = HumidifierSchedule.rules(from: schedule)
        #expect(rules.count == 1, "Blocks without a rule id are ignored")
        let parsed = rules[0]
        #expect(parsed.label == "Scheduled activity")
        #expect(parsed.mode == .manual)
        #expect(parsed.mistLevel == 9)
        #expect(parsed.targetHumidity == 40)
        #expect(parsed.days == [.monday])
        #expect(parsed.start == "22:00" && parsed.end == "24:00")
        #expect(!parsed.display)
        #expect(HassSchedule(json: .object(["name": .string("no id")])) == nil)
    }

    @Test func timesAndFormatting() {
        #expect(HumidifierSchedule.normalizedTime("7:05", fallback: "x") == "07:05")
        #expect(HumidifierSchedule.normalizedTime("25:99", fallback: "x") == "24:59")
        #expect(HumidifierSchedule.normalizedTime("noon", fallback: "12:00") == "12:00")
        #expect(HumidifierSchedule.isValidTime("23:59"))
        #expect(!HumidifierSchedule.isValidTime("24:00"))
        #expect(!HumidifierSchedule.isValidTime("7:00"))
        #expect(HumidifierSchedule.formatDays(Weekday.allCases) == "Every day")
        #expect(HumidifierSchedule.formatDays([.friday, .monday, .tuesday, .wednesday, .thursday]) == "Weekdays")
        #expect(HumidifierSchedule.formatDays([.saturday, .sunday]) == "Weekends")
        #expect(HumidifierSchedule.formatDays([.wednesday, .monday]) == "Mon, Wed")
        #expect(HumidifierSchedule.formatTimes(start: "22:00", end: "07:30") == "10:00 PM–7:30 AM")
        #expect(HumidifierSchedule.formatClock("00:15") == "12:15 AM")
        #expect(HumidifierSchedule.formatClock("12:00") == "12:00 PM")
        var r = rule()
        #expect(HumidifierSchedule.profileSummary(r) == "Sleep")
        r.mode = .targetHumidity
        r.mistLevel = 5
        #expect(HumidifierSchedule.profileSummary(r) == "Auto 50% • Mist 5")
        r.mode = .manual
        #expect(HumidifierSchedule.profileSummary(r) == "Manual • Mist 5 • Warm 0")
        r.label = " "
        #expect(!r.isComplete)
        #expect(Weekday.monday.shortTitle == "Mon" && Weekday.monday.title == "Monday")
    }
}

/// An in-memory schedule helper.
@MainActor
final class MemoryScheduleStore: HassScheduleStoring {
    var schedules: [HassSchedule]
    var admin: Bool? = true
    var failList = false
    var failUpdate = false
    var updates: [[String: JSONValue]] = []
    struct Failure: Error {}

    init(_ schedules: [HassSchedule]) { self.schedules = schedules }

    func listSchedules() async throws -> [HassSchedule] {
        if failList { throw Failure() }
        return schedules
    }

    func updateSchedule(_ message: [String: JSONValue]) async throws -> HassSchedule {
        if failUpdate { throw Failure() }
        updates.append(message)
        var json = message
        json["id"] = message["schedule_id"]
        let saved = HassSchedule(json: .object(json))!
        schedules = [saved]
        return saved
    }

    func userIsAdmin() async throws -> Bool {
        guard let admin else { throw Failure() }
        return admin
    }
}

@MainActor
@Suite(.demoHouse)
struct HumidifierScheduleControllerTests {
    let h = HumidifierConfig.all[0]
    let night = HumidifierScheduleRule.new(id: "night")

    func controller(rules: [HumidifierScheduleRule] = [], enabled: String = "off", vacation: String = "off",
                    schedule: String = "off", ruleId: String? = nil)
        -> (HumidifierScheduleController, MemoryScheduleStore, RecordingCaller, EntityStore)
    {
        let store = makeStore([h.scheduleEnabledEntityId: enabled, h.vacationModeEntityId: vacation, h.scheduleEntityId: schedule],
                              attributes: ruleId.map { [h.scheduleEntityId: ["rule_id": .string($0)]] } ?? [:])
        let storage = MemoryScheduleStore([
            HassSchedule(id: "other", name: "Other"),
            HassSchedule(id: h.scheduleId, name: "Demo Humidifier Schedule", days: HumidifierSchedule.days(from: rules)),
        ])
        let caller = RecordingCaller()
        return (HumidifierScheduleController(config: h, store: store, caller: caller, storage: storage, scheduler: ManualScheduler()),
                storage, caller, store)
    }

    @Test func loadsTheHelperAndTheUserRole() async {
        let (schedules, storage, _, _) = controller(rules: [night], enabled: "on", schedule: "on", ruleId: "night")
        #expect(schedules.loading && !schedules.ready)
        storage.admin = false
        await schedules.load()
        #expect(!schedules.loading && schedules.ready)
        #expect(schedules.rules == [night])
        #expect(!schedules.canEdit)
        #expect(schedules.isRunning(night))
        #expect(schedules.toggleTitle == "Scheduling On")
        #expect(schedules.toggleSubtitle == "Activity running now")
        #expect(!schedules.toggleDisabled)
    }

    @Test func reportsAMissingHelperOrALoadFailure() async {
        let (schedules, storage, _, _) = controller()
        storage.schedules = []
        storage.admin = nil
        await schedules.load()
        #expect(schedules.error == "The humidifier schedule helper was not found.")
        #expect(schedules.canEdit, "An unknown role may edit, as on the web")
        storage.failList = true
        await schedules.load()
        #expect(schedules.error == "Could not load scheduled activities.")
        schedules.clearError()
        #expect(schedules.error == nil)
        #expect(await !schedules.save(night), "Nothing saves before the helper loads")
    }

    @Test func switchTitlesFollowTheHelpers() async {
        let (empty, _, _, _) = controller()
        await empty.load()
        #expect(empty.toggleTitle == "Scheduling Paused")
        #expect(empty.toggleSubtitle == "Add an activity to enable scheduling")
        #expect(empty.toggleDisabled)
        let (vacation, _, _, _) = controller(rules: [night], enabled: "on", vacation: "on")
        await vacation.load()
        #expect(vacation.toggleTitle == "Paused for Vacation")
        #expect(vacation.toggleSubtitle == "Vacation mode disables scheduled runs")
        let (missing, _, _, _) = controller(rules: [night], enabled: "unavailable")
        await missing.load()
        #expect(missing.toggleTitle == "Scheduling Unavailable")
        #expect(missing.toggleSubtitle == "Home Assistant schedule control is unavailable")
        let (two, _, _, _) = controller(rules: [night, HumidifierScheduleRule.new(id: "nap").with(start: "13:00", end: "14:00")], enabled: "on")
        await two.load()
        #expect(two.toggleSubtitle == "2 activities configured")
    }

    @Test func togglingSendsTheInputBoolean() async {
        let (schedules, _, caller, _) = controller(rules: [night], enabled: "on")
        await schedules.load()
        schedules.toggleEnabled()
        #expect(!schedules.enabled)
        await schedules.waitForCalls()
        #expect(caller.calls == [.init(domain: "input_boolean", service: "turn_off",
                                       data: ["entity_id": "input_boolean.demo_bedroom_1_schedule_1"])])
    }

    @Test func theFirstActivityEnablesSchedulingAndTheLastDisablesIt() async {
        let (schedules, storage, caller, _) = controller()
        await schedules.load()
        var draft = night
        draft.label = "  Night  "
        #expect(await schedules.save(draft))
        #expect(schedules.rules.map(\.label) == ["Night"])
        #expect(storage.updates.count == 1)
        #expect(schedules.enabled)
        #expect(await schedules.delete("night"))
        #expect(schedules.rules.isEmpty)
        #expect(!schedules.enabled)
        await schedules.waitForCalls()
        #expect(caller.calls.map(\.service) == ["turn_on", "turn_off"])
    }

    @Test func editingReplacesTheRuleAndConflictsBlockSaving() async {
        let (schedules, storage, _, _) = controller(rules: [night])
        await schedules.load()
        var edited = night
        edited.mode = .manual
        #expect(schedules.rules(saving: edited) == [edited])
        #expect(await schedules.save(edited))
        #expect(schedules.rules.first?.mode == .manual)

        let clash = HumidifierScheduleRule.new(id: "clash").with(start: "23:00", end: "23:30")
        #expect(schedules.conflict(for: clash)?.day == .monday)
        #expect(await !schedules.save(clash))
        #expect(schedules.error == "This activity overlaps another activity on Monday.")
        #expect(storage.updates.count == 1)
    }

    @Test func aFailedSaveKeepsTheRules() async {
        let (schedules, storage, _, _) = controller(rules: [night])
        await schedules.load()
        storage.failUpdate = true
        #expect(await !schedules.delete("night"))
        #expect(schedules.error == "Could not save scheduled activities.")
        #expect(schedules.rules == [night])
        #expect(!schedules.saving)
    }
}

extension HumidifierScheduleRule {
    func with(start: String, end: String) -> HumidifierScheduleRule {
        var copy = self
        copy.start = start
        copy.end = end
        return copy
    }
}
