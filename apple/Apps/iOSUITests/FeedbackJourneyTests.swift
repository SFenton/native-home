import XCTest

/// Settings → Feedback: Report an Issue and Request a Feature against the in-app fixture
/// (`FENTON_FEEDBACK_FIXTURE`), so no journey reaches Home Assistant's relay or files a real GitHub issue. Audits
/// run on every form and the setup notice, with an AX5 relaunch.
@MainActor
final class FeedbackJourneyTests: JourneyTestCase {
    /// Open (app side): in the live house XCUITest's idle wait times out at 60 s on many actions in this form (tapping or typing
    /// in a focused field, Submit, a scroll, the alerts' buttons), so the typing, filing and setup-notice tests run 210 to 340 s.
    /// The runner's 300 s default is too short for them; the plan's 900 s maximum still bounds them.
    override func setUp() {
        super.setUp()
        executionTimeAllowance = 600
    }

    // MARK: - Helpers

    /// Signs in with the feedback fixture: `1` with the relay set up, `unavailable` without it.
    ///
    /// `prefill` starts the form with a title (after its prefix) and the sample description already in the draft, for the tests
    /// that are not about typing: in the live house every action on a focused field waits out XCUITest's 60 s
    /// animations-idle timeout (five of them took 300 of `testCaptureFeedbackBugFilled`'s 366 s), so typing is kept to the one
    /// test that is about it.
    private func launch(fixture: String = "1", arguments: [String] = [], prefill: String? = nil) throws -> XCUIApplication {
        var environment = ["FENTON_FEEDBACK_FIXTURE": fixture]
        if let prefill {
            environment["FENTON_FEEDBACK_PREFILL_TITLE"] = prefill
            environment["FENTON_FEEDBACK_PREFILL_DESCRIPTION"] = Self.sampleDescription
        }
        return try FentonHomeApp.launchSignedIn(arguments: arguments, environment: environment)
    }

    private static let sampleDescription = "The garage tile stays on Opening."

    /// Goes to Settings, the last tab (owner, 2026-10-16).
    private func goToSettings(_ app: XCUIApplication) {
        app.openAccountSettings()
    }

    /// The open form's list: the Settings tab behind the sheet stays in the hierarchy, so `settingsList` would scroll that.
    private func formList(_ app: XCUIApplication) -> XCUIElement {
        // The list that holds the form's own Submit: another collection view can sit first in the hierarchy behind the sheet.
        let form = app.collectionViews.containing(.button, identifier: "feedback.submit").firstMatch
        if form.exists { return form }
        return app.collectionViews.matching(NSPredicate(format: "identifier != 'settings.list'")).firstMatch
    }

    /// The feedback row for `kind`, scrolled into view: it ends the Settings list, below the fold.
    private func feedbackRow(_ app: XCUIApplication, _ kind: String) -> XCUIElement {
        let row = app.buttons["settings.feedback.\(kind)"]
        _ = app.buttons["settings.homeAssistant"].appears(timeout: 10)
        // The list grew (App Icon, Backdrop blur): ten slow swipes stopped above the last rows.
        // Clear of the bottom edge too: at ax5 a hittable row can sit under the tab bar's hit area.
        let list = app.settingsList
        for _ in 0..<40 where !(row.exists && row.isHittable && row.frame.maxY < list.frame.maxY - 100) {
            list.swipeUp(velocity: .slow)
        }
        return row
    }

    /// Opens the form for `kind` from Settings and waits for its Submit button.
    private func openForm(_ app: XCUIApplication, _ kind: String) {
        goToSettings(app)
        let row = feedbackRow(app, kind)
        XCTAssertTrue(row.appears(timeout: 5), "Feedback row \(kind) not found")
        assertTarget(row)
        row.tap()
        if !app.buttons["feedback.submit"].appears(timeout: 5) {
            // The row can still be settling after the last swipe: scroll it clear again and retry once.
            let again = feedbackRow(app, kind)
            if again.exists, again.isHittable { again.tap() }
        }
        XCTAssertTrue(app.buttons["feedback.submit"].appears(timeout: 5), "Feedback form did not open")
        settleScreen() // Let the sheet finish presenting.
    }

