import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// Vacation Mode's entities, copy, date ranges, service calls and routing (`Vacation`, web `portedDashboard.ts`).
@Suite(.demoHouse)
struct VacationConfigTests {
    let calendar = AwayTestClock.calendar
    let now = AwayTestClock.now

    @Test func defaultRangeIsOneDay() {
        let range = Vacation.DateRange.makeDefault(now: now, calendar: calendar)
        #expect(range.start == WallClock(date: "2026-10-11", time: "16:30"))
        #expect(range.end == WallClock(date: "2026-10-12", time: "16:30"))
        #expect(!range.isInvalid(calendar: calendar))
        #expect(range.isFuture(now: now, calendar: calendar))
    }

    @Test func rangeFromHelperStates() {
        let range = Vacation.DateRange(startState: "2026-12-20 07:15:00", endState: "2026-12-27T19:45:00", now: now, calendar: calendar)
        #expect(range.start == WallClock(date: "2026-12-20", time: "07:15"))
        #expect(range.end == WallClock(date: "2026-12-27", time: "19:45"))
    }

    @Test func malformedPartsFallBackOneByOne() {
        let range = Vacation.DateRange(startState: "2026-12-20 nope", endState: "unknown", now: now, calendar: calendar)
        #expect(range.start == WallClock(date: "2026-12-20", time: "16:30"))
        #expect(range.end == WallClock(date: "2026-10-12", time: "16:30"))
        #expect(Vacation.DateRange(startState: nil, endState: "2026-12-20", now: now, calendar: calendar).end == WallClock(date: "2026-12-20", time: "16:30"))
    }

    @Test func invalidAndFutureRanges() {
        let reversed = Vacation.DateRange(start: WallClock(date: "2026-10-20", time: "09:00"), end: WallClock(date: "2026-10-19", time: "09:00"))
        #expect(reversed.isInvalid(calendar: calendar))
        let equal = Vacation.DateRange(start: WallClock(date: "2026-10-20", time: "09:00"), end: WallClock(date: "2026-10-20", time: "09:00"))
        #expect(equal.isInvalid(calendar: calendar))
        let unreadable = Vacation.DateRange(start: WallClock(date: "", time: ""), end: WallClock(date: "2026-10-20", time: "09:00"))
        #expect(!unreadable.isInvalid(calendar: calendar))
        let past = Vacation.DateRange(start: WallClock(date: "2026-10-01", time: "09:00"), end: WallClock(date: "2026-10-02", time: "09:00"))
        #expect(!past.isFuture(now: now, calendar: calendar))
        #expect(!Vacation.DateRange(start: past.start, end: WallClock(date: "", time: "")).isFuture(now: now, calendar: calendar))
    }

