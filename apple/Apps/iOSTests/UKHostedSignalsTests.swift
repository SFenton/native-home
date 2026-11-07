import CoreSpotlight
import HassCore
import HassDesign
import OSLog
import UIKit
import XCTest
@testable import HassUI

/// The Duo's fold and rail (stood in for with `UKDeviceSignals` overrides), the layout census, the diagnostics probes, and the
/// entry points of the port.
@MainActor
final class UKHostedSignalsTests: DemoHouseTestCase {
    private func settle(_ seconds: TimeInterval = 0.3) { HostedPage.wait(seconds) }

    override func tearDown() {
        UKDeviceSignals.regionsOverride = nil
        UKDeviceSignals.verticalBarOverride = nil
        UKMotion.reduceMotionOverride = nil
        UKLayoutCensus.isEnabled = false
        UKLayoutCensus.uninstall()
    }

    // MARK: Fold and rail

    func testTheFoldIsReadFromTheWindowsReservedRegions() throws {
        let shell = UKShellEnvironment()
        let controller = UIViewController()
        guard let window = HostedScene.show(controller, size: CGSize(width: 800, height: 600)) else { throw XCTSkip("the host app has no window scene") }  // a scene-less window cannot snapshot
        defer { window.isHidden = true }
        let content = UILabel(frame: CGRect(x: 10, y: 10, width: 200, height: 40))
        content.text = "Page content"
        controller.view.addSubview(content)
        let signals = UKDeviceSignals(view: controller.view, environment: shell)
        let frame = CGRect(x: 388, y: 0, width: 24, height: 600)
        var folding = true
        UKDeviceSignals.regionsOverride = { _, includeInactive in
            folding ? [(frame, true)] : (includeInactive ? [(frame, false)] : [])
        }
        signals.refresh()
        XCTAssertEqual(shell.windowFold, WindowFold(hinge: frame, isFolding: true))
        XCTAssertEqual(shell.windowHinge, frame, "partly folded: content keeps clear of the band")
        // Lying flat: the hinge is still there, but the band content avoids is gone. The change at the same size reflows.
        folding = false
        signals.refresh()
        XCTAssertEqual(shell.windowFold, WindowFold(hinge: frame, isFolding: false))
        XCTAssertNil(shell.windowHinge, "a flat Duo avoids nothing")
        // Reduce Motion cross-fades the old picture into the new one.
        settle(0.3)
        UKMotion.reduceMotionOverride = true
        let before = controller.view.subviews.count
        folding = true
        signals.refresh()
        XCTAssertEqual(controller.view.subviews.count, before + 1, "the old picture is held over the page while it fades")
        settle(0.8)
        HostedPage.until { controller.view.subviews.count == before }
        XCTAssertEqual(controller.view.subviews.count, before, "and fades away")
        XCTAssertEqual(UKDeviceSignals.hinge(in: controller.view), frame)
        // No hinge at all.
        UKDeviceSignals.regionsOverride = { _, _ in [] }
        signals.refresh()
        XCTAssertEqual(shell.windowFold, WindowFold.none)
    }

    func testAViewInsideTheWindowAsksTheRootViewAndConvertsTheFrame() {
        let controller = UIViewController()
        let window = HostedPage.show(controller, size: CGSize(width: 800, height: 600))
        defer { window.isHidden = true }
        let inner = UIView(frame: CGRect(x: 100, y: 0, width: 400, height: 600))
        controller.view.addSubview(inner)
        UKDeviceSignals.regionsOverride = { view, _ in view === controller.view ? [(CGRect(x: 388, y: 0, width: 24, height: 600), false)] : [] }
        XCTAssertEqual(UKDeviceSignals.fold(in: inner).hinge, CGRect(x: 288, y: 0, width: 24, height: 600), "the root's hinge, in the inner view's space")
        XCTAssertEqual(UKDeviceSignals.fold(in: window).hinge, CGRect(x: 388, y: 0, width: 24, height: 600))
    }

