import HassCore
import UIKit
import XCTest
@testable import HassUI

/// Debug probes a host script uses to capture a screen without a tap (`xcrun simctl spawn … notifyutil -p`, environment switches):
/// each does what the tap it stands in for does.
@MainActor
final class UKHostedDebugProbeTests: DemoHouseTestCase {
    override func tearDown() {
        for name in ["FENTON_DEBUG_QL_ROOMS", "FENTON_DEBUG_QL_BACK", "FENTON_AUTOSIGNIN", "FENTON_AUTOSIGNIN_DELAY"] { unsetenv(name) }
        super.tearDown()
    }

    func testTheHomeAssistantProbeOpensTheSettingsSheetOnASignedInSession() throws {
        let signedIn = try FeatureHost.signedIn()
        var context = signedIn.context
        context.section = .home
        let page = UKPageViewController(context: context, title: "Probe")
        page.isSectionRoot = true
        let window = HostedPage.show(UINavigationController(rootViewController: page))
        defer { window.isHidden = true }
        page.viewDidAppear(false)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName("uk.debug.haSettings" as CFString), nil, nil, true)
        XCTAssertTrue(HostedPage.until(4) { page.presentedViewController != nil }, "the Home Assistant settings sheet opens without a tap")
    }

    func testTheQuickLinksProbePushesRoomsThenGoesBack() throws {
        setenv("FENTON_DEBUG_QL_ROOMS", "1.0", 1)
        setenv("FENTON_DEBUG_QL_BACK", "1.5", 1)
        let modal = UKQuickLinks.make(context: UKGalleryChrome.context(), choose: { _ in })
        let window = HostedPage.show(modal, size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        XCTAssertEqual(modal.viewControllers.count, 1)
        XCTAssertTrue(HostedPage.until(4) { modal.viewControllers.count == 2 }, "the Rooms page is pushed after the probe's delay")
        XCTAssertTrue(HostedPage.until(6) { modal.viewControllers.count == 1 }, "and popped after the second delay")
    }

    func testTheAutoSignInProbeSubmitsTheFormByItself() {
        setenv("FENTON_AUTOSIGNIN", "1", 1)
        setenv("FENTON_AUTOSIGNIN_DELAY", "0.8", 1)
        var signedIn = false
        let defaults = UserDefaults(suiteName: "hosted.login.probe.\(UUID().uuidString)")!
        let model = LoginModel(mode: .fresh, store: RememberedAccountStore(defaults: defaults), makeFlow: { server in
            HassLoginFlow(server: server, session: DebugSignInStub.session(["FENTON_SIGNIN_STUB": "success"]) ?? .shared)
        })
        let page = UKLoginViewController(model: model, playsIntro: false, environment: nil, onIntroPlayed: {}, onUseDifferentAccount: {},
                                         onSignedIn: { _, _ in signedIn = true })
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 852))
        defer { window.isHidden = true }
        func field(_ id: String) -> UITextField? { HostedPage.descendants(of: page.view).first { $0.accessibilityIdentifier == id } as? UITextField }
        // Sign In needs all three fields (`house-config-states.md` rule 3): a fresh form on fresh defaults has no server yet.
        field("login.server")?.text = "homeassistant.local:8123"
        field("login.server")?.sendActions(for: .editingChanged)
        XCTAssertFalse(model.serverText.isEmpty, "the form has a server, typed or prefilled")
        field("login.username")?.text = "alex"
        field("login.username")?.sendActions(for: .editingChanged)
        field("login.password")?.text = "secret"
        field("login.password")?.sendActions(for: .editingChanged)
        XCTAssertFalse(signedIn)
        XCTAssertTrue(HostedPage.until(6) { signedIn }, "with the probe on, the filled form signs in with no tap")
    }
}
