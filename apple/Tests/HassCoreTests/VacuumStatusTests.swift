import Foundation
@testable import HassCore
import Testing
import HassTestSupport

/// A coherent v1 status contract (web `vacuumStatus.test.ts` fixture) with overrides.
func statusContract(_ overrides: [String: Any] = [:]) -> [String: JSONValue] {
    var object: [String: Any] = [
        "active_conditions": [Any](),
        "availability": ["since": NSNull(), "status": "available"],
        "command_policy": ["mode": "normal", "reason": NSNull()],
        "current_issue": ["code": NSNull(), "raw": NSNull(), "reported_at": NSNull(), "status": "clear"],
        "last_issue": NSNull(),
        "observed_vacuum_state": "docked",
        "vacuum_entity_id": "vacuum.valetudo_test",
        "version": 1,
    ]
    object.merge(overrides) { _, new in new }
    guard case let .object(attributes) = JSONValue(any: object) else { return [:] }
    return attributes
}

var presentIssue: [String: Any] { ["code": "navigation.stuck", "raw": "Robot stuck or trapped", "reported_at": "2026-08-21T21:20:11Z", "status": "present"] }
var resumeCondition: [String: Any] { ["code": "vacuum.task_resume_pending", "since": "2026-08-21T21:20:11.500Z", "source": "coordinator"] }

struct VacuumStatusContractTests {
    @Test func acceptsACoherentContract() throws {
        let parsed = try #require(VacuumStatusContract.parse(statusContract()))
        #expect(parsed.availability == .available)
        #expect(parsed.policyMode == .normal)
        #expect(parsed.currentIssue == .clear)
        #expect(parsed.lastIssue == nil)
        #expect(parsed.observedVacuumState == "docked")
    }

    @Test func rejectsIncoherentContracts() {
        let rejected: [[String: Any]] = [
            ["version": 2],
            ["vacuum_entity_id": " "],
            ["observed_vacuum_state": 3],
            ["current_issue": ["status": "present"]],
            ["current_issue": ["status": "clear", "code": "x"]],
            ["availability": ["since": "2026-08-21T21:51:49Z", "status": "unavailable"], "command_policy": ["mode": "none", "reason": "primary_unavailable"],
             "current_issue": presentIssue, "observed_vacuum_state": "unavailable"],
            ["current_issue": ["code": NSNull(), "raw": NSNull(), "reported_at": NSNull(), "status": "unknown"]],
            ["current_issue": presentIssue],
            ["active_conditions": [resumeCondition]],
            ["availability": ["since": NSNull(), "status": "unavailable"], "command_policy": ["mode": "none", "reason": "primary_unavailable"]],
            ["availability": ["since": "yesterday", "status": "available"]],
            ["command_policy": ["mode": "restricted", "reason": 4]],
            ["active_conditions": [["code": "x", "since": "2026-08-21T21:20:11Z", "source": "elsewhere"]], "command_policy": ["mode": "restricted", "reason": "x"]],
            ["last_issue": ["code": "e", "raw": "E", "reported_at": "2026-08-21T21:20:11Z", "provenance": "guess"]],
            ["last_issue": ["code": "e", "raw": "E", "reported_at": "2026-08-21T21:20:11Z", "provenance": "observed", "cleared_at": "soon"]],
            ["availability": ["since": NSNull(), "status": "unavailable"], "command_policy": ["mode": "restricted", "reason": NSNull()],
             "observed_vacuum_state": "unavailable"],
        ]
        for overrides in rejected {
            #expect(VacuumStatusContract.parse(statusContract(overrides)) == nil, "\(overrides)")
        }
        var missing = statusContract()
        missing["last_issue"] = nil
        #expect(VacuumStatusContract.parse(missing) == nil)
    }

