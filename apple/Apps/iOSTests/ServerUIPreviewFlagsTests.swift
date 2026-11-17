import HassCore
import HassDemoHouse
import UIKit
import XCTest
@testable import HassUI

// MARK: - Preview state flags: parsing and fakes

/// The DEBUG state flags of the `--server-ui-preview` route (``UKServerUIPreviewFlags``): how they are read, and what each fake does.
@MainActor
final class ServerUIPreviewFlagsTests: DemoHouseTestCase {
    private var directory: URL!

    override func setUp() async throws {
        try await super.setUp()
        directory = URL.temporaryDirectory.appendingPathComponent("ServerUIPreviewFlagsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try FileManager.default.removeItem(at: directory)
        UKDesign.animationsPaused = false
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Parsing

    func testNoFlagIsTheDefaultAndLeavesTheBootstrapAlone() throws {
        XCTAssertTrue(UKServerUIPreviewFlags().isDefault)
        XCTAssertTrue(UKServerUIPreviewFlags().receipt.isEmpty)
        XCTAssertNil(UKServerUIPreviewFlags().gateDelay)
        XCTAssertTrue(UKServerUIPreviewFlags().isConnected)
        XCTAssertEqual(UKServerUIPreviewFlags().overlaying(environment: [:]), UKServerUIPreviewFlags())
        let configuration = try JSONDecoder().decode(UKServerUIPreview.Configuration.self, from: Data(#"{"entities":{}}"#.utf8))
        XCTAssertNil(configuration.flags, "A bootstrap with no flags object decodes to no flags")
        let empty = try JSONDecoder().decode(UKServerUIPreviewFlags.self, from: Data("{}".utf8))
        XCTAssertTrue(empty.isDefault)
    }

    func testBootstrapFlagsDecodeEveryKeyAndRejectAnUnknownConnection() throws {
        let json = #"{"connection":"reconnecting","failCalls":true,"empty":true,"gateDelayMs":1200,"animationsPaused":true,"reduceMotion":true}"#
        let flags = try JSONDecoder().decode(UKServerUIPreviewFlags.self, from: Data(json.utf8))
        XCTAssertEqual(flags, UKServerUIPreviewFlags(connection: .reconnecting, failCalls: true, empty: true, gateDelayMs: 1200,
                                                      animationsPaused: true, reduceMotion: true))
        XCTAssertFalse(flags.isDefault)
        XCTAssertEqual(flags.gateDelay, .milliseconds(1200))
        XCTAssertFalse(flags.isConnected)
        XCTAssertThrowsError(try JSONDecoder().decode(UKServerUIPreviewFlags.self, from: Data(#"{"connection":"flaky"}"#.utf8)),
                             "An unknown connection is an error, never a silent default")
        let configuration = try JSONDecoder().decode(UKServerUIPreview.Configuration.self,
                                                     from: Data(#"{"entities":{},"flags":{"empty":true}}"#.utf8))
        XCTAssertEqual(configuration.flags?.empty, true)
    }

    func testTheGateDelayIsHeldBetweenZeroAndTheMaximum() {
        XCTAssertEqual(UKServerUIPreviewFlags(gateDelayMs: -5).gateDelayMs, 0)
        XCTAssertEqual(UKServerUIPreviewFlags(gateDelayMs: 9_999_999).gateDelayMs, UKServerUIPreviewFlags.maximumGateDelayMs)
        XCTAssertEqual(UKServerUIPreviewFlags().overlaying(environment: ["FENTON_GALLERY_GATE_DELAY_MS": "9999999"]).gateDelayMs,
                       UKServerUIPreviewFlags.maximumGateDelayMs)
    }

    func testEachReferenceVariableSetsItsFlag() {
        func flags(_ name: String, _ value: String = "1") -> UKServerUIPreviewFlags {
            UKServerUIPreviewFlags().overlaying(environment: ["FENTON_GALLERY_" + name: value])
        }
        XCTAssertEqual(flags("OFFLINE").connection, .offline)
        XCTAssertEqual(flags("RECONNECTING").connection, .reconnecting)
        XCTAssertTrue(flags("FAIL").failCalls)
        XCTAssertTrue(flags("FAIL_COMPLETE").failCalls)
        XCTAssertTrue(flags("EMPTY").empty)
        XCTAssertEqual(flags("GATE_DELAY_MS", "750").gateDelayMs, 750)
        XCTAssertTrue(flags("PAUSE_CONTINUOUS_ANIMATIONS").animationsPaused)
        XCTAssertTrue(flags("REDUCE_MOTION").reduceMotion)
        for name in ["OFFLINE", "FAIL", "EMPTY", "PAUSE_CONTINUOUS_ANIMATIONS", "REDUCE_MOTION"] {
            XCTAssertTrue(flags(name, "0").isDefault, "\(name)=0 sets nothing")
            XCTAssertTrue(flags(name, "true").isDefault, "Only 1 turns a reference variable on: \(name)")
        }
        XCTAssertNil(flags("GATE_DELAY_MS", "soon").gateDelayMs, "A delay that is not a number is ignored")
        XCTAssertEqual(UKServerUIPreviewFlags().overlaying(environment: ["FENTON_GALLERY_OFFLINE": "1", "FENTON_GALLERY_RECONNECTING": "1"]).connection,
                       .offline, "Offline wins over reconnecting, as the policy does")
        XCTAssertTrue(UKServerUIPreviewFlags().overlaying(environment: ["FENTON_OFFLINE": "1", "OFFLINE": "1", "FENTON_PREVIEW_OFFLINE": "1"]).isDefault,
                      "Only the reference's own names count")
    }

    func testTheEnvironmentIsLaidOverTheBootstrap() {
        let bootstrap = UKServerUIPreviewFlags(connection: .offline, gateDelayMs: 100, animationsPaused: true)
        let merged = bootstrap.overlaying(environment: ["FENTON_GALLERY_RECONNECTING": "1", "FENTON_GALLERY_GATE_DELAY_MS": "250"])
        XCTAssertEqual(merged.connection, .reconnecting, "A variable replaces the bootstrap's connection")
        XCTAssertEqual(merged.gateDelayMs, 250)
        XCTAssertTrue(merged.animationsPaused, "A flag the environment does not name stays")
    }

    func testTheReceiptNamesOnlyTheFlagsThatAreSet() {
        XCTAssertEqual(UKServerUIPreviewFlags(connection: .offline, empty: true).receipt as? [String: AnyHashable],
                       ["connection": "offline", "empty": true])
        let all = UKServerUIPreviewFlags(connection: .reconnecting, failCalls: true, empty: true, gateDelayMs: 5, animationsPaused: true,
                                         reduceMotion: true)
        XCTAssertEqual(Set(all.receipt.keys), ["connection", "failCalls", "empty", "gateDelayMs", "animationsPaused", "reduceMotion"])
    }

    // MARK: Shell header

    func testTheConnectionFlagIsTheShellHeaderStateProductionReads() {
        let base = UKShellHeaderItems.State(profileName: "Alex Demo", attentionCount: 2)
        XCTAssertEqual(UKServerUIPreviewFlags().applying(to: base), base, "Live changes nothing")
        let offline = UKServerUIPreviewFlags(connection: .offline).applying(to: base)
        XCTAssertTrue(offline.isOffline)
        XCTAssertFalse(offline.reconnectingPresent, "Offline never shows the arc (ReconnectingPolicy)")
        let retrying = UKServerUIPreviewFlags(connection: .reconnecting).applying(to: base)
        XCTAssertTrue(retrying.reconnectingPresent)
        XCTAssertTrue(retrying.reconnectingLit)
        XCTAssertFalse(retrying.isOffline)
        XCTAssertEqual(retrying.profileName, "Alex Demo")
        XCTAssertEqual(retrying.attentionCount, 2)
    }

    // MARK: Process switches

    func testTheProcessSwitchesAreSetByTheirFlagsAndRestored() {
        UKDesign.animationsPaused = false
        UKMotion.reduceMotionOverride = nil
        let restore = UKServerUIPreviewFlags(animationsPaused: true, reduceMotion: true).applyProcessSwitches()
        XCTAssertTrue(UKDesign.animationsPaused)
        XCTAssertTrue(UKMotion.reduceMotion)
        XCTAssertTrue(UKDesign.reduceMotion, "The design's one reader follows UKMotion")
        XCTAssertTrue(UKShellEnvironment().reduceMotion, "The shell's mirror follows UKMotion")
        restore()
        XCTAssertFalse(UKDesign.animationsPaused)
        XCTAssertNil(UKMotion.reduceMotionOverride)
    }

    func testAnUnflaggedLaunchLeavesBothSwitchesWhereTheyWere() {
        UKDesign.animationsPaused = true
        UKMotion.reduceMotionOverride = false
        let restore = UKServerUIPreviewFlags().applyProcessSwitches()
        XCTAssertTrue(UKDesign.animationsPaused)
        XCTAssertEqual(UKMotion.reduceMotionOverride, false)
        restore()
        XCTAssertTrue(UKDesign.animationsPaused)
        XCTAssertEqual(UKMotion.reduceMotionOverride, false)
    }

    // MARK: Failing calls

    func testTheFailingCallerAnswersEveryCallWithAnErrorReplyAndSendsNothing() async {
        let caller = UKServerUIPreviewFailingCaller()
        do {
            try await caller.callService("input_boolean", "turn_on", data: ["entity_id": "input_boolean.demo_unit"])
            XCTFail("A call succeeded")
        } catch { XCTAssertEqual(error as? UKServerUIPreviewFault, .callFailed) }
        do {
            _ = try await caller.callServiceWithResponse("weather", "get_forecasts", data: [:])
            XCTFail("A call with a response succeeded")
        } catch { XCTAssertEqual(error as? UKServerUIPreviewFault, .callFailed) }
        XCTAssertEqual(caller.refused, ["input_boolean.turn_on", "weather.get_forecasts"])
        XCTAssertEqual(ServiceErrorText.message(for: UKServerUIPreviewFault.callFailed, fallback: "x"),
                       "Home Assistant could not complete the call.", "The user sees the fault's own words")
    }

    func testTheFlaggedFixturesFailEveryCallAndTheUnflaggedOnesDoNot() async throws {
        let viewer = try XCTUnwrap(DemoHouse.config.chores.people.first)
        let configuration = UKServerUIPreviewFixtures.Configuration(viewerUserID: viewer.haUserId, administrator: true)
        let working = try UKServerUIPreviewFixtures(configuration: configuration, store: EntityStore())
        try await working.caller.callService("input_boolean", "turn_on", data: ["entity_id": "input_boolean.demo_unit"])
        try await working.recordService.callService("todo", "add_item", data: ["entity_id": "todo.demo_todo_2", "item": "Fine"])

        let failing = try UKServerUIPreviewFixtures(configuration: configuration, store: EntityStore(), flags: .init(failCalls: true))
        func assertFault(_ body: () async throws -> Void, _ what: String) async {
            do { try await body(); XCTFail("\(what) succeeded under failCalls") }
            catch { XCTAssertEqual(error as? UKServerUIPreviewFault, .callFailed, what) }
        }
        await assertFault({ try await failing.caller.callService("input_boolean", "turn_on", data: ["entity_id": "input_boolean.demo_unit"]) }, "a device call")
        await assertFault({ _ = try await failing.caller.callServiceWithResponse("wake_light", "command", data: [:]) }, "a response call")
        await assertFault({ try await failing.recordService.callService("todo", "add_item", data: ["entity_id": "todo.demo_todo_2", "item": "No"]) }, "a todo call")
        await assertFault({ _ = try await failing.recordService.callServiceForResponse("donetick", "get_task", data: [:]) }, "a record response call")
        await assertFault({ try await failing.recordService.callService("evershelf", "list_inventory", data: [:]) }, "an inventory call")
        XCTAssertTrue(failing.recordService.inventory.calls.isEmpty, "The inventory fixture never saw a call")
        let todo = try await failing.recordService.todoItems(entityId: "todo.demo_todo_2")
        XCTAssertFalse(todo.isEmpty, "Reads still work: the fault is a failed call, not a missing list")
    }

    // MARK: Empty fixtures

    func testTheEmptyFlagEmptiesEveryListAndTheInventoryButKeepsTheListIds() async throws {
        let full = UKServerUIPreviewFixtureRecords(store: EntityStore())
        let empty = UKServerUIPreviewFixtureRecords(store: EntityStore(), empty: true)
        let fullItems = try await full.todoItems(entityId: "todo.demo_todo_2")
        XCTAssertFalse(fullItems.isEmpty)
        let emptyItems = try await empty.todoItems(entityId: "todo.demo_todo_2")
        XCTAssertTrue(emptyItems.isEmpty, "An empty list, not an unsupported one")
        XCTAssertFalse(full.inventory.rows.isEmpty)
        XCTAssertTrue(empty.inventory.rows.isEmpty)
        try await empty.callService("todo", "add_item", data: ["entity_id": "todo.demo_todo_2", "item": "First"])
        let added = try await empty.todoItems(entityId: "todo.demo_todo_2")
        XCTAssertEqual(added.map(\.summary), ["First"], "An empty list still takes an item")
    }

    // MARK: The preview itself

    private func stage(_ bootstrap: String) throws {
        try Data(bootstrap.utf8).write(to: directory.appendingPathComponent("bootstrap.json"))
    }

    private func receipt() throws -> [String: Any] {
        let data = try Data(contentsOf: directory.appendingPathComponent("receipt.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testThePreviewReadsTheFlagsRecordsThemAndSetsTheSwitchesUntilItLeaves() async throws {
        UKDesign.animationsPaused = false
        try stage(#"{"entities":{},"flags":{"connection":"offline","animationsPaused":true}}"#)
        let preview = UKServerUIPreview(directory: directory, environmentName: "FENTON_FLAGS_TEST_\(UUID().uuidString.prefix(6))",
                                        launchEnvironment: ["FENTON_GALLERY_REDUCE_MOTION": "1"])
        await preview.loadPublication()  // no publication.json: the load fails after the flags were applied
        XCTAssertEqual(preview.flags, UKServerUIPreviewFlags(connection: .offline, animationsPaused: true, reduceMotion: true),
                       "The environment and the bootstrap both count")
        XCTAssertTrue(UKDesign.animationsPaused)
        XCTAssertTrue(UKMotion.reduceMotion)
        let recorded = try XCTUnwrap(receipt()["flags"] as? [String: AnyHashable])
        XCTAssertEqual(recorded, ["connection": "offline", "animationsPaused": true, "reduceMotion": true])
        preview.didMove(toParent: nil)
        XCTAssertFalse(UKDesign.animationsPaused, "Leaving the preview puts the switches back")
        XCTAssertNil(UKMotion.reduceMotionOverride)
    }

    func testAnUnflaggedPreviewWritesNoFlagsAndTouchesNoSwitch() async throws {
        UKDesign.animationsPaused = false
        UKMotion.reduceMotionOverride = nil
        try stage(#"{"entities":{}}"#)
        let preview = UKServerUIPreview(directory: directory, environmentName: "FENTON_FLAGS_TEST_\(UUID().uuidString.prefix(6))",
                                        launchEnvironment: [:])
        await preview.loadPublication()
        XCTAssertTrue(preview.flags.isDefault)
        XCTAssertNil(try receipt()["flags"], "The receipt is as it was before the flags existed")
        XCTAssertFalse(UKDesign.animationsPaused)
        XCTAssertNil(UKMotion.reduceMotionOverride)
    }

    func testTheGateDelayHoldsTheLoadAndTheStatusLineStaysUp() async throws {
        try stage(#"{"entities":{},"flags":{"gateDelayMs":600}}"#)
        let preview = UKServerUIPreview(directory: directory, environmentName: "FENTON_FLAGS_TEST_\(UUID().uuidString.prefix(6))",
                                        launchEnvironment: [:])
        _ = HostedPage.show(preview, size: HostedPage.inScene(CGSize(width: 390, height: 844)))
        defer { HostedPage.hideTracked() }
        let started = ContinuousClock.now
        let load = Task { await preview.loadPublication() }
        HostedPage.wait(0.2)
        XCTAssertNil(preview.renderer, "The first layout has not happened")
        let status = try XCTUnwrap(HostedPage.descendants(of: preview.view).first { $0.accessibilityIdentifier == "server-ui.preview.status" } as? UILabel)
        XCTAssertEqual(status.text, "Downloading configuration...", "The wait shows the loading line, not a failure")
        XCTAssertFalse(status.isHidden)
        XCTAssertTrue(status.adjustsFontForContentSizeCategory)
        await load.value
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - started, .milliseconds(600), "The load waited out the delay")
        XCTAssertNotEqual(status.text, "Downloading configuration...", "After the wait the load went on and reported")
    }
}
