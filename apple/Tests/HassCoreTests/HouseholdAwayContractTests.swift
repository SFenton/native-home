import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// A fixed Gregorian UTC calendar and clock so date tests don't depend on the machine.
enum AwayTestClock {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-10-11 16:30 UTC.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11, hour: 16, minute: 30))!
}

/// The status sensor attributes for a test snapshot.
func awayAttributes(
    mode: String = "none", traveler: String = "none", home: String = "none", revision: Int = 3,
    commandAvailable: Bool = true, version: Int = 1, effects: Bool = false,
    startsAt: String? = nil, endsAt: String? = nil
) -> [String: JSONValue] {
    var attributes: [String: JSONValue] = [
        "contract_version": .number(Double(version)),
        "command_available": .bool(commandAvailable),
        "mode": .string(mode),
        "traveler": .string(traveler),
        "home_resident": .string(home),
        "revision": .number(Double(revision)),
        "effects": .object(["sleepypod_live_follow": .bool(effects), "sleepypod_schedule": .bool(effects), "wake_light_source": .bool(effects)]),
        "blockers": .array([.string("needs_setup"), .string(" "), .number(1)]),
    ]
    if let startsAt { attributes["starts_at"] = .string(startsAt) }
    if let endsAt { attributes["ends_at"] = .string(endsAt) }
    return attributes
}

func awayEntity(_ state: String = "idle", _ attributes: [String: JSONValue] = awayAttributes()) -> EntityState {
    EntityState(entityId: HouseholdAway.statusEntityId, state: state, attributes: attributes)
}

@Suite(.demoHouse)
struct HouseholdAwayContractTests {
    // MARK: Snapshot

    @Test func missingSensorIsUnavailableIdle() {
        let snapshot = HouseholdAway.Snapshot(entity: nil)
        #expect(!snapshot.available)
        #expect(!snapshot.canCommand)
        #expect(snapshot.state == .idle)
        #expect(snapshot.mode == .none)
        #expect(snapshot.traveler == nil)
    }

    @Test(arguments: ["unavailable", "unknown"])
    func unavailableSensor(state: String) {
        #expect(!HouseholdAway.Snapshot(entity: awayEntity(state)).available)
    }

    @Test func incompatibleContractIsUnavailable() {
        let snapshot = HouseholdAway.Snapshot(entity: awayEntity("idle", awayAttributes(version: 2)))
        #expect(!snapshot.compatible)
        #expect(!snapshot.available)
        #expect(snapshot.contractVersion == 2)
    }

    @Test func parsesASoloTrip() {
        let snapshot = HouseholdAway.Snapshot(entity: awayEntity("active", awayAttributes(
            mode: "solo_trip", traveler: Resident.resident1.soloTripId, home: Resident.resident2.soloTripId, revision: 7, effects: true,
            startsAt: "2026-10-11T09:00:00-07:00", endsAt: "2026-10-14 18:30:00")))
        #expect(snapshot.available && snapshot.canCommand)
        #expect(snapshot.mode == .soloTrip)
        #expect(snapshot.traveler == .resident1)
        #expect(snapshot.homeResident == .resident2)
        #expect(snapshot.revision == 7)
        #expect(snapshot.blockers == ["needs_setup"])
        #expect(snapshot.start == WallClock(date: "2026-10-11", time: "09:00"))
        #expect(snapshot.end == WallClock(date: "2026-10-14", time: "18:30"))
        #expect(snapshot.isFullyActive)
        #expect(snapshot.isTravelerAway)
        #expect(snapshot.isActivationSettling)
        #expect(snapshot.isEngaged(.soloTrip))
        #expect(!snapshot.isEngaged(.vacation))
    }

    @Test func unknownValuesFallBack() {
        var attributes = awayAttributes(mode: "cruise", traveler: "guest")
        attributes["revision"] = .string("-4")
        attributes["starts_at"] = .string("  ")
        let snapshot = HouseholdAway.Snapshot(entity: awayEntity("sleeping", attributes))
        #expect(snapshot.state == .idle)
        #expect(snapshot.mode == .none)
        #expect(snapshot.traveler == nil)
        #expect(snapshot.revision == 0)
        #expect(snapshot.startsAt == nil)
    }

    @Test func fullyActiveNeedsEveryEffect() {
        var attributes = awayAttributes(mode: "solo_trip", traveler: Resident.resident2.soloTripId, effects: true)
        attributes["effects"] = .object(["sleepypod_live_follow": .bool(true), "sleepypod_schedule": .bool(false), "wake_light_source": .bool(true)])
        let snapshot = HouseholdAway.Snapshot(entity: awayEntity("active", attributes))
        #expect(!snapshot.isFullyActive)
        #expect(snapshot.isActivationSettling)
        #expect(!HouseholdAway.Snapshot(entity: awayEntity("degraded", awayAttributes(mode: "solo_trip", effects: true))).isFullyActive)
    }

