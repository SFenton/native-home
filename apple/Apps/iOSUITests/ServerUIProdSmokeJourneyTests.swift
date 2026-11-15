import XCTest

/// Live smoke for the server-driven layout against production Home Assistant (`sdui-ha-transport-contract`, boundary states).
///
/// Run by the Verifier, one family at a time, with `TEST_RUNNER_FENTON_HASS_TOKEN` and `_SERVER` in the environment (the
/// `--env shell` runner passes them through; they are never printed). With no token every test skips. It signs in, waits for
/// the published layout, opens the room named by `TEST_RUNNER_FENTON_SMOKE_ROOM` (that test skips when it is unset, so no room
/// name lives in the repository) and relaunches cold, and it is read only: it never taps a card, switch,
/// slider or anything else that calls a service. A test that signs in is classified Live by `tools/test_plans.py`, so the
/// class is outside the PR and nightly plans.
@MainActor
final class ServerUIProdSmokeJourneyTests: JourneyTestCase {
    /// The titles of the recovery boundary (`UKServerUIProductionHost.Boundary`): none may be on screen once a layout shows.
    private static let boundaryTitles = ["No Layout Published", "Update Required", "Layout Unavailable", "Getting Your Layout\u{2026}"]

    /// `portrait` or `landscape`, for screenshot names.
    private var pose: String { Self.wantsLandscape && Self.rotatingFamilies.contains(FentonHomeApp.family) ? "landscape" : "portrait" }

    /// The family for screenshot names: `iphone`, `iphoneduo` or `ipad`.
    private var family: String { "\(FentonHomeApp.family)".lowercased() }

    private func shot(_ app: XCUIApplication, _ step: String) {
        keepScreenshot(app, "\(family)-\(pose)-\(step)")
    }

    /// The launch environment of a token sign-in, or a skip when the runner gave no token.
    private func tokenEnvironment() throws -> [String: String] {
        let environment = ProcessInfo.processInfo.environment
        guard let token = environment["FENTON_HASS_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_FENTON_HASS_TOKEN and _SERVER to run the server UI production smoke")
        }
        try FentonHomeApp.requireServer(environment)
        var launch = ["FENTON_HASS_TOKEN": token]
        if let server = environment["FENTON_HASS_SERVER"] { launch["FENTON_HASS_SERVER"] = server }
        return launch
    }

    /// Launches with the token; `reset` signs out and clears the saved layout first, a relaunch without it keeps the cache.
    private func launch(reset: Bool) throws -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        if reset { app.launchEnvironment["FENTON_UITEST_RESET"] = "1" }
        app.launchEnvironment.merge(try tokenEnvironment()) { _, new in new }
        app.launch()
        return app
    }

    private func hasChrome(_ app: XCUIApplication) -> Bool {
        app.tabBars.firstMatch.exists || app.navigationBars.firstMatch.exists || app.buttons["nav.open"].exists
    }

    private func boundaryShowing(_ app: XCUIApplication) -> String? {
        // The boundary title is not a `staticText` to XCUITest (probed in the first run), so match by label on any element type.
        Self.boundaryTitles.first { app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", $0)).firstMatch.exists }
    }

    /// Attaches the recovery boundary's DEBUG diagnostic (error case and JSON pointer, never values) when a boundary is showing.
    private func attachDiagnostic(_ app: XCUIApplication) {
        let label = app.staticTexts["server-ui.production.diagnostic"]
        guard label.exists else { return }
        let note = XCTAttachment(string: label.label)
        note.name = "boundary-diagnostic"
        note.lifetime = .keepAlways
        add(note)
        print("BOUNDARY-DIAGNOSTIC: \(label.label)")
    }

    /// Waits for the shell chrome with no boundary title; returns whether chrome exists and the boundary still showing, if any.
    private func waitForLayout(_ app: XCUIApplication, timeout: TimeInterval) -> (chrome: Bool, boundary: String?) {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if hasChrome(app), boundaryShowing(app) == nil { return (true, nil) }
            usleep(200_000)
        }
        attachDiagnostic(app)
        return (hasChrome(app), boundaryShowing(app))
    }

    // MARK: - Tests

    /// A reset sign-in ends on the published layout, not a boundary.
    func testSignedInLaunchRendersPublishedLayout() throws {
        let app = try launch(reset: true)
        let state = waitForLayout(app, timeout: 60)
        shot(app, "1-first-page")
        XCTAssertNil(state.boundary, "Boundary still showing: \(state.boundary ?? "")")
        XCTAssertTrue(state.chrome, "No tab bar or navigation chrome after sign-in")
    }

    /// The room named by `FENTON_SMOKE_ROOM`, reached through the published navigation, shows cards. Navigation only: no card
    /// is tapped. Skips when the runner gave no room label.
    func testNamedRoomShowsCards() throws {
        guard let room = ProcessInfo.processInfo.environment["FENTON_SMOKE_ROOM"], !room.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_FENTON_SMOKE_ROOM to the room label to open")
        }
        let app = try launch(reset: true)
        let state = waitForLayout(app, timeout: 60)
        XCTAssertTrue(state.chrome && state.boundary == nil, "Layout did not render: \(state.boundary ?? "no chrome")")
        let target = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", room, room + ",")).firstMatch
        if !target.appears(timeout: 5) || !target.isHittable {
            // A room is a navigation tile in Quick Links, not on the first page: open Quick Links before scrolling.
            let quickLinks = app.buttons["quickLinks.open"]
            if !target.exists, quickLinks.exists { quickLinks.tap() }
            if !target.appears(timeout: 5) || !target.isHittable { scrollTo(target, in: app) }
        }
        XCTAssertTrue(target.exists && target.isHittable, "The room is not in the published navigation: \(app.debugDescription)")
        target.tap() // Navigation to the room only.
        let cards = app.scrollViews.descendants(matching: .any).matching(NSPredicate(format: "identifier != ''"))
        XCTAssertTrue(cards.firstMatch.appears(timeout: 20), "The room showed no cards")
        shot(app, "2-room")
        XCTAssertGreaterThan(cards.count, 0)
    }

    /// A cold relaunch without the reset flag draws the cached layout at once: chrome and no boundary within about 2 s.
    func testColdRelaunchShowsCachedLayoutWithoutBoundary() throws {
        let first = try launch(reset: true)
        let state = waitForLayout(first, timeout: 60)
        XCTAssertTrue(state.chrome && state.boundary == nil, "Layout did not render before relaunch: \(state.boundary ?? "no chrome")")
        first.terminate()

        let app = try launch(reset: false)
        shot(app, "3-relaunch-launch")
        let begun = Date()
        var sawBoundary: String?
        var chrome = false
        while Date().timeIntervalSince(begun) < 2 {
            chrome = chrome || hasChrome(app)
            sawBoundary = sawBoundary ?? boundaryShowing(app)
            usleep(100_000)
        }
        shot(app, "3-relaunch-plus2s")
        XCTAssertNil(sawBoundary, "Boundary shown on relaunch: \(sawBoundary ?? "")")
        XCTAssertTrue(chrome && hasChrome(app), "Chrome missing within 2 s of a cold relaunch")
    }
}
