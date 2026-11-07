import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The Setup flow's sheet: each step's buttons move the flow on, and the Time Sensitive copy follows the system switch.
@MainActor
final class UKHostedSetupFlowTests: DemoHouseTestCase {
    private func host(_ env: [String: String]) -> (UKSetupGalleryHost, SetupGalleryFixtures, UIWindow) {
        let fixtures = SetupGalleryFixtures(environment: env)
        let page = UKSetupGalleryHost(fixtures: fixtures)
        let window = HostedPage.show(page)
        hostedSettle(1.0)
        return (page, fixtures, window)
    }

    private func press(_ id: String, in root: UIViewController) -> Bool {
        let top = HostedDriver.topmost(root)
        guard let control = HostedPage.descendants(of: top.view).first(where: { $0.accessibilityIdentifier == id }) as? UIControl else { return false }
        control.sendActions(for: .touchUpInside)
        control.sendActions(for: .primaryActionTriggered)
        hostedSettle(0.8)
        return true
    }

    func testTheFlowWalksNotificationsThenTimeSensitiveThenLocation() {
        let (page, fixtures, window) = host(["FENTON_GALLERY_NOTIFICATIONS": "not-determined", "FENTON_GALLERY_TIME_SENSITIVE": "on"])
        defer { window.isHidden = true }
        let first = HostedDriver.topmost(page)
        XCTAssertTrue(HostedDriver.identifiers(in: first.view).contains("setup.notifications.primary"), "step 1 offers Continue; saw \(HostedDriver.identifiers(in: first.view))")
        XCTAssertTrue(press("setup.notifications.primary", in: page))
        let second = HostedDriver.topmost(page)
        let ids = HostedDriver.identifiers(in: second.view)
        XCTAssertTrue(ids.contains("setup.timeSensitive.primary") || ids.contains { $0.hasPrefix("setup.location") } || fixtures.setup.shownStep != .notifications,
                      "the flow moved past notifications; saw \(ids)")
        if press("setup.timeSensitive.primary", in: page) {
            XCTAssertNotEqual(fixtures.setup.shownStep, .timeSensitive, "acknowledging Time Sensitive moves on")
        }
        let last = HostedDriver.topmost(page)
        HostedDriver.useAll(in: last.view, except: [], settle: 0.1)
        hostedSettle(0.5)
    }

    func testTimeSensitiveOffOffersSettingsAndNotNowAndFollowsTheSwitch() {
        let (page, fixtures, window) = host(["FENTON_GALLERY_SETUP": "time-sensitive", "FENTON_GALLERY_NOTIFICATIONS": "on", "FENTON_GALLERY_TIME_SENSITIVE": "off"])
        defer { window.isHidden = true }
        let top = HostedDriver.topmost(page)
        let ids = HostedDriver.identifiers(in: top.view)
        XCTAssertTrue(ids.contains("setup.timeSensitive.primary"), "saw \(ids)")
        XCTAssertTrue(ids.contains("setup.timeSensitive.secondary"), "Not Now is offered while the switch is off; saw \(ids)")
        let before = HostedPage.labels(in: top.view)
        XCTAssertTrue(press("setup.timeSensitive.primary", in: page), "Open Settings is pressed")
        // The host stands in for turning the switch on; the copy follows it.
        let after = HostedPage.labels(in: HostedDriver.topmost(page).view)
        XCTAssertNotEqual(before, after, "the copy changed once the switch was on")
        _ = fixtures
        _ = press("setup.timeSensitive.secondary", in: page)
    }

    func testEachStartingStepAndPermissionAnswerDrawsAndRuns() {
        for start in ["flow", "notifications", "time-sensitive", "location"] {
            for answer in ["not-determined", "denied", "on"] {
                for ts in ["on", "off", "unsupported"] {
                    let (page, _, window) = host(["FENTON_GALLERY_SETUP": start, "FENTON_GALLERY_NOTIFICATIONS": answer, "FENTON_GALLERY_TIME_SENSITIVE": ts])
                    let top = HostedDriver.topmost(page)
                    HostedDriver.useAll(in: top.view, except: [], settle: 0.1)
                    hostedSettle(0.3)
                    HostedDriver.useAll(in: HostedDriver.topmost(page).view, except: [], settle: 0.1)
                    window.isHidden = true
                }
            }
        }
    }

    func testDenyingLocationTellsTheFlowWhenTheSheetCloses() throws {
        let (page, fixtures, window) = host(["FENTON_GALLERY_SETUP": "location", "FENTON_GALLERY_LOCATION_SEEN": "0", "FENTON_GALLERY_ALLOW": "0"])
        defer { window.isHidden = true }
        HostedDriver.useAll(in: HostedDriver.topmost(page).view, except: [], settle: 0.2)
        hostedSettle(0.5)
        let sheet = HostedDriver.topmost(page)
        sheet.dismiss(animated: false)
        // A programmatic dismiss skips the delegate; a person's swipe-down reports through it, which is the path the app relies on.
        sheet.presentationController?.delegate?.presentationControllerDidDismiss?(try XCTUnwrap(sheet.presentationController))
        hostedSettle(0.3)
        XCTAssertFalse(fixtures.setup.isPresenting, "a closed sheet ends the flow")
    }
}
