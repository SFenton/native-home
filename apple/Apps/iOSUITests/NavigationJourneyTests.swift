import XCTest

/// Root navigation and on-demand split (`.agents/design/apple/split-view.md`, `ipados.md`):
/// tab bar in compact width, overlay flyout in regular width; Settings is the last tab (owner, 2026-10-16).
@MainActor
final class NavigationJourneyTests: JourneyTestCase {

    // MARK: - Helpers

    /// The window uses the flyout (regular width) rather than the tab bar; the test is the tab bar itself.
    private func usesFlyout(_ app: XCUIApplication) -> Bool {
        _ = app.buttons["nav.open"].appears(timeout: 3)
        let home = tab("Home", in: app)
        return !(home.exists && home.isHittable)
    }

    /// A tab item: in the tab bar, or on the folded iPhone Duo in the vertical bar, which XCUITest
    /// reports as a toolbar.
    private func tab(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let item = app.tabBars.buttons[title]
        return item.exists ? item : app.toolbars.buttons[title]
    }

    /// Goes back one page: the system Back button wherever the bar puts it (the folded iPhone Duo moves
    /// bar items into its vertical bar), else the system leading-edge back swipe.
    private func goBack(in app: XCUIApplication) {
        let back = app.buttons["BackButton"]
        if back.exists, back.isHittable {
            back.tap()
            return
        }
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: window.frame.height / 2))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: window.frame.width * 0.7, dy: 0)))
    }

    /// The flyout panel (SwiftUI puts its identifier on the panel's scroll view).
    private func flyout(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["nav.flyout"]
    }

    private func isLandscape(_ app: XCUIApplication) -> Bool {
        let frame = app.windows.firstMatch.frame
        return frame.width > frame.height
    }

    /// Goes to a section through whichever navigation the window shows (the tab bar, or the flyout).
    private func open(_ section: String, title: String, in app: XCUIApplication) {
        let item = tab(title, in: app)
        if !(item.exists && item.isHittable) {
            app.buttons["nav.open"].tap()
            XCTAssertTrue(flyout(app).appears(timeout: 3), "Flyout did not open")
            app.buttons["nav.\(section)"].tap()
            XCTAssertTrue(flyout(app).disappears(timeout: 3), "Flyout stayed open")
        } else {
            tab(title, in: app).tap()
        }
        XCTAssertTrue(app.navigationBars[title].appears(timeout: 5), "\(title) did not appear")
    }

    // MARK: - Compact width

    /// Launches signed in and skips in a regular-width window (the flyout), where these compact-width journeys do not apply.
    private func launchCompact() throws -> XCUIApplication {
        let app = try FentonHomeApp.launchSignedIn()
        guard !usesFlyout(app) else { throw XCTSkip("Regular-width window") }
        return app
    }

    /// iPhone (and folded Duo) navigate with the tab bar: the five sections, Settings last. Quick Links is a header
    /// button, not a tab; the section root carries Profile.
    func testCompactNavTabBarItems() throws {
        let app = try launchCompact()
        for title in ["Home", "Security", "Climate", "Chores", "Settings"] {
            XCTAssertTrue(tab(title, in: app).exists, "\(title) tab missing")
        }
        XCTAssertFalse(app.tabBars.buttons["Quick Links"].exists, "Quick Links is a header button, not a tab")
        XCTAssertTrue(app.buttons["nav.profile"].isHittable, "No profile button on the section root")
    }

    /// Owner, 2026-10-20: the hamburger is back on iPhone (44 pt circle, opens the flyout), not on the Duo's vertical rail.
    func testCompactNavHamburgerOpensFlyout() throws {
        let app = try launchCompact()
        if FentonHomeApp.family == .iPhone {
            let menu = app.buttons["nav.open"]
            XCTAssertTrue(menu.appears(timeout: 5), "No hamburger on iPhone")
            // XCUITest reports a glass bar item's frame inside its circle; the screenshot shows the 44 pt circle (HIG).
            XCTAssertGreaterThanOrEqual(menu.frame.width, 36)
            XCTAssertGreaterThanOrEqual(menu.frame.height, 36)
            XCTAssertTrue(menu.isHittable)
            XCTAssertEqual(menu.label, "Open Navigation")
            menu.tap()
            XCTAssertTrue(flyout(app).appears(timeout: 3), "The hamburger did not open the flyout")
            app.buttons["nav.flyout.scrim"].tap()
            XCTAssertTrue(flyout(app).disappears(timeout: 3))
        } else {
            XCTAssertFalse(app.buttons["nav.open"].exists, "Menu button on the Duo's rail")
        }
    }

    /// Quick Links opens as a sheet over Home and returns to it unchanged.
    func testCompactNavQuickLinksSheet() throws {
        let app = try launchCompact()
        app.buttons["quickLinks.open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quickLinks.rooms"].appears(timeout: 5), "Quick Links did not open")
        keepScreenshot(app, "quick-links-sheet")
        app.buttons["quickLinks.close"].tap()
        XCTAssertTrue(app.buttons["home.chip.lights"].appears(timeout: 5))
    }

    /// A Settings topic pushes inside the tab with Back and never splits.
    func testCompactNavSettingsPushesTopic() throws {
        let app = try launchCompact()
        open("settings", title: "Settings", in: app)
        app.revealSettingsRow(app.buttons["settings.topic.specialDeviceModes"])
        app.buttons["settings.topic.specialDeviceModes"].tap()
        XCTAssertTrue(app.navigationBars["Special Device Modes"].appears(timeout: 5))
        XCTAssertFalse(app.buttons["split.close"].exists, "Compact width split")
        goBack(in: app)
        XCTAssertTrue(app.buttons["settings.topic.specialDeviceModes"].appears(timeout: 5))
    }

    /// The Settings list audits clean in compact width, AX5 included.
    func testCompactSettingsTabPassesAccessibilityAudit() throws {
        let app = try launchCompact()
        open("settings", title: "Settings", in: app)
        settleScreen()
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.open("settings", title: "Settings", in: large)
            settleScreen()
            return large
        }
    }

    /// The pushed Settings topic page audits clean in compact width, AX5 included.
    func testCompactSettingsTopicPagePassesAccessibilityAudit() throws {
        let app = try launchCompact()
        open("settings", title: "Settings", in: app)
        app.revealSettingsRow(app.buttons["settings.topic.specialDeviceModes"])
        app.buttons["settings.topic.specialDeviceModes"].tap()
        XCTAssertTrue(app.navigationBars["Special Device Modes"].appears(timeout: 5))
        settleScreen()
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.open("settings", title: "Settings", in: large)
            let modes = large.buttons["settings.topic.specialDeviceModes"]
            for _ in 0..<8 where !(modes.exists && modes.isHittable) { large.settingsList.swipeUp() }
            modes.tap()
            XCTAssertTrue(large.navigationBars["Special Device Modes"].appears(timeout: 5))
            settleScreen()
            return large
        }
    }

    /// Back from the pushed topic returns to the Settings list in compact width.
    func testCompactSettingsBackReturnsToTheList() throws {
        let app = try launchCompact()
        open("settings", title: "Settings", in: app)
        app.revealSettingsRow(app.buttons["settings.topic.specialDeviceModes"])
        app.buttons["settings.topic.specialDeviceModes"].tap()
        XCTAssertTrue(app.navigationBars["Special Device Modes"].appears(timeout: 5))
        goBack(in: app)
        XCTAssertTrue(app.buttons["settings.topic.specialDeviceModes"].appears(timeout: 5))
    }

    // MARK: - Regular width

    /// iPad and unfolded Duo hide the tab bar and navigate with the overlay flyout.
    func testFlyoutOpensSelectsAndDismisses() throws {
        let app = try FentonHomeApp.launchSignedIn()
        guard usesFlyout(app) else { throw XCTSkip("Compact window") }
        XCTAssertFalse(tab("Security", in: app).isHittable, "Tab bar visible beside the flyout")
        app.buttons["nav.open"].tap()
        let flyout = flyout(app)
        XCTAssertTrue(flyout.appears(timeout: 3))
        XCTAssertFalse(app.buttons["home.chip.lights"].exists, "Content under the scrim still reachable by VoiceOver")
        for section in ["home", "security", "climate", "chores", "settings"] {
            let row = app.buttons["nav.\(section)"]
            XCTAssertTrue(row.isHittable, "\(section) row unreachable")
            XCTAssertGreaterThanOrEqual(row.frame.height, 44, "\(section) row under 44 pt")
        }
        XCTAssertTrue(app.buttons["nav.home"].isSelected, "Current section not marked selected")
        // Settings is the last row; Quick Links is a header button, not a row.
        XCTAssertGreaterThan(app.buttons["nav.settings"].frame.minY, app.buttons["nav.chores"].frame.maxY)
        XCTAssertFalse(app.buttons["nav.quickLinks"].exists, "Quick Links row in the flyout")
        // The scrim closes it without navigating.
        app.buttons["nav.flyout.scrim"].tap()
        XCTAssertTrue(flyout.disappears(timeout: 3))
        XCTAssertTrue(app.buttons["home.chip.lights"].exists)
        open("security", title: "Security", in: app)
        open("home", title: "Home", in: app)
    }

    /// While the flyout is open, a tap outside the panel (the status bar strip, the header, the page body) only closes it:
    /// no card or tile behind it, the weather card included, opens a sheet or a page.
    func testTapsOutsideOpenFlyoutOnlyCloseIt() throws {
        let app = try FentonHomeApp.launchSignedIn()
        guard usesFlyout(app) else { throw XCTSkip("Compact window") }
        let window = app.windows.firstMatch
        for fraction in [0.06, 0.12, 0.3, 0.5, 0.75] {
            app.buttons["nav.open"].tap()
            XCTAssertTrue(flyout(app).appears(timeout: 3))
            let point = window.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: fraction))
            point.tap()
            // The tap lands on the page behind the strip: it must not have opened anything while the panel slid away.
            XCTAssertTrue(flyout(app).disappears(timeout: 3), "Tap at \(fraction) did not close the flyout")
            XCTAssertFalse(app.navigationBars.buttons["Close"].exists, "Tap at \(fraction) reached the page under the flyout")
            XCTAssertTrue(app.buttons["nav.open"].appears(timeout: 3))
        }
    }

    /// A drag from the leading edge opens the flyout wherever the hamburger shows (iPad, unfolded Duo, iPhone), and only the flyout.
    func testEdgeSwipeOpensFlyout() throws {
        let app = try FentonHomeApp.launchSignedIn()
        guard app.buttons["nav.open"].appears(timeout: 5) else { throw XCTSkip("No hamburger in this window") }
        // Start on a control at the leading edge (the first camera tile's row): the swipe must open only
        // the flyout, never the control under it (the landscape Duo opened the camera too).
        let window = app.windows.firstMatch
        let camera = app.buttons["home.camera.front_door"]
        let y = camera.exists && camera.frame.minX < 40 ? camera.frame.midY : window.frame.height / 2
        let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: y))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 200, dy: 0)))
        XCTAssertTrue(flyout(app).appears(timeout: 3), "Edge swipe did not open the flyout")
        // The drawer's blur reaches the top and bottom of the screen (look at the screenshot).
        keepScreenshot(app, "flyout-edge-swipe")
        XCTAssertFalse(app.navigationBars.buttons["Close"].exists, "The edge swipe also activated the control under it")
        app.buttons["nav.flyout.scrim"].tap()
        XCTAssertTrue(flyout(app).disappears(timeout: 3))
    }

    /// The edge does not swallow taps: Open Navigation and a camera tile still work when tapped inside the edge-swipe width
    /// (the leading 18 pt). The two controls share one "at least one was there to tap" check, so they stay in one test.
    func testEdgeTapsAtTheEdgeReachTheirControls() throws {
        let app = try FentonHomeApp.launchSignedIn()
        guard app.buttons["nav.open"].appears(timeout: 5) else { throw XCTSkip("No hamburger in this window") }
        let camera = app.buttons["home.camera.front_door"]
        var tappedAtEdge = 0
        let open = app.buttons["nav.open"]
        XCTAssertTrue(open.appears(timeout: 3))
        // On the unfolded Duo the system moves Open Navigation into its trailing vertical bar.
        if open.frame.minX < 18 {
            open.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 18 - open.frame.minX - 1, dy: open.frame.height / 2)).tap()
            XCTAssertTrue(flyout(app).appears(timeout: 3), "A tap on Open Navigation inside the leading edge was swallowed")
            app.buttons["nav.flyout.scrim"].tap()
            XCTAssertTrue(flyout(app).disappears(timeout: 3))
            tappedAtEdge += 1
        }
        if camera.exists, camera.frame.minX < 18 {
            camera.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 18 - camera.frame.minX - 1, dy: camera.frame.height / 2)).tap()
            let done = app.navigationBars.buttons["Close"]
            XCTAssertTrue(done.appears(timeout: 5), "A tap on a camera tile inside the leading edge was swallowed")
            done.tap()
            tappedAtEdge += 1
        }
        XCTAssertGreaterThan(tappedAtEdge, 0, "No control inside the leading edge to tap")
    }

    /// The open flyout audits clean (names, roles, contrast, targets, Dynamic Type).
    func testFlyoutPassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        guard usesFlyout(app) else { throw XCTSkip("Compact window") }
        app.buttons["nav.open"].tap()
        XCTAssertTrue(flyout(app).appears(timeout: 3))
        settleScreen()
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            large.buttons["nav.open"].tap()
            XCTAssertTrue(self.flyout(large).appears(timeout: 3))
            settleScreen()
            return large
        }
    }

    /// Settings is its own tab on every family and orientation: a topic pushes inside the tab with Back and never splits.
    func testSettingsTabPushesTopic() throws {
        let app = try FentonHomeApp.launchSignedIn()
        open("settings", title: "Settings", in: app)
        XCTAssertFalse(app.descendants(matching: .any)["settings.placeholder"].exists, "Split placeholder in the Settings tab")
        let modes = app.buttons["settings.topic.specialDeviceModes"]
        for _ in 0..<6 where !(modes.exists && modes.isHittable) { app.settingsList.swipeUp() }
        modes.tap()
        XCTAssertTrue(app.navigationBars["Special Device Modes"].appears(timeout: 5))
        XCTAssertFalse(app.buttons["split.close"].exists, "The Settings tab split")
        goBack(in: app)
        XCTAssertTrue(modes.appears(timeout: 5))
    }

    /// The Settings tab audits clean (AX5 included), scrolled to the Special Device Modes row as the original pass left it.
    func testSettingsTabPassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        open("settings", title: "Settings", in: app)
        let modes = app.buttons["settings.topic.specialDeviceModes"]
        for _ in 0..<6 where !(modes.exists && modes.isHittable) { app.settingsList.swipeUp() }
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.open("settings", title: "Settings", in: large)
            settleScreen()
            return large
        }
    }

    /// Quick Links is the header button in a flyout window too, and the flyout is closed while its sheet is up.
    func testQuickLinksHeaderButtonPresentsTheSheet() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.buttons["quickLinks.open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["quickLinks.rooms"].appears(timeout: 5), "Quick Links did not open")
        XCTAssertFalse(flyout(app).exists, "Flyout open under the sheet")
        app.buttons["quickLinks.close"].tap()
        XCTAssertTrue(app.buttons["home.chip.lights"].appears(timeout: 5))
    }

    // MARK: - Screenshots

    /// One capture step: `home-*`, `nav-*`, `account-*`, `settings-*` and `settings-topic-*` screenshots.
    private enum CaptureStep { case home, nav, account, settings, settingsTopic }

    /// iPad's pose for a capture: portrait, or landscape. Other families run the one pose they have.
    @MainActor private enum CapturePose {
        case upright, iPadLandscape
        var suffix: String {
            switch (self, FentonHomeApp.family) {
            case (.iPadLandscape, _): "landscape"
            case (.upright, .iPad): "portrait"
            default: "current"
            }
        }
    }

    /// Launches in `pose`, goes to the step's screen directly and keeps its screenshot.
    private func capture(_ step: CaptureStep, pose: CapturePose) throws {
        if pose == .iPadLandscape {
            guard FentonHomeApp.family == .iPad else { throw XCTSkip("iPad landscape only") }
            XCUIDevice.shared.orientation = .landscapeLeft
        } else if FentonHomeApp.family == .iPad {
            XCUIDevice.shared.orientation = .portrait
        }
        defer { if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait } }
        let suffix = pose.suffix
        let app = try FentonHomeApp.launchSignedIn()
        // Set again after launch: set only before it, iPad captures came out portrait.
        if pose == .iPadLandscape { XCUIDevice.shared.orientation = .landscapeLeft }
        else if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
        settleScreen()
        switch step {
        case .home:
            keep(app, "home-\(suffix)")
        case .nav:
            if usesFlyout(app) {
                app.buttons["nav.open"].tap()
                XCTAssertTrue(flyout(app).appears(timeout: 3))
                settleScreen()
                keep(app, "nav-flyout-\(suffix)")
            } else {
                keep(app, "nav-tabbar-\(suffix)")
            }
        case .account:
            app.openAccountSheet()
            settleScreen()
            keep(app, "account-\(suffix)")
        case .settings:
            open("settings", title: "Settings", in: app)
            XCTAssertTrue(app.navigationBars["Settings"].appears(timeout: 5))
            // Show the end of the list: it closes with the Home Assistant row (below the fold on
            // phones and in the split's leading pane).
            let list = app.settingsList
            let homeAssistant = app.buttons["settings.homeAssistant"]
            for _ in 0..<6 where !(homeAssistant.exists && homeAssistant.isHittable) { list.swipeUp() }
            settleScreen()
            keep(app, "settings-\(suffix)")
        case .settingsTopic:
            open("settings", title: "Settings", in: app)
            let guests = app.buttons["settings.topic.guests"]
            app.revealSettingsRow(guests)
            guests.tap()
            settleScreen()
            keep(app, "settings-topic-\(suffix)")
        }
    }

    /// Home, upright (and iPad portrait).
    func testCaptureNavigationHome() throws { try capture(.home, pose: .upright) }
    func testCaptureNavigationHomeInIPadLandscape() throws { try capture(.home, pose: .iPadLandscape) }
    /// The flyout, or the tab bar where the window has one.
    func testCaptureNavigationNavFlyoutOrTabBar() throws { try capture(.nav, pose: .upright) }
    func testCaptureNavigationNavFlyoutOrTabBarInIPadLandscape() throws { try capture(.nav, pose: .iPadLandscape) }
    /// The Account sheet.
    func testCaptureNavigationAccount() throws { try capture(.account, pose: .upright) }
    func testCaptureNavigationAccountInIPadLandscape() throws { try capture(.account, pose: .iPadLandscape) }
    /// The end of the Settings list.
    func testCaptureNavigationSettings() throws { try capture(.settings, pose: .upright) }
    func testCaptureNavigationSettingsInIPadLandscape() throws { try capture(.settings, pose: .iPadLandscape) }
    /// A pushed Settings topic (Guests).
    func testCaptureNavigationSettingsTopic() throws { try capture(.settingsTopic, pose: .upright) }
    func testCaptureNavigationSettingsTopicInIPadLandscape() throws { try capture(.settingsTopic, pose: .iPadLandscape) }

    private func keep(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let folder = ProcessInfo.processInfo.environment["FENTON_CAPTURE_DIR"], !folder.isEmpty else { return }
        let ready = URL(fileURLWithPath: folder).appendingPathComponent("\(name).ready")
        let done = URL(fileURLWithPath: folder).appendingPathComponent("\(name).done")
        FileManager.default.createFile(atPath: ready.path, contents: nil)
        // Generous: under load from other lanes' simulators a host screenshot took over 30 s.
        let deadline = Date().addingTimeInterval(120)
        while !FileManager.default.fileExists(atPath: done.path), Date() < deadline { usleep(200_000) }
    }
}
