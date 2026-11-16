import HassCore
import HassDesign
import UIKit
import WebKit
import XCTest
@testable import HassUI

/// Home Assistant's own pages in the web view, hosted on a signed-in session whose server never answers.
@MainActor
final class UKHostedHomeAssistantTests: DemoHouseTestCase {
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
}
