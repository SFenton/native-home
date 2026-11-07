import XCTest

/// Settings → App Icon: the row, the sheet of eight named choices (Navy + Sky is the default), choosing one and the
/// accessibility audits, with an AX5 relaunch. On the simulator `setAlternateIconName` works: the journey asserts the
/// selection and dismisses the system's own notice.
@MainActor
final class AppIconJourneyTests: JourneyTestCase {
    private static let choices = ["navySky", "tealMint", "plumLilac", "forestGreen", "burgundyRose",
                                  "indigoPeriwinkle", "espressoAmber", "midnightGold"]

    // MARK: - Helpers

    /// The App Icon row, scrolled into view: it sits near the end of the Settings list, below the fold on a phone.
    private func appIconRow(_ app: XCUIApplication) -> XCUIElement {
        let row = app.buttons["settings.appIcon"]
        _ = app.descendants(matching: .any)["settings.list"].appears(timeout: 10)
        scrollTo(row, in: app, scroller: { app.settingsList }, isClear: { $0.isHittable })
        return row
    }

    /// Opens Settings → App Icon and waits for the sheet's default choice.
    private func openSheet(_ app: XCUIApplication) {
        app.openAccountSettings()
        let row = appIconRow(app)
        XCTAssertTrue(row.exists, "No App Icon row in Settings")
        assertTarget(row)
        row.tap()
        XCTAssertTrue(choice(app, "navySky").appears(timeout: 5), "The App Icon sheet did not open")
        choice(app, "navySky").settled() // The sheet has finished presenting.
    }

    private func choice(_ app: XCUIApplication, _ name: String) -> XCUIElement {
        app.buttons["appIcon.choice.\(name)"]
    }

    /// Scrolls the sheet until `element` can be tapped (one column at AX5, taller than the screen).
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        scrollTo(element, in: app, scroller: { app.scrollViews.firstMatch }, isClear: { $0.isHittable })
        return element
    }

    /// Dismisses the system's "You have changed the icon" notice. SpringBoard draws it, and the app's main thread is
    /// busy until it is answered, so only SpringBoard is asked (an app query would wait out its 30 s busy timeout).
    private func dismissSystemNotice() {
        let ok = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["OK"].firstMatch
        if ok.appears(timeout: 10) { ok.tap() }
    }

    /// Chooses `name` and waits for it to read Selected.
    private func pick(_ name: String, in app: XCUIApplication) {
        let button = reveal(choice(app, name), in: app)
        XCTAssertTrue(button.appears(timeout: 5), name)
        assertTarget(button)
        button.tap()
        dismissSystemNotice()
        // The state is the button's `.isSelected` trait (`AppIconChoiceButton`, since #159), not a value string.
        let selected = NSPredicate(format: "isSelected == true")
        expectation(for: selected, evaluatedWith: choice(app, name))
        waitForExpectations(timeout: 10)
    }

    // MARK: - Journeys

    /// The row names the installed icon; the sheet lists the eight choices, each a button named for VoiceOver with its
    /// state, the default marked, every target 44 pt or more.
    func testRowOpensSheetOfEightNamedChoicesWithDefaultMarked() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSheet(app)
        XCTAssertTrue(app.navigationBars["App Icon"].exists || app.staticTexts["App Icon"].exists, "Sheet has no App Icon title")
        var selectedChoices: [String] = []
        for name in Self.choices {
            let button = reveal(choice(app, name), in: app)
            XCTAssertTrue(button.exists, "No choice \(name)")
            assertTarget(button)
            XCTAssertTrue(button.isEnabled, "\(name) is disabled")
            // The state is the `.isSelected` trait (XCUIElement.isSelected); the button carries no value string.
            if button.isSelected { selectedChoices.append(name) }
        }
        XCTAssertEqual(selectedChoices.count, 1, "Exactly one icon reads Selected, got \(selectedChoices)")
        let navy = choice(app, "navySky")
        _ = reveal(navy, in: app)
        XCTAssertEqual(navy.label, "Navy and Sky, default")
        XCTAssertEqual(choice(app, "tealMint").label, "Teal and Mint")
    }

    /// Choosing an icon moves the selection and the row's subtitle; choosing the default again restores it.
    func testChoosingAnIconChangesTheSelectionAndTheDefaultRestoresIt() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSheet(app)
        // A failure part-way leaves the simulator's installed icon on Teal + Mint: put the default back whatever happens.
        addTeardownBlock {
            MainActor.assumeIsolated {
                guard app.state == .runningForeground, self.choice(app, "navySky").exists, !self.choice(app, "navySky").isSelected else { return }
                self.pick("navySky", in: app)
            }
        }
        // Whatever an earlier run left installed, start from the default.
        if !choice(app, "navySky").isSelected { pick("navySky", in: app) }
        pick("tealMint", in: app)
        XCTAssertFalse(choice(app, "navySky").isSelected)
        XCTAssertTrue(choice(app, "tealMint").isSelected)
        keepScreenshot(app, "app-icon-sheet-\(layout)")
        pick("navySky", in: app)
        XCTAssertFalse(choice(app, "tealMint").isSelected)
        app.buttons["appIcon.close"].tap()
        XCTAssertTrue(choice(app, "navySky").disappears(timeout: 5), "The sheet did not close")
        let row = appIconRow(app)
        XCTAssertTrue(row.label.contains("Navy + Sky"), "The row reads: \(row.label)")
    }

    /// The Settings list with the row, and the sheet, pass the accessibility audit, with an AX5 relaunch.
    func testSettingsRowAndSheetPassAccessibilityAudit() throws {
        let app = try FentonHomeApp.launchSignedIn()
        openSheet(app)
        try FentonHomeApp.audit(app, ax5Page: {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5)
            self.openSheet(large)
            return large
        })
    }

    /// The sheet in the system's light appearance (pages stay dark; sheets follow it).
    func testSheetPassesAccessibilityAuditInLightAppearance() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_APPEARANCE": "light"])
        openSheet(app)
        // The AX5 relaunch, as the dark audit has: without it "Dynamic Type font sizes are partially unsupported" on the 48 pt artwork
        // and the one-column layout cannot be told from a real clip.
        try FentonHomeApp.audit(app, ax5Page: {
            let large = try FentonHomeApp.launchSignedIn(arguments: FentonHomeApp.ax5, environment: ["FENTON_APPEARANCE": "light"])
            self.openSheet(large)
            return large
        })
    }
}