    @Test func unavailableContractsFailClosedAndKeepTheLastIssue() throws {
        let parsed = try #require(VacuumStatusContract.parse(statusContract([
            "availability": ["since": "2026-08-21T21:51:49Z", "status": "unavailable"],
            "command_policy": ["mode": "none", "reason": "primary_unavailable"],
            "current_issue": ["code": NSNull(), "raw": NSNull(), "reported_at": NSNull(), "status": "unknown"],
            "last_issue": ["code": "unknown_error_75", "provenance": "observed", "raw": "Unknown error 75",
                           "reported_at": "2026-08-21T21:20:11Z", "cleared_at": NSNull()],
            "observed_vacuum_state": "unavailable",
        ])))
        #expect(parsed.policyMode == .none)
        #expect(parsed.lastIssue?.raw == "Unknown error 75")
        #expect(parsed.lastIssue?.clearedAt == nil)
    }

    @Test func parsesConditionsAndPresentIssues() throws {
        let parsed = try #require(VacuumStatusContract.parse(statusContract([
            "active_conditions": [resumeCondition], "current_issue": presentIssue,
            "command_policy": ["mode": "restricted", "reason": "current_issue"],
        ])))
        #expect(parsed.activeConditions.first?.source == .coordinator)
        #expect(parsed.currentIssue.raw == "Robot stuck or trapped")
        #expect(parsed.policyReason == "current_issue")

        let missing = try #require(VacuumStatusContract.parse(statusContract([
            "observed_vacuum_state": NSNull(), "availability": ["since": NSNull(), "status": "missing"],
            "command_policy": ["mode": "none", "reason": "primary_missing"],
            "current_issue": ["code": NSNull(), "raw": NSNull(), "reported_at": NSNull(), "status": "unknown"],
        ])))
        #expect(missing.observedVacuumState == nil)
        #expect(missing.availability == .missing)
    }
}

struct VacuumStatusResolverTests {
    func inputs(vacuum: String? = "docked", exists: Bool = true, battery: String? = "80", error: String? = "No error",
                flag: String? = "none", dock: String? = "idle", hasDock: Bool = true,
                attributes: [String: JSONValue]? = nil) -> VacuumStatusResolver.Inputs {
        .init(vacuumEntityId: "vacuum.valetudo_test", vacuumState: vacuum, vacuumExists: exists, batteryState: battery, errorState: error,
              statusFlagState: flag, hasDockControls: hasDock, dockState: dock, statusAttributes: attributes)
    }

    @Test func availabilityAndNativeIssue() {
        #expect(VacuumStatusResolver.availability(nil, exists: false) == .missing)
        #expect(VacuumStatusResolver.availability("unknown") == .unknown)
        #expect(VacuumStatusResolver.availability("") == .unknown)
        #expect(VacuumStatusResolver.availability("unavailable") == .unavailable)
        #expect(VacuumStatusResolver.availability("docked") == .available)
        #expect(VacuumStatusResolver.nativeIssue(nil) == .unknown)
        #expect(VacuumStatusResolver.nativeIssue("Unavailable") == .unknown)
        #expect(VacuumStatusResolver.nativeIssue(" No error ") == .clear)
        let issue = VacuumStatusResolver.nativeIssue("Main brush jammed!")
        #expect(issue.status == .present && issue.code == "main_brush_jammed" && issue.raw == "Main brush jammed!")
        #expect(VacuumStatusResolver.isUnavailable(nil))
        #expect(VacuumStatusResolver.isUnavailable(" Unknown "))
        #expect(!VacuumStatusResolver.isUnavailable("docked"))
    }

    @Test func normalWhenDockedAndReadable() {
        let status = VacuumStatusResolver.resolve(inputs())
        #expect(status.policyMode == .normal && status.policyReason == nil && status.primaryAvailable)
    }

    @Test func eachRestrictionNamesItsReason() {
        #expect(VacuumStatusResolver.resolve(inputs(vacuum: "unavailable")).policyReason == "primary_unavailable")
        #expect(VacuumStatusResolver.resolve(inputs(vacuum: "unavailable")).policyMode == .none)
        #expect(VacuumStatusResolver.resolve(inputs(vacuum: nil, exists: false)).policyReason == "primary_missing")
        #expect(VacuumStatusResolver.resolve(inputs(battery: "unknown")).policyReason == "source_unreadable")
        #expect(VacuumStatusResolver.resolve(inputs(battery: "full")).policyReason == "source_unreadable")
        #expect(VacuumStatusResolver.resolve(inputs(dock: "unavailable")).policyReason == "source_unreadable")
        #expect(VacuumStatusResolver.resolve(inputs(dock: "unavailable", hasDock: false)).policyMode == .normal)
        #expect(VacuumStatusResolver.resolve(inputs(error: "Stuck")).policyReason == "current_issue")
        #expect(VacuumStatusResolver.resolve(inputs(flag: "resumable")).policyReason == "vacuum.task_resume_pending")
        #expect(VacuumStatusResolver.resolve(inputs(vacuum: "cleaning")).policyReason == "vacuum_cleaning")
        #expect(VacuumStatusResolver.resolve(inputs(dock: "drying")).policyReason == "dock_drying")
        #expect(VacuumStatusResolver.resolve(inputs(vacuum: "unavailable")).currentIssue == .unknown)
    }

