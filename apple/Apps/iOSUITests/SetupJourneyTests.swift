import XCTest

/// The Setup flow in the debug gallery (`FENTON_GALLERY=setup`): Notifications, Time Sensitive and Location swap in one
/// sheet, the pre-alert steps have one Continue and no Close, the Time Sensitive step reports the switch, and every step
/// passes the accessibility audit at the default and AX5 text sizes on iPhone, iPhone Duo and iPad
/// (`.agents/platforms/apple/push.md`, `.agents/platforms/apple/location.md`; owner, 2026-10-27).
@MainActor
final class SetupJourneyTests: JourneyTestCase {
    private func launch(_ step: String = "flow", notifications: String = "not-determined", timeSensitive: String = "on",
                        allow: Bool = true, arguments: [String] = []) -> XCUIApplication {
        // Time Sensitive comes up the way it does for an install that already saw location: through the flow itself,
        // not forced onto the screen.
        // The scripted system, the coordinators and their defaults are built per gallery from `FENTON_GALLERY_*` variables (no statics,
        // no real permission), so a test's state is a reset of the class's resident app; AX5 (`arguments`) launches fresh.
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "setup"
        app.launchEnvironment.merge([
            "FENTON_GALLERY_LOCATION_SEEN": step == "time-sensitive" ? "1" : "0",
            "FENTON_GALLERY_SETUP": step == "time-sensitive" ? "flow" : step,
            "FENTON_GALLERY_NOTIFICATIONS": notifications,
            "FENTON_GALLERY_TIME_SENSITIVE": timeSensitive,
            "FENTON_GALLERY_ALLOW": allow ? "1" : "0",
        ]) { _, new in new }
        app.launchArguments += arguments
        return open(app)
    }

    /// Launches or resets the app and waits for the setup sheet.
    private func open(_ configured: XCUIApplication) -> XCUIApplication {
        let app = startApp(configured)
        XCTAssertTrue(app.buttons["setup.notifications.primary"].appears(timeout: 15)
                      || app.buttons["setup.timeSensitive.primary"].exists || app.buttons["location.primary"].exists,
                      "The setup sheet did not open")
        return app
    }

    private func status(_ app: XCUIApplication, _ id: String) -> String {
        element(id, in: app).value as? String ?? ""
    }

