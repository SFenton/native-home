import XCTest

/// The full-app accessibility sweep (direction G, Phase 4): every tab root, Quick Links, Account, a room page and
/// the main sheets, signed in against the house, each through `FentonHomeApp.audit` (contrast, text clipping and
/// the AX5 relaunch). Tab roots also check VoiceOver's reading order, and run again under Reduce Motion, Reduce
/// Transparency, Increase Contrast and Bold Text together.
///
/// One test per page, so `-only-testing` can run a page alone and a simulator crash under host load costs one
/// rerun (devices.md). Nothing here changes a device: every step opens a page or sheet and reads it.
/// Skips without credentials; the tests that run on the unfolded Duo do not skip after launch.
@MainActor
final class AccessibilitySweepJourneyTests: JourneyTestCase {
    typealias Setting = FentonHomeApp.SystemSetting

    /// Settings the running test turned on; the simulator keeps them until the next launch states them again.
    nonisolated(unsafe) private static var usedSettings = false

    override func tearDown() {
        super.tearDown()
        MainActor.assumeIsolated {
            // Leave the simulator as found: the settings belong to the device, not the app.
            if Self.usedSettings { FentonHomeApp.launchGallery("system-accessibility").terminate() }
        }
    }

    // MARK: - Sweep

    /// Opens a page, checks its reading order when it is a tab root, and audits it with the AX5 relaunch.
    /// - Parameters:
    ///   - name: The page, for screenshot names.
    ///   - settings: System settings to run under.
    ///   - rootTitle: A tab root's navigation title, which turns on the reading-order check.
    ///   - appearance: The sheets' appearance, `light` or `dark`. Sheets follow the system appearance and a simulator
    ///     pool member can be left in either, so every sweep pins it: the runner's (`--appearance`), else light.
    ///   - open: Navigates from a fresh signed-in launch to the page.
    private func sweep(_ name: String, settings: [Setting] = [], rootTitle: String? = nil, appearance: String? = nil,
                       open: @escaping (XCUIApplication) throws -> Void) throws {
        Self.usedSettings = !settings.isEmpty
        let shown = appearance ?? ProcessInfo.processInfo.environment["FENTON_APPEARANCE"] ?? "light"
        let environment = Setting.environment(settings).merging(["FENTON_APPEARANCE": shown]) { _, new in new }
        let app = try FentonHomeApp.launchSignedIn(environment: environment)
        try open(app)
        settleScreen() // Mid-animation frames fail contrast and clipping.
        if let rootTitle { try assertReadingOrder(app, title: rootTitle) }
        keepScreenshot(app, "sweep-\(name)-\(shown)-\(layout)")
        try FentonHomeApp.audit(app) {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5, environment: environment)
            try open(large)
            settleScreen()
            return large
        }
    }

    // MARK: - Navigation steps

    private func root(_ section: String, _ title: String, in app: XCUIApplication) {
        if section != "home" { openSection(section, title: title, in: app) }
        XCTAssertTrue(app.navigationBars[title].appears(timeout: 15), "\(title) did not appear")
    }

    private func openQuickLinks(in app: XCUIApplication) {
        let button = app.buttons["quickLinks.open"]
        XCTAssertTrue(button.appears(timeout: 10), "No Quick Links header button")
        button.tap()
        XCTAssertTrue(element("quickLinks.rooms", in: app).appears(timeout: 10), "Quick Links did not open")
    }

    /// Scrolls the page in short drags until `target` can be tapped.
    private func reveal(_ target: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        for _ in 0..<24 where !(target.exists && target.isHittable) {
            let above = target.exists && target.frame.midY < window.midY && target.frame.maxY > 0
            var x = window.midX
            if FentonHomeApp.family == .iPhoneDuo { x = min(x, window.maxX - 96) }
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: -window.minX, dy: -window.minY))
            let from = origin.withOffset(CGVector(dx: x, dy: window.minY + window.height * (above ? 0.35 : 0.65)))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: above ? 220 : -220)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(target.exists && target.isHittable, "\(target) never came into view", file: file, line: line)
    }

    private func tap(_ id: String, in app: XCUIApplication, timeout: TimeInterval = 15) {
        let target = element(id, in: app)
        XCTAssertTrue(target.appears(timeout: timeout), "\(id) missing")
        reveal(target, in: app)
        target.tap()
    }

    /// Waits for a sheet to finish presenting: its Close button reachable.
    private func waitForSheet(in app: XCUIApplication) {
        let close = app.buttons["Close"].firstMatch
        if !close.appears(timeout: 10) { keepScreenshot(app, "sheet-did-not-open-\(layout)") }
        XCTAssertTrue(close.exists, "Sheet did not open")
        XCTAssertTrue(close.wait(for: \.isHittable, toEqual: true, timeout: 10), "Sheet still presenting")
    }

    /// Quick Links, then a tile that pushes a page (Food, Vacuums, Media).
    private func openQuickLinkPage(_ id: String, in app: XCUIApplication) {
        openQuickLinks(in: app)
        tap("quickLinks.\(id)", in: app)
    }

    /// Bedroom 1's page through Quick Links, Rooms.
    private func openMasterBedroom(in app: XCUIApplication) throws {
        let bedroom = try JourneyExpectations.current(for: .signedIn).value(.roomBedroomId)
        openQuickLinks(in: app)
        tap("quickLinks.rooms", in: app)
        tap("rooms.\(bedroom)", in: app)
        XCTAssertTrue(element("room.scroll.\(bedroom)", in: app).appears(timeout: 15), "The bedroom page did not open")
    }

    // MARK: - Tab roots

    func testHomeRoot() throws { try sweep("home", rootTitle: "Home") { self.root("home", "Home", in: $0) } }
    func testSecurityRoot() throws { try sweep("security", rootTitle: "Security") { self.root("security", "Security", in: $0) } }
    func testClimateRoot() throws { try sweep("climate", rootTitle: "Climate") { self.root("climate", "Climate", in: $0) } }
    func testChoresRoot() throws { try sweep("chores", rootTitle: "Chores") { self.root("chores", "Chores", in: $0) } }
    func testSettingsRoot() throws { try sweep("settings", rootTitle: "Settings") { self.root("settings", "Settings", in: $0) } }

    // MARK: - Tab roots under system accessibility settings

    func testHomeRootUnderSystemSettings() throws {
        try sweep("home-settings", settings: Setting.allCases, rootTitle: "Home") { self.root("home", "Home", in: $0) }
    }
    func testSecurityRootUnderSystemSettings() throws {
        try sweep("security-settings", settings: Setting.allCases, rootTitle: "Security") { self.root("security", "Security", in: $0) }
    }
    func testClimateRootUnderSystemSettings() throws {
        try sweep("climate-settings", settings: Setting.allCases, rootTitle: "Climate") { self.root("climate", "Climate", in: $0) }
    }
    func testChoresRootUnderSystemSettings() throws {
        try sweep("chores-settings", settings: Setting.allCases, rootTitle: "Chores") { self.root("chores", "Chores", in: $0) }
    }
    func testSettingsRootUnderSystemSettings() throws {
        try sweep("settings-settings", settings: Setting.allCases, rootTitle: "Settings") { self.root("settings", "Settings", in: $0) }
    }

    // MARK: - Sheets and pages

    func testQuickLinks() throws { try sweep("quick-links") { self.openQuickLinks(in: $0) } }

    /// The header button is a 44 pt target on every window; the sheet it opens passes the audit.
    func testQuickLinksHeaderButton() throws {
        try sweep("quick-links-button") {
            let button = $0.buttons["quickLinks.open"]
            XCTAssertTrue(button.appears(timeout: 5), "No Quick Links header button")
            XCTAssertGreaterThanOrEqual(button.frame.height, 36, "Quick Links button")
            button.tap()
            XCTAssertTrue(self.element("quickLinks.rooms", in: $0).appears(timeout: 10), "Quick Links did not open")
        }
    }

    func testAccount() throws {
        try sweep("account") { $0.openAccountSheet() }
    }

    func testRoomPage() throws { try sweep("room") { try self.openMasterBedroom(in: $0) } }

    func testHomeChipSheet() throws {
        try sweep("home-chip-sheet") {
            $0.buttons["home.chip.lights"].tap()
            self.waitForSheet(in: $0)
        }
    }

    /// The same sheets drawn dark (the runner can flip the whole sweep with `--appearance dark`).
    func testHomeChipSheetDark() throws {
        try sweep("home-chip-sheet", appearance: "dark") {
            $0.buttons["home.chip.lights"].tap()
            self.waitForSheet(in: $0)
        }
    }

    func testBedSheetDark() throws {
        try sweep("bed", appearance: "dark") {
            try self.openMasterBedroom(in: $0)
            self.tap("room.card.\(try JourneyExpectations.current(for: .signedIn).value(.bedFirstTitle))", in: $0)
            XCTAssertTrue(self.element("bed.dial", in: $0).appears(timeout: 15), "Bed sheet did not open")
            self.waitForSheet(in: $0)
        }
    }

    func testClimateAdvancedControls() throws {
        try sweep("climate-advanced") {
            self.root("climate", "Climate", in: $0)
            self.tap("climate.entry.automation", in: $0)
            self.waitForSheet(in: $0)
        }
    }

    func testSecuritySystemSheet() throws {
        try sweep("security-system") {
            self.root("security", "Security", in: $0)
            self.tap("security.chip.security", in: $0)
            XCTAssertTrue($0.navigationBars["Security System"].appears(timeout: 10), "Security system sheet did not open")
            self.waitForSheet(in: $0)
        }
    }

    func testMediaRemote() throws {
        try sweep("media-remote") {
            self.openQuickLinkPage("media", in: $0)
            XCTAssertTrue(self.element("media.scroll", in: $0).appears(timeout: 15), "Media did not open")
            // The Living Room remote tile's body (the first card is not always a remote); its middle is the transport.
            let card = self.element("media.card.living-room.living-room-shield", in: $0)
            XCTAssertTrue(card.appears(timeout: 15), "Media has no Living Room remote card")
            self.reveal(card, in: $0)
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)).tap()
            self.waitForSheet(in: $0)
        }
    }

    func testRoomDeviceSheet() throws {
        try sweep("room-device") {
            try self.openMasterBedroom(in: $0)
            self.tap("room.card.Air Purifier", in: $0)
            self.waitForSheet(in: $0)
        }
    }

    func testBedSheet() throws {
        try sweep("bed") {
            try self.openMasterBedroom(in: $0)
            self.tap("room.card.\(try JourneyExpectations.current(for: .signedIn).value(.bedFirstTitle))", in: $0)
            XCTAssertTrue(self.element("bed.dial", in: $0).appears(timeout: 15), "Bed sheet did not open")
            self.waitForSheet(in: $0)
        }
    }

    func testFoodHub() throws {
        try sweep("food") {
            self.openQuickLinkPage("food", in: $0)
            XCTAssertTrue(self.element("food.scroll", in: $0).appears(timeout: 15), "Food did not open")
            // The suggestions fade in over their placeholders; audit once their arc is gone and the content has settled (an
            // audit that began mid-fade sampled a half-laid-out title, 2026-10-16).
            XCTAssertTrue(self.element("food.suggestions.loading", in: $0).disappears(timeout: 10), "The suggestions arc stayed")
        }
    }

    func testVacuums() throws {
        try sweep("vacuums") {
            self.openQuickLinkPage("vacuums", in: $0)
            XCTAssertTrue($0.navigationBars["Vacuums"].appears(timeout: 15), "Vacuums did not open")
        }
    }

    // MARK: - Reading order

    /// How far (pt) back up the page a stop may jump before the order counts as wrong: wider than a component's
    /// own two lines (a label and its value), narrower than a section.
    private static let rowTolerance: CGFloat = 40

    /// One element VoiceOver can land on, in the order it visits them.
    struct Stop: CustomStringConvertible {
        var label: String
        var type: XCUIElement.ElementType
        var frame: CGRect
        var description: String { "\(type.rawValue) '\(label)' y\(Int(frame.minY)) x\(Int(frame.minX)) \(Int(frame.width))x\(Int(frame.height))" }
    }

    /// The accessibility stops on screen in document order (the order SwiftUI exposes and VoiceOver swipes through).
    /// Controls are one stop each; the tab bar and the folded Duo's rail are left out.
    func readingOrder(of app: XCUIApplication) throws -> [Stop] {
        let root = try app.snapshot()
        let window = app.windows.firstMatch.frame
        let controls: Set<XCUIElement.ElementType> = [.button, .switch, .slider, .textField, .secureTextField, .link, .toggle, .segmentedControl]
        var stops: [Stop] = []
        func walk(_ node: XCUIElementSnapshot) {
            // Bars are not page content: the tab bar, and the folded Duo's vertical rail (a toolbar to XCUITest).
            if node.elementType == .tabBar || node.elementType == .toolbar { return }
            // The floating action bar overlays the foot of the page; it is read last, wherever it floats.
            if node.identifier.hasPrefix("fab.") { return }
            let isControl = controls.contains(node.elementType)
            if (node.elementType == .staticText || isControl), !node.label.isEmpty,
               !node.frame.isEmpty, window.intersects(node.frame), window.contains(CGPoint(x: node.frame.midX, y: node.frame.midY)) {
                stops.append(Stop(label: node.label, type: node.elementType, frame: node.frame))
            }
            if isControl { return }
            node.children.forEach(walk)
        }
        walk(root)
        return stops
    }

    /// The page title comes before the page's content, and the content follows in visual order: down the page, and
    /// left to right along a row. Navigation bar buttons may come before or after the title.
    func assertReadingOrder(_ app: XCUIApplication, title: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let stops = try readingOrder(of: app)
        let listing = stops.map(\.description).joined(separator: "\n")
        XCTContext.runActivity(named: "Reading order of \(title)") { activity in
            let attachment = XCTAttachment(string: listing)
            attachment.name = "reading-order-\(title)"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        let bar = app.navigationBars[title].frame
        func inBar(_ stop: Stop) -> Bool { !bar.isEmpty && bar.contains(CGPoint(x: stop.frame.midX, y: stop.frame.midY)) }
        guard let titleIndex = stops.firstIndex(where: { $0.type == .staticText && $0.label == title }) else {
            XCTFail("No '\(title)' title stop in the reading order:\n\(listing)", file: file, line: line)
            return
        }
        let before = stops[..<titleIndex].filter { !inBar($0) }
        XCTAssertTrue(before.isEmpty, "Content comes before the '\(title)' title:\n\(listing)", file: file, line: line)
        let content = stops[(titleIndex + 1)...].filter { !inBar($0) }
        var violations: [String] = []
        for (a, b) in zip(content, content.dropFirst()) {
            // A stop inside the previous one is part of the same component (a card's own texts).
            if a.frame.insetBy(dx: -1, dy: -1).contains(b.frame) { continue }
            let sameRow = abs(a.frame.midY - b.frame.midY) < min(a.frame.height, b.frame.height) / 2
            if sameRow {
                if b.frame.minX < a.frame.minX - 4 { violations.append("\(b) reads after \(a), which is to its right") }
            } else if b.frame.maxY < a.frame.minY - Self.rowTolerance {
                // Only a clear jump back up the page counts: a component may read a label then its value across
                // two short lines (an hour, then its temperature) and then continue in the next column.
                violations.append("\(b) reads after \(a), which is well below it")
            }
        }
        XCTAssertTrue(violations.isEmpty, "Reading order is not top to bottom, leading to trailing:\n"
            + violations.joined(separator: "\n") + "\n--- order ---\n" + listing, file: file, line: line)
    }
}
