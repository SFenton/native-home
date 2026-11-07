import Foundation
@testable import HassCore
import Testing
import HassTestSupport

/// Edits the fixture report before parsing.
func sampleReport(_ edit: (inout [String: Any]) -> Void = { _ in }) -> JSONValue {
    var object = VacuumOutcomeFixtures.sample.foundation as! [String: Any]
    edit(&object)
    return JSONValue(any: object)
}

extension JSONValue {
    /// Foundation form, for editing fixtures.
    var foundation: Any {
        switch self {
        case let .string(value): value
        case let .number(value): value
        case let .bool(value): value
        case let .array(values): values.map(\.foundation)
        case let .object(values): values.mapValues(\.foundation)
        case .null: NSNull()
        }
    }
}

struct VacuumOutcomeParserTests {
    @Test func acceptsTheFixtureReport() throws {
        guard case let .valid(contract) = VacuumOutcomeParser.parse(VacuumOutcomeFixtures.sample) else {
            Issue.record("fixture did not parse"); return
        }
        #expect(contract.version == 2)
        #expect(contract.day == "2026-10-10")
        #expect(contract.rooms.map(\.roomId) == ["kitchen", "office", "living_room", "dining_room"])
        #expect(contract.rooms[2].latestAttempt?.reason?.code == "occupancy.person_arrived")
        #expect(contract.rooms[3].outstanding?.operation == .vacuumMop)
        #expect(contract.eventRoomNames["dining_room"] == "Dining Room")
    }

    @Test func classifiesProtocolProblems() {
        #expect(VacuumOutcomeParser.parse(nil) == .absent)
        #expect(VacuumOutcomeParser.parse(.null) == .absent)
        #expect(VacuumOutcomeParser.parse(.string("x")) == .malformed)
        #expect(VacuumOutcomeParser.parse(sampleReport { $0["version"] = 3 }) == .unsupported)
        #expect(VacuumOutcomeParser.parse(sampleReport { $0["version"] = 1.5 }) == .malformed)
        #expect(VacuumOutcomeParser.parse(sampleReport { $0["complete"] = false }) == .incomplete)
        #expect(VacuumOutcomeParser.parse(sampleReport { $0["complete"] = "yes" }) == .malformed)
        #expect(VacuumOutcomeParser.parse(sampleReport { $0["day"] = "2026-02-30" }) == .malformed)
    }