    /// The sheet's bar names the step on screen, and the whole title is on screen: not cut by the window's edge, and
    /// (with no Close on these steps) not truncated by the bar's items. The system draws the inline title at one size, so
    /// AX5 does not grow it; the full text is the bar's identifier either way.
    private func assertBarTitle(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.appears(timeout: 10), "The bar should read '\(title)'", file: file, line: line)
        let text = bar.staticTexts[title]
        if text.exists {
            let window = app.windows.firstMatch.frame
            XCTAssertGreaterThanOrEqual(text.frame.minX, window.minX, "\(title) is cut at the leading edge", file: file, line: line)
            XCTAssertLessThanOrEqual(text.frame.maxX, window.maxX, "\(title) is cut at the trailing edge", file: file, line: line)
            XCTAssertFalse(text.label.hasSuffix("…"), "\(title) is truncated", file: file, line: line)
        }
    }

    /// The reading order: the headline, the message, the status, the points, the footnote, then the action.
    private func assertOrder(_ ids: [String], in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // One tree snapshot for every frame (a frame read on an element is a request each).
        var found: [String: CGRect] = [:]
        func walk(_ node: any XCUIElementSnapshot) {
            if ids.contains(node.identifier), found[node.identifier] == nil { found[node.identifier] = node.frame }
            node.children.forEach(walk)
        }
        if let root = try? app.snapshot() { walk(root) }
        let frames = ids.map { found[$0] ?? element($0, in: app).frame }
        for (above, below) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThanOrEqual(above.minY, below.minY + 1, "\(ids) are out of reading order", file: file, line: line)
        }
    }

    // MARK: Notifications

    /// A pre-alert screen: one Continue titled as such, no Close, no swipe-down (HIG Privacy).
    func testNotificationsStepIsAPreAlertScreen() {
        let app = launch("notifications")
        XCTAssertEqual(app.staticTexts["setup.notifications.title"].label, "Get door and camera alerts")
        XCTAssertEqual(app.staticTexts["setup.notifications.message"].label, "S+H can tell you when a door is left open or someone rings.")
        XCTAssertEqual(app.staticTexts["setup.notifications.footnote"].label, "Next, iOS asks to send notifications. Choose Allow.")
        assertBarTitle("Notification Settings", in: app)
        let primary = app.buttons["setup.notifications.primary"]
        XCTAssertEqual(primary.label, "Continue")
        assertTarget(primary)
        XCTAssertFalse(app.buttons["setup.close"].exists, "A pre-alert screen has no Close")
        XCTAssertFalse(app.buttons["setup.timeSensitive.secondary"].exists)
        assertOrder(["setup.notifications.title", "setup.notifications.message", "setup.notifications.footnote",
                     "setup.notifications.primary"], in: app)
        // Swiping the sheet down does not dismiss it.
        app.swipeDown()
        XCTAssertTrue(app.buttons["setup.notifications.primary"].exists, "Not swipe-dismissible")
        keepScreenshot(app, "setup-notifications-\(layout)")
    }

    // MARK: The walk

    /// First launch, everything allowed: Notifications, then Time Sensitive on, then Location, in one sheet.
    func testAFirstLaunchWalksEveryStepInPlace() {
        let app = launch()
        XCTAssertEqual(app.staticTexts["setup.notifications.title"].label, "Get door and camera alerts")
        app.buttons["setup.notifications.primary"].tap()

        // Allowed: Time Sensitive swaps in, with the switch on.
        XCTAssertTrue(app.staticTexts["setup.timeSensitive.title"].appears(timeout: 10))
        XCTAssertEqual(app.staticTexts["setup.timeSensitive.title"].label, "Let Urgent Alerts Through")
        XCTAssertEqual(status(app, "setup.timeSensitive.status"), "On")
        assertBarTitle("Time Sensitive Notification Settings", in: app)
        XCTAssertFalse(app.buttons["setup.notifications.primary"].exists, "One step at a time, in the same sheet")
        let gotIt = app.buttons["setup.timeSensitive.primary"]
        XCTAssertEqual(gotIt.label, "Got It")
        XCTAssertFalse(app.buttons["setup.timeSensitive.secondary"].exists, "Already on: nothing to defer")
        keepScreenshot(app, "setup-time-sensitive-on-\(layout)")
        gotIt.tap()

        // Then Location, which asks as before.
        XCTAssertTrue(app.staticTexts["location.title"].appears(timeout: 10))
        XCTAssertEqual(app.staticTexts["location.title"].label, "Know When You're Home")
        assertBarTitle("Location Settings", in: app)
        XCTAssertFalse(app.buttons["location.close"].exists, "A pre-alert screen has no Close")
        app.buttons["location.primary"].tap()
        XCTAssertTrue(app.staticTexts["Notice When You Leave"].appears(timeout: 10))
        assertBarTitle("Location Settings", in: app)
        app.buttons["location.primary"].tap()
        XCTAssertTrue(app.staticTexts["Home and Away Are On"].appears(timeout: 10))
        assertBarTitle("Location Settings", in: app)
        app.buttons["location.close"].tap()
        XCTAssertTrue(app.buttons["location.primary"].disappears(timeout: 10), "Closing the last step closes the sheet")
        XCTAssertFalse(app.buttons["setup.notifications.primary"].exists)
    }

    /// A refusal skips Time Sensitive (nothing to be time-sensitive about) and goes on to Location.
    func testRefusedNotificationsSkipTimeSensitive() {
        let app = launch(allow: false)
        app.buttons["setup.notifications.primary"].tap()
        XCTAssertTrue(app.staticTexts["location.title"].appears(timeout: 10))
        XCTAssertFalse(app.staticTexts["setup.timeSensitive.title"].exists)
    }

    /// Someone who already accepted location gets only Time Sensitive.
    func testAnInstallThatSawLocationGetsOnlyTimeSensitive() {
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "setup"
        configured.launchEnvironment.merge([
            "FENTON_GALLERY_NOTIFICATIONS": "granted", "FENTON_GALLERY_TIME_SENSITIVE": "on",
            "FENTON_GALLERY_LOCATION_SEEN": "1",
        ]) { _, new in new }
        let app = startApp(configured)
        XCTAssertTrue(app.staticTexts["setup.timeSensitive.title"].appears(timeout: 15))
        app.buttons["setup.timeSensitive.primary"].tap()
        XCTAssertTrue(app.staticTexts["setup.timeSensitive.title"].disappears(timeout: 10), "That was the only step")
        XCTAssertFalse(app.staticTexts["location.title"].exists)
    }

    // MARK: Time Sensitive

    /// Off: the held-back copy, Open Settings as the primary action, Not Now under it; both are 44 pt targets.
    func testTimeSensitiveOffOffersSettingsAndNotNow() {
        let app = launch("time-sensitive", notifications: "granted", timeSensitive: "off")
        assertBarTitle("Time Sensitive Notification Settings", in: app)
        XCTAssertEqual(app.staticTexts["setup.timeSensitive.title"].label, "Urgent Alerts Are Held Back")
        XCTAssertEqual(app.staticTexts["setup.timeSensitive.footnote"].label, "Turn on Time Sensitive Notifications, then come back.")
        let statusRow = element("setup.timeSensitive.status", in: app)
        XCTAssertEqual(statusRow.label, "Time Sensitive Notifications")
        XCTAssertEqual(status(app, "setup.timeSensitive.status"), "Off")
        let primary = app.buttons["setup.timeSensitive.primary"]
        XCTAssertEqual(primary.label, "Open Settings")
        let notNow = app.buttons["setup.timeSensitive.secondary"]
        XCTAssertEqual(notNow.label, "Not Now")
        // The Setup sheet is full height, so its targets draw at design size.
        for _ in 0..<4 where !notNow.isHittable { app.swipeUp() }
        assertTarget(primary)
        assertTarget(notNow)
        for key in ["urgent", "focus", "settings"] {
            XCTAssertFalse(element("setup.timeSensitive.point.\(key)", in: app).label.isEmpty, key)
        }
        assertOrder(["setup.timeSensitive.title", "setup.timeSensitive.message", "setup.timeSensitive.status",
                     "setup.timeSensitive.point.urgent", "setup.timeSensitive.point.focus", "setup.timeSensitive.point.settings",
                     "setup.timeSensitive.footnote", "setup.timeSensitive.primary", "setup.timeSensitive.secondary"], in: app)
        XCTAssertFalse(app.buttons["setup.close"].exists)
        keepScreenshot(app, "setup-time-sensitive-off-\(layout)")
    }

    /// Open Settings keeps the step; coming back with the switch on turns it into the On step with Got It.
    func testOpenSettingsThenComingBackShowsOn() {
        let app = launch("time-sensitive", notifications: "granted", timeSensitive: "off")
        app.buttons["setup.timeSensitive.primary"].tap()
        XCTAssertTrue(app.buttons["setup.timeSensitive.primary"].appears(timeout: 5))
        let predicate = NSPredicate(format: "label == %@", "Got It")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app.buttons["setup.timeSensitive.primary"])],
                                        timeout: 10), .completed, "The step follows the switch")
        XCTAssertEqual(status(app, "setup.timeSensitive.status"), "On")
        XCTAssertFalse(app.buttons["setup.timeSensitive.secondary"].exists)
    }

    func testNotNowClosesTheStep() {
        let app = launch("time-sensitive", notifications: "granted", timeSensitive: "off")
        app.buttons["setup.timeSensitive.secondary"].tap()
        XCTAssertTrue(app.buttons["setup.timeSensitive.primary"].disappears(timeout: 10))
    }

    // MARK: Accessibility

    /// One step passes the audit at the default size and at AX5, where the action stays reachable at the end of the content.
    private func assertStepPassesAudit(_ step: String, notifications: String, timeSensitive: String, action: String) throws {
        let app = launch(step, notifications: notifications, timeSensitive: timeSensitive)
        keepScreenshot(app, "setup-\(step)-\(timeSensitive)-\(layout)")
        try FentonHomeApp.audit(app) {
            self.launch(step, notifications: notifications, timeSensitive: timeSensitive, arguments: FentonHomeApp.ax5)
        }
        let large = launch(step, notifications: notifications, timeSensitive: timeSensitive, arguments: FentonHomeApp.ax5)
        keepScreenshot(large, "setup-\(step)-\(timeSensitive)-ax5-\(layout)")
        assertBarTitle(["notifications": "Notification Settings", "time-sensitive": "Time Sensitive Notification Settings",
                        "location": "Location Settings"][step]!, in: large)
        let button = large.buttons[action]
        for _ in 0..<12 where !button.isHittable { large.swipeUp() }
        XCTAssertTrue(button.isHittable, "\(step): the action is out of reach at AX5")
        // No terminate: the next launch of the app ends this AX5 process, and a reuse launch drops the resident that it replaced.
    }

    func testSetupStepNotificationsPassesAudit() throws {
        try assertStepPassesAudit("notifications", notifications: "not-determined", timeSensitive: "on", action: "setup.notifications.primary")
    }

    func testSetupStepTimeSensitiveOnPassesAudit() throws {
        try assertStepPassesAudit("time-sensitive", notifications: "granted", timeSensitive: "on", action: "setup.timeSensitive.primary")
    }

    func testSetupStepTimeSensitiveOffPassesAudit() throws {
        try assertStepPassesAudit("time-sensitive", notifications: "granted", timeSensitive: "off", action: "setup.timeSensitive.secondary")
    }

    func testSetupStepLocationPassesAudit() throws {
        try assertStepPassesAudit("location", notifications: "granted", timeSensitive: "on", action: "location.primary")
    }
}