    @Test func theMostRestrictiveContractPolicyWins() {
        let restricted = statusContract(["vacuum_entity_id": "vacuum.valetudo_test",
                                         "command_policy": ["mode": "restricted", "reason": "coordinator_busy"],
                                         "active_conditions": [resumeCondition]])
        let status = VacuumStatusResolver.resolve(inputs(attributes: restricted))
        #expect(status.policyMode == .restricted)
        #expect(status.policyReason == "vacuum.task_resume_pending", "the local reason ranks equal and comes first")
        #expect(status.activeConditions.count == 1, "the derived resume condition does not duplicate the contract's")

        let cleaning = VacuumStatusResolver.resolve(inputs(vacuum: "docked", attributes: statusContract([
            "vacuum_entity_id": "vacuum.valetudo_test", "command_policy": ["mode": "restricted", "reason": "coordinator_busy"],
            "current_issue": ["code": NSNull(), "raw": NSNull(), "reported_at": NSNull(), "status": "unknown"]])))
        #expect(cleaning.policyReason == "coordinator_busy")
    }

    @Test func staleOrForeignContractsAreIgnored() {
        let foreign = statusContract(["vacuum_entity_id": "vacuum.demo_other", "command_policy": ["mode": "restricted", "reason": "x"],
                                      "active_conditions": [resumeCondition]])
        #expect(VacuumStatusResolver.resolve(inputs(attributes: foreign)).policyMode == .normal)
        let stale = statusContract(["vacuum_entity_id": "vacuum.valetudo_test", "observed_vacuum_state": "idle",
                                    "command_policy": ["mode": "restricted", "reason": "x"], "active_conditions": [resumeCondition]])
        #expect(VacuumStatusResolver.resolve(inputs(attributes: stale)).policyMode == .normal)
    }

    @Test func coherentIssuePrefersAgreeingSources() {
        let contractIssue = VacuumStatusContract.Issue(code: "c", raw: "Stuck", reportedAt: nil, status: .present)
        #expect(VacuumStatusResolver.coherentIssue(contractIssue, VacuumStatusResolver.nativeIssue("Stuck")) == contractIssue)
        #expect(VacuumStatusResolver.coherentIssue(contractIssue, VacuumStatusResolver.nativeIssue("Other")).raw == "Other")
        #expect(VacuumStatusResolver.coherentIssue(contractIssue, .unknown) == .unknown)
        #expect(VacuumStatusResolver.coherentIssue(.clear, .clear) == .clear)
        #expect(VacuumStatusResolver.coherentIssue(.unknown, .clear) == .clear)
    }

    @Test func lastIssueShowsOnlyWhileUncleared() {
        let attributes = statusContract([
            "vacuum_entity_id": "vacuum.valetudo_test", "observed_vacuum_state": "unavailable",
            "availability": ["since": NSNull(), "status": "unavailable"], "command_policy": ["mode": "none", "reason": "primary_unavailable"],
            "current_issue": ["code": NSNull(), "raw": NSNull(), "reported_at": NSNull(), "status": "unknown"],
            "last_issue": ["code": "e", "raw": "Error 75", "reported_at": "2026-08-21T21:20:11Z", "provenance": "recorder_backfill"],
        ])
        #expect(VacuumStatusResolver.resolve(inputs(vacuum: "unavailable", attributes: attributes)).lastIssue?.raw == "Error 75")
        var cleared = attributes
        cleared["last_issue"] = JSONValue(any: ["code": "e", "raw": "Error 75", "reported_at": "2026-08-21T21:20:11Z",
                                                "provenance": "observed", "cleared_at": "2026-08-21T22:00:00Z"])
        #expect(VacuumStatusResolver.resolve(inputs(vacuum: "unavailable", attributes: cleared)).lastIssue == nil)
    }

