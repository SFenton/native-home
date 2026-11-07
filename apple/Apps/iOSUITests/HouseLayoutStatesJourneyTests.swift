import XCTest

/// The missing-layout states on Home and Security (`.agents/design/house-config-states.md`, rules 10 to 15), on iPhone, iPhone Duo
/// and iPad. The debug gallery forces a state with `FENTON_GALLERY_HOUSECONFIG` (and the role with `FENTON_HOUSECONFIG_ROLE`), so no
/// server is involved. Written in the migration tier and run in the end-of-migration pass.
@MainActor
final class HouseLayoutStatesJourneyTests: JourneyTestCase {
    private func launch(_ gallery: String, state: String, role: String? = nil, arguments: [String] = []) -> XCUIApplication {
        var environment = ["FENTON_GALLERY_HOUSECONFIG": state]
        if let role { environment["FENTON_HOUSECONFIG_ROLE"] = role }
        return FentonHomeApp.launchGallery(gallery, arguments: arguments, environment: environment)
    }

    // MARK: - Skeleton

    func testHomeShowsOneSkeletonElementWhileTheLayoutLoads() {
        let app = launch("home", state: "loading")
        let skeleton = element("home.skeleton", in: app)
        XCTAssertTrue(skeleton.appears(timeout: 20), "Home draws its skeleton")
        XCTAssertEqual(skeleton.label, "Getting your home from Home Assistant")
        XCTAssertFalse(app.buttons["home.chip.lights"].exists, "no content behind it is reachable")
        XCTAssertFalse(element("houseConfig.state", in: app).exists)
    }

    func testSecurityShowsTheGenericSkeletonWhileOffline() {
        let app = launch("security", state: "offline")
        let skeleton = element("page.skeleton", in: app)
        XCTAssertTrue(skeleton.appears(timeout: 20))
        XCTAssertEqual(skeleton.label, "Getting your home from Home Assistant")
    }

    func testTheSkeletonPassesTheAuditAtDefaultAndLargestTextSize() throws {
        let app = launch("home", state: "loading")
        XCTAssertTrue(element("home.skeleton", in: app).appears(timeout: 20))
        settleScreen()
        try FentonHomeApp.audit(app) {
            let large = self.launch("home", state: "loading", arguments: FentonHomeApp.ax5)
            XCTAssertTrue(self.element("home.skeleton", in: large).appears(timeout: 20))
            settleScreen()
            return large
        }
    }

    // MARK: - Messages

    private struct Case {
        let state: String
        let title: String
        let action: String?
    }

    private let cases = [
        Case(state: "missing", title: "Add the S+H Home Integration", action: "Open Integrations"),
        Case(state: "notconfigured", title: "Home Isn't Set Up Yet", action: "Open S+H Home Integration"),
        Case(state: "invalid", title: "Unable to Read the House Layout", action: "Open Repairs"),
        Case(state: "newer", title: "Update S+H", action: nil),
        Case(state: "timeout", title: "Unable to Load the House Layout", action: "Try Again"),
    ]

    func testAnAdministratorSeesEachMessageWithItsAction() {
        for item in cases {
            let app = launch("security", state: item.state, role: "admin")
            XCTAssertTrue(element("houseConfig.state", in: app).appears(timeout: 20), item.state)
            XCTAssertTrue(app.staticTexts[item.title].exists, "\(item.state): \(item.title)")
            let action = app.buttons["houseConfig.action"]
            if let title = item.action {
                XCTAssertTrue(action.appears(timeout: 5), "\(item.state): the action")
                XCTAssertEqual(action.label, title)
                XCTAssertGreaterThanOrEqual(action.frame.height, 50, "the 50 pt button")
            } else {
                XCTAssertFalse(action.exists, "\(item.state): a newer layout has no action")
            }
        }
    }

    func testAMemberSeesEachMessageWithoutAnActionExceptTryAgain() {
        for item in cases {
            let app = launch("security", state: item.state, role: "member")
            XCTAssertTrue(element("houseConfig.state", in: app).appears(timeout: 20), item.state)
            XCTAssertEqual(app.buttons["houseConfig.action"].exists, item.state == "timeout", "\(item.state): only Try Again is for everyone")
        }
    }

    func testTheMessageReadsHeadingThenButton() {
        let app = launch("home", state: "timeout", role: "member")
        XCTAssertTrue(element("houseConfig.state", in: app).appears(timeout: 20))
        let heading = app.staticTexts["Unable to Load the House Layout"]
        let action = app.buttons["houseConfig.action"]
        XCTAssertTrue(heading.exists && action.exists)
        XCTAssertLessThan(heading.frame.minY, action.frame.minY, "the heading comes before the button")
        XCTAssertGreaterThanOrEqual(action.frame.height, 50)
    }

    func testTryAgainShowsTheBusyTitle() {
        let app = launch("security", state: "timeout", role: "member")
        let action = app.buttons["houseConfig.action"]
        XCTAssertTrue(action.appears(timeout: 20))
        action.tap()
        XCTAssertTrue(action.wait(for: \.label, toEqual: "Trying Again", timeout: 10), "the button says Trying Again while it asks")
    }

    func testTheMessageScrollsAtTheLargestTextSizeAndPassesTheAudit() throws {
        let app = launch("home", state: "missing", role: "admin")
        XCTAssertTrue(element("houseConfig.state", in: app).appears(timeout: 20))
        settleScreen()
        try FentonHomeApp.audit(app) {
            let large = self.launch("home", state: "missing", role: "admin", arguments: FentonHomeApp.ax5)
            XCTAssertTrue(self.element("houseConfig.state", in: large).appears(timeout: 20))
            settleScreen()
            let action = large.buttons["houseConfig.action"]
            if !action.isHittable { large.swipeUp() }
            XCTAssertTrue(action.exists, "the action is reachable by scrolling")
            return large
        }
    }

    // MARK: - A saved layout and a missing entity

    func testASavedLayoutShowsThePageUnchangedWhateverTheServerSays() {
        let app = launch("security", state: "cached-missing")
        XCTAssertTrue(element("security.system.state", in: app).appears(timeout: 20), "the page is drawn from the saved copy")
        XCTAssertFalse(element("houseConfig.state", in: app).exists)
        XCTAssertFalse(element("page.skeleton", in: app).exists)
    }

    // MARK: - The action, signed in

    func testTheActionOpensTheHomeAssistantModalWithThePagePushed() throws {
        let app = try FentonHomeApp.launchSignedIn(environment: ["FENTON_GALLERY_HOUSECONFIG": "missing", "FENTON_HOUSECONFIG_ROLE": "admin"])
        let action = app.buttons["houseConfig.action"]
        XCTAssertTrue(action.appears(timeout: 20), "the message offers Open Integrations")
        action.tap()
        XCTAssertTrue(app.buttons["haSettings.done"].appears(timeout: 15), "the Home Assistant modal opens")
        let page = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'haWeb.'")).firstMatch
        XCTAssertTrue(page.appears(timeout: 15), "with Integrations already pushed")
    }
}