    @Test func serviceCalls() {
        let range = Vacation.DateRange(start: WallClock(date: "2026-10-20", time: "09:00"), end: WallClock(date: "2026-10-27", time: "18:30"))
        #expect(Vacation.confirmCalls(range) == [
            ServiceCall("input_datetime", "set_datetime", target: Vacation.startEntityId, data: ["date": .string("2026-10-20"), "time": .string("09:00:00")]),
            ServiceCall("input_datetime", "set_datetime", target: Vacation.endEntityId, data: ["date": .string("2026-10-27"), "time": .string("18:30:00")]),
            ServiceCall("input_boolean", "turn_off", target: Vacation.invalidDatesPendingEntityId),
            ServiceCall("input_boolean", "turn_on", target: Vacation.modeEntityId),
        ])
        let disable = Vacation.disableCalls()
        #expect(disable.count == 7)
        #expect(disable.allSatisfy { $0.service == "turn_off" })
        #expect(Set(disable.compactMap(\.target)) == Set([Vacation.modeEntityId, Vacation.invalidDatesPendingEntityId] + Vacation.checklist.map(\.entityId)))
        #expect(Vacation.recoveryCalls().map(\.service) == ["turn_on", "turn_off"])
        #expect(Vacation.pageEntityIds.count == 9)
    }

    @Test func routing() {
        let idle = HouseholdAway.Snapshot(entity: awayEntity())
        #expect(Vacation.route(snapshot: idle, vacationModeOn: false, invalidDatesPending: false) == .chooser)
        #expect(Vacation.route(snapshot: idle, vacationModeOn: true, invalidDatesPending: false) == .vacationMode)
        #expect(Vacation.route(snapshot: idle, vacationModeOn: false, invalidDatesPending: true) == .vacationMode)
        let backendVacation = HouseholdAway.Snapshot(entity: awayEntity("active", awayAttributes(mode: "vacation")))
        #expect(Vacation.route(snapshot: backendVacation, vacationModeOn: false, invalidDatesPending: false) == .vacationMode)
        let solo = HouseholdAway.Snapshot(entity: awayEntity("scheduled", awayAttributes(mode: "solo_trip", traveler: "sam")))
        #expect(Vacation.route(snapshot: solo, vacationModeOn: false, invalidDatesPending: false) == .soloTrip)
        let idleSolo = HouseholdAway.Snapshot(entity: awayEntity("idle", awayAttributes(mode: "solo_trip")))
        #expect(Vacation.route(snapshot: idleSolo, vacationModeOn: false, invalidDatesPending: false) == .chooser)
    }

    @Test func entitiesAndChecklistFollowTheWeb() {
        #expect(Vacation.modeEntityId == "input_boolean.demo_mode_3")
        #expect(Vacation.invalidDatesPendingEntityId == "input_boolean.demo_mode_4")
        #expect(Vacation.startEntityId == "input_datetime.demo_input_datetime_4")
        #expect(Vacation.endEntityId == "input_datetime.demo_input_datetime_3")
        #expect(Vacation.checklist.map(\.title) == [
            "Turn off outdoor sprinklers", "Flush the drain", "Make the bed",
            "Unload and Check Dishwasher", "Take out the trash",
        ])
        #expect(Vacation.checklist.allSatisfy { $0.id == $0.entityId && $0.entityId.hasPrefix("input_boolean.demo_input_boolean_") })
        #expect(Set(Vacation.checklist.map(\.entityId)).count == 5)
        #expect(Vacation.pageEntityIds.first == Vacation.modeEntityId)
        #expect(Set(Vacation.pageEntityIds).count == 9)
    }

    @Test func copyIsVerbatim() {
        #expect(Vacation.Copy.modeTitle == "Vacation Mode")
        #expect(Vacation.Copy.confirmTitle == "Confirm Vacation")
        #expect(Vacation.Copy.confirmAction == "Confirm Vacation")
        #expect([Vacation.Copy.starts, Vacation.Copy.ends] == ["Starts", "Ends"])
        #expect([Vacation.Copy.pending, Vacation.Copy.on, Vacation.Copy.off, Vacation.Copy.unavailable]
            == ["Pending", "On", "Off", "Unavailable"])
        #expect(Vacation.Copy.dateRangeError.hasPrefix("Start date and time must be before end date and time."))
        #expect(Vacation.Copy.chooserTitle == Vacation.Copy.settingsLinkTitle)
        #expect(Vacation.Copy.vacationLinkSubtitle == Vacation.Copy.settingsLinkSubtitle)
        #expect(Vacation.Copy.checklistTitle == "Pre-Vacation Checklist")
        #expect(Vacation.Copy.datesTitle == "Vacation Dates")
    }

    @Test func singleServiceCallsTargetOneEntity() {
        let on = Vacation.setBoolean(Vacation.modeEntityId, on: true)
        #expect(on == ServiceCall("input_boolean", "turn_on", target: Vacation.modeEntityId))
        #expect(on.serviceData["entity_id"] == .string(Vacation.modeEntityId))
        #expect(Vacation.setBoolean(Vacation.modeEntityId, on: false).service == "turn_off")
        let set = Vacation.setDateTime(Vacation.endEntityId, WallClock(date: "2026-11-02", time: "07:05"))
        #expect(set.domain == "input_datetime")
        #expect(set.service == "set_datetime")
        #expect(set.serviceData["entity_id"] == .string(Vacation.endEntityId))
        #expect(set.serviceData["date"] == .string("2026-11-02"))
        // Home Assistant wants seconds on the time.
        #expect(set.serviceData["time"] == .string("07:05:00"))
    }

    @Test func recoveryEnablesTheModeAndClearsTheFlag() {
        #expect(Vacation.recoveryCalls() == [
            ServiceCall("input_boolean", "turn_on", target: Vacation.modeEntityId),
            ServiceCall("input_boolean", "turn_off", target: Vacation.invalidDatesPendingEntityId),
        ])
    }

    @Test func parsingKeepsAValidDateWhenTheTimeIsBadAndTheTimeWhenTheDateIsBad() {
        let fallback = WallClock(date: "2026-10-11", time: "16:30")
        #expect(Vacation.DateRange.parse("2026-12-20 25:99", fallback: fallback) == WallClock(date: "2026-12-20", time: "16:30"))
        #expect(Vacation.DateRange.parse("garbage 07:15", fallback: fallback) == WallClock(date: "2026-10-11", time: "07:15"))
        #expect(Vacation.DateRange.parse("2026-12-20", fallback: fallback) == WallClock(date: "2026-12-20", time: "16:30"))
        #expect(Vacation.DateRange.parse(nil, fallback: fallback) == fallback)
        #expect(Vacation.DateRange.parse("", fallback: fallback) == fallback)
        #expect(Vacation.DateRange.parse("2026-12-20T07:15:30", fallback: fallback) == WallClock(date: "2026-12-20", time: "07:15"))
    }

    @Test func aRangeWhoseStartIsUnreadableIsNeitherInvalidNorFuture() {
        let unreadable = Vacation.DateRange(start: WallClock(date: "", time: ""), end: WallClock(date: "", time: ""))
        #expect(!unreadable.isInvalid(calendar: calendar))
        #expect(!unreadable.isFuture(now: now, calendar: calendar))
    }

    @Test func routingPrefersVacationOverSoloTrip() {
        let solo = HouseholdAway.Snapshot(entity: awayEntity("active", awayAttributes(mode: "solo_trip", traveler: "alex")))
        // The helpers say vacation even while a Solo Trip runs, as on the web.
        #expect(Vacation.route(snapshot: solo, vacationModeOn: true, invalidDatesPending: false) == .vacationMode)
        #expect(Vacation.route(snapshot: solo, vacationModeOn: false, invalidDatesPending: true) == .vacationMode)
    }
}
