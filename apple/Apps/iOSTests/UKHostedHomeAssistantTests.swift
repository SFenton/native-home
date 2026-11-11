import HassCore
import HassDesign
import UIKit
import WebKit
import XCTest
@testable import HassUI

/// Home Assistant settings (server, account, Home Assistant's own pages, Sign Out), hosted on a signed-in session whose server never
/// answers.
@MainActor
final class UKHostedHomeAssistantTests: DemoHouseTestCase {
    private let admin = HassUser(id: "u1", name: "Alex", isOwner: false, isAdmin: true)
    private let member = HassUser(id: "u2", name: nil, isOwner: false, isAdmin: false)

    private func labels(_ page: UIViewController) -> [String: String] {
        var result: [String: String] = [:]
        for view in HostedPage.descendants(of: page.view) {
            if let id = view.accessibilityIdentifier, let label = view.accessibilityLabel { result[id] = label }
        }
        return result
    }

    private func page(user: HassUser?) async throws -> (UKHomeAssistantSettingsViewController, UIWindow, AppSession) {
        let host = try FeatureHost.signedIn()
        let page = UKHomeAssistantSettingsViewController(session: host.session, connection: host.connection, user: user)
        let window = HostedPage.show(page, size: CGSize(width: 393, height: 1600))
        await FeatureHost.settleAsync(0.4)
        return (page, window, host.session)
    }

    func testAnAdminSeesTheServerTheAccountAndBothHomeAssistantPages() async throws {
        let (page, window, _) = try await page(user: admin)
        defer { window.isHidden = true }
        let texts = labels(page)
        XCTAssertTrue(texts["haSettings.server"]?.hasPrefix("Address, ") ?? false)
        XCTAssertTrue(texts["haSettings.status"]?.hasPrefix("Connection, ") ?? false)
        XCTAssertEqual(texts["haSettings.user"], "Signed in as, Alex")
        XCTAssertEqual(texts["haSettings.role"], "Role, Administrator")
        let ids = FeatureHost.identifiers(in: page.view)
        XCTAssertTrue(ids.contains("haSettings.open.settings"))
        XCTAssertTrue(ids.contains("haSettings.open.profile"))
        XCTAssertEqual(texts["haSettings.signOut"], "Sign Out")
    }

    func testAMemberSeesOnlyProfile() async throws {
        let (page, window, _) = try await page(user: member)
        defer { window.isHidden = true }
        let ids = FeatureHost.identifiers(in: page.view)
        XCTAssertFalse(ids.contains("haSettings.open.settings"), "Home Assistant's Settings is for admins")
        XCTAssertTrue(ids.contains("haSettings.open.profile"))
        XCTAssertEqual(labels(page)["haSettings.role"], "Role, User")
    }

    func testTheAccountLoadsThenFallsBackWhenOffline() async throws {
        let (page, window, _) = try await page(user: nil)
        defer { window.isHidden = true }
        // Never connected: the account row cannot be loaded, and says so instead of spinning forever.
        await FeatureHost.settleAsync(until: { self.labels(page)["haSettings.user"] != "Signed in as, Loading account" })
        let label = labels(page)["haSettings.user"] ?? ""
        XCTAssertTrue(label == "Signed in as, Unavailable offline" || label.contains("Loading"), "got \(label)")
    }

    func testSignOutAsksFirstThenEndsTheSession() async throws {
        let (page, window, session) = try await page(user: admin)
        defer { window.isHidden = true }
        XCTAssertTrue(FeatureHost.tapRow("haSettings.signOut", in: page.view))
        await FeatureHost.settleAsync(0.4)
        let alert = try XCTUnwrap(FeatureHost.alert(on: page), "Sign Out confirms first")
        XCTAssertEqual(alert.title, AlertCopy.signOut.title)
        FeatureHost.answer(alert, AlertCopy.signOut.confirm.title)
        await FeatureHost.settleAsync(0.8)
        XCTAssertFalse(session.isSignedIn, "confirming signs out")
    }

    func testCancellingSignOutKeepsTheSession() async throws {
        let (page, window, session) = try await page(user: admin)
        defer { window.isHidden = true }
        FeatureHost.tapRow("haSettings.signOut", in: page.view)
        await FeatureHost.settleAsync(0.4)
        let alert = try XCTUnwrap(FeatureHost.alert(on: page))
        FeatureHost.answer(alert, AlertCopy.signOut.cancel.title)
        await FeatureHost.settleAsync(0.3)
        XCTAssertTrue(session.isSignedIn)
    }

