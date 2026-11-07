import XCTest

/// The sign-in screen on every device family (owner design, 2026-10-17): layout, labels, targets, the plain-words errors, the
/// welcome back for an ended session, AX5 and Reduce Motion. Errors come from canned answers (`FENTON_SIGNIN_STUB`), so
/// no journey fails a sign-in on the real server.
@MainActor
final class LoginJourneyTests: JourneyTestCase {
    // MARK: - Helpers

    /// The server the journeys prefill (`FENTON_HASS_SERVER`); canned answers never reach it.
    private static let prefilledServer = "https://ha.example.com"

    /// A launch signed out with a canned sign-in answer, the intro skipped unless asked for. `server` prefills the Server field
    /// (nil leaves it empty).
    private func launch(stub: String? = nil, expired: String? = nil, arguments: [String] = [], intro: Bool = false,
                        server: String? = LoginJourneyTests.prefilledServer,
                        settings: [FentonHomeApp.SystemSetting] = []) -> XCUIApplication {
        let app = FentonHomeApp.makeApp()
        app.launchEnvironment["FENTON_UITEST_RESET"] = "1"
        if let server { app.launchEnvironment["FENTON_HASS_SERVER"] = server }
        app.launchEnvironment["FENTON_SKIP_INTRO"] = intro ? "0" : "1"
        app.launchEnvironment.merge(FentonHomeApp.SystemSetting.environment(settings)) { $1 }
        if let stub { app.launchEnvironment["FENTON_SIGNIN_STUB"] = stub }
        if let expired { app.launchEnvironment["FENTON_EXPIRED_ACCOUNT"] = expired }
        app.launchArguments += arguments
        app.launch()
        return app
    }

    // `fill` and `submit` use `waitForExistence`, not `appears`: its idle wait lets focus and the keyboard settle before the next
    // keystroke or tap. With the instant `appears`, on iPhone the Sign In tap lands before the form is ready and the submit never starts.
    /// Types a username and password the way a person does: tap, type, Return moves on, type, and the keyboard stays.
    private func fill(_ app: XCUIApplication, username: String = "alex", password: String = "secret") {
        let user = app.textFields["login.username"]
        XCTAssertTrue(user.waitForExistence(timeout: 10), "username field")
        user.tap()
        user.typeText(username)
        // Return on the username moves to the password (submitLabel .next, focus chaining).
        app.typeText("\n")
        let pass = app.secureTextFields["login.password"]
        XCTAssertTrue(pass.waitForExistence(timeout: 5), "password field")
        pass.typeText(password)
    }