/// Settings → Notifications in the debug gallery (`FENTON_GALLERY=notification-settings`): never asked, refused, and
/// allowed with the Time Sensitive switch on, off and unsupported. The allowed rows are one combined element each, 44 pt
/// tall, with a chevron and the hint "Opens Settings" (owner, 2026-10-27).
@MainActor
final class NotificationSettingsJourneyTests: JourneyTestCase {
    private func launch(_ notifications: String, timeSensitive: String = "on", arguments: [String] = []) -> XCUIApplication {
        // The page is a fixture with a scripted push system (no real notification permission, no Settings app), and its states are
        // `FENTON_GALLERY_*` variables, so a test's state is a reset of the class's resident app; AX5 (`arguments`) launches fresh.
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_GALLERY"] = "notification-settings"
        app.launchEnvironment["FENTON_GALLERY_NOTIFICATIONS"] = notifications
        app.launchEnvironment["FENTON_GALLERY_TIME_SENSITIVE"] = timeSensitive
        app.launchArguments += arguments
        _ = startApp(app)
        XCTAssertTrue(app.descendants(matching: .any)["settings.list"].appears(timeout: 15), "The page did not open")
        return app
    }

    func testAllowedShowsTwoRowsWithTheirStatus() {
        let app = launch("on", timeSensitive: "on")
        let notifications = app.buttons["settings.notifications"]
        XCTAssertTrue(notifications.appears(timeout: 5))
        let timeSensitive = app.buttons["settings.notifications.timeSensitive"]
        // One snapshot per row for its label, value and frame.
        guard let notificationsFacts = try? notifications.snapshot(), let timeSensitiveFacts = try? timeSensitive.snapshot() else {
            return XCTFail("No row snapshot")
        }
        XCTAssertTrue(notificationsFacts.label.hasPrefix("Notifications"), notificationsFacts.label)
        XCTAssertTrue(notificationsFacts.label.contains("On. Door and camera alerts reach you."), notificationsFacts.label)
        XCTAssertEqual(notificationsFacts.value as? String ?? "", "")
        assertTarget(notifications)
        XCTAssertTrue(timeSensitiveFacts.label.contains("Time Sensitive Notifications"), timeSensitiveFacts.label)
        XCTAssertTrue(timeSensitiveFacts.label.contains("On. Urgent alerts can break through a Focus."), timeSensitiveFacts.label)
        assertTarget(timeSensitive)
        XCTAssertLessThan(notificationsFacts.frame.minY, timeSensitiveFacts.frame.minY, "Notifications reads before Time Sensitive")
        XCTAssertFalse(app.switches.count > 0, "The app cannot flip either value, so there is no switch")
        keepScreenshot(app, "notification-settings-on-\(layout)")
    }