    @Test func conditionText() {
        func text(_ code: String) -> String { VacuumStatusResolver.conditionText(.init(code: code, since: .distantPast, source: .derived)) }
        #expect(text("vacuum.task_resume_pending") == "Kept for Later")
        #expect(text("mop.vacuum_only_fallback") == "Vacuuming Only")
        #expect(text("dock.return_incomplete") == "Docking May Be Incomplete")
        #expect(text("coordinator.low_water") == "Low water", "web titleCaseState splits on underscores only")
    }
}

@Suite(.demoHouse)
struct VacuumRuntimeTests {
    @Test func fullOnlyWhenACleanCanStart() {
        #expect(VacuumRuntime.mode(policy: .normal, displayState: "docked", statusFlag: "none", error: nil) == .full)
        #expect(VacuumRuntime.mode(policy: .normal, displayState: "idle", statusFlag: nil, error: nil) == .full)
        #expect(VacuumRuntime.mode(policy: .normal, displayState: "error", statusFlag: nil, error: "Stuck") == .full)
        #expect(VacuumRuntime.mode(policy: .normal, displayState: "error", statusFlag: nil, error: "Low battery") == .minimal)
        #expect(VacuumRuntime.mode(policy: .normal, displayState: "cleaning", statusFlag: nil, error: nil) == .minimal)
        #expect(VacuumRuntime.mode(policy: .normal, displayState: "docked", statusFlag: "resumable", error: nil) == .minimal)
        #expect(VacuumRuntime.mode(policy: .restricted, displayState: "docked", statusFlag: nil, error: nil) == .minimal)
    }

    @Test func tabsFollowModeAndConfig() {
        #expect(VacuumRuntime.tabs(for: Vacuums.mainFloor, mode: .full, dockState: "idle") == [.controls, .zones, .autoClean, .more, .info])
        #expect(VacuumRuntime.tabs(for: Vacuums.mainFloor, mode: .minimal, dockState: "idle") == [.controls, .autoClean, .info])
        #expect(VacuumRuntime.tabs(for: Vacuums.mainFloor, mode: .minimal, dockState: "drying") == [.controls, .autoClean, .more, .info])
        #expect(VacuumRuntime.tabs(for: Vacuums.theaterRoom, mode: .full, dockState: nil) == [.controls, .more, .info])
        #expect(VacuumTab.allCases.map(\.title) == ["Controls", "Rooms", "Auto-Clean", "Dock", "Info"])
        #expect(VacuumTab.allCases.allSatisfy { $0.icon.hasPrefix("mdi:") && $0.id == $0.rawValue })
    }

    @Test func visuals() {
        #expect(VacuumVisual.state("cleaning") == .init(icon: "mdi:broom", tone: .active))
        #expect(VacuumVisual.state("Docked").tone == .ok)
        #expect(VacuumVisual.state("error").tone == .danger)
        #expect(VacuumVisual.state("paused").tone == .warning)
        #expect(VacuumVisual.state("returning").tone == .returning)
        #expect(VacuumVisual.state("idle").tone == .neutral)
        #expect(VacuumVisual.state("unavailable").icon == "mdi:robot-vacuum-off")
        #expect(VacuumVisual.dock("cleaning").icon == "mdi:water")
        #expect(VacuumVisual.dock("drying").icon == "mdi:weather-windy")
        #expect(VacuumVisual.dock("emptying").tone == .warning)
        #expect(VacuumVisual.dock("pause").tone == .warning)
        #expect(VacuumVisual.dock("error").tone == .danger)
        #expect(VacuumVisual.dock("idle").tone == .neutral)
        #expect(VacuumVisual.dock(nil).tone == .unavailable)
        let filter = Vacuums.mainFloor.consumables.first { $0.title == "Main Filter" }!
        let dustbag = Vacuums.mainFloor.consumables.first { $0.title == "Dustbag" }!
        #expect(VacuumVisual.consumable(filter, state: "unknown").tone == .unavailable)
        #expect(VacuumVisual.consumable(filter, state: "0").tone == .danger)
        #expect(VacuumVisual.consumable(filter, state: "600").tone == .warning)
        #expect(VacuumVisual.consumable(filter, state: "601").tone == .neutral)
        #expect(VacuumVisual.consumable(filter, state: "soon").tone == .neutral)
        #expect(VacuumVisual.consumable(dustbag, state: "OK").tone == .ok)
        #expect(VacuumVisual.consumable(dustbag, state: "full").tone == .warning)
    }