    private func submit(_ app: XCUIApplication) {
        let button = app.buttons["login.submit"]
        for _ in 0..<6 where !(button.exists && button.isHittable) {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
    }

    // MARK: - Layout and labels

    func testLoginScreenPassesAccessibilityAudit() throws {
        let app = launch()
        XCTAssertTrue(app.textFields["login.username"].appears(timeout: 10))
        try FentonHomeApp.audit(app, ax5Page: { self.launch(arguments: FentonHomeApp.ax5) })
    }

    /// Three rows (server, username, password), and a name, a line and the footnote; the title reads as "S and H".
    func testTheScreenHasTheThreeFieldsAndItsWords() {
        let app = launch()
        XCTAssertTrue(app.textFields["login.username"].appears(timeout: 10))
        XCTAssertTrue(app.secureTextFields["login.password"].exists)
        XCTAssertTrue(app.textFields["login.server"].exists, "the server address is the first row")
        XCTAssertFalse(app.textFields["login.code"].exists, "there is no second step")
        XCTAssertEqual(element("login.title", in: app).label, "S and H", "VoiceOver says the spoken name")
        XCTAssertTrue(app.staticTexts["Sign in to your Home Assistant"].exists)
        XCTAssertTrue(element("login.footnote", in: app).exists)
        XCTAssertFalse(app.buttons["login.submit"].isEnabled, "Sign In waits for all three fields")
        XCTAssertTrue(app.buttons["login.submit"].label.contains("Sign In"))
    }

    /// Each row is a 52 pt target, tapping its empty space focuses the field, and Return moves from username to password.
    func testRowsAreTargetsAndReturnMovesOnToThePassword() {
        let app = launch()
        let user = app.textFields["login.username"]
        XCTAssertTrue(user.appears(timeout: 10))
        for field in [app.textFields["login.server"], user, app.secureTextFields["login.password"]] {
            assertTarget(field)
            XCTAssertGreaterThanOrEqual(field.frame.height, 51, "rows are 52 pt")
        }
        // The whole row is the target: its trailing space focuses it.
        app.textFields["login.username"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        app.typeText("ab")
        XCTAssertEqual(user.value as? String, "ab", "the row's space focused the username")
        app.typeText("\n")
        app.typeText("secret")
        XCTAssertTrue(app.buttons["login.submit"].isEnabled, "both fields are filled")
        assertTarget(app.buttons["login.submit"])
    }

    /// iPad and the unfolded Duo: the form is a centred column no wider than 460 pt; iPhone fills its width.
    func testTheFormIsACentredColumnOnWideScreens() {
        let app = launch()
        let user = app.textFields["login.username"]
        XCTAssertTrue(user.appears(timeout: 10))
        let window = app.windows.firstMatch.frame
        XCTAssertLessThanOrEqual(user.frame.width, 460, "the column is at most 460 pt wide")
        XCTAssertEqual(user.frame.midX, element("login.title", in: app).frame.midX, accuracy: 2, "and centred under the title")
        if FentonHomeApp.family == .iPhone {
            XCTAssertGreaterThan(user.frame.width, window.width - 80, "on a phone it fills the width")
        }
    }

    // MARK: - Errors

    func testAWrongPasswordIsSaidPlainlyAndKeepsTheUsername() {
        let app = launch(stub: "wrong")
        fill(app)
        submit(app)
        let message = element("login.error", in: app)
        XCTAssertTrue(message.appears(timeout: 10), "the red line appears under the fields")
        XCTAssertTrue(message.label.contains("That username and password don't match"), message.label)
        XCTAssertEqual(app.textFields["login.username"].value as? String, "alex", "the username stays")
        let pass = app.secureTextFields["login.password"]
        XCTAssertTrue((pass.value as? String ?? "").isEmpty || pass.value as? String == "Password", "the password clears")
        XCTAssertFalse(app.buttons["login.submit"].isEnabled, "Sign In waits for a new password")
        XCTAssertFalse(element("login.error.card", in: app).exists, "a refused password is a line, not a card")
        pass.typeText("again")
        XCTAssertTrue(app.buttons["login.submit"].isEnabled, "the password field had the keyboard")
    }

    func testAnUnreachableServerGetsACardWithDetailsAndTryAgain() {
        let app = launch(stub: "unreachable")
        fill(app)
        submit(app)
        XCTAssertTrue(element("login.error.card", in: app).appears(timeout: 10))
        XCTAssertTrue(app.staticTexts["Can't reach Home Assistant"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Check the server address")).firstMatch.exists)
        XCTAssertFalse(element("login.error.detail", in: app).exists, "the raw reason is behind Details")
        let details = element("login.error.details", in: app)
        XCTAssertTrue(details.exists)
        details.tap()
        XCTAssertTrue(element("login.error.detail", in: app).appears(timeout: 5), "Details shows the raw reason")
        XCTAssertTrue(app.buttons["login.submit"].label.contains("Try Again"))
        XCTAssertEqual(app.textFields["login.username"].value as? String, "alex", "the fields keep their values")
    }

    func testAnotherFailureGetsTheSignInDidntWorkCard() {
        let app = launch(stub: "failed")
        fill(app)
        submit(app)
        XCTAssertTrue(app.staticTexts["Sign-in didn't work"].appears(timeout: 10))
        XCTAssertTrue(element("login.error.details", in: app).exists)
    }

    func testTwoStepSignInIsExplainedNotOffered() {
        let app = launch(stub: "twostep")
        fill(app)
        submit(app)
        let message = element("login.error", in: app)
        XCTAssertTrue(message.appears(timeout: 10))
        XCTAssertTrue(message.label.contains("Two-step sign-in isn't supported"), message.label)
        XCTAssertFalse(app.textFields["login.code"].exists, "no code field")
    }

    /// While the request is out the button reads "Signing In…" and says it is busy; the fields are off.
    func testTheBusyStateShowsInTheButton() {
        let app = launch(stub: "slow")
        fill(app)
        submit(app)
        let button = app.buttons["login.submit"]
        let busy = NSPredicate(format: "label CONTAINS %@", "Signing In")
        expectation(for: busy, evaluatedWith: button)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(button.value as? String, "Signing In", "the arc is silent; the button says it is busy")
        XCTAssertFalse(app.textFields["login.username"].isEnabled, "the fields are off while it works")
    }

    // MARK: - Server field

    /// Types into the Server field the way a person does: tap, type (no Return, so the keyboard stays).
    private func typeServer(_ app: XCUIApplication, _ text: String) {
        let field = app.textFields["login.server"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "server field")
        field.tap()
        field.typeText(text)
    }

    /// The Server row is first, empty with its placeholder, a 52 pt target, and Sign In waits for it.
    func testTheServerRowIsFirstWithItsPlaceholderAndSignInWaitsForIt() {
        let app = launch(server: nil)
        let server = app.textFields["login.server"]
        XCTAssertTrue(server.appears(timeout: 10))
        XCTAssertEqual(server.label, "Server address", "VoiceOver reads the field as the server address")
        XCTAssertEqual(server.value as? String, "homeassistant.local:8123", "the placeholder reads when it is empty")
        assertTarget(server)
        XCTAssertGreaterThanOrEqual(server.frame.height, 51, "rows are 52 pt")
        XCTAssertLessThan(server.frame.minY, app.textFields["login.username"].frame.minY, "Server, then Username")
        XCTAssertLessThan(app.textFields["login.username"].frame.minY, app.secureTextFields["login.password"].frame.minY)
        app.textFields["login.username"].tap()
        app.textFields["login.username"].typeText("alex")
        app.typeText("\n")
        app.secureTextFields["login.password"].typeText("secret")
        XCTAssertFalse(app.buttons["login.submit"].isEnabled, "Sign In needs the server too")
    }

    /// A prefilled address shows as is; typing one and moving on shows it normalised, and Return runs Server, Username, Password.
    func testTheServerIsNormalisedWhenEditingEndsAndReturnMovesOn() {
        let app = launch(server: nil)
        typeServer(app, "Ha.Example.com/lovelace")
        app.typeText("\n")
        XCTAssertEqual(app.textFields["login.server"].value as? String, "https://ha.example.com", "scheme added, path dropped")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText("alex")
        XCTAssertEqual(app.textFields["login.username"].value as? String, "alex", "Return on the server moved to the username")
        app.typeText("\n")
        app.typeText("secret")
        XCTAssertTrue(app.buttons["login.submit"].isEnabled)
    }

    func testALocalAddressGetsHTTP() {
        let app = launch(server: nil)
        typeServer(app, "homeassistant.local:8123")
        app.typeText("\n")
        XCTAssertEqual(app.textFields["login.server"].value as? String, "http://homeassistant.local:8123")
    }

    /// An address that does not parse shows the plain line next to the field, keeps the text and the keyboard in the Server field.
    func testABadAddressIsSaidNextToTheFieldAndKeepsItsText() {
        let app = launch(server: nil)
        typeServer(app, "ha example")
        app.typeText("\n")
        let message = element("login.error", in: app)
        XCTAssertTrue(message.appears(timeout: 10), "the red line appears")
        XCTAssertTrue(message.label.contains("Enter the address you open Home Assistant with"), message.label)
        XCTAssertEqual(app.textFields["login.server"].value as? String, "ha example", "the text is kept")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "focus is back in the Server field")
        XCTAssertFalse(element("login.error.card", in: app).exists, "a bad address is a line, not a card")
    }

    /// An address that answers but is not Home Assistant: the line, the hairline, and no card.
    func testAnAddressThatIsNotHomeAssistantIsSaidPlainly() {
        let app = launch(stub: "nothomeassistant")
        fill(app)
        submit(app)
        let message = element("login.error", in: app)
        XCTAssertTrue(message.appears(timeout: 10))
        XCTAssertTrue(message.label.contains("Home Assistant didn't answer at that address"), message.label)
        XCTAssertEqual(app.textFields["login.server"].value as? String, Self.prefilledServer, "the address is kept")
        XCTAssertFalse(element("login.error.card", in: app).exists)
    }

    /// At AX5 the Server label sits above its field and Sign In stays reachable.
    func testAtTheLargestTextTheServerLabelSitsAboveItsField() {
        let app = launch(arguments: FentonHomeApp.ax5)
        let server = app.textFields["login.server"]
        XCTAssertTrue(server.appears(timeout: 10))
        XCTAssertLessThan(server.frame.maxY, app.textFields["login.username"].frame.minY + 1, "Server stays above Username")
        XCTAssertGreaterThanOrEqual(server.frame.height, 90, "the row grows to hold the label above the field")
        assertTarget(server)
    }

    func testTheServerRowPassesTheAudit() throws {
        let app = launch(server: nil)
        XCTAssertTrue(app.textFields["login.server"].appears(timeout: 10))
        try FentonHomeApp.audit(app, ax5Page: { self.launch(arguments: FentonHomeApp.ax5, server: nil) })
    }

    // MARK: - Session ended

    func testAnEndedSessionWelcomesTheAccountBackAndAsksForThePasswordAlone() {
        let app = launch(expired: "alex|Alex Morgan")
        XCTAssertTrue(element("login.title", in: app).appears(timeout: 10))
        XCTAssertTrue(element("login.title", in: app).label.contains("Welcome back, Alex"))
        XCTAssertFalse(app.textFields["login.username"].exists, "the account is shown, not asked for")
        let readonly = element("login.username.readonly", in: app)
        XCTAssertTrue(readonly.exists)
        XCTAssertTrue(readonly.label.contains("alex"))
        let serverRow = element("login.server.readonly", in: app)
        XCTAssertTrue(serverRow.exists, "the server is shown read-only too")
        XCTAssertEqual(serverRow.label, "Server, ha.example.com", "one element: the label and the host")
        XCTAssertFalse(app.textFields["login.server"].exists)
        XCTAssertTrue(app.secureTextFields["login.password"].exists)
        let different = app.buttons["login.differentAccount"]
        XCTAssertTrue(different.exists)
        assertTarget(different)
        different.tap()
        XCTAssertTrue(app.textFields["login.username"].appears(timeout: 5), "Use a Different Account asks for the username")
        XCTAssertEqual(app.textFields["login.server"].value as? String, Self.prefilledServer, "and keeps the server")
        XCTAssertEqual(element("login.title", in: app).label, "S and H")
    }

    func testTheWelcomeBackScreenPassesTheAudit() throws {
        let app = launch(expired: "alex|Alex Morgan")
        XCTAssertTrue(app.secureTextFields["login.password"].appears(timeout: 10))
        try FentonHomeApp.audit(app, ax5Page: { self.launch(expired: "alex|Alex Morgan", arguments: FentonHomeApp.ax5) })
    }

    // MARK: - Large text and motion

    /// At AX5 the labels sit above the fields, the form scrolls, and Sign In stays reachable.
    func testAtTheLargestTextTheFormScrollsAndSignInStaysReachable() throws {
        let app = launch(arguments: FentonHomeApp.ax5)
        XCTAssertTrue(app.textFields["login.username"].appears(timeout: 10))
        let button = app.buttons["login.submit"]
        for _ in 0..<6 where !(button.exists && button.isHittable) {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(button.isHittable, "Sign In is reachable by scrolling")
        // The labels sit above their fields, and the 44 pt targets hold at this size.
        XCTAssertGreaterThan(app.secureTextFields["login.password"].frame.minY, app.textFields["login.username"].frame.maxY - 1)
        assertTarget(button)
    }

    private func assertIntroEndsOnTheForm(settings: [FentonHomeApp.SystemSetting]) {
        let app = launch(intro: true, settings: settings)
        XCTAssertTrue(app.textFields["login.username"].appears(timeout: 10), "\(settings)")
        let deadline = Date().addingTimeInterval(4)
        while !app.buttons["login.submit"].isHittable, Date() < deadline { usleep(200_000) }
        XCTAssertTrue(element("login.footnote", in: app).exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "no keyboard comes up by itself")
        app.terminate()
    }

    /// The intro ends on the form.
    func testIntroEndsOnTheFormWithMotion() {
        assertIntroEndsOnTheForm(settings: [])
    }

    /// With Reduce Motion the intro is a cross-fade that ends on the form too.
    func testIntroEndsOnTheFormReduceMotion() {
        assertIntroEndsOnTheForm(settings: [.reduceMotion])
    }
}