    @Test func scheduledTravelerIsNotAwayYet() {
        let snapshot = HouseholdAway.Snapshot(entity: awayEntity("scheduled", awayAttributes(mode: "solo_trip", traveler: Resident.resident2.soloTripId)))
        #expect(!snapshot.isTravelerAway)
        #expect(snapshot.isEngaged(.soloTrip))
    }

    // MARK: Service data

    @Test func scheduleServiceData() {
        let data = HouseholdAway.serviceData(
            for: .scheduleSoloTrip(traveler: .resident2, start: WallClock(date: "2026-10-12", time: "08:00"), end: WallClock(date: "2026-10-15", time: "20:15")),
            expectedRevision: 9, requestId: "req")
        #expect(data == [
            "expected_revision": .number(9), "operation": .string("schedule"), "request_id": .string("req"),
            "mode": .string("solo_trip"), "traveler": .string(Resident.resident2.soloTripId),
            "start_date": .string("2026-10-12"), "start_time": .string("08:00"),
            "end_date": .string("2026-10-15"), "end_time": .string("20:15"),
        ])
    }

    @Test func otherServiceData() {
        #expect(HouseholdAway.serviceData(for: .cancel, expectedRevision: 1, requestId: "a")["operation"] == .string("cancel"))
        #expect(HouseholdAway.serviceData(for: .endNow, expectedRevision: 1, requestId: "a")["operation"] == .string("end_now"))
        let restore = HouseholdAway.serviceData(for: .resolveRestore(.restoreSaved), expectedRevision: 1, requestId: "a")
        #expect(restore["operation"] == .string("resolve_restore"))
        #expect(restore["resolve_action"] == .string("restore_saved"))
        let update = HouseholdAway.serviceData(for: .updateEnd(WallClock(date: "2026-10-20", time: "07:05")), expectedRevision: 1, requestId: "a")
        #expect(update["operation"] == .string("update_end"))
        #expect(update["end_date"] == .string("2026-10-20"))
        #expect(update["end_time"] == .string("07:05"))
        #expect(update.count == 5)
    }

    // MARK: Wall clock

    @Test(arguments: [
        ("2026-10-11T16:30:00-07:00", "2026-10-11", "16:30"),
        ("2026-10-11 16:30:00", "2026-10-11", "16:30"),
        (" 2026-10-11 07:05 ", "2026-10-11", "07:05"),
    ])
    func parsesWallClocks(input: String, date: String, time: String) {
        #expect(WallClock(parsing: input) == WallClock(date: date, time: time))
    }

    @Test(arguments: ["2026-10-11", "2026-10-1116:30", "2026/10/11 16:30", "2026-10-11 25:00", "2026-10-11 16:3", "x"])
    func rejectsMalformedWallClocks(input: String) {
        #expect(WallClock(parsing: input) == nil)
    }

    @Test func convertsToAndFromDates() {
        let wall = WallClock(AwayTestClock.now, calendar: AwayTestClock.calendar)
        #expect(wall == WallClock(date: "2026-10-11", time: "16:30"))
        #expect(wall.date(in: AwayTestClock.calendar) == AwayTestClock.now)
        #expect(wall.timeWithSeconds == "16:30:00")
        #expect(WallClock(date: "2026-02-30", time: "10:00").date(in: AwayTestClock.calendar) == nil)
        #expect(WallClock(date: "", time: "10:00").date(in: AwayTestClock.calendar) == nil)
        #expect(WallClock(date: "2026-10-11", time: "10:00:00").timeWithSeconds == "10:00:00")
    }

    // MARK: Drafts

    @Test func defaultDraftIsThreeDays() {
        let draft = SoloTripDraft.makeDefault(now: AwayTestClock.now, calendar: AwayTestClock.calendar)
        #expect(draft.start == WallClock(date: "2026-10-11", time: "16:30"))
        #expect(draft.end == WallClock(date: "2026-10-14", time: "16:30"))
        #expect(draft.endAfterStart(calendar: AwayTestClock.calendar))
        #expect(draft.isValid(traveler: .resident2, calendar: AwayTestClock.calendar))
        #expect(!draft.isValid(traveler: nil, calendar: AwayTestClock.calendar))
    }

    @Test func draftEndMustFollowStart() {
        let same = WallClock(date: "2026-10-11", time: "10:00")
        #expect(!SoloTripDraft(start: same, end: same).endAfterStart(calendar: AwayTestClock.calendar))
        #expect(!SoloTripDraft(start: same, end: WallClock(date: "", time: "")).endAfterStart(calendar: AwayTestClock.calendar))
    }

    @Test func returnValidation() {
        let start = WallClock(date: "2026-10-10", time: "09:00")
        let future = SoloTripReturnValidation(end: WallClock(date: "2026-10-12", time: "09:00"), start: start, now: AwayTestClock.now, calendar: AwayTestClock.calendar)
        #expect(future.isValid)
        let past = SoloTripReturnValidation(end: WallClock(date: "2026-10-11", time: "08:00"), start: start, now: AwayTestClock.now, calendar: AwayTestClock.calendar)
        #expect(past.endAfterStart && !past.endInFuture && !past.isValid)
        let beforeStart = SoloTripReturnValidation(end: WallClock(date: "2026-10-12", time: "09:00"), start: WallClock(date: "2026-10-13", time: "09:00"), now: AwayTestClock.now, calendar: AwayTestClock.calendar)
        #expect(beforeStart.endInFuture && !beforeStart.endAfterStart)
        #expect(!SoloTripReturnValidation(end: WallClock(date: "2026-10-12", time: "09:00"), start: nil, now: AwayTestClock.now, calendar: AwayTestClock.calendar).endAfterStart)
        #expect(!SoloTripReturnValidation(end: WallClock(date: "", time: ""), start: start, now: AwayTestClock.now, calendar: AwayTestClock.calendar).endInFuture)
    }

    // MARK: Residents

    @Test func residents() {
        #expect(HouseholdResident.forUserId(HouseholdResident.resident1.haUserId.uppercased()) == .resident1)
        #expect(HouseholdResident.forUserId(" \(HouseholdResident.resident2.haUserId) ") == .resident2)
        #expect(HouseholdResident.forUserId("someone") == nil)
        #expect(HouseholdResident.forUserId(nil) == nil)
        #expect(HouseholdResident.resident1.other == .resident2)
        #expect(HouseholdResident.resident2.other == .resident1)
        #expect(HouseholdResident.resident2.name == DemoHouse.config.chores.people[1].name)
    }

    // MARK: Status

    @Test func statusSections() {
        func status(_ state: String, effects: Bool = false, error: String? = nil, options: SoloTripStatus.Options = .init()) -> SoloTripStatus {
            SoloTripStatus.make(snapshot: HouseholdAway.Snapshot(entity: awayEntity(state, awayAttributes(mode: "solo_trip", traveler: Resident.resident2.soloTripId, effects: effects))),
                                errorCode: error, options: options)
        }
        #expect(status("restore_required").actions == [.keepCurrent, .restoreSaved])
        #expect(status("restore_required").title == SoloTripCopy.restoreRequiredTitle)
        #expect(status("activating").actions == [.endNow])
        #expect(status("activating", options: .soloTripPage) == SoloTripStatus())
        #expect(status("activating", options: SoloTripStatus.Options(showsActivatingEndNow: false)).actions.isEmpty)
        #expect(status("ending").title == SoloTripCopy.endingTitle)
        #expect(status("scheduled", error: "x") == SoloTripStatus(error: SoloTripCopy.commandFailed))
        #expect(status("scheduled").isEmpty)
        #expect(status("degraded").title == SoloTripCopy.degradedTitle)
        #expect(status("active", effects: true) == SoloTripStatus(showsActiveNotice: true))
        #expect(status("active", effects: true, options: .soloTripPage).isEmpty)
        #expect(status("active") == SoloTripStatus(title: "\(Resident.resident2.name) Away", description: SoloTripCopy.activeUnconfirmedDescription))
        #expect(status("active", options: SoloTripStatus.Options(showsConfirmedActiveNotice: false)).description == SoloTripCopy.activeUnconfirmedDescription)
        #expect(status("active", options: .soloTripPage).isEmpty)
        #expect(status("active", error: HouseholdAwayController.ErrorCode.unknownOutcome).error == SoloTripCopy.unknownOutcome)
        #expect(SoloTripStatus.Action.allCases.map(\.title) == [SoloTripCopy.restoreKeepCurrent, SoloTripCopy.restoreSaved, SoloTripCopy.endNow])
    }

    @Test func notices() {
        let active = HouseholdAway.Snapshot(entity: awayEntity("active", awayAttributes(mode: "solo_trip", traveler: Resident.resident1.soloTripId, home: Resident.resident2.soloTripId, effects: true)))
        #expect(SoloTripNotice.make(snapshot: active, viewer: .resident2)
            == SoloTripNotice(title: "\(Resident.resident1.name) Away", isSuccess: true, description: SoloTripCopy.activeDescription(traveler: Resident.resident1.name)))
        #expect(SoloTripNotice.make(snapshot: active, viewer: .resident1)?.description == SoloTripCopy.activeDescriptionTraveler(homeResident: Resident.resident2.name))
        let degraded = HouseholdAway.Snapshot(entity: awayEntity("degraded", awayAttributes(mode: "solo_trip", traveler: Resident.resident1.soloTripId, home: Resident.resident2.soloTripId)))
        #expect(SoloTripNotice.make(snapshot: degraded, viewer: nil) == SoloTripNotice(title: "\(Resident.resident1.name) Away", isSuccess: false, description: nil))
        #expect(SoloTripNotice.make(snapshot: HouseholdAway.Snapshot(entity: nil), viewer: nil) == nil)
    }
}
