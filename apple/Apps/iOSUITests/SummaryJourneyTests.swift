import XCTest

/// The Your Summary sheet (the header Profile button) on fixtures in the debug gallery: four tabs with badges, the Chores
/// page's rows with their edit button and swipe actions, the Food page's rows, the empty and Vacation Mode states, and
/// the accessibility rules (names, reading order, 44 pt targets, AX5). No house is touched: every change lands on the
/// gallery's fixture services. Spec: `.agents/pages/settings/profile.md`.
@MainActor
final class SummaryJourneyTests: JourneyTestCase {
    // MARK: Helpers

    private func launch(tab: SummaryTabID? = nil, viewer: String? = nil, vacation: Bool = false, empty: Bool = false,
                        clean: Bool = false, photos: Bool = false, arguments: [String] = [], appearance: String? = nil) -> XCUIApplication {
        var environment: [String: String] = clean ? ["FENTON_GALLERY_CLEAN": "1"] : [:]
        if let tab { environment["FENTON_GALLERY_TAB"] = tab.rawValue }
        if let viewer { environment["FENTON_GALLERY_VIEWER"] = viewer }
        if vacation { environment["FENTON_GALLERY_VACATION"] = "1" }
        if empty { environment["FENTON_GALLERY_EMPTY"] = "1" }
        if photos { environment["FENTON_GALLERY_PHOTOS"] = "1" }
        // Through `startApp`: with reuse on the class keeps one resident app, reset per test (`app-reuse.md`). The gallery builds its
        // fixtures and recording service per gallery; AX5 (arguments) and the pinned light appearance are their own launch signatures.
        let configured = FentonHomeApp.makeApp()
        configured.launchEnvironment["FENTON_GALLERY"] = "profile"
        configured.launchEnvironment.merge(environment) { _, new in new }
        if let appearance { configured.launchEnvironment["FENTON_APPEARANCE"] = appearance }
        configured.launchArguments += arguments
        let app = startApp(configured)
        XCTAssertTrue(app.buttons["account.close"].appears(timeout: 15), "The Summary sheet did not open")
        return app
    }

    /// A tab's segment, or nil at accessibility sizes where the bar is a menu.
    private func segment(_ tab: SummaryTabID, in app: XCUIApplication) -> XCUIElement { app.buttons["summary.tabs.\(tab.rawValue)"] }

    /// Every node of the app's tree by identifier, from one snapshot (instead of a lookup per element).
    private func tree(_ app: XCUIApplication) throws -> [String: any XCUIElementSnapshot] {
        var nodes: [String: any XCUIElementSnapshot] = [:]
        func collect(_ node: any XCUIElementSnapshot) {
            if !node.identifier.isEmpty, nodes[node.identifier] == nil { nodes[node.identifier] = node }
            node.children.forEach(collect)
        }
        collect(try app.snapshot())
        return nodes
    }

    private func screenshotName(_ name: String) -> String { "summary-\(name)-\(layout)" }

