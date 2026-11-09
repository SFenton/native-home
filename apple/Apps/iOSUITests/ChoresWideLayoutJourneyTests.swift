import XCTest

/// The Chores pages in a wide window (area J of the Chores split): where `SplitPolicy` allows a split (iPad landscape, the unfolded
/// iPhone Duo in landscape) a task opens in the trailing detail pane instead of a sheet, and a draft typed there survives the window
/// turning single-page. Rules: `.agents/design/apple/split-view.md`; the draft hand-over is `TodoDraftStore` and
/// `TodoPageLayout.presentation(open:split:)`.
@MainActor
final class ChoresWideLayoutJourneyTests: ChoresJourneyTestCase {
    /// The trailing pane, which exists only while the window splits.
    private func pane(in app: XCUIApplication) -> XCUIElement { element("todo.pane", in: app) }

    /// Whether this window may split: iPad, and the Duo only unfolded in landscape (951 pt wide; folded it is single-page).
    private func windowSplits(_ app: XCUIApplication) -> Bool {
        let window = app.windows.firstMatch.frame
        switch FentonHomeApp.family {
        case .iPhone: return false
        case .iPad: return window.width > window.height
        case .iPhoneDuo: return window.width > window.height && window.width >= 900
        }
    }

    /// Opening a task in a split window shows it in the detail pane, not a sheet; its name is editable there, and when the window
    /// turns single-page (iPad rotated to portrait) the same form opens as a sheet with the same text. The unfolded Duo cannot be
    /// rotated by the runner (devices.md), so it checks the pane only; a folded Duo checks that no pane opens.
    func testATaskOpensInTheDetailPaneAndItsDraftSurvivesRotation() throws {
        try XCTSkipIf(FentonHomeApp.family == .iPhone, "iPhone is portrait-only and never splits (split-view.md)")
        if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .landscapeLeft }
        let app = launch()
        let splits = windowSplits(app)
        let edit = reveal(element("todo.edit.12--fixture", in: app), in: app)
        XCTAssertTrue(edit.appears(timeout: 5), "The Past Due row's pencil is missing")

        guard splits else {
            // Folded Duo: single-page, so the task opens as a sheet and no pane exists.
            edit.tap()
            XCTAssertTrue(app.textFields["task.name"].appears(timeout: 5), "The task did not open")
            XCTAssertFalse(pane(in: app).exists, "A single-page window opened a detail pane")
            return
        }

        // The pane shows its prompt until a row is picked.
        XCTAssertTrue(element("todo.pane.placeholder", in: app).appears(timeout: 5), "No prompt in the empty detail pane")
        edit.tap()
        let name = app.textFields["task.name"]
        XCTAssertTrue(name.appears(timeout: 5), "The task did not open")
        XCTAssertTrue(pane(in: app).exists, "The task did not open in the detail pane")
        XCTAssertFalse(element("todo.pane.placeholder", in: app).exists, "The prompt stays over the open form")
        XCTAssertTrue(name.frame.minX >= app.windows.firstMatch.frame.midX - 16, "The form is not in the trailing half: \(name.frame)")
        let original = name.value as? String ?? ""
        XCTAssertFalse(original.isEmpty, "The task did not load into the pane")
        name.tap()
        name.typeText("!")
        XCTAssertTrue(app.buttons["task.save"].wait(for: \.isEnabled, toEqual: true, timeout: 5), "The edit did not enable Save")
        keepScreenshot(app, screenshotName("chores-detail-pane"))

        // Turn single-page: the form moves to a sheet with its draft.
        guard FentonHomeApp.family == .iPad else { return }
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(pane(in: app).disappears(timeout: 10), "The detail pane stays in a single-page window")
        let sheetName = app.textFields["task.name"]
        XCTAssertTrue(sheetName.appears(timeout: 10), "The form was lost when the window turned single-page")
        XCTAssertEqual(sheetName.value as? String, original + "!", "The draft did not survive the rotation")
        XCTAssertTrue(app.buttons["task.save"].isEnabled, "The draft's edit no longer enables Save")
        keepScreenshot(app, screenshotName("chores-detail-sheet"))
    }
}