    func testTheVerticalBarIsPublishedAndTakesTheRailOffTheFreeWidth() {
        let shell = UKShellEnvironment()
        let controller = UIViewController()
        let window = HostedPage.show(controller, size: CGSize(width: 800, height: 600))
        defer { window.isHidden = true }
        let signals = UKDeviceSignals(view: controller.view, environment: shell)
        UKDeviceSignals.verticalBarOverride = { _ in true }
        signals.refresh()
        XCTAssertTrue(shell.inVerticalBar)
        XCTAssertEqual(UKDeviceSignals.railWidth(in: window), window.safeAreaInsets.right)
        XCTAssertEqual(UKDeviceSignals.freeWidth(in: window), window.bounds.width - window.safeAreaInsets.right)
        UKDeviceSignals.verticalBarOverride = { _ in false }
        signals.refresh()
        XCTAssertFalse(shell.inVerticalBar)
    }

    func testAHingeUpdateReadsTheFoldAgainOnTheNextTurn() {
        let shell = UKShellEnvironment()
        let controller = UIViewController()
        let window = HostedPage.show(controller, size: CGSize(width: 800, height: 600))
        defer { window.isHidden = true }
        let signals = UKDeviceSignals(view: controller.view, environment: shell)
        let frame = CGRect(x: 388, y: 0, width: 24, height: 600)
        UKDeviceSignals.regionsOverride = { _, _ in [(frame, true)] }
        signals.hingeChanged(.partiallyOpen)
        XCTAssertEqual(shell.windowFold, .none, "not on this turn")
        settle(0.2)
        XCTAssertEqual(shell.windowHinge, frame)
        if #available(iOS 27.1, *) {
            XCTAssertEqual(UKDeviceSignals.hingeState(.closed), .closed)
            XCTAssertEqual(UKDeviceSignals.hingeState(.fullyOpen), .fullyOpen)
            XCTAssertEqual(UKDeviceSignals.hingeState(.partiallyOpen), .partiallyOpen)
            XCTAssertEqual(UKDeviceSignals.hingeState(.unknown), .partiallyOpen)
        }
    }

    // MARK: Layout census

    func testTheCensusCountsLayoutPassesAndWritesOneLine() throws {
        UKLayoutCensus.isEnabled = true
        UKLayoutCensus.install()
        UKLayoutCensus.install()
        let controller = UIViewController()
        let window = HostedPage.show(controller)
        defer { window.isHidden = true }
        let probe = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        controller.view.addSubview(probe)
        for _ in 0..<70 {
            probe.setNeedsLayout()
            controller.view.layoutIfNeeded()
        }
        UKLayoutCensus.bump("page.CensusProbePage")
        UKLayoutCensus.note("hinge nil -> 24")
        UKLayoutCensus.dirtied(probe)
        settle(0.9)
        HostedPage.until(8) {
            guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
                  let all = try? store.getEntries(at: store.position(date: Date().addingTimeInterval(-30))) else { return false }
            return all.compactMap { $0 as? OSLogEntryLog }.contains { $0.category == "layout-census" && $0.composedMessage.contains("CensusProbePage") }
        }
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(at: store.position(date: Date().addingTimeInterval(-30)))
            .compactMap { $0 as? OSLogEntryLog }.filter { $0.category == "layout-census" }.map(\.composedMessage)
        XCTAssertTrue(entries.contains { $0.contains("installed view census") })
        XCTAssertTrue(entries.contains { $0.contains("page.CensusProbePage=1") && $0.contains("hinge nil -> 24") && $0.contains("v.UIView@100x50") },
                      "the summary names the page, the note and the view that laid out: \(entries.suffix(5))")
        UKLayoutCensus.isEnabled = false
        UKLayoutCensus.bump("never")
        UKLayoutCensus.note("never")
        UKLayoutCensus.dirtied(probe)
    }

    // MARK: Probes

    private func waitForLabel(_ element: UKProbeElementView, timeout: TimeInterval = 8, until done: (String) -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end, !done(element.accessibilityLabel ?? "") { try? await Task.sleep(for: .milliseconds(50)) }
    }

    private func post(_ name: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil, true)
    }

    func testTheScrollCostProbeReportsWhatTheDriverMeasuredOrThatThereWasNothingToScroll() async {
        setenv("FENTON_SCROLLCOST_SECONDS", "0.3", 1)
        defer { unsetenv("FENTON_SCROLLCOST_SECONDS") }
        let probe = UKScrollCostProbe()
        XCTAssertEqual(probe.element.accessibilityLabel, "ready")
        try? await Task.sleep(for: .milliseconds(400))
        let window = HostedPage.show(UIViewController())
        defer { window.isHidden = true }
        post(ScrollCostProbe.idleNotification)
        await waitForLabel(probe.element) { $0 != "ready" && $0 != "running" }
        // With a page that scrolls the line is the meter's summary.
        let page = HostedScrollPage(context: UKGalleryChrome.context(), title: "Cost")
        let navigation = UINavigationController(rootViewController: page)
        let pageWindow = HostedPage.show(navigation)
        defer { pageWindow.isHidden = true }
        post(ScrollCostProbe.scrollNotification)
        await waitForLabel(probe.element) { !$0.hasPrefix("no scroll view") && $0 != "running" }
        XCTAssertFalse(probe.element.accessibilityLabel?.hasPrefix("no scroll view") ?? true, "\(probe.element.accessibilityLabel ?? "")")
    }

    func testTheScrollCostAutorunWritesItsLinesToTheNamedFile() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "uk-scrollcost-\(UUID().uuidString).txt").path
        for (key, value) in [("FENTON_SCROLLCOST_AUTORUN", "0"), ("FENTON_SCROLLCOST_FILE", file), ("FENTON_SCROLLCOST_NAME", "hosted"),
                             ("FENTON_SCROLLCOST_SECONDS", "0.3"), ("FENTON_LAYER_CENSUS", "1")] { setenv(key, value, 1) }
        defer { for key in ["FENTON_SCROLLCOST_AUTORUN", "FENTON_SCROLLCOST_FILE", "FENTON_SCROLLCOST_NAME", "FENTON_SCROLLCOST_SECONDS", "FENTON_LAYER_CENSUS"] { unsetenv(key) } }
        let window = HostedPage.show(UIViewController())
        defer { window.isHidden = true }
        let probe = UKScrollCostProbe()
        let end = Date().addingTimeInterval(10)
        var text = ""
        while Date() < end, !text.contains("SCROLLCOST_DONE") {
            try? await Task.sleep(for: .milliseconds(100))
            text = (try? String(contentsOfFile: file, encoding: .utf8)) ?? ""
        }
        XCTAssertTrue(text.contains("LAYERCENSUS\thosted"), text)
        XCTAssertTrue(text.contains("SCROLLCOST\thosted\tidle"), text)
        XCTAssertTrue(text.contains("SCROLLCOST_DONE\thosted"))
        _ = probe
        try? FileManager.default.removeItem(atPath: file)
    }

    func testTheNavigationPerfProbeResetsAndReports() async {
        let probe = UKNavigationPerfProbe()
        try? await Task.sleep(for: .milliseconds(400))
        post(NavigationPerfProbe.resetNotification)
        await waitForLabel(probe.element) { $0 == "reset" }
        XCTAssertEqual(probe.element.accessibilityLabel, "reset")
        post(NavigationPerfProbe.reportNotification)
        await waitForLabel(probe.element) { $0 != "reset" }
        XCTAssertNotEqual(probe.element.accessibilityLabel, "reset", "the label becomes the measured summary")
    }

    func testTheLaunchCostAndResourceProbesShowTheirLatestLine() async {
        let launch = UKLaunchCostProbe()
        XCTAssertEqual(launch.element.accessibilityLabel, LaunchCostProbe.latest)
        LaunchCostProbe.begin("hosted-probe")
        _ = LaunchCostProbe.finish()
        await waitForLabel(launch.element, timeout: 3) { $0 == LaunchCostProbe.latest }
        XCTAssertEqual(launch.element.accessibilityLabel, LaunchCostProbe.latest)
        let resources = UKResourceCensusProbe()
        await waitForLabel(resources.element, timeout: 3) { !$0.isEmpty }
        XCTAssertFalse(resources.element.accessibilityLabel?.isEmpty ?? true, "the live counts")
        XCTAssertEqual(resources.element.accessibilityIdentifier, "diagnostics.resources")
    }

    func testTheProbesAreOnlyInstalledWhenAsked() {
        UKScrollCostProbe.forceEnabled = true
        UKNavigationPerfProbe.forceEnabled = true
        UKLaunchCostProbe.forceEnabled = true
        UKResourceCensusProbe.forceEnabled = true
        setenv("FENTON_APPEARANCE_DEBUG", "1", 1)
        defer {
            UKScrollCostProbe.forceEnabled = false
            UKNavigationPerfProbe.forceEnabled = false
            UKLaunchCostProbe.forceEnabled = false
            UKResourceCensusProbe.forceEnabled = false
            unsetenv("FENTON_APPEARANCE_DEBUG")
        }
        let root = UKRootViewController(session: AppSession(tokenStore: InMemoryTokenStore()))
        let window = HostedPage.show(root)
        defer { window.isHidden = true }
        let ids = Set(root.view.subviews.compactMap { $0 as? UKProbeElementView }.compactMap(\.accessibilityIdentifier))
        XCTAssertTrue(ids.isSuperset(of: ["diagnostics.scrollcost", "diagnostics.navperf", "diagnostics.launchcost", "diagnostics.resources", "appearance.probe"]), "\(ids)")
    }

    // MARK: Entry points

    func testPlaceholderScreenShowsItsTitleAndSymbol() {
        let placeholder = UKPlaceholderViewController(title: "Vacuums", symbol: "fan")
        let window = HostedPage.show(placeholder)
        defer { window.isHidden = true }
        XCTAssertTrue(HostedPage.labels(in: placeholder.view).contains("Vacuums"))
        XCTAssertNotNil(HostedPage.descendants(of: placeholder.view).compactMap { $0 as? UIImageView }.first?.image)
    }

    func testEveryTabAndEveryHomeRouteHasAScreen() {
        let context = UKGalleryChrome.context()
        for section in AppSection.allCases {
            let page = UKScreens.root(for: section, context: context)
            let window = HostedPage.show(UINavigationController(rootViewController: page))
            XCTAssertNotNil(page.view.window, "\(section) has a root page")
            window.isHidden = true
        }
        let routes: [HomeRoute] = [.room("living-room"), .vacuums, .media, .customLights, .sprinklers, .groceryList, .food]
        for route in routes {
            let page = UKScreens.destination(for: route, context: context)
            let window = HostedPage.show(UINavigationController(rootViewController: page))
            XCTAssertNotNil(page.view.window, "\(route) has a page")
            window.isHidden = true
        }
    }

    func testTheAppEntryPointsOpenLinksAndSpotlightResults() throws {
        let session = AppSession(tokenStore: InMemoryTokenStore())
        XCTAssertTrue(UKApp.makeRootViewController(session: session) is UKRootViewController)
        let state = try XCTUnwrap(URL(string: "fentonhome://liveactivity?url=%2Fsfenton-react-dash%2Fhome%3Fpath%3Dkitchen"))
        UKApp.open(state, session: session)
        XCTAssertEqual(session.push.pendingRequest?.destination, PushDestination(dashboardPath: "kitchen"), "a Live Activity tap opens the job's page")
        UKApp.open(try XCTUnwrap(URL(string: "https://example.com")), session: session)
        XCTAssertEqual(session.push.pendingRequest?.destination, PushDestination(dashboardPath: "kitchen"), "any other URL changes nothing")
        let id = try XCTUnwrap(SpotlightCatalog.entries.first).id
        let other = AppSession(tokenStore: InMemoryTokenStore())
        let wrongType = NSUserActivity(activityType: "com.example.other")
        wrongType.userInfo = [SpotlightLink.userInfoKey: id]
        UKApp.continue(wrongType, session: other)
        XCTAssertNil(other.push.pendingRequest, "only a Core Spotlight result is ours")
        let result = NSUserActivity(activityType: CSSearchableItemActionType)
        result.userInfo = [CSSearchableItemActivityIdentifier: id]
        UKApp.continue(result, session: other)
        XCTAssertNotNil(other.push.pendingRequest, "a tapped Spotlight result opens its page")
    }

    func testAScenePersistedByTheSwiftUIAppIsAdoptedAndOurOwnIsKept() {
        XCTAssertTrue(UKSceneUpgrade.needsAdoption(sceneDelegate: nil, ours: NSObject.self))
        XCTAssertTrue(UKSceneUpgrade.needsAdoption(sceneDelegate: NSString(), ours: UIResponder.self))
        XCTAssertFalse(UKSceneUpgrade.needsAdoption(sceneDelegate: UIResponder(), ours: UIResponder.self))
        XCTAssertEqual(UKSceneUpgrade.configurationName, "Default")
    }
}
