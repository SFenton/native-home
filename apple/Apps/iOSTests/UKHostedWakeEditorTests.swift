import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The wake alarm editor on an existing alarm: switching to a one-time alarm, saving and deleting it with confirmation.
@MainActor
final class UKHostedWakeEditorTests: DemoHouseTestCase {
    private func open(_ scenario: BedroomFixtures.Scenario) throws -> (UKHassModalController, UKWakeLightEditor, LoggingResponder, UIWindow) {
        let store = EntityStore()
        store.replaceAll(BedroomFixtures.states(scenario), freshness: .live)
        let log = LoggingResponder(BedroomGalleryRecorder(store: store))
        let devices = BedroomDevices(store: store, caller: log)
        let context = UKGalleryChrome.context(store: store, caller: log)
        let modal = UKWakeLightSheet.make(devices: devices, context: context)
        // In the app's scene: a window with no scene never finishes a push, so the editor would stay out of the window.
        let window = HostedScene.show(modal, size: HostedDriver.tall) ?? HostedPage.show(modal, size: HostedDriver.tall)
        hostedSettle(0.5)
        let row = HostedDriver.controls(in: modal.view).first {
            let id = $0.accessibilityIdentifier ?? ""
            return id.hasPrefix("wake.alarm.") && !id.contains(".enabled") && !id.contains(".link") && !id.contains(".open")
        }
        try XCTUnwrap(row, "an alarm row").sendActions(for: .touchUpInside)
        hostedSettle(0.5)
        let editor = try XCTUnwrap(modal.topViewController as? UKWakeLightEditor)
        return (modal, editor, log, window)
    }

    func testChangingAnAlarmToOneTimeAndSavingSendsAnUpsert() throws {
        let (_, editor, log, window) = try open(.default)
        defer { window.isHidden = true }
        let kind = try XCTUnwrap(HostedDriver.controls(UISegmentedControl.self, in: editor.view).first { ($0.accessibilityIdentifier ?? "").contains("kind") }
                                 ?? HostedDriver.controls(UISegmentedControl.self, in: editor.view).first)
        kind.selectedSegmentIndex = 1
        kind.sendActions(for: .valueChanged)
        hostedSettle(0.3)
        let name = HostedPage.descendants(of: editor.view).compactMap { $0 as? UITextField }.first
        name?.text = "Weekend lie-in"
        name?.sendActions(for: .editingChanged)
        hostedSettle(0.2)
        HostedDriver.useAll(in: editor.view, except: ["close", "done", "dismiss", "delete"], settle: 0.05)
        hostedSettle(0.3)
        if let save = HostedDriver.controls(in: editor.view).first(where: { ($0.accessibilityLabel ?? "") == "Save" }) {
            save.sendActions(for: .touchUpInside)
        } else if let item = editor.navigationItem.rightBarButtonItem?.primaryAction {
            item.performWithSender(nil, target: nil)
        }
        hostedSettle(0.8)
        XCTAssertTrue(log.calls.contains("wake_light.command"), "saving sends a wake_light command; saw \(log.calls)")
    }

    func testDeletingAnAlarmAsksFirstThenSendsTheDelete() throws {
        let (modal, editor, log, window) = try open(.default)
        defer { window.isHidden = true }
        let delete = try XCTUnwrap(HostedDriver.controls(in: editor.view).first { ($0.accessibilityLabel ?? "").hasPrefix("Delete") }, "a Delete button")
        let before = log.calls.count
        delete.sendActions(for: .touchUpInside)
        hostedSettle(0.5)
        XCTAssertEqual(log.calls.count, before, "nothing is deleted before the person confirms")
        let alert = try XCTUnwrap(FeatureHost.alert(on: modal), "a confirmation appears")
        let title = alert.actions.first { $0.style == .destructive }?.title
        XCTAssertTrue(FeatureHost.answer(alert, title))
        hostedSettle(0.8)
        XCTAssertGreaterThan(log.calls.count, before, "confirming sends the delete; saw \(log.calls)")
    }
}