    @Test func rejectsInconsistentRoomsAndEvents() {
        func room(_ index: Int, _ edit: @escaping (inout [String: Any]) -> Void) -> JSONValue {
            sampleReport { report in
                var rooms = report["rooms"] as! [[String: Any]]
                edit(&rooms[index])
                report["rooms"] = rooms
            }
        }
        func event(_ index: Int, _ edit: @escaping (inout [String: Any]) -> Void) -> JSONValue {
            sampleReport { report in
                var events = report["events"] as! [[String: Any]]
                edit(&events[index])
                report["events"] = events
            }
        }
        let broken: [JSONValue] = [
            room(0) { $0["status"] = "wonderful" },
            room(0) { $0["event_ids"] = [String]() },
            room(0) { $0["event_ids"] = ["e1", "e1"] },
            room(0) { $0["event_ids"] = ["e2"] },
            room(0) { $0["credit"] = ["status": "none", "operation": "vacuum"] },
            room(0) { $0["latest_attempt"] = nil },
            room(0) { $0["outstanding"] = nil },
            room(0) { $0["latest_attempt"] = ["event_id": "e1", "mode": "vacuum", "result": "completed", "reason": NSNull()] },
            room(1) { $0["room_id"] = "kitchen" },
            event(0) { $0["day"] = "2026-10-09" },
            event(0) { $0["type"] = "mystery" },
            event(1) { $0["id"] = "e1" },
            event(3) { $0["reason"] = NSNull() },
            sampleReport { report in
                var events = report["events"] as! [[String: Any]]
                var extra = events[0]
                extra["id"] = "e9"
                events.append(extra)
                report["events"] = events
            },
        ]
        for value in broken { #expect(VacuumOutcomeParser.parse(value) == .malformed) }
    }

    @Test func version1RejectsVersion2Results() {
        let v1 = sampleReport { $0["version"] = 1 }
        #expect(VacuumOutcomeParser.parse(v1) != .unsupported)
        let uncertain = sampleReport { report in
            report["version"] = 1
            var rooms = report["rooms"] as! [[String: Any]]
            rooms[0]["status"] = "uncertain"
            report["rooms"] = rooms
        }
        #expect(VacuumOutcomeParser.parse(uncertain) == .malformed)
    }

    @Test func reconciliationMarksTheMatchingAttemptCompleted() throws {
        guard case let .valid(contract) = VacuumOutcomeParser.parse(VacuumOutcomeFixtures.sample) else { Issue.record("parse"); return }
        let reconciled = VacuumOutcomeParser.reconcile(contract, ["living_room": "e3", "dining_room": "e4", "office": "e2"])
        let living = try #require(reconciled.rooms.first { $0.roomId == "living_room" })
        #expect(living.status == .completed && living.isReconciled && living.outstanding == nil)
        #expect(reconciled.rooms.first { $0.roomId == "dining_room" }?.status == .deferred, "no attempt to reconcile")
        #expect(VacuumOutcomeParser.reconcile(contract, ["living_room": "e1"]).rooms[2].status == .interrupted)
    }
}

struct VacuumWhileAwayTests {
    @Test func readsEveryPresentation() {
        #expect(VacuumWhileAway.read(nil) == .empty)
        #expect(VacuumWhileAway.read([:]) == .empty)
        #expect(VacuumWhileAway.read(["while_away_cleaned": .array([.string("Kitchen"), .string(" ")])]) == .legacy(cleaned: ["Kitchen"], issues: []))
        if case .typed = VacuumWhileAway.read(["while_away_outcomes": VacuumOutcomeFixtures.sample]) {} else { Issue.record("typed") }
        #expect(VacuumWhileAway.read(["while_away_outcomes": sampleReport { $0["complete"] = false }]) == .protocolNotice(.incomplete, cleaned: [], issues: []))
        #expect(VacuumWhileAway.read(["while_away_outcomes": .string("bad"), "while_away_issues": .array([.string("Stuck")])])
            == .protocolNotice(.malformed, cleaned: [], issues: ["Stuck"]))
        #expect(VacuumWhileAway.read(["while_away_outcomes": sampleReport { $0["version"] = 9 }]) == .protocolNotice(.incompatible, cleaned: [], issues: []))
        #expect(VacuumWhileAway.read(["while_away_outcomes": sampleReport { $0["rooms"] = [Any](); $0["events"] = [Any]() }]) == .empty)
    }
}

@Suite(.demoHouse)
struct VacuumOutcomeTextTests {
    var contract: VacuumOutcomeContract {
        guard case let .valid(contract) = VacuumOutcomeParser.parse(VacuumOutcomeFixtures.sample) else { fatalError("fixture") }
        return contract
    }

    @Test func reportTitleIsShortAndTheDetailIsASubtitle() {
        #expect(VacuumOutcomeText.reportTitle == "Cleaning Report")
        #expect(VacuumOutcomeText.reportSubtitle(vacuum: "Main Floor", rooms: 4) == "Main Floor · Automatic · 4 rooms")
        #expect(VacuumOutcomeText.reportSubtitle(vacuum: "Upstairs", rooms: 1) == "Upstairs · Automatic · 1 room")
        #expect(VacuumOutcomeText.reportTitle.count < 20, "short enough for the Duo's outer display")
    }