    func testRowsOpenSettingsWithAHint() {
        let app = launch("on")
        for id in ["settings.notifications", "settings.notifications.timeSensitive"] {
            let row = app.buttons[id]
            XCTAssertEqual(row.value as? String ?? "", "")
            row.tap()
            XCTAssertEqual(app.staticTexts["gallery.lastCall"].firstMatch.label, "Last action: open settings", id)
        }
    }

    func testNotificationSettingsTimeSensitiveOff() {
        let off = launch("on", timeSensitive: "off")
        XCTAssertTrue(off.buttons["settings.notifications.timeSensitive"].label.contains("Off. Urgent alerts wait until your Focus ends."))
        keepScreenshot(off, "notification-settings-ts-off-\(layout)")
    }

    func testNotificationSettingsTimeSensitiveUnsupported() {
        let unsupported = launch("on", timeSensitive: "unsupported")
        XCTAssertTrue(unsupported.buttons["settings.notifications"].appears(timeout: 5)) // Final layout first, then the absence.
        XCTAssertFalse(unsupported.buttons["settings.notifications.timeSensitive"].exists)
    }

    func testNotificationSettingsNeverAsked() {
        let asked = launch("not-determined")
        XCTAssertTrue(asked.buttons["settings.notifications.turnOn"].appears(timeout: 5)) // Final layout first, then the absence.
        XCTAssertFalse(asked.buttons["settings.notifications"].exists)
    }

