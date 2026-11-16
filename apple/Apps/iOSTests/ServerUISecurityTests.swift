import HassCore
import UIKit
import XCTest
@testable import HassUI

// MARK: - Synthetic configured security journeys

@MainActor
enum ServerUISecurityHostedFixture {
    static func json() throws -> JSONValue {
        let apple = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let nodes = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf:
            apple.appendingPathComponent("Tests/HassCoreTests/ServerUISecurityNodes.json")))
        var root = try ServerUIRendererFixture.json()
        let sources = try XCTUnwrap(root["document"]?["dataSources"]?.array) + XCTUnwrap(nodes["sources"]?.array)
        var components = try XCTUnwrap(root["document"]?["pages"]?.array?[0]["components"]?.array) + XCTUnwrap(nodes["components"]?.array)
        var sheetLink = try XCTUnwrap(components[0]["children"]?.array?[1])
        sheetLink = try ServerUIRendererFixture.changing(sheetLink, path: "/id", to: .string("demo-open-sheet"))
        sheetLink = try ServerUIRendererFixture.changing(sheetLink, path: "/action", to: .object([
            "type": .string("present"), "modalId": .string("demo-alarm-sheet"), "arguments": .object([:]), "ifPresented": .string("reject")
        ]))
        components.append(sheetLink)
        root = try ServerUIRendererFixture.changing(root, path: "/document/dataSources", to: .array(sources))
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components", to: .array(components))
        var pages = try XCTUnwrap(root["document"]?["pages"]?.array)
        var local = pages[2]
        local = try ServerUIRendererFixture.changing(local, path: "/id", to: .string("demo-local-alarm"))
        var panel = try XCTUnwrap(nodes["components"]?.array?.first)
        panel = try ServerUIRendererFixture.changing(panel, path: "/id", to: .string("demo-local-panel"))
        local = try ServerUIRendererFixture.changing(local, path: "/components", to: .array([panel]))
        local = try ServerUIRendererFixture.changing(local, path: "/toolbar", to: .object(["type": .string("replace"), "groups": .array([])]))
        pages.append(local)
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages", to: .array(pages))
        var link = try XCTUnwrap(components[0]["children"]?.array?[1])
        link = try ServerUIRendererFixture.changing(link, path: "/id", to: .string("demo-local-link"))
        link = try ServerUIRendererFixture.changing(link, path: "/title", to: .string("Security System"))
        link = try ServerUIRendererFixture.changing(link, path: "/action/pageId", to: .string("demo-local-alarm"))
        link = try ServerUIRendererFixture.changing(link, path: "/props/selected", to: .string("none"))
        link = try ServerUIRendererFixture.changing(link, path: "/props/subtitle", to: .object([
            "type": .string("literal"), "value": .string("")
        ]))
        let panelProps = try XCTUnwrap(panel["props"])
        let alarm = try Dictionary(uniqueKeysWithValues:
            ["sourceId", "states", "fallback", "loadingText", "unavailableText", "errorText", "hiddenText"].map {
                ($0, try XCTUnwrap(panelProps[$0]))
            }).merging(["projection": .string("alarm-navigation@1")]) { _, new in new }
        link = try ServerUIRendererFixture.changing(link, path: "/props/alarm", to: .object(alarm))
        root = try ServerUIRendererFixture.changing(root, path: "/document/modals/0/title", to: .string("Quick Links"))
        root = try ServerUIRendererFixture.changing(root, path: "/document/modals/0/components", to: .array([link]))
        var standalone = try XCTUnwrap(root["document"]?["modals"]?.array?.first)
        standalone = try ServerUIRendererFixture.changing(standalone, path: "/id", to: .string("demo-alarm-sheet"))
        standalone = try ServerUIRendererFixture.changing(standalone, path: "/title", to: .string("Security System"))
        standalone = try ServerUIRendererFixture.changing(standalone, path: "/layout/maxWidth", to: .object([
            "type": .string("points"), "value": .number(560)
        ]))
        standalone = try ServerUIRendererFixture.changing(standalone, path: "/presentation/height", to: .object([
            "type": .string("fitted"), "follows": .string("top-page"), "firstOpen": .string("canonical@1")
        ]))
        let sheetPanel = try ServerUIRendererFixture.changing(panel, path: "/id", to: .string("demo-sheet-panel"))
        standalone = try ServerUIRendererFixture.changing(standalone, path: "/components", to: .array([sheetPanel]))
        let modals = try XCTUnwrap(root["document"]?["modals"]?.array) + [standalone]
        root = try ServerUIRendererFixture.changing(root, path: "/document/modals", to: .array(modals))
        return try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array(
            (ServerUICompositionPublication.firstSliceCapabilities
                + ["sh.alarm-mode@1", "sh.alarm-panel@1", "sh.security-door@1", "sh.sheet-fit@1", "sh.tile-presentation@1"])
                .sorted().map(JSONValue.string)))
    }

    static func host(size: CGSize = CGSize(width: 393, height: 852)) throws -> (UKServerUIRenderer, UIWindow, HostedCaller) {
        let caller = HostedCaller()
        let (host, window) = try host(caller: caller, size: size)
        return (host, window, caller)
    }

    static func host(caller: any HassServiceCalling, size: CGSize = CGSize(width: 393, height: 852)) throws -> (UKServerUIRenderer, UIWindow) {
        let store = EntityStore()
        store.replaceAll([
            EntityState(entityId: "alarm_control_panel.demo_unit", state: "armed_home"),
            EntityState(entityId: "lock.demo_unit", state: "locked"),
            EntityState(entityId: "cover.demo_unit", state: "closed"),
        ])
        let host = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(json()),
                                         context: UKContext(store: store, caller: caller), backdrop: ServerUIRendererFixture.backdrop())
        let window = HostedPage.show(host, size: HostedPage.inScene(size))
        HostedPage.wait(0.1)
        return (host, window)
    }
}