    /// Drags a row part of the way, which opens that edge's swipe actions without performing the full swipe.
    private func reveal(_ row: XCUIElement, from: CGFloat, to: CGFloat) {
        row.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.5)))
    }

    // MARK: Tabs and badges

    /// The sheet opens on Profile for everyone (owner, 2026-11-01); the tabs are named for VoiceOver with their counts, are 44 pt targets, and each
    /// shows its content. One test per tab (`testSummary<Step>`), each entering that tab directly.
    func testSummaryOpensOnOverdue() throws {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Your Summary"].appears(timeout: 5), "The title reads Your Summary for a resident")
        let overdue = segment(.overdue, in: app)
        XCTAssertTrue(overdue.appears(timeout: 5), "No Overdue Chores tab")
        // One snapshot answers every label, selection and size below (it was about 20 lookups).
        let nodes = try tree(app)
        func tab(_ tab: SummaryTabID) -> any XCUIElementSnapshot { nodes["summary.tabs.\(tab.rawValue)"]! }
        XCTAssertEqual(tab(.overdue).label, "Overdue Chores, 2 items")
        XCTAssertEqual(tab(.expiredFood).label, "Expired Food, 6 items")
        XCTAssertEqual(tab(.upcoming).label, "Upcoming Chores", "Upcoming chores never badge")
        XCTAssertEqual(tab(.profile).label, "Profile")
        XCTAssertTrue(tab(.profile).isSelected, "It opens on Profile (owner, 2026-11-01)")
        for id in SummaryTabID.allCases {
            XCTAssertGreaterThanOrEqual(tab(id).frame.width, 43, tab(id).label)
            XCTAssertGreaterThanOrEqual(tab(id).frame.height, 43, tab(id).label)
        }
        overdue.tap()
        XCTAssertTrue(overdue.isSelected)
        XCTAssertTrue(element("todo.item.11--fixture", in: app).appears(timeout: 5), "Overdue chores listed")
        XCTAssertTrue(app.staticTexts["Overdue Chores"].exists, "Its section header")
        keepScreenshot(app, screenshotName("overdue"))
    }

    func testSummaryUpcomingTab() {
        let app = launch()
        segment(.upcoming, in: app).tap()
        XCTAssertTrue(element("todo.item.13--fixture", in: app).appears(timeout: 5), "Chores due today")
        XCTAssertTrue(app.staticTexts["Upcoming Chores"].exists && app.staticTexts["No Due Date"].exists, "Two sections, each with its header")
        XCTAssertTrue(segment(.upcoming, in: app).isSelected)
        keepScreenshot(app, screenshotName("upcoming"))
    }

    func testSummaryExpiredFoodTab() {
        let app = launch()
        segment(.expiredFood, in: app).tap()
        XCTAssertTrue(element("inventory.row.Cereal", in: app).appears(timeout: 8), "Expired food listed")
        keepScreenshot(app, screenshotName("expired"))
    }

    func testSummaryProfileTab() {
        let app = launch()
        segment(.profile, in: app).tap()
        XCTAssertTrue(element("account.header", in: app).appears(timeout: 5), "The account header")
        XCTAssertTrue(app.staticTexts["People at Home"].exists)
        XCTAssertTrue(app.buttons["account.signOut"].exists)
        keepScreenshot(app, screenshotName("profile"))
    }

    /// Profile keeps the account's extras: who is signed in, who is home (a monogram per person, Home or Away), and Sign
    /// Out behind a confirmation that is cancelled here.
    func testProfileHoldsTheAccountPeopleAndSignOut() {
        let app = launch(tab: .profile)
        let header = element("account.header", in: app)
        XCTAssertTrue(header.appears(timeout: 5))
        XCTAssertTrue(header.label.contains(expectations[.personFirstFullName]), header.label)
        XCTAssertTrue(app.staticTexts["People at Home"].exists)
        // A person's row is one element reading name and state (SwiftUI combined children; so does the UIKit row).
        XCTAssertTrue(element("profile.person.\(expectations[.personFirstEntity])", in: app).label == "\(expectations[.personFirstFullName]), Home"
                      && element("profile.person.\(expectations[.personSecondEntity])", in: app).label == "\(expectations[.personSecondFullName]), Away")
        let signOut = app.buttons["account.signOut"]
        let list = element("account.list", in: app)
        // Clear of the tab bar, which XCUITest still counts as hittable under it. One tree snapshot answers both frames per swipe.
        let clear = {
            guard let nodes = try? self.tree(app), let button = nodes["account.signOut"], let bar = nodes["summary.tabs"] else { return false }
            return !button.frame.isEmpty && button.frame.maxY <= bar.frame.minY && signOut.isHittable
        }
        for _ in 0..<8 where !clear() { list.swipeUp() }
        XCTAssertTrue(signOut.exists)
        assertTarget(signOut)
        signOut.tap()
        XCTAssertTrue(app.alerts["Sign Out of Home Assistant?"].appears(timeout: 5), "Sign Out confirms first")
        app.alerts.buttons["account.signOut.cancel"].firstMatch.tapUntilAlertCloses(in: app)
        XCTAssertTrue(app.alerts.firstMatch.disappears(timeout: 3))
        XCTAssertTrue(signOut.exists, "Cancelling keeps the sheet and the session")
    }

    // MARK: Photos

    /// Scrolls the Profile tab until `target` is on screen.
    private func scrollTo(_ id: String, in app: XCUIApplication) {
        let target = element(id, in: app)
        let list = element("account.list", in: app)
        // On a short sheet (AX5 on iPad) XCUITest still calls a row under the tab bar hittable: it must be wholly clear of it.
        // One tree snapshot answers the three frames; `isHittable` (a live read) is asked only once the frames say it is clear.
        let clear = {
            guard let nodes = try? self.tree(app), let row = nodes[id], let bar = nodes["summary.tabs"],
                  let area = nodes["account.list"] else { return false }
            return !row.frame.isEmpty && row.frame.maxY <= bar.frame.minY && row.frame.minY >= area.frame.minY && target.isHittable
        }
        for _ in 0..<14 where !clear() { list.swipeUp() }
    }

    /// The photo pixels in the leading part of a People row, where its 36 pt avatar is.
    private func rowPhoto(_ row: XCUIElement, in app: XCUIApplication) -> Int {
        let frame = row.frame
        return AvatarPixels.photoPixels(in: frame, of: app)
    }

    /// Alex and Sam have photos on the Account header (Alex is signed in) and on their People rows; the guest keeps
    /// initials. Every label and identifier reads as it does without photos, and the row is a 44 pt target.
    func testProfileShowsPhotosOnTheHeaderAndPeopleRows() {
        let app = launch(tab: .profile, photos: true)
        let header = element("account.header", in: app)
        XCTAssertTrue(header.appears(timeout: 5))
        XCTAssertTrue(header.label.contains(expectations[.personFirstFullName]), header.label)
        XCTAssertGreaterThanOrEqual(AvatarPixels.photoPixels(in: header.frame, of: app), AvatarPixels.photoThreshold, "No photo on the Account header")
        let firstRow = element("profile.person.\(expectations[.personFirstEntity])", in: app)
        scrollTo("profile.person.\(expectations[.personFirstEntity])", in: app)
        XCTAssertEqual(firstRow.label, "\(expectations[.personFirstFullName]), Home")
        assertTarget(firstRow)
        XCTAssertGreaterThanOrEqual(rowPhoto(firstRow, in: app), AvatarPixels.photoThreshold, "No photo on Alex's row")
        let secondRow = element("profile.person.\(expectations[.personSecondEntity])", in: app)
        scrollTo("profile.person.\(expectations[.personSecondEntity])", in: app)
        XCTAssertEqual(secondRow.label, "\(expectations[.personSecondFullName]), Away")
        XCTAssertGreaterThanOrEqual(rowPhoto(secondRow, in: app), AvatarPixels.photoThreshold, "No photo on Sam's row")
        let guest = element("profile.person.person.demo_guest", in: app)
        scrollTo("profile.person.person.demo_guest", in: app)
        XCTAssertEqual(guest.label, "Guest, Home")
        XCTAssertLessThan(rowPhoto(guest, in: app), AvatarPixels.photoThreshold, "The guest has no photo")
        keepScreenshot(app, screenshotName("profile-photos"))
    }

    /// With no photos (never synced, or after sign-out) the header and rows draw initials: the state a person is left in once
    /// sign-out has deleted the photos (the wipe itself is unit tested; the gallery cannot sign out).
    func testProfileWithoutPhotosDrawsInitials() {
        let app = launch(tab: .profile)
        let header = element("account.header", in: app)
        XCTAssertTrue(header.appears(timeout: 5))
        XCTAssertLessThan(AvatarPixels.photoPixels(in: header.frame, of: app), AvatarPixels.photoThreshold)
        let firstRow = element("profile.person.\(expectations[.personFirstEntity])", in: app)
        scrollTo("profile.person.\(expectations[.personFirstEntity])", in: app)
        XCTAssertLessThan(rowPhoto(firstRow, in: app), AvatarPixels.photoThreshold)
    }

    /// At AX5 the photos scale with the text (header and rows); names and rows still read and stay 44 pt targets.
    func testProfilePhotosAtAX5() {
        let app = launch(tab: .profile, photos: true, arguments: FentonHomeApp.ax5)
        let header = element("account.header", in: app)
        XCTAssertTrue(header.appears(timeout: 8))
        XCTAssertTrue(header.label.contains(expectations[.personFirstFullName]), header.label)
        XCTAssertGreaterThanOrEqual(AvatarPixels.photoPixels(in: header.frame, of: app), AvatarPixels.photoThreshold)
        let firstRow = element("profile.person.\(expectations[.personFirstEntity])", in: app)
        scrollTo("profile.person.\(expectations[.personFirstEntity])", in: app)
        keepScreenshot(app, screenshotName("profile-photos-ax5"))
        XCTAssertEqual(firstRow.label, "\(expectations[.personFirstFullName]), Home")
        assertTarget(firstRow)
        XCTAssertGreaterThanOrEqual(rowPhoto(firstRow, in: app), AvatarPixels.photoThreshold, "row frame \(firstRow.frame)")
    }

    // MARK: Chores

    /// The rows are the Chores page's own: a check, the due label and an edit button that opens the task form.
    func testChoreRowsCarryTheEditButtonThatOpensTheTaskForm() {
        let app = launch(tab: .overdue)
        let row = element("todo.item.11--fixture", in: app)
        XCTAssertTrue(row.appears(timeout: 5))
        XCTAssertEqual(row.label, "Take out the recycling")
        XCTAssertTrue((row.value as? String)?.hasPrefix("Not done") == true, "\(row.value ?? "")")
        let edit = app.buttons["todo.edit.11--fixture"]
        XCTAssertTrue(edit.exists)
        XCTAssertEqual(edit.label, "Edit Take out the recycling")
        assertTarget(edit)
        edit.tap()
        let name = app.textFields["task.name"]
        XCTAssertTrue(name.appears(timeout: 8), "The edit button opens the Chores page's task form")
        XCTAssertEqual(name.value as? String, "Take out the recycling")
        app.buttons["task.cancel"].tap()
        XCTAssertTrue(name.disappears(timeout: 5))
        XCTAssertTrue(row.exists, "The Summary is still under the form")
    }

    /// The swipe actions are the Chores page's: Complete from the leading edge; Delete and Edit from the trailing edge.
    func testChoreRowsSwipeToCompleteEditAndDelete() {
        let app = launch(tab: .overdue)
        let row = element("todo.item.11--fixture", in: app)
        XCTAssertTrue(row.appears(timeout: 5))
        reveal(row, from: 0.15, to: 0.55)
        XCTAssertTrue(app.buttons["todo.swipe.complete.11--fixture"].appears(timeout: 3), "Complete swipes in from the leading edge")
        reveal(row, from: 0.55, to: 0.1)
        reveal(row, from: 0.85, to: 0.35)
        XCTAssertTrue(app.buttons["todo.swipe.edit.11--fixture"].appears(timeout: 3), "Edit swipes in from the trailing edge")
        XCTAssertTrue(app.buttons["todo.swipe.delete.11--fixture"].exists, "So does Delete")
        keepScreenshot(app, screenshotName("overdue-swipe"))
        app.buttons["todo.swipe.edit.11--fixture"].tap()
        XCTAssertTrue(app.textFields["task.name"].appears(timeout: 8), "The Edit swipe opens the same form")
    }

    /// Checking a chore off keeps it with Undo for 5 s, then hides it and calls the (fixture) service, as on the Chores page.
    func testCheckingAChoreOffHidesItAndRecordsTheCall() {
        let app = launch(tab: .overdue)
        let row = element("todo.item.12--fixture", in: app)
        XCTAssertTrue(row.appears(timeout: 5))
        row.tap()
        XCTAssertTrue(element("todo.undo.12--fixture", in: app).appears(timeout: 3), "The tick offers Undo")
        XCTAssertTrue(row.disappears(timeout: 10), "A completed chore leaves the list after the undo grace")
        expectLastCall("todo.update_item 12--fixture", in: app)
        XCTAssertEqual(segment(.overdue, in: app).label, "Overdue Chores, 1 item", "The tab's badge follows, and is singular for one")
    }

    /// Deleting asks first, through the Chores page's dialog, and nothing is sent until it is confirmed.
    func testDeletingAChoreAsksFirst() {
        let app = launch(tab: .overdue)
        let row = element("todo.item.12--fixture", in: app)
        XCTAssertTrue(row.appears(timeout: 5))
        reveal(row, from: 0.85, to: 0.35)
        let delete = app.buttons["todo.swipe.delete.12--fixture"]
        XCTAssertTrue(delete.appears(timeout: 3))
        delete.tap()
        let confirm = app.buttons["todo.delete.confirm"].firstMatch
        XCTAssertTrue(confirm.appears(timeout: 5), "Delete confirms first")
        XCTAssertEqual(confirm.label, "Delete Task")
        XCTAssertNotEqual(lastCall(in: app), "todo.remove_item 12--fixture", "Deleted before the answer")
        XCTAssertTrue(row.exists)
        // Confirming removes it from the fixture list, never from a house.
        confirm.tap()
        XCTAssertTrue(row.disappears(timeout: 5))
        expectLastCall("todo.remove_item 12--fixture", in: app)
    }

    // MARK: Expired food

    /// The rows are the Food page's own, soonest expiry first: name, the red "Expired" line, the stock count above one,
    /// the add-to-Groceries cart and a chevron into the item editor.
    func testExpiredFoodRowsAreTheFoodPagesRows() {
        let app = launch(tab: .expiredFood)
        let cereal = element("inventory.row.Cereal", in: app)
        XCTAssertTrue(cereal.appears(timeout: 8))
        let rice = element("inventory.row.Jasmine Rice", in: app)
        let yogurt = element("inventory.row.Greek Yogurt", in: app)
        XCTAssertTrue(rice.exists && yogurt.exists)
        XCTAssertLessThan(cereal.frame.minY, rice.frame.minY, "The oldest expiry leads")
        XCTAssertLessThan(rice.frame.minY, yogurt.frame.minY)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Cereal, Quantity 2, Expired'")).firstMatch.exists,
                      "The stock count, then the expiry line")
        let cart = app.buttons["Add Cereal to shopping list"]
        let chevron = app.buttons["Edit Cereal"]
        XCTAssertTrue(cart.exists && chevron.exists)
        assertTarget(cart)
        assertTarget(chevron)
        keepScreenshot(app, screenshotName("expired-rows"))

        // The cart asks how many; cancelling adds nothing.
        cart.tap()
        XCTAssertTrue(app.alerts["Add Cereal to Groceries"].appears(timeout: 5), "The cart asks for a quantity")
        // A tap on an alert's button is sometimes lost while it settles; tap again until it closes.
        app.alerts.buttons["Cancel"].tapUntilAlertCloses(in: app)
        XCTAssertTrue(app.alerts["Add Cereal to Groceries"].disappears(timeout: 10), "Cancel closes the prompt")

        // The chevron opens the Food page's item editor.
        chevron.tap()
        XCTAssertTrue(element("inventory.editor", in: app).appears(timeout: 8), "The chevron opens the item editor")
        keepScreenshot(app, screenshotName("expired-editor"))
    }

    // MARK: Empty and vacation

    func testEmptyTabsSayTheWebsWords() {
        let app = launch(tab: .overdue, empty: true)
        XCTAssertTrue(element("summary.empty.overdue", in: app).appears(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Chores Due"].exists)
        XCTAssertTrue(app.staticTexts["You are all caught up on chores that slipped past their due date."].exists)
        XCTAssertEqual(segment(.overdue, in: app).label, "Overdue Chores", "No count when nothing is overdue")
        // Centred between the sheet's title and its tab bar, not a row under the title.
        let message = element("summary.empty.overdue", in: app)
        let top = app.staticTexts["Your Summary"].frame.maxY, bottom = element("summary.tabs", in: app).frame.minY
        XCTAssertEqual(message.frame.midY, (top + bottom) / 2, accuracy: 40, "Centred between the title and the tab bar")
        keepScreenshot(app, screenshotName("overdue-empty"))
        segment(.upcoming, in: app).tap()
        XCTAssertTrue(app.staticTexts["No Chores Upcoming"].appears(timeout: 5))
        XCTAssertTrue(app.staticTexts["There is nothing else on your schedule for the rest of today."].exists)
        segment(.expiredFood, in: app).tap()
        XCTAssertTrue(app.staticTexts["No Expired Food"].appears(timeout: 5))
        XCTAssertTrue(app.staticTexts["Everything in the kitchen is still within date."].exists)
        keepScreenshot(app, screenshotName("expired-empty"))
    }

    func testSummaryVacationEmptyTabs() {
        let app = launch(tab: .overdue, vacation: true, empty: true)
        XCTAssertTrue(app.staticTexts["Enjoy vacation!"].appears(timeout: 5), "An empty chore tab")
        segment(.upcoming, in: app).tap()
        XCTAssertTrue(app.staticTexts["Enjoy vacation!"].appears(timeout: 5))
        segment(.expiredFood, in: app).tap()
        XCTAssertTrue(app.staticTexts["No Expired Food"].appears(timeout: 5), "A confirmed zero stays 'No Expired Food'")
        XCTAssertTrue(app.staticTexts["Enjoy vacation!"].exists)
        keepScreenshot(app, screenshotName("expired-vacation-none"))
    }

    func testSummaryVacationExpiredFoodHidden() {
        let busy = launch(tab: .expiredFood, vacation: true)
        XCTAssertTrue(busy.staticTexts["Expired Food Hidden"].appears(timeout: 5), "Vacation hides a list that has items")
        XCTAssertTrue(busy.staticTexts["Enjoy vacation!"].exists)
        XCTAssertEqual(segment(.expiredFood, in: busy).label, "Expired Food", "Vacation puts the badge on hold")
        XCTAssertFalse(element("inventory.row.Cereal", in: busy).exists)
        keepScreenshot(busy, screenshotName("expired-vacation"))
    }

    /// Someone who is not a resident has no personal chores: the title reads Summary, with Profile and Expired Food.
    func testAGuestSeesSummaryWithProfileAndExpiredFoodOnly() {
        let app = launch(viewer: "guest")
        XCTAssertTrue(app.navigationBars["Summary"].appears(timeout: 5))
        XCTAssertFalse(app.navigationBars["Your Summary"].exists)
        XCTAssertTrue(segment(.profile, in: app).exists && segment(.expiredFood, in: app).exists)
        XCTAssertFalse(segment(.overdue, in: app).exists || segment(.upcoming, in: app).exists)
        XCTAssertTrue(segment(.profile, in: app).isSelected, "It opens on Profile (owner, 2026-11-01)")
        segment(.expiredFood, in: app).tap()
        XCTAssertTrue(element("inventory.row.Cereal", in: app).appears(timeout: 8), "Expired Food lists the rows")
        keepScreenshot(app, screenshotName("guest"))
    }

    // MARK: Accessibility

    /// Reading order is the close button and title, then the tab's content, then the tab bar last; targets are 44 pt and every tab passes the
    /// accessibility audit.
    private func auditAndReadInOrder(_ tab: SummaryTabID) throws {
        let app = launch(tab: tab)
        let content: String = switch tab {
        case .profile: "account.header"
        case .overdue: "todo.item.11--fixture"
        case .upcoming: "todo.item.13--fixture"
        case .expiredFood: "inventory.row.Cereal"
        }
        XCTAssertTrue(element(content, in: app).appears(timeout: 8), "\(tab) content")
        settleScreen()
        let close = element("account.close", in: app), bar = element("summary.tabs", in: app)
        XCTAssertLessThan(close.frame.minY, bar.frame.minY, "\(tab): the close button is above the tab bar")
        XCTAssertLessThan(element(content, in: app).frame.minY, bar.frame.minY, "\(tab): the tab bar is last, along the bottom")
        keepScreenshot(app, screenshotName("audit-\(tab.rawValue)"))
        try FentonHomeApp.audit(app) { self.launch(tab: tab, arguments: FentonHomeApp.ax5) }
    }

    func testSummaryProfilePassesAuditAndReadsInOrder() throws { try auditAndReadInOrder(.profile) }
    func testSummaryOverduePassesAuditAndReadsInOrder() throws { try auditAndReadInOrder(.overdue) }
    func testSummaryUpcomingPassesAuditAndReadsInOrder() throws { try auditAndReadInOrder(.upcoming) }
    func testSummaryExpiredFoodPassesAuditAndReadsInOrder() throws { try auditAndReadInOrder(.expiredFood) }

    /// At accessibility text sizes the bar is a menu that names the selected section and lists every tab with its count.
    func testAtAX5TheTabBarIsAMenuWithCounts() {
        let app = launch(tab: .overdue, arguments: FentonHomeApp.ax5)
        let menu = app.buttons["summary.tabs"]
        XCTAssertTrue(menu.appears(timeout: 8), "At AX5 the bar is a menu")
        XCTAssertGreaterThanOrEqual(menu.frame.height, 43)
        keepScreenshot(app, screenshotName("ax5-overdue"))
        menu.tap()
        keepScreenshot(app, screenshotName("ax5-menu"))
        let items = ["Profile", "Overdue Chores, 2 items", "Upcoming Chores", "Expired Food, 6 items"]
        for item in items {
            // At AX5 the system menu is taller than the screen and scrolls; bring a clipped item into view first.
            var scrolls = 0
            while !app.buttons[item].exists, scrolls < 6 {
                app.buttons["Profile"].exists ? app.buttons["Profile"].swipeDown() : app.buttons["Overdue Chores, 2 items"].swipeUp()
                scrolls += 1
            }
            XCTAssertTrue(app.buttons[item].appears(timeout: 5), "No '\(item)' in the menu; buttons: \(app.buttons.allElementsBoundByIndex.map(\.label))")
        }
        keepScreenshot(app, screenshotName("ax5-menu"))
        app.buttons["Upcoming Chores"].tap()
        XCTAssertTrue(element("todo.item.13--fixture", in: app).appears(timeout: 8), "Choosing a tab shows it")
    }

    /// Rows and the bar read in a light sheet too (the sheet follows the system appearance; the row cards are the sheet's cell).
    private func readInALightSheet(_ tab: SummaryTabID) throws {
        let app = launch(tab: tab, clean: true, appearance: "light")
        XCTAssertTrue(element(tab == .overdue ? "todo.item.11--fixture" : "inventory.row.Cereal", in: app).appears(timeout: 8))
        settleScreen()
        keepScreenshot(app, screenshotName("light-\(tab.rawValue)"))
        try FentonHomeApp.audit(app)
    }

    func testSummaryOverdueRowsReadInALightSheet() throws { try readInALightSheet(.overdue) }
    func testSummaryExpiredFoodRowsReadInALightSheet() throws { try readInALightSheet(.expiredFood) }
}

private extension XCUIElement {
    /// Taps an alert's button, then taps again (up to three taps) until the alert has closed: a tap that lands while an alert is
    /// still settling is dropped on a loaded host.
    func tapUntilAlertCloses(in app: XCUIApplication) {
        for _ in 0..<3 {
            tap()
            let deadline = Date().addingTimeInterval(8)
            while Date() < deadline {
                if !app.alerts.firstMatch.exists { return }
                usleep(250_000)
            }
            guard exists, isHittable else { return }
        }
    }
}