    @Test func formatting() {
        #expect(StateText.titleCase("vacuum_and_mop") == "Vacuum And Mop")
        #expect(VacuumFormat.state(nil) == "Unavailable")
        #expect(VacuumFormat.state("", fallback: "Vacuum") == "Vacuum")
        #expect(VacuumFormat.state("unknown") == "Unknown")
        #expect(VacuumFormat.state("unavailable") == "Unavailable")
        #expect(VacuumFormat.tileSubtitle(state: "docked", battery: "87") == "Docked • 87%")
        #expect(VacuumFormat.tileSubtitle(state: "docked", battery: "87.5") == "Docked • 87.5%")
        #expect(VacuumFormat.tileSubtitle(state: "unavailable", battery: "87") == "Unavailable")
        #expect(VacuumFormat.tileSubtitle(state: nil, battery: nil) == "Unavailable")
        #expect(VacuumFormat.tileSubtitle(state: "cleaning", battery: "n/a") == "Cleaning")
        #expect(VacuumFormat.passes(nil) == "1x")
        #expect(VacuumFormat.passes("2") == "2x")
        #expect(VacuumFormat.passes("deep") == "Deep")
        let filter = Vacuums.mainFloor.consumables.first { $0.title == "Main Filter" }!
        let dustbag = Vacuums.mainFloor.consumables.first { $0.title == "Dustbag" }!
        #expect(VacuumFormat.consumable(filter, state: nil, unit: nil) == "Unknown")
        #expect(VacuumFormat.consumable(filter, state: "0", unit: "min") == "Due")
        #expect(VacuumFormat.consumable(filter, state: "30", unit: "min") == "30m left")
        #expect(VacuumFormat.consumable(filter, state: "90", unit: "min") == "1.5h left")
        #expect(VacuumFormat.consumable(filter, state: "5400", unit: "min") == "90h left")
        #expect(VacuumFormat.consumable(filter, state: "soon", unit: "min") == "soon min")
        #expect(VacuumFormat.consumable(filter, state: "soon", unit: nil) == "soon")
        #expect(VacuumFormat.consumable(dustbag, state: "ok", unit: nil) == "OK")
        #expect(VacuumFormat.consumable(dustbag, state: "full", unit: nil) == "Full")
        #expect(VacuumFormat.metres(200) == "2 m")
        #expect(VacuumFormat.metres(125) == "1.25 m")
        #expect(VacuumFormat.metres(130) == "1.3 m")
        #expect(VacuumDates.parse("2026-08-21T21:20:11Z") != nil)
        #expect(VacuumDates.parse("2026-08-21T21:20:11.250Z") != nil)
        #expect(VacuumDates.parse("tomorrow") == nil)
    }

    @Test func configHelpers() {
        #expect(Vacuums.all.map(\.title) == ["Main Floor", "Studio", "Media room"])
        #expect(Vacuums.mainFloor.mapCameraEntityId == "camera.\(Vacuums.mainFloor.vacuumMapId)_map_data")
        #expect(Vacuums.outcomeReconciliations(Vacuums.mainFloor.vacuumMapId).count == 11)
        #expect(Vacuums.outcomeReconciliations(Vacuums.musicRoom.vacuumMapId).isEmpty)
        #expect(Vacuums.autoCleanControls[0].isEnabled(state: "off"))
        #expect(!Vacuums.autoCleanControls[0].isEnabled(state: "on"))
        #expect(Vacuums.autoCleanControls[1].isEnabled(state: "on"))
        #expect(Vacuums.autoCleanControls.map(\.domain) == ["switch", "automation", "automation"])
        #expect(Vacuums.mainFloor.zones.first { $0.title == "Closet" }?.segmentName == "Bedroom 1 Closet")
        #expect(Vacuums.musicRoom.zones[0].segmentName == "Studio")
    }
}