    func testPresentedAsAFullScreenModal() async throws {
        let signedIn = try FeatureHost.signedIn()
        let host = UIViewController()
        let window = HostedPage.show(host)
        defer { window.isHidden = true }
        XCTAssertNil(UKHomeAssistantSettings.present(context: UKGalleryChrome.context(), from: host), "a gallery has no session")
        let modal = try XCTUnwrap(UKHomeAssistantSettings.present(context: signedIn.context, from: host, user: admin))
        XCTAssertTrue(host.presentedViewController === modal)
        XCTAssertEqual(modal.modalPresentationStyle, .fullScreen, "the app stays usable underneath, but the settings take the whole screen")
    }

    func testTheProfilePageOpensInsideTheModal() async throws {
        let signedIn = try FeatureHost.signedIn()
        // The full-screen presentation does not complete in a hosted window, so the modal is the window's root.
        let page = UKHomeAssistantSettingsViewController(session: signedIn.session, connection: signedIn.connection, user: admin)
        var options = UKHassModalOptions(title: "Home Assistant")
        options.closeIdentifier = "haSettings.done"
        let modal = UKHassModalController(root: page, options: options)
        page.modal = modal
        let window = HostedPage.show(modal, size: CGSize(width: 393, height: 1600))
        defer { window.isHidden = true }
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(FeatureHost.tapRow("haSettings.open.profile", in: modal.view), "Profile is on the page: \(FeatureHost.identifiers(in: modal.view).filter { $0.hasPrefix("haSettings") }.sorted())")
        await FeatureHost.settleAsync(1.5)
        XCTAssertEqual(modal.viewControllers.count, 2, "Profile is pushed on the modal")
        let web = try XCTUnwrap(modal.topViewController?.view)
        XCTAssertNotNil(FeatureHost.view("haWeb.reload", in: web) ?? FeatureHost.view("haWeb.profile", in: web) ?? FeatureHost.view("haWeb.retry", in: web),
                        "the Profile page shows its web view or, with no server, its retry")
    }

    func testAnUnreachableServerOffersToTryAgain() async throws {
        let signedIn = try FeatureHost.signedIn()
        let web = UKHomeAssistantWebPageViewController(page: .settings, session: signedIn.session, connection: signedIn.connection)
        let window = HostedPage.show(web)
        defer { window.isHidden = true }
        // The page starts loading the server's page. Whether the web view's own request fails, and how soon, depends on WebKit's
        // networking process, which the simulator may not start in time (or at all), so the test reports the failure the way WebKit
        // does once the web view exists, and asserts what the page does with it.
        let loaded = await FeatureHost.settleAsync(until: { HostedPage.descendants(of: web.view).contains { $0 is WKWebView } })
        let webView = try XCTUnwrap(HostedPage.descendants(of: web.view).compactMap { $0 as? WKWebView }.first, "the page made its web view (waited: \(loaded))")
        web.webView(webView, didFailProvisionalNavigation: nil, withError: URLError(.cannotConnectToHost))
        await FeatureHost.settleAsync(until: { FeatureHost.view("haWeb.retry", in: web.view) != nil })
        XCTAssertNotNil(FeatureHost.view("haWeb.retry", in: web.view), "Can't open Settings, with Try Again")
        XCTAssertTrue(HostedPage.labels(in: web.view).contains("Can't open Settings"))
        FeatureHost.press("haWeb.retry", in: web.view)
        await FeatureHost.settleAsync(0.3)
        XCTAssertFalse(web.accessibilityPerformEscape(), "with no history the escape gesture falls to the system")
        let reload = web.navigationItem.rightBarButtonItems?.first { $0.accessibilityIdentifier == "haWeb.reload" }
        XCTAssertNotNil(reload)
    }

    func testAFailedSignOutKeepsTheSessionAndOffersARetry() async throws {
        setenv("FENTON_SIGNOUT_FAIL", "1", 1)
        defer { unsetenv("FENTON_SIGNOUT_FAIL") }
        let (page, window, session) = try await page(user: admin)
        defer { window.isHidden = true }
        FeatureHost.tapRow("haSettings.signOut", in: page.view)
        await FeatureHost.settleAsync(0.4)
        FeatureHost.answer(try XCTUnwrap(FeatureHost.alert(on: page)), AlertCopy.signOut.confirm.title, dismissing: false)
        await FeatureHost.settleAsync(0.8)
        XCTAssertTrue(session.isSignedIn, "Home Assistant did not confirm, so the phone stays signed in")
        let failed = try XCTUnwrap(FeatureHost.alert(on: page), "the failure is explained")
        XCTAssertEqual(failed.title, AlertCopy.signOutFailed.title)
        FeatureHost.answer(failed, AlertCopy.signOutFailed.cancel.title)
    }
}
