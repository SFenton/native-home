import XCTest

/// Native notifications on each device (`.agents/platforms/apple/push.md`): the permission prompt after sign-in, a
/// delivered banner and the page a tap opens, the buttons and attachments the service extension builds, a link
/// button, and `clear_notification`.
///
/// Remote banners come from the host, since only `xcrun simctl push` can send them: `send-<fixture>.ready` in
/// `FENTON_CAPTURE_DIR` asks for `tools/push_fixtures/<fixture>.apns`, `send-<fixture>.done` answers
/// (`tools/push_sim.sh`). The simulator never runs service extensions for `simctl push` and refuses background
/// pushes, so buttons, attachments and `clear_notification` go through the app's debug hooks
/// (`FENTON_PUSH_PREVIEW`, `FENTON_PUSH_COMMAND`), which run the same enrichment and command code. Without a capture
/// folder the journeys skip.
final class PushJourneyTests: JourneyTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    /// Permission was answered in this run (by the alert, or by a banner where the simulator kept the answer).
    private static var answeredPermission = false

    // MARK: - Journeys

    func testTappingABannerOpensItsPage() throws {
        let app = try launch()
        XCUIDevice.shared.press(.home)
        try push("banner")
        let banner = notification("Front Door")
        XCTAssertTrue(banner.appears(timeout: 20), "The banner did not appear")
        attach("push-banner-\(layout)")
        banner.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "The app did not open")
        XCTAssertTrue(element("security.scroll", in: app).appears(timeout: 20), "The tap did not open Security")
        keepScreenshot(app, "push-banner-opened-\(layout)")
    }

    func testButtonsComeFromThePayloadAndALinkButtonOpensItsPage() throws {
        let app = try launch(preview: "actions", banner: "Garage Door")
        let banner = notification("Garage Door")
        XCTAssertTrue(banner.appears(timeout: 240), "The banner did not appear")
        banner.press(forDuration: 1.2)
        // Built from `fenton.actions`, in payload order.
        for title in ["Close", "Show Garage", "Reply", "Ignore"] {
            XCTAssertTrue(springboard.buttons[title].appears(timeout: 10), "\(title) is missing")
        }
        keepScreenshot(springboard, "push-actions-\(layout)")
        springboard.buttons["Show Garage"].tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "The app did not open")
        XCTAssertTrue(element("room.scroll.garage", in: app).appears(timeout: 20), "Show Garage did not open the Garage page")
        keepScreenshot(app, "push-actions-opened-\(layout)")
    }

    func testTheCameraSnapshotIsAttached() throws {
        let app = try launch(preview: "camera", banner: "Doorbell")
        let banner = notification("Doorbell")
        XCTAssertTrue(banner.appears(timeout: 240), "The banner did not appear")
        attach("push-camera-\(layout)")
        banner.press(forDuration: 1.2)
        XCTAssertTrue(springboard.buttons["View Camera"].appears(timeout: 10), "View Camera is missing")
        keepScreenshot(springboard, "push-camera-expanded-\(layout)")
        springboard.buttons["View Camera"].tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "The app did not open")
        XCTAssertTrue(element("security.scroll", in: app).appears(timeout: 20), "View Camera did not open Security")
    }

    func testClearNotificationRemovesTheTaggedNotification() throws {
        let app = try launch(preview: "banner", banner: "Front Door")
        XCTAssertTrue(notification("Front Door").appears(timeout: 240), "The banner did not appear")
        // Let it move to Notification Center, then run the house's clear_notification for its tag.
        XCTAssertTrue(notification("Front Door").disappears(timeout: 15))
        app.terminate()
        _ = try FentonHomeApp.launchSignedIn(environment: ["FENTON_PUSH": "1", "FENTON_PUSH_COMMAND": try fixture("clear")])
        sleep(4)
        XCUIDevice.shared.press(.home)
        openNotificationCenter()
        keepScreenshot(springboard, "push-cleared-\(layout)")
        XCTAssertFalse(notification("Front Door").exists, "clear_notification left the notification")
        XCUIDevice.shared.press(.home)
    }

    // MARK: - Helpers

    /// Signs in with push on and answers the permission prompt, which appears once per install.
    /// - Parameters:
    ///   - preview: A fixture the app shows as a local notification a few seconds after launch.
    ///   - banner: The preview's title. Where the simulator already stored the permission (a reinstall keeps it), no
    ///     alert ever comes, so the wait also ends when this banner shows; waiting out the alert would miss it.
    private func launch(preview: String? = nil, banner: String? = nil) throws -> XCUIApplication {
        guard captureFolder != nil else { throw XCTSkip("Set TEST_RUNNER_FENTON_CAPTURE_DIR and run tools/push_sim.sh") }
        var environment = ["FENTON_PUSH": "1"]
        if let preview {
            environment["FENTON_PUSH_PREVIEW"] = try fixture(preview)
            environment["FENTON_PUSH_PREVIEW_DELAY"] = "8"
        }
        let app = try FentonHomeApp.launchSignedIn(environment: environment)
        // After a boot the iOS 27 simulator can take minutes to show the alert, or to answer with a stored
        // permission; until then, pushes are refused ("Source is not authorized"). Wait once per run.
        let allow = springboard.alerts.buttons["Allow"]
        let deadline = Date().addingTimeInterval(Self.answeredPermission ? 5 : 300)
        while Date() < deadline {
            if allow.exists {
                allow.tap()
                Self.answeredPermission = true
                break
            }
            if let banner, notification(banner).exists {
                Self.answeredPermission = true
                break
            }
            usleep(500_000)
        }
        return app
    }

    /// Keeps a screenshot in the result bundle at once (a host capture takes long enough for a banner to leave).
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A fixture from `tools/push_fixtures`, base64 (the simulator reads the host's files).
    private func fixture(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("tools/push_fixtures/\(name).apns")).base64EncodedString()
    }

    private var captureFolder: URL? {
        ProcessInfo.processInfo.environment["FENTON_CAPTURE_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
    }

    /// Asks the host to send a fixture and waits until it has.
    private func push(_ fixture: String) throws {
        let folder = try XCTUnwrap(captureFolder)
        let ready = folder.appendingPathComponent("send-\(fixture).ready")
        let done = folder.appendingPathComponent("send-\(fixture).done")
        try? FileManager.default.removeItem(at: done)
        FileManager.default.createFile(atPath: ready.path, contents: nil)
        let deadline = Date().addingTimeInterval(60)
        while !FileManager.default.fileExists(atPath: done.path), Date() < deadline { usleep(200_000) }
        try? FileManager.default.removeItem(at: ready)
        XCTAssertTrue(FileManager.default.fileExists(atPath: done.path), "The host did not send \(fixture)")
        try? FileManager.default.removeItem(at: done)
    }

    /// A notification on the Home Screen or in Notification Center, by its title.
    private func notification(_ title: String) -> XCUIElement {
        springboard.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func openNotificationCenter() {
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.001))
        top.press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.6)))
    }
}