    @Test func countsAndOverview() {
        let counts = VacuumOutcomeText.counts(contract)
        #expect(counts.completed == 2 && counts.interrupted == 1 && counts.due == 2 && counts.needsAttention == 1 && counts.attention == 0)
        #expect(VacuumOutcomeText.overviewSubtitle(counts) == "2 Rooms Completed • 1 Room Needs Attention")
        #expect(VacuumOutcomeText.overviewVisual(counts).icon == "mdi:pause-circle")
        var other = VacuumOutcomeText.Counts()
        #expect(VacuumOutcomeText.overviewVisual(other).icon == "mdi:check-circle")
        other.due = 1
        #expect(VacuumOutcomeText.overviewVisual(other).icon == "mdi:clock-outline")
        other.unverified = 2
        #expect(VacuumOutcomeText.overviewVisual(other).icon == "mdi:help-circle-outline")
        other.attention = 1
        #expect(VacuumOutcomeText.overviewVisual(other).tone == .danger)
        #expect(VacuumOutcomeText.overviewSubtitle(other) == "2 Rooms Unverified • 1 Error")
    }

    @Test func dayAndStatusCopy() {
        #expect(VacuumOutcomeText.day("2026-10-10").contains("2026"))
        #expect(VacuumOutcomeText.day("soon") == "soon")
        for status in [VacuumOutcomeContract.Status.completed, .deferred, .failed, .interrupted, .partial, .uncertain] {
            #expect(!VacuumOutcomeText.statusTitle(status).isEmpty)
            #expect(VacuumOutcomeText.statusVisual(status).icon.hasPrefix("mdi:"))
        }
        #expect(VacuumOutcomeText.protocolTitle(.incomplete).title == "Report Still Being Prepared")
        #expect(VacuumOutcomeText.protocolTitle(.malformed).title == "Report Could Not Be Read")
        #expect(VacuumOutcomeText.protocolTitle(.incompatible).title == "Dashboard Update Required")
    }

    @Test func roomDetailsPreferKnownReasons() {
        let names = VacuumOutcomeText.roomNames(contract, vacuum: Vacuums.mainFloor)
        #expect(names["bedroom_1_closet"] == "Bedroom 1 Closet")
        let rooms = contract.rooms
        #expect(VacuumOutcomeText.detail(rooms[0], roomNames: names) == "Vacuuming and mopping completed for the room.")
        #expect(VacuumOutcomeText.detail(rooms[2], roomNames: names) == "Cleaning was interrupted because someone returned home.")
        #expect(VacuumOutcomeText.detail(rooms[3], roomNames: names) == "The mop dock's clean-water tank was empty; refill it.")
        var partial = rooms[2]
        partial.status = .partial
        #expect(VacuumOutcomeText.detail(partial, roomNames: names) == "Combined vacuuming and mopping remain due.")
        partial.outstanding = nil
        #expect(VacuumOutcomeText.detail(partial, roomNames: names) == "Cleaning was interrupted because someone returned home.")
        var reconciled = rooms[2]
        reconciled.reconciledEventId = "e3"
        reconciled.status = .completed
        #expect(VacuumOutcomeText.detail(reconciled, roomNames: names) == "Vacuuming and mopping completed for the room.")
        var deferred = rooms[3]
        deferred.outstanding = nil
        #expect(VacuumOutcomeText.detail(deferred, roomNames: names) == "Vacuuming and mopping were deferred before any attempt.")
    }

    @Test func everyAttemptAndOperationHasCopy() {
        for mode in [VacuumOutcomeContract.AttemptMode.vacuum, .vacuumMop, .fallbackVacuum] {
            for result in [VacuumOutcomeContract.AttemptResult.completed, .failed, .interrupted, .partial, .uncertain] {
                #expect(VacuumOutcomeText.attemptSentence(mode, result).hasSuffix("."))
            }
        }
        for operation in [VacuumOutcomeContract.Operation.vacuum, .vacuumMop, .mop] {
            #expect(VacuumOutcomeText.deferredSentence(operation).hasSuffix("."))
            #expect(VacuumOutcomeText.outstandingSentence(operation).hasSuffix("."))
        }
    }

