import HassCore
import UIKit
import XCTest
@testable import HassUI

/// What the wake-light sheet shows when Home Assistant refuses or never answers a change: an inline error on the list, and on the
/// alarm editor an error with a "reload" button when the alarm changed elsewhere.
@MainActor
final class UKHostedWakeLightErrorTests: DemoHouseTestCase {
    /// Answers every service call with `answer` (or throws when it is nil), after the way Home Assistant would.
    private final class Refusing: HassServiceResponding {
        let answer: JSONValue?
        private(set) var calls: [String] = []
        init(_ answer: JSONValue?) { self.answer = answer }
        func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws { calls.append("\(domain).\(service)") }
        func callServiceWithResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
            calls.append("\(domain).\(service)")
            guard let answer else { throw URLError(.cannotConnectToHost) }
            return answer
        }
    }

    private func open(_ responder: Refusing, states: [EntityState]? = nil) -> (UKHassModalController, UIWindow) {
        let store = EntityStore()
        store.replaceAll(states ?? BedroomFixtures.states(.default), freshness: .live)
        let devices = BedroomDevices(store: store, caller: responder)
        let context = UKGalleryChrome.context(store: store, caller: responder)
        let modal = UKWakeLightSheet.make(devices: devices, context: context)
        let window = HostedScene.show(modal, size: HostedDriver.tall) ?? HostedPage.show(modal, size: HostedDriver.tall)
        FeatureHost.settle(0.5)
        return (modal, window)
    }

    private func firstAlarmRow(in modal: UIViewController) -> UIControl? {
        HostedDriver.controls(in: modal.view).first {
            let id = $0.accessibilityIdentifier ?? ""
            return id.hasPrefix("wake.alarm.") && !id.contains(".enabled") && !id.contains(".link") && !id.contains(".open")
        }
    }

    func testAnAlarmSwitchThatHomeAssistantNeverConfirmsShowsATransportError() throws {
        let responder = Refusing(nil)
        let (modal, window) = open(responder)
        defer { window.isHidden = true }
        let toggle = try XCTUnwrap(HostedDriver.controls(UISwitch.self, in: modal.view).first { ($0.accessibilityIdentifier ?? "").hasSuffix(".enabled") },
                                   "an alarm's on/off switch")
        toggle.isOn.toggle()
        toggle.sendActions(for: .valueChanged)
        XCTAssertTrue(HostedPage.until(8) { FeatureHost.view("wake.error", in: modal.view) != nil }, "the failed change is reported on the list")
        XCTAssertTrue(HostedPage.labels(in: modal.view).contains { $0.contains("did not confirm the change") },
                      "the message says Home Assistant did not confirm; saw \(HostedPage.labels(in: modal.view).prefix(12))")
        XCTAssertTrue(responder.calls.contains("wake_light.command"))
    }

    func testAConflictingSaveOffersToReloadTheAlarmAndReloadingDropsTheEdit() throws {
        let conflict: JSONValue = .object(["response": .object(["outcome": "rejected", "error_code": "revision_conflict", "conflict": "alarm_revision"])])
        let responder = Refusing(conflict)
        let (modal, window) = open(responder)
        defer { window.isHidden = true }
        try XCTUnwrap(firstAlarmRow(in: modal), "an alarm row").sendActions(for: .touchUpInside)
        FeatureHost.settle(0.5)
        let editor = try XCTUnwrap(modal.topViewController as? UKWakeLightEditor)
        let name = try XCTUnwrap(HostedPage.descendants(of: editor.view).compactMap { $0 as? UITextView }.first { $0.accessibilityIdentifier == "wake.editor.name" })
        let original = name.text ?? ""
        name.text = "Changed elsewhere"
        name.delegate?.textViewDidChange?(name)
        FeatureHost.settle(0.2)
        XCTAssertNil(FeatureHost.view("wake.editor.error", in: editor.view), "no error before anything was sent")

        let save = try XCTUnwrap(HostedDriver.control("wake.editor.save", in: editor.view), "Save is enabled for an edited alarm")
        save.sendActions(for: .touchUpInside)
        XCTAssertTrue(HostedPage.until(8) { FeatureHost.view("wake.editor.error", in: editor.view) != nil }, "the refused save is explained")
        XCTAssertTrue(HostedPage.labels(in: editor.view).contains { $0.contains("changed elsewhere") }, "the message says the alarm changed elsewhere")
        let reload = try XCTUnwrap(HostedDriver.control("wake.editor.reload", in: editor.view), "a conflict offers the latest alarm")
        XCTAssertFalse(HostedDriver.controls(in: editor.view).contains { $0.accessibilityIdentifier == "wake.editor.save" && $0.isEnabled },
                       "Save stays off while the alarm is stale")

        reload.sendActions(for: .touchUpInside)
        FeatureHost.settle(0.3)
        XCTAssertEqual(name.text, original, "reloading puts the alarm's saved name back")
        XCTAssertNil(FeatureHost.view("wake.editor.error", in: editor.view), "reloading clears the error")
    }

    private func states(wakeState: String, contract: Double) -> [EntityState] {
        var states = BedroomFixtures.states(.default)
        let id = MasterBedroom.wakeLight.statusEntityId
        let original = states.first { $0.entityId == id }
        states.removeAll { $0.entityId == id }
        var attributes = original?.attributes ?? [:]
        attributes["contract_version"] = .number(contract)
        states.append(EntityState(entityId: id, state: wakeState, attributes: attributes))
        return states
    }

    func testAnOutdatedIntegrationKeepsAlarmsReadableButSaysEditingNeedsAnUpdate() {
        let (modal, window) = open(Refusing(nil), states: states(wakeState: "scheduled", contract: 99))
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.labels(in: modal.view).contains("Editing wake light alarms requires an integration update. Saved alarms remain available to view."),
                      "saw \(HostedPage.labels(in: modal.view).prefix(12))")
    }

    func testAnUnavailableWakeLightSaysItsControlsAreUnavailable() {
        let (modal, window) = open(Refusing(nil), states: states(wakeState: "unavailable", contract: 6))
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.labels(in: modal.view).contains { $0.contains("Wake-light controls are unavailable") },
                      "saw \(HostedPage.labels(in: modal.view).prefix(12))")
    }
}