@MainActor
final class ServerUISecurityHostedTests: XCTestCase {
    override func tearDown() async throws {
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    /// Runs unchanged on the parent's iPhone, Duo and iPad test plans.
    func testConfiguredPanelHasOrderedAccessibleControlsAndLiveUpdatesRetainIdentity() throws {
        for size in [CGSize(width: 393, height: 852), CGSize(width: 540, height: 720), CGSize(width: 1080, height: 720), CGSize(width: 834, height: 1194)] {
            let (host, window, caller) = try ServerUISecurityHostedFixture.host(size: size)
            let page = try ServerUIRendererFixture.root(host)
            let panel = try XCTUnwrap(page.nodes["demo-panel-control"]?.view as? UKAlarmPanelControl)
            XCTAssertTrue(panel.followsFold)
            let buttons = HostedPage.descendants(of: panel).compactMap { $0 as? UKAlarmModeButton }
            XCTAssertEqual(buttons.map(\.accessibilityLabel), ["Disarm", "Home", "Away", "Night"])
            XCTAssertTrue(buttons[1].accessibilityTraits.contains(.selected))
            XCTAssertTrue(buttons.allSatisfy { $0.accessibilityTraits.contains(.button) && !$0.accessibilityIdentifier!.isEmpty })
            XCTAssertTrue(buttons.allSatisfy { $0.bounds.height >= 44 && $0.bounds.width >= 44 })
            buttons[1].sendActions(for: .touchUpInside)
            XCTAssertTrue(caller.calls.isEmpty, "Choosing the current mode is a no-op")
            host.pageContext.store.apply([EntityState(entityId: "alarm_control_panel.demo_unit", state: "armed_night")])
            HostedPage.until { buttons[3].accessibilityTraits.contains(.selected) }
            XCTAssertTrue(page.nodes["demo-panel-control"]?.view === panel)
            XCTAssertTrue(buttons[3].accessibilityTraits.contains(.selected))
            host.pageContext.store.apply([EntityState(entityId: "alarm_control_panel.demo_unit", state: "unavailable")])
            HostedPage.until { !buttons[0].isEnabled }
            XCTAssertTrue(buttons.allSatisfy { !$0.isEnabled })
            XCTAssertTrue(caller.calls.isEmpty)
            window.isHidden = true
        }
    }

    func testStandaloneAlarmUsesASheetSurfaceWithoutPushingTheRootStack() async throws {
        let (host, window, caller) = try ServerUISecurityHostedFixture.host()
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let original = host.navigation.snapshot.stacks
        let component = try XCTUnwrap(root.definition.components.last)
        guard case .navigationTile(let open) = component else { return XCTFail("Expected sheet link") }
        host.activate(open.action, from: root)
        let opened = await FeatureHost.settleAsync(until: { host.modal?.topViewController is UKServerUIPage && host.modal?.isBeingPresented == false })
        XCTAssertTrue(opened)
        let sheet = try XCTUnwrap(host.modal?.topViewController as? UKServerUIPage)
        sheet.loadViewIfNeeded()
        let panel = try XCTUnwrap(sheet.nodes["demo-sheet-panel"]?.view as? UKAlarmPanelControl)
        XCTAssertFalse(panel.followsFold)
        XCTAssertEqual(sheet.context.surface, .sheet)
        XCTAssertNotNil(sheet.sheetFitScrollView)
        XCTAssertEqual(host.navigation.snapshot.stacks, original)
        XCTAssertEqual(host.modal?.viewControllers.count, 1)
        XCTAssertTrue(caller.calls.isEmpty)
    }

    func testReadOnlyAndLoadingSourcesCannotReserveCommands() throws {
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "alarm_control_panel.demo_unit", state: "armed_home")])
        let readOnly = UKServerUIAlarmSource(entityID: "alarm_control_panel.demo_unit", context: UKContext(store: store))
        XCTAssertFalse(readOnly.canSend)
        XCTAssertEqual(readOnly.modeSpec("disarmed", confirmation: StateStyle.alarmDisarmConfirmation)?.phase, .unavailable)
        let caller = HostedCaller()
        let expected = try XCTUnwrap(readOnly.modeSpec("disarmed", confirmation: StateStyle.alarmDisarmConfirmation))
        XCTAssertThrowsError(try readOnly.reserveMode("disarmed", expected: expected, confirmation: StateStyle.alarmDisarmConfirmation))
        var loading = UKContext(store: EntityStore(), caller: caller)
        loading.valuesPending = true
        let loadingSource = UKServerUIAlarmSource(entityID: "alarm_control_panel.demo_unit", context: loading)
        XCTAssertFalse(loadingSource.canSend)
        XCTAssertTrue(caller.calls.isEmpty)
    }

    func testDisarmUsesAuthoredQuestionAndCancelOrStaleConfirmationCannotSend() async throws {
        let (host, window, caller) = try ServerUISecurityHostedFixture.host()
        defer { window.isHidden = true }
        let page = try ServerUIRendererFixture.root(host)
        let panel = try XCTUnwrap(page.nodes["demo-panel-control"]?.view as? UKAlarmPanelControl)
        let button = try XCTUnwrap(HostedPage.descendants(of: panel).compactMap { $0 as? UKAlarmModeButton }.first)
        button.sendActions(for: .touchUpInside)
        let model = try XCTUnwrap(host.bindings.alarms["demo-alarm"])
        var alert = try XCTUnwrap(FeatureHost.alert(on: page))
        XCTAssertEqual(alert.title, "Disarm the Security System?")
        XCTAssertTrue(caller.calls.isEmpty)
        XCTAssertTrue(FeatureHost.answer(alert, "Cancel"))
        XCTAssertFalse(model.hasPendingIntent)
        let dismissed = await FeatureHost.settleAsync(until: { FeatureHost.alert(on: page) == nil })
        XCTAssertTrue(dismissed)
        button.sendActions(for: .touchUpInside)
        alert = try XCTUnwrap(FeatureHost.alert(on: page))
        host.pageContext.store.apply([EntityState(entityId: "alarm_control_panel.demo_unit", state: "armed_away")])
        var errors: [UKServerUIRendererError] = []
        host.onError = { errors.append($0) }
        XCTAssertTrue(FeatureHost.answer(alert, "Disarm"))
        XCTAssertTrue(caller.calls.isEmpty)
        XCTAssertEqual(errors.last?.code, .unavailableSource)
    }

    func testQuickLinksPushesConfiguredAlarmInsideTheExistingModalWithoutCommands() async throws {
        let (host, window, caller) = try ServerUISecurityHostedFixture.host()
        defer { window.isHidden = true }
        let root = try ServerUIRendererFixture.root(host)
        let shellPath = host.navigation.snapshot.stacks
        guard case .button(let open) = host.publication.document.navigation.chrome.groups[1].items[0] else {
            return XCTFail("Expected modal navigation action")
        }
        host.activate(open.action, from: root)
        let opened = await FeatureHost.settleAsync(until: { host.modal?.topViewController is UKServerUIPage && host.modal?.isBeingPresented == false })
        XCTAssertTrue(opened)
        let modalPage = try XCTUnwrap(host.modal?.topViewController as? UKServerUIPage)
        guard case .navigationTile(let link) = modalPage.definition.components[0] else { return XCTFail("Expected local push") }
        host.activate(link.action, from: modalPage)
        let pushed = await FeatureHost.settleAsync(until: { host.modal?.viewControllers.count == 2 })
        XCTAssertTrue(pushed)
        let local = try XCTUnwrap(host.modal?.topViewController as? UKServerUIPage)
        local.loadViewIfNeeded()
        XCTAssertTrue(local.nodes["demo-local-panel"]?.view is UKAlarmPanelControl)
        XCTAssertEqual(host.navigation.snapshot.stacks, shellPath)
        XCTAssertEqual(host.navigation.snapshot.presentations.count, 1)
        XCTAssertTrue(caller.calls.isEmpty)
        host.activate(.back, from: local)
        let returned = await FeatureHost.settleAsync(until: { host.modal?.viewControllers.count == 1 })
        XCTAssertTrue(returned)
    }

    func testLockAndGarageUseTheirCanonicalCommandsAndImmutableExecutionTargets() async throws {
        let (host, window, caller) = try ServerUISecurityHostedFixture.host()
        defer { window.isHidden = true }
        let lock = try XCTUnwrap(host.bindings.doors["demo-lock"])
        let ticket = try lock.reserve(expected: lock.spec)
        host.pageContext.store.apply([EntityState(entityId: "lock.demo_unit", state: "unlocked")])
        XCTAssertThrowsError(try lock.execute(ticket))
        XCTAssertTrue(caller.calls.isEmpty)
        try lock.execute(lock.reserve(expected: lock.spec))
        await lock.completion?.value
        XCTAssertEqual(caller.calls, ["lock.lock"])
        XCTAssertEqual(caller.data.last?["entity_id"] as? String, "lock.demo_unit")
        let door = try XCTUnwrap(host.bindings.doors["demo-garage"])
        try door.execute(door.reserve(expected: door.spec))
        XCTAssertThrowsError(try door.reserve(expected: door.spec), "No double tap during the sending lockout")
        await door.garage?.waitForCall()
        XCTAssertEqual(caller.calls.last, "cover.open_cover")
        XCTAssertEqual(caller.data.last?["entity_id"] as? String, "cover.demo_unit")
        XCTAssertEqual(door.garage?.phase, .pending)
    }

    func testPanelModesSendConfiguredTargetAndDisarmStillRequiresConfirmationAfterArming() async throws {
        let (host, window, caller) = try ServerUISecurityHostedFixture.host()
        defer { window.isHidden = true }
        let page = try ServerUIRendererFixture.root(host)
        let panel = try XCTUnwrap(page.nodes["demo-panel-control"]?.view as? UKAlarmPanelControl)
        let buttons = HostedPage.descendants(of: panel).compactMap { $0 as? UKAlarmModeButton }
        buttons[2].sendActions(for: .touchUpInside)
        let source = try XCTUnwrap(host.bindings.alarms["demo-alarm"])
        await source.completion?.value
        XCTAssertEqual(caller.calls, ["alarm_control_panel.alarm_arm_away"])
        XCTAssertEqual(caller.data.last?["entity_id"] as? String, "alarm_control_panel.demo_unit")
        let rendered = await FeatureHost.settleAsync(until: { buttons[0].isEnabled })
        XCTAssertTrue(rendered)
        buttons[0].sendActions(for: .touchUpInside)
        let alert = try XCTUnwrap(FeatureHost.alert(on: page))
        let shown = await FeatureHost.settleAsync(until: { !alert.isBeingPresented })
        XCTAssertTrue(shown)
        XCTAssertEqual(caller.calls.count, 1)
        XCTAssertTrue(FeatureHost.answer(alert, "Disarm"))
        await source.completion?.value
        XCTAssertEqual(caller.calls, ["alarm_control_panel.alarm_arm_away", "alarm_control_panel.alarm_disarm"])
        XCTAssertEqual(source.shownState, "disarmed")
    }

    func testNetworkLifetimePinsAlarmAndLockSourcesAfterLiveAcknowledgement() async throws {
        let publication = try ServerUIRendererFixture.publication(ServerUISecurityHostedFixture.json())
        let store = EntityStore()
        store.replaceAll([
            EntityState(entityId: "alarm_control_panel.demo_unit", state: "disarmed"),
            EntityState(entityId: "lock.demo_unit", state: "locked"),
        ])
        let caller = SecurityHostedHeldCaller()
        defer { caller.finish() }
        let bindings = UKServerUIBindings(sources: publication.document.dataSources, context: UKContext(store: store, caller: caller))
        let source = try XCTUnwrap(bindings.alarms["demo-alarm"])
        let expected = try XCTUnwrap(source.modeSpec("armed_away", confirmation: StateStyle.alarmDisarmConfirmation))
        try source.execute(source.reserveMode("armed_away", expected: expected, confirmation: StateStyle.alarmDisarmConfirmation))
        await caller.waitForStart()
        store.apply([EntityState(entityId: "alarm_control_panel.demo_unit", state: "arming")])
        let changed = try ServerUIRendererFixture.changing(ServerUISecurityHostedFixture.json(),
            path: "/document/dataSources/2/inputs/entityId/value", to: .string("alarm_control_panel.demo_other_demo"))
        let replacement = try ServerUIRendererFixture.publication(changed)
        XCTAssertThrowsError(try bindings.validateReplacement(replacement.document.dataSources))
        XCTAssertTrue(source.hasPendingIntent)
        XCTAssertThrowsError(try source.reserveMode("armed_night",
            expected: XCTUnwrap(source.modeSpec("armed_night", confirmation: StateStyle.alarmDisarmConfirmation)),
            confirmation: StateStyle.alarmDisarmConfirmation))
        caller.finish(failing: true)
        await source.completion?.value
        XCTAssertEqual(source.shownState, "arming", "An old failure must not overwrite live acknowledgement")

        let lock = try XCTUnwrap(bindings.doors["demo-lock"])
        try lock.execute(lock.reserve(expected: lock.spec))
        await caller.waitForStart()
        store.apply([EntityState(entityId: "lock.demo_unit", state: "unlocked")])
        let retargeted = try ServerUIRendererFixture.changing(ServerUISecurityHostedFixture.json(),
            path: "/document/dataSources/3/inputs/entityId/value", to: .string("lock.demo_other_demo"))
        XCTAssertThrowsError(try bindings.validateReplacement(ServerUIRendererFixture.publication(retargeted).document.dataSources))
        XCTAssertTrue(lock.hasPendingIntent)
        caller.finish(failing: true)
        await lock.completion?.value
        XCTAssertEqual(lock.state, "unlocked")
    }

    func testPublicationCannotRemoveOrReconfigureAPendingPanel() async throws {
        let caller = SecurityHostedHeldCaller()
        defer { caller.finish() }
        let (host, window) = try ServerUISecurityHostedFixture.host(caller: caller)
        defer { window.isHidden = true }
        let source = try XCTUnwrap(host.bindings.alarms["demo-alarm"])
        let expected = try XCTUnwrap(source.modeSpec("armed_away", confirmation: StateStyle.alarmDisarmConfirmation))
        try source.execute(source.reserveMode("armed_away", expected: expected, confirmation: StateStyle.alarmDisarmConfirmation))
        await caller.waitForStart()
        var candidate = try ServerUISecurityHostedFixture.json()
        var nodes = try XCTUnwrap(candidate["document"]?["pages"]?.array?[0]["components"]?.array)
        nodes.remove(at: 1)
        candidate = try ServerUIRendererFixture.changing(candidate, path: "/document/pages/0/components", to: .array(nodes))
        let removed = try ServerUIRendererFixture.publication(candidate)
        XCTAssertThrowsError(try host.validateUpdate(removed))
        let changed = try ServerUIRendererFixture.changing(ServerUISecurityHostedFixture.json(),
            path: "/document/pages/0/components/1/props/modes/1/label", to: .string("Changed during call"))
        XCTAssertThrowsError(try host.validateUpdate(ServerUIRendererFixture.publication(changed)))
        caller.finish(failing: true)
        await source.completion?.value
        try host.validateUpdate(removed)
    }

    func testSharedSectionCannotHideAPendingPanelsReconfiguration() async throws {
        var root = try ServerUISecurityHostedFixture.json()
        let panel = try XCTUnwrap(root["document"]?["pages"]?.array?[0]["components"]?.array?[1])
        let section = JSONValue.object([
            "id": "security-section", "title": "Security", "type": "section", "layout": .object(["span": .number(1)]),
            "props": .object(["header": "", "footer": "", "style": "plain", "density": "thin", "hasGlyphs": false,
                              "spacing": .object(["type": "token", "name": "m"])]),
            "children": .array([panel])
        ])
        root = try ServerUIRendererFixture.changing(root, path: "/document/pages/0/components/1", to: section)
        let capabilities = try XCTUnwrap(root["capabilities"]?.array).compactMap(\.string) + ["sh.section@1"]
        root = try ServerUIRendererFixture.changing(root, path: "/capabilities", to: .array(capabilities.sorted().map(JSONValue.string)))
        let store = EntityStore()
        store.replaceAll([EntityState(entityId: "alarm_control_panel.demo_unit", state: "armed_home")])
        let caller = SecurityHostedHeldCaller()
        defer { caller.finish() }
        let host = try UKServerUIRenderer(publication: ServerUIRendererFixture.publication(root),
            context: UKContext(store: store, caller: caller), backdrop: ServerUIRendererFixture.backdrop())
        let source = try XCTUnwrap(host.bindings.alarms["demo-alarm"])
        let expected = try XCTUnwrap(source.modeSpec("armed_away", confirmation: StateStyle.alarmDisarmConfirmation))
        try source.execute(source.reserveMode("armed_away", expected: expected, confirmation: StateStyle.alarmDisarmConfirmation))
        await caller.waitForStart()
        let changed = try ServerUIRendererFixture.changing(root,
            path: "/document/pages/0/components/1/children/0/props/modes/1/label", to: .string("Changed during call"))
        let candidate = try ServerUIRendererFixture.publication(changed)
        XCTAssertThrowsError(try host.validateUpdate(candidate)) {
            XCTAssertEqual(($0 as? UKServerUIRendererError)?.code, .interactionBlocked)
        }
        caller.finish(failing: true)
        await source.completion?.value
        try host.validateUpdate(candidate)
    }
}

// MARK: - Controlled service completion

@MainActor
private final class SecurityHostedHeldCaller: HassServiceCalling {
    struct Failure: Error {}
    private var continuation: CheckedContinuation<Void, Error>?
    private var started: CheckedContinuation<Void, Never>?

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            started?.resume()
            started = nil
        }
    }

    func waitForStart() async {
        if continuation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(failing: Bool = false) {
        let pending = continuation
        continuation = nil
        if failing { pending?.resume(throwing: Failure()) } else { pending?.resume() }
    }
}