    @Test func reasonSentences() {
        func text(_ code: String, _ data: [String: JSONValue] = [:], context: VacuumOutcomeText.ReasonContext = .standard) -> String {
            VacuumOutcomeText.text(for: .init(category: "x", code: code, data: data, raw: "raw"),
                                   roomNames: ["kitchen": "Kitchen", "office": "Office"], context: context)
        }
        let fixed = ["mop.clean_water_empty", "dock.dustbag_full_or_duct_blocked", "occupancy.person_arrived", "power.low_battery",
                     "dispatch.failed", "navigation.stuck", "navigation.room_unreachable", "navigation.dock_unreachable",
                     "execution.cleaning_not_observed", "execution.segment_not_observed", "operation.cancelled", "mop.attachment_missing",
                     "mop.dirty_water_unavailable", "mop.detergent_unavailable", "mop.hardware_unavailable",
                     "telemetry.task_identity_conflict", "verification.iterations_uncertain", "verification.area_below_minimum"]
        for code in fixed { #expect(text(code) != text("nonsense"), "\(code)") }
        #expect(text("mop.fresh_water_unavailable", ["state": .string("missing")]) == "Fresh-water status is missing.")
        #expect(text("mop.fresh_water_unavailable", ["state": .string("unknown")]) == "Fresh-water status is unknown.")
        #expect(text("mop.fresh_water_unavailable", ["state": .string("unavailable")]) == "Fresh-water status is unavailable.")
        #expect(text("mop.fresh_water_unavailable") == "The vacuum outcome reason was not recognized.")
        for measurement in ["time", "area", "other"] {
            #expect(text("telemetry.counter_attribution_ambiguous", ["measurement": .string(measurement)]).contains("ambiguous"))
            #expect(text("verification.measurement_unavailable", ["measurement": .string(measurement)]).contains("unavailable"))
        }
        #expect(text("telemetry.source_outage_unresolved", ["timeout_seconds": .number(90)]) == "Telemetry recovery was not coherent within 90 seconds.")
        #expect(text("telemetry.source_outage_unresolved") == "Telemetry recovery was not coherent.")
        #expect(text("verification.iterations_incomplete", ["observed_iterations": .number(1), "requested_iterations": .number(2)])
            == "Observed 1 of 2 requested iterations.")
        #expect(text("verification.iterations_incomplete") == "Requested iterations could not all be verified.")
        #expect(text("dispatch.timeout", ["timeout_seconds": .number(30)]).contains("30 seconds"))
        #expect(text("dispatch.timeout").contains("timed out"))
        #expect(text("recovery.native_resume_timeout", ["timeout_seconds": .number(30)]).contains("30 seconds"))
        #expect(text("recovery.native_resume_timeout").contains("timed out"))
        #expect(text("verification.duration_below_minimum", ["observed_seconds": .number(10), "minimum_seconds": .number(60)]).contains("10 seconds"))
        #expect(text("verification.duration_below_minimum").contains("retry"))
        #expect(text("verification.estimated_dwell_below_minimum", ["observed_seconds": .number(10), "minimum_seconds": .number(60)]).contains("10 seconds"))
        #expect(text("verification.estimated_dwell_below_minimum").contains("unavailable"))
        let wrong: [String: JSONValue] = ["dominant_seconds": .number(80), "commanded_seconds": .number(20),
                                          "dominant_room_id": .string("kitchen"), "commanded_room_id": .string("office")]
        #expect(text("verification.wrong_room", wrong) == "Observed cleaning was dominated by Kitchen for 80 seconds instead of the requested Office for 20 seconds.")
        #expect(text("verification.wrong_room", ["dominant_seconds": .number(80), "commanded_seconds": .number(20)]).contains("elsewhere"))
        #expect(text("verification.wrong_room") == "The vacuum outcome reason was not recognized.")
        #expect(text("nonsense", context: .uncertain) == "Completion could not be verified from the available vacuum data.")
    }
}
