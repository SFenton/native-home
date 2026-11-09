import XCTest

/// Home after a real sign-in: audit, chips, sheets and reopening without a reload.
@MainActor
final class HomeJourneyTests: JourneyTestCase {

    func testHomePassesAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            settleScreen()
            return large
        }
    }

    func testStatusChipsHaveValueLabels() throws {
        let app = try FentonHomeApp.launchSignedIn()
        for sheet in ["lights", "security", "climate", "occupancy", "contacts", "airQuality"] {
            let chip = app.buttons["home.chip.\(sheet)"]
            XCTAssertTrue(chip.exists, sheet)
            XCTAssertTrue(chip.label.contains(","), "\(sheet) chip label lacks its summary: \(chip.label)")
            XCTAssertGreaterThanOrEqual(chip.frame.height, 43)
        }
    }

    /// Every Home chip keeps its text at 4.5:1 as rendered, whatever colour the house gives it (the temperature and AQI
    /// colours come from Home Assistant, the contact chip from the alarm and who is home).
    func testStatusChipsKeepTheirTextReadableInTheirColours() throws {
        let app = try FentonHomeApp.launchSignedIn()
        settleScreen()
        for sheet in ["lights", "security", "climate", "occupancy", "contacts", "airQuality"] {
            let chip = app.buttons["home.chip.\(sheet)"]
            XCTAssertTrue(chip.appears(timeout: 10), sheet)
            revealChip(chip, in: app)
            settleScreen() // A colour cross-fade settles before it is measured.
            if let capture = RenderedContrast.Capture.screen(), let ratio = RenderedContrast.ratio(of: chip.frame, in: capture) {
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(sheet) chip measured \(ratio):1 (\(chip.label))")
            }
        }
    }

    func testLightsSheetOpensAndAudits() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.buttons["home.chip.lights"].tap()
        XCTAssertTrue(app.buttons["Close"].appears(timeout: 5))
        settleScreen() // Let the sheet finish presenting; mid-animation frames fail contrast and clipping.
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            large.buttons["home.chip.lights"].tap()
            XCTAssertTrue(large.buttons["Close"].appears(timeout: 5))
            settleScreen()
            return large
        }
    }

    /// Opens the Lights sheet and pushes the Guest Room's lights.
    private func openGuestRoomLights(_ app: XCUIApplication) {
        app.buttons["home.chip.lights"].tap()
        let room = app.buttons["overview.lights.room.Guest Room"]
        XCTAssertTrue(room.appears(timeout: 5))
        XCTAssertTrue(room.wait(for: \.isHittable, toEqual: true, timeout: 5), "Sheet still presenting")
        room.tap()
        XCTAssertTrue(app.navigationBars["Guest Room Lights"].appears(timeout: 5))
    }

    /// A room in the Lights sheet pushes its lights (web room detail), and Back returns to the rooms.
    func testLightsRoomPushesItsLights() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openGuestRoomLights(app)
        XCTAssertTrue(app.descendants(matching: .any)["room.light.light.demo_guest_room_light_1"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["room.light.light.demo_guest_room_light_2"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["room.lightGroup.light.demo_guest_room_item_1"].exists)
        goBack(in: app)
        XCTAssertTrue(app.buttons["overview.lights.room.Guest Room"].appears(timeout: 5))
        app.buttons["Close"].tap()
    }

    /// Every room card in the Lights sheet has the height of the tallest one (a wrapping room name lifts them all). The room power
    /// discs (`.action.power`) are not cards.
    func testLightsRoomCardsShareOneHeight() throws {
        let app = try FentonHomeApp.launchSignedIn()
        app.buttons["home.chip.lights"].tap()
        let rooms = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'overview.lights.room.' AND NOT identifier CONTAINS '.action.'"))
        XCTAssertTrue(rooms.firstMatch.appears(timeout: 5))
        settleScreen()
        let heights = rooms.allElementsBoundByIndex.filter(\.isHittable).map(\.frame.height)
        XCTAssertGreaterThan(heights.count, 1)
        let tallest = heights.max() ?? 0
        for height in heights { XCTAssertEqual(height, tallest, accuracy: 1, "Room cards differ in height: \(heights)") }
        app.buttons["Close"].tap()
    }

    // Each chip opens its overview and a room pushes its detail; both pages pass the audit at default and AX5 size.
    // One test per page, so a simulator crash under host load costs one rerun, not the whole sweep.
    func testLightsOverviewAudit() throws { try auditChip("lights") }
    func testLightsDetailAudit() throws { try auditRoom("Kitchen", chip: "lights") }
    func testClimateOverviewAudit() throws { try auditChip("climate") }
    func testClimateDetailAudit() throws { try auditRoom("Office", chip: "climate") }
    func testOccupancyOverviewAudit() throws { try auditChip("occupancy") }
    func testOccupancyDetailAudit() throws { try auditRoom("Office", chip: "occupancy") }
    func testContactsOverviewAudit() throws { try auditChip("contacts") }
    func testContactsDetailAudit() throws { try auditRoom("Office", chip: "contacts") }
    func testAirQualityOverviewAudit() throws { try auditChip("airQuality") }
    func testSecuritySheetAudit() throws { try auditChip("security") }

    private func auditChip(_ chip: String) throws {
        let app = try FentonHomeApp.launchSignedIn()
        openChip(chip, in: app)
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.openChip(chip, in: large)
            return large
        }
    }

    private func auditRoom(_ room: String, chip: String) throws {
        let app = try FentonHomeApp.launchSignedIn()
        openRoom(room, chip: chip, in: app)
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.openRoom(room, chip: chip, in: large)
            return large
        }
    }

    /// Scrolls the status rail sideways until the chip is on screen (later chips start past the iPhone's edge).
    private func revealChip(_ chip: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch
        // `isHittable` reports chips clipped by the rail as hittable, so compare frames instead.
        func offScreen() -> Bool { chip.frame.maxX > window.frame.maxX - 8 || chip.frame.minX < window.frame.minX + 8 }
        for _ in 0..<6 where offScreen() {
            let y = chip.frame.midY
            let direction: CGFloat = chip.frame.maxX > window.frame.maxX - 8 ? -1 : 1
            let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.frame.midX, dy: y))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: direction * window.frame.width * 0.4, dy: 0)))
        }
    }

    /// Goes back one page: the system Back button wherever the bar puts it (the folded iPhone Duo moves bar items into
    /// its vertical bar), else the leading-edge back swipe (devices.md).
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

    private func openChip(_ chip: String, in app: XCUIApplication) {
        let button = app.buttons["home.chip.\(chip)"]
        XCTAssertTrue(button.appears(timeout: 10), chip)
        revealChip(button, in: app)
        button.tap()
        XCTAssertTrue(app.buttons["Close"].appears(timeout: 5), chip)
        settleScreen() // Let the sheet finish presenting; mid-animation frames fail contrast and clipping.
    }

    private func openRoom(_ room: String, chip: String, in app: XCUIApplication) {
        openChip(chip, in: app)
        let tile = app.buttons["overview.\(chip).room.\(room)"]
        if !tile.isHittable { app.swipeUp() }
        tile.tap()
        XCTAssertTrue(app.staticTexts["overview.detail.subtitle"].appears(timeout: 5), "\(chip) \(room)")
        settleScreen()
    }

    /// Turning the Guest Room's group light on or off flips its live state, then the test restores it.
    func testLightsSheetTogglesAGroup() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openGuestRoomLights(app)
        let tile = app.descendants(matching: .any)["room.lightGroup.light.demo_guest_room_item_1"]
        XCTAssertTrue(tile.appears(timeout: 5))
        XCTAssertTrue(tile.wait(for: \.isHittable, toEqual: true, timeout: 5), "Sheet still presenting")
        let before = try XCTUnwrap(tile.value as? String)
        XCTAssertNotEqual(before, "Unavailable")
        tile.tap()
        let changed = NSPredicate(format: "value != %@", before)
        wait(for: [XCTNSPredicateExpectation(predicate: changed, object: tile)], timeout: 10)
        tile.tap()
        let restored = NSPredicate(format: "value == %@", before)
        wait(for: [XCTNSPredicateExpectation(predicate: restored, object: tile)], timeout: 10)
        app.buttons["Close"].tap()
    }

    /// Dragging across a dimmable group sets its brightness live, then the test restores the old state.
    func testLightsSheetDragSetsBrightness() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openGuestRoomLights(app)
        let tile = app.descendants(matching: .any)["room.lightGroup.light.demo_guest_room_item_1"]
        XCTAssertTrue(tile.appears(timeout: 5))
        XCTAssertTrue(tile.wait(for: \.isHittable, toEqual: true, timeout: 5), "Sheet still presenting")
        // The sheet can open before the guest room light's state has arrived: wait on the state rather than read the
        // "Unavailable" a tile shows until then (live run, 2026-10-17).
        let arrived = NSPredicate(format: "value != 'Unavailable'")
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: arrived, object: tile)], timeout: 15)
        let before = try XCTUnwrap(tile.value as? String)
        XCTAssertNotEqual(before, "Unavailable")
        XCTAssertTrue(before == "Off" || before.hasSuffix("%"), "Not a brightness tile: \(before)")
        let target = before == "30%" ? 0.7 : 0.3
        drag(tile, to: target)
        let set = NSPredicate(format: "value != %@ AND value != 'Off'", before)
        wait(for: [XCTNSPredicateExpectation(predicate: set, object: tile)], timeout: 10)
        let level = Int((tile.value as? String ?? "").dropLast()) ?? -1
        XCTAssertEqual(Double(level), target * 100, accuracy: 6, "Drag landed at \(level)%")
        // Restore: off by tapping, else drag back to the old level.
        if before == "Off" { tile.tap() } else { drag(tile, to: (Double(before.dropLast()) ?? 100) / 100) }
        let moved = NSPredicate(format: "value != %@", "\(level)%")
        wait(for: [XCTNSPredicateExpectation(predicate: moved, object: tile)], timeout: 10)
        let after = tile.value as? String ?? ""
        if before == "Off" { XCTAssertEqual(after, "Off") } else {
            // brightness_pct round-trips through 0...255, so allow a few percent.
            XCTAssertEqual(Double(after.dropLast()) ?? -1, Double(before.dropLast()) ?? 0, accuracy: 3)
        }
        app.buttons["Close"].tap()
    }

    /// Drags horizontally from the leading edge to `fraction` of the tile's width.
    private func drag(_ tile: XCUIElement, to fraction: Double) {
        let start = tile.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = tile.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    /// The pose a capture test runs in. `upright` is the device's own pose (iPad: portrait, set first); `iPadLandscape`
    /// is iPad only. Screenshots are named `<screen>-<orientation>`, for design review on every layout.
    private enum Pose {
        case upright, iPadLandscape
        func suffix(on family: FentonHomeApp.Family) -> String {
            self == .iPadLandscape ? "landscape" : family == .iPad ? "portrait" : "current"
        }
    }

    /// Sets `pose` (iPad only; setting the orientation on an unfolded Duo hangs the runner, devices.md) and returns
    /// the screenshot suffix. Landscape tests skip off iPad before any launch.
    private func enter(_ pose: Pose) throws -> String {
        if pose == .iPadLandscape { try XCTSkipUnless(FentonHomeApp.family == .iPad, "iPad landscape only") }
        if FentonHomeApp.family == .iPad {
            XCUIDevice.shared.orientation = pose == .iPadLandscape ? .landscapeLeft : .portrait
            if pose == .iPadLandscape { addTeardownBlock { XCUIDevice.shared.orientation = .portrait } }
        }
        return pose.suffix(on: FentonHomeApp.family)
    }

    private func captureSignIn(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let signedOut = FentonHomeApp.launchSignedOut()
        XCTAssertTrue(signedOut.textFields["login.username"].appears(timeout: 10))
        keepScreenshot(signedOut, "signin-\(suffix)")
    }

    private func captureHome(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let app = try FentonHomeApp.launchSignedIn()
        settleScreen()
        keepScreenshot(app, "home-\(suffix)")
    }

    private func captureLightsSheet(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let app = try FentonHomeApp.launchSignedIn()
        settleScreen()
        app.buttons["home.chip.lights"].tap()
        XCTAssertTrue(app.buttons["Close"].appears(timeout: 5))
        settleScreen()
        keepScreenshot(app, "lights-\(suffix)")
    }

    /// Keeps a chip's overview and, where it has one, a room's detail page, named `<chip>-<page>-<orientation>`.
    private func captureChip(_ chip: String, _ pose: Pose) throws {
        // Only the lights chip needs the house's bedroom title; the others open generic rooms, so they never skip.
        var rooms = ["climate": "Living Room", "occupancy": "Living Room", "contacts": "Office"]
        if chip == "lights" { rooms["lights"] = try JourneyExpectations.current(for: .signedIn).value(.roomBedroomTitle) }
        let suffix = try enter(pose)
        let app = try FentonHomeApp.launchSignedIn()
        settleScreen()
        openChip(chip, in: app)
        keepScreenshot(app, "\(chip)-overview-\(suffix)")
        if let room = rooms[chip] {
            let tile = app.buttons["overview.\(chip).room.\(room)"]
            if !tile.isHittable { app.swipeUp() }
            tile.tap()
            XCTAssertTrue(app.staticTexts["overview.detail.subtitle"].appears(timeout: 5))
            settleScreen()
            keepScreenshot(app, "\(chip)-detail-\(suffix)")
        }
    }

    func testCaptureHomeSignIn() throws { try captureSignIn(.upright) }
    func testCaptureHomeSignInInIPadLandscape() throws { try captureSignIn(.iPadLandscape) }
    func testCaptureHomeHome() throws { try captureHome(.upright) }
    func testCaptureHomeHomeInIPadLandscape() throws { try captureHome(.iPadLandscape) }
    func testCaptureHomeLightsSheet() throws { try captureLightsSheet(.upright) }
    func testCaptureHomeLightsSheetInIPadLandscape() throws { try captureLightsSheet(.iPadLandscape) }
    func testCaptureHomeLightsChip() throws { try captureChip("lights", .upright) }
    func testCaptureHomeLightsChipInIPadLandscape() throws { try captureChip("lights", .iPadLandscape) }
    func testCaptureHomeClimateChip() throws { try captureChip("climate", .upright) }
    func testCaptureHomeClimateChipInIPadLandscape() throws { try captureChip("climate", .iPadLandscape) }
    func testCaptureHomeOccupancyChip() throws { try captureChip("occupancy", .upright) }
    func testCaptureHomeOccupancyChipInIPadLandscape() throws { try captureChip("occupancy", .iPadLandscape) }
    func testCaptureHomeContactsChip() throws { try captureChip("contacts", .upright) }
    func testCaptureHomeContactsChipInIPadLandscape() throws { try captureChip("contacts", .iPadLandscape) }
    func testCaptureHomeAirQualityChip() throws { try captureChip("airQuality", .upright) }
    func testCaptureHomeAirQualityChipInIPadLandscape() throws { try captureChip("airQuality", .iPadLandscape) }
    func testCaptureHomeSecurityChip() throws { try captureChip("security", .upright) }
    func testCaptureHomeSecurityChipInIPadLandscape() throws { try captureChip("security", .iPadLandscape) }

    /// Keeps a screenshot of live Home in the result bundle.
    func testHomeScreenshot() throws {
        let app = try FentonHomeApp.launchSignedIn()
        settleScreen()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Home"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A password sign-in keeps its refresh token in the Keychain, so a cold relaunch opens on Home.
    func testRelaunchSkipsSignIn() throws {
        let app = try FentonHomeApp.launchSignedIn(passwordOnly: true)
        app.terminate()
        let relaunched = FentonHomeApp.target()
        relaunched.launch()
        XCTAssertTrue(relaunched.buttons["home.chip.lights"].appears(timeout: 10), "Relaunch did not open on Home")
        XCTAssertFalse(relaunched.textFields["login.username"].exists)
    }

    /// Reopening keeps Home on screen: no sign-in screen, no blank page.
    func testReopeningDoesNotReload() throws {
        let app = try FentonHomeApp.launchSignedIn()
        XCUIDevice.shared.press(.home)
        settleScreen()
        app.activate()
        XCTAssertTrue(app.buttons["home.chip.lights"].appears(timeout: 2))
        XCTAssertFalse(app.textFields["login.username"].exists)
    }
}