    /// Scrolls the form until `element` can be tapped (a `Form` only exposes rows it has laid out).
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) -> XCUIElement {
        // Short drags: the folded Duo opens this sheet at its half detent, a viewport so short that a full swipe skips
        // the row between two checks.
        for _ in 0..<16 where !(element.exists && element.isHittable) {
            let list = formList(app)
            let step = min(0.5, 110 / max(list.frame.height, 1))
            let from = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.75 : 0.25))
            let to = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.75 - step : 0.25 + step))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        return element
    }

    /// Types after the title's prefix: the tap lands at the field's trailing end, after the prefix.
    private func typeTitle(_ app: XCUIApplication, _ text: String) {
        // The title can sit below the fold (the setup notice and a short folded-Duo sheet push it down) or above it
        // after a scroll. Swipe up first: a swipe down on a sheet already at its top dismisses the sheet.
        let field = app.textFields["feedback.field.title"]
        reveal(field, in: app)
        if !field.isHittable { reveal(field, in: app, up: false) }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(text)
    }

    /// Waits for a prefilled draft to be on screen: the title field holds `title`.
    private func prefilled(_ app: XCUIApplication, title: String) {
        let field = reveal(app.textFields["feedback.field.title"], in: app, up: false)
        let holds = NSPredicate(format: "value CONTAINS %@", title)
        expectation(for: holds, evaluatedWith: field)
        waitForExpectations(timeout: 10)
    }

    /// The form dismisses the keyboard interactively: drag the list down from its middle.
    private func dismissKeyboard(_ app: XCUIApplication) {
        for _ in 0..<3 where app.keyboards.firstMatch.exists {
            let list = formList(app)
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            _ = app.keyboards.firstMatch.disappears(timeout: 2)
        }
    }

    /// Submit, scrolled back into view: the folded iPhone Duo hides its bar while the form is scrolled down.
    private func submitButton(_ app: XCUIApplication) -> XCUIElement {
        let submit = app.buttons["feedback.submit"]
        // Short drags in the form (a full swipe skips rows in the folded Duo's half-height sheet); down first, as before.
        reveal(submit, in: app, up: false)
        if !(submit.exists && submit.isHittable) { reveal(submit, in: app) }
        return submit
    }

    /// The Sent alert's Done button. A `UIAlertAction` has no accessibility identifier (the SwiftUI form's `feedback.done` went
    /// with the port), so it is found by its alert and label: waiting on the identifier was why `testCaptureFeedbackSent` and
    /// `testBugReportFilesTheReport` failed after a successful filing.
    private func doneButton(_ app: XCUIApplication) -> XCUIElement {
        app.alerts.matching(NSPredicate(format: "label == 'Report Sent' OR label == 'Request Sent'")).firstMatch.buttons["Done"]
    }

    private func submit(_ app: XCUIApplication) -> XCUIElement {
        let submit = submitButton(app)
        XCTAssertTrue(submit.appears(timeout: 5))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: submit)
        waitForExpectations(timeout: 15)
        submit.tap()
        return submit
    }

    // MARK: - Journeys

    /// The bug row opens its form, and an empty form closes without asking.
    func testFeedbackBugFormOpensEmptyAndCloses() throws {
        let app = try launch()
        openForm(app, "bug")
        XCTAssertFalse(app.buttons["feedback.submit"].isEnabled, "Submit enabled on an empty form")
        reveal(app.buttons["feedback.close"], in: app, up: false).tap()
        XCTAssertTrue(app.buttons["feedback.submit"].disappears(timeout: 5), "Empty form asked before closing")
    }

    /// The feature row opens its form, and an empty form closes without asking.
    func testFeedbackFeatureFormOpensAndCloses() throws {
        let app = try launch()
        openForm(app, "feature")
        reveal(app.buttons["feedback.close"], in: app, up: false).tap()
        XCTAssertTrue(app.buttons["feedback.submit"].disappears(timeout: 5))
    }

    /// The Settings list with both feedback rows passes the audit, with an AX5 relaunch.
    func testFeedbackRowsPassAudit() throws {
        let app = try launch()
        goToSettings(app)
        // Audited from the top of the list like SettingsJourneyTests: scrolled to the end on the short folded Duo, the
        // topics fade under the header and the audit reports that faded text as element-less contrast issues it can't
        // attribute.
        XCTAssertTrue(feedbackRow(app, "feature").exists)
        // Back to the top of the Settings list (the tab, not a sheet: a swipe down at the top is harmless now).
        let top = app.buttons["settings.vacation"]
        for _ in 0..<8 where !(top.exists && top.isHittable) { app.settingsList.swipeDown(velocity: .fast) }
        try FentonHomeApp.audit(app) {
            let large = try self.launch(arguments: FentonHomeApp.ax5)
            // Same position as the audited page: the AX5 page is only compared with it (an element-less Dynamic
            // Type issue is waived when the same on-screen texts grow 1.35x), so scrolling one of them breaks the
            // comparison (folded Duo, 2026-10-14: 2 of 12 texts matched). The rows themselves are SettingsLinkRow,
            // audited at their position on iPhone and iPad.
            self.goToSettings(large)
            _ = large.buttons["settings.homeAssistant"].appears(timeout: 10)
            return large
        }
    }

    /// The bug form: reproduction boxes, Submit disabled while empty, and the audit with its AX5 relaunch.
    func testBugFormPassesAudit() throws {
        let app = try launch()
        openForm(app, "bug")
        XCTAssertTrue(reveal(app.textViews["feedback.field.repro"], in: app).exists, "Steps to Reproduce missing")
        reveal(app.buttons["feedback.close"], in: app, up: false)
        try FentonHomeApp.audit(app, ax5Page: {
            let large = try self.launch(arguments: FentonHomeApp.ax5)
            self.openForm(large, "bug")
            return large
        }, presenter: app.buttons["settings.feedback.bug"])
    }

    /// The feature form: no reproduction boxes, the Sending-as row, and the audit with its AX5 relaunch (its own
    /// launch, so the AX5 comparison measures two separate app instances).
    func testFeatureFormPassesAudit() throws {
        let app = try launch()
        openForm(app, "feature")
        XCTAssertFalse(app.textViews["feedback.field.repro"].exists, "Feature form shows Steps to Reproduce")
        try FentonHomeApp.audit(app, ax5Page: {
            let large = try self.launch(arguments: FentonHomeApp.ax5)
            self.openForm(large, "feature")
            return large
        }, presenter: app.buttons["settings.feedback.feature"])
    }

    /// Typed input asks before closing; Keep Editing keeps it.
    func testBugReportDiscardConfirmKeepsEditing() throws {
        // A prefilled title is unsaved input without focusing a field (each action on a focused field costs a 60 s idle wait).
        let app = try launch(prefill: "Garage tile stuck")
        openForm(app, "bug")
        prefilled(app, title: "Garage tile stuck")
        let cancel = reveal(app.buttons["feedback.close"], in: app, up: false)
        cancel.tap()
        // A UIAlertAction has no accessibility identifier: find the dialog's actions by label.
        let discard = app.buttons["Discard Changes"].firstMatch
        XCTAssertTrue(discard.appears(timeout: 5), "Discard confirmation missing")
        let keep = app.buttons["Keep Editing"].firstMatch
        if keep.exists && keep.isHittable {
            keep.tap()
        } else {
            // iOS 27 anchors the dialog as a popover without Keep Editing; an outside tap keeps editing. Tap the middle
            // of the larger free band above or below the popover: the window's middle fell on the popover in iPad
            // landscape and kept it open (2026-10-15), and a tap 40 pt above a popover that starts at 88 pt lands in the
            // status bar on iPhone, which ignores it (2026-10-17).
            let popover = app.popovers.firstMatch.exists ? app.popovers.firstMatch.frame : discard.frame
            let window = app.windows.firstMatch.frame
            let below = window.maxY - popover.maxY, above = popover.minY - window.minY
            let y = below >= above ? popover.maxY + min(below / 2, 240) : popover.minY - min(above / 2, 240)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: popover.midX, dy: y)).tap()
        }
        XCTAssertTrue(discard.disappears(timeout: 5))
        XCTAssertTrue(app.buttons["feedback.submit"].exists, "Keep Editing closed the form")
    }

    /// Submit files issue #1 (the relay fixture answers the filing) and Done closes the form.
    func testBugReportFilesTheReport() throws {
        let app = try launch(prefill: "Garage tile stuck")
        openForm(app, "bug")
        prefilled(app, title: "Garage tile stuck")
        _ = submit(app)
        let done = doneButton(app)
        XCTAssertTrue(done.appears(timeout: 15), "Sent alert missing")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'issue #1'")).firstMatch.exists)
        done.tap()
        XCTAssertTrue(app.buttons["feedback.submit"].disappears(timeout: 5), "Done did not close the form")
    }

    /// Without the relay in Home Assistant the form leads with the setup notice and Submit stays off; the
    /// notice passes the audit.
    func testUnavailableRelayShowsSetupNotice() throws {
        let app = try launch(fixture: "unavailable", prefill: "Arrival lights")
        openForm(app, "bug")
        let notice = app.descendants(matching: .any)["feedback.setup"].firstMatch
        XCTAssertTrue(notice.appears(timeout: 5), "Setup notice missing")
        XCTAssertTrue(notice.label.contains("Fenton Home Feedback"))
        prefilled(app, title: "Arrival lights")
        XCTAssertTrue(reveal(app.staticTexts["feedback.validation"], in: app).label.contains("isn't set up"))
        XCTAssertFalse(submitButton(app).isEnabled)
        reveal(notice, in: app, up: false)
        try FentonHomeApp.audit(app, ax5Page: {
            let large = try self.launch(fixture: "unavailable", arguments: FentonHomeApp.ax5)
            self.openForm(large, "bug")
            XCTAssertTrue(large.descendants(matching: .any)["feedback.setup"].firstMatch.appears(timeout: 5))
            return large
        }, presenter: app.buttons["settings.feedback.bug"])
    }

    /// A failed filing keeps everything typed.
    func testFailedFilingKeepsTheForm() throws {
        let app = try launch(prefill: "fixture-failed check")
        openForm(app, "bug")
        prefilled(app, title: "fixture-failed check")
        _ = submit(app)
        let alert = app.alerts["Couldn't Send"]
        if !alert.appears(timeout: 10), app.buttons["feedback.submit"].isEnabled {
            app.buttons["feedback.submit"].tap() // The first tap can land while the keyboard is closing.
        }
        XCTAssertTrue(alert.appears(timeout: 15), "Failure alert missing")
        alert.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["feedback.submit"].appears(timeout: 5))
        let title = reveal(app.textFields["feedback.field.title"], in: app, up: false)
        XCTAssertTrue((title.value as? String)?.contains("fixture-failed") == true, "Typed title lost")
    }

    /// The pose a capture runs in: ``upright`` leaves phones and the Duo as they are and sets portrait on an iPad;
    /// ``iPadLandscape`` is iPad only (skipped elsewhere).
    enum Pose { case upright, iPadLandscape }

    /// Sets `pose` before the launch (rotating from a fresh launch, never with a form up) and returns its screenshot suffix.
    private func enter(_ pose: Pose) throws -> String {
        switch pose {
        case .upright:
            if FentonHomeApp.family == .iPad { XCUIDevice.shared.orientation = .portrait }
            return FentonHomeApp.family == .iPad ? "portrait" : "current"
        case .iPadLandscape:
            guard FentonHomeApp.family == .iPad else { throw XCTSkip("iPad only") }
            FentonHomeApp.target().terminate()
            XCUIDevice.shared.orientation = .landscapeLeft
            return "landscape"
        }
    }

    private func captureRows(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let app = try launch()
        goToSettings(app)
        _ = feedbackRow(app, "feature")
        keepScreenshot(app, "feedback-rows-\(suffix)")
    }

    private func captureBugEmpty(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let app = try launch()
        openForm(app, "bug")
        keepScreenshot(app, "feedback-bug-empty-\(suffix)")
    }

    private func captureBugFilled(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let app = try launch(prefill: "Garage tile stuck")
        openForm(app, "bug")
        prefilled(app, title: "Garage tile stuck")
        reveal(app.textViews["feedback.field.description"], in: app, up: false)
        keepScreenshot(app, "feedback-bug-filled-\(suffix)")
    }

    private func captureSent(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let app = try launch(prefill: "Garage tile stuck")
        openForm(app, "bug")
        prefilled(app, title: "Garage tile stuck")
        _ = submit(app)
        XCTAssertTrue(doneButton(app).appears(timeout: 10))
        keepScreenshot(app, "feedback-sent-\(suffix)")
        doneButton(app).tap()
        XCTAssertTrue(app.buttons["feedback.submit"].disappears(timeout: 5))
    }

    private func captureFeature(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let app = try launch()
        openForm(app, "feature")
        keepScreenshot(app, "feedback-feature-\(suffix)")
    }

    private func captureSetupNotice(_ pose: Pose) throws {
        let suffix = try enter(pose)
        let unset = try launch(fixture: "unavailable")
        openForm(unset, "bug")
        _ = unset.descendants(matching: .any)["feedback.setup"].firstMatch.appears(timeout: 5)
        keepScreenshot(unset, "feedback-setup-notice-\(suffix)")
    }

    // Screenshots of the rows, both forms, the sent alert and the setup notice; iPad also captures landscape.
    func testCaptureFeedbackRows() throws { try captureRows(.upright) }
    func testCaptureFeedbackRowsInIPadLandscape() throws { try captureRows(.iPadLandscape) }
    func testCaptureFeedbackBugEmpty() throws { try captureBugEmpty(.upright) }
    func testCaptureFeedbackBugEmptyInIPadLandscape() throws { try captureBugEmpty(.iPadLandscape) }
    func testCaptureFeedbackBugFilled() throws { try captureBugFilled(.upright) }
    func testCaptureFeedbackBugFilledInIPadLandscape() throws { try captureBugFilled(.iPadLandscape) }
    func testCaptureFeedbackSent() throws { try captureSent(.upright) }
    func testCaptureFeedbackSentInIPadLandscape() throws { try captureSent(.iPadLandscape) }
    func testCaptureFeedbackFeature() throws { try captureFeature(.upright) }
    func testCaptureFeedbackFeatureInIPadLandscape() throws { try captureFeature(.iPadLandscape) }
    func testCaptureFeedbackSetupNotice() throws { try captureSetupNotice(.upright) }
    func testCaptureFeedbackSetupNoticeInIPadLandscape() throws { try captureSetupNotice(.iPadLandscape) }
}