    func testNotificationSettingsDenied() {
        let denied = launch("denied")
        XCTAssertTrue(denied.buttons["settings.notifications.openSettings"].appears(timeout: 5)) // Final layout first, then the absence.
        XCTAssertFalse(denied.buttons["settings.notifications.timeSensitive"].exists)
    }

    /// One state passes the audit at the default size and at AX5.
    private func assertStatePassesAudit(_ notifications: String, timeSensitive: String) throws {
        let app = launch(notifications, timeSensitive: timeSensitive)
        try FentonHomeApp.audit(app) { self.launch(notifications, timeSensitive: timeSensitive, arguments: FentonHomeApp.ax5) }
        let large = launch(notifications, timeSensitive: timeSensitive, arguments: FentonHomeApp.ax5)
        keepScreenshot(large, "notification-settings-\(notifications)-\(timeSensitive)-ax5-\(layout)")
        if notifications == "on" {
            // At accessibility sizes the glyph moves above the text and the row grows; it is still one element.
            let row = large.buttons["settings.notifications.timeSensitive"]
            // The list builds the rows in view: scroll to it first (the folded Duo at AX5 starts above it).
            for _ in 0..<8 where !row.exists { large.swipeUp() }
            XCTAssertTrue(row.exists)
            XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        }
        // No terminate: the next launch of the app ends this AX5 process, and a reuse launch drops the resident that it replaced.
    }

    func testNotificationSettingsOnOnPassesAccessibilityAudit() throws { try assertStatePassesAudit("on", timeSensitive: "on") }
    func testNotificationSettingsOnOffPassesAccessibilityAudit() throws { try assertStatePassesAudit("on", timeSensitive: "off") }
    func testNotificationSettingsDeniedOnPassesAccessibilityAudit() throws { try assertStatePassesAudit("denied", timeSensitive: "on") }
    func testNotificationSettingsNotDeterminedOnPassesAccessibilityAudit() throws { try assertStatePassesAudit("not-determined", timeSensitive: "on") }
}
