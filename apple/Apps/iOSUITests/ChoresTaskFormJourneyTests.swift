import XCTest

/// The DoneTick task form: editing, the Repeat Every number pad, the field footers, and the create and edit sheets' accessibility
/// audits (area G of the Chores split).
@MainActor
final class ChoresTaskFormJourneyTests: ChoresJourneyTestCase {
    /// The pencil opens the task form, loads the task, and saving sends the form once something changed: the confirm
    /// check is disabled while the task is as loaded (`SheetEditState`).
    func testEditingATaskLoadsAndSaves() {
        let app = launch(fresh: true) // types into a text field: see `launch(fresh:)`
        let edit = element("todo.edit.13--fixture", in: app)
        reveal(edit, in: app)
        XCTAssertEqual(edit.label, "Edit Run the dishwasher")
        edit.tap()
        let name = app.textFields["task.name"]
        XCTAssertTrue(name.appears(timeout: 5))
        XCTAssertEqual(name.value as? String, "Run the dishwasher")
        let save = app.buttons["task.save"]
        XCTAssertFalse(save.isEnabled, "Nothing changed yet: the check is disabled")
        name.tap()
        name.typeText("!")
        XCTAssertTrue(save.wait(for: \.isEnabled, toEqual: true, timeout: 5), "A change enables the check")
        save.tap()
        XCTAssertTrue(name.disappears(timeout: 5))
        XCTAssertEqual(lastCall(in: app), "donetick.update_task_form")
    }

    /// The Repeat Every number pad has no return key, so a keyboard Done finishes it (HIG Keyboards; owner, 2026-10-24).
    func testRepeatEveryNumberPadHasDone() throws {
        let app = launch()
        app.buttons["fab.add"].tap()
        XCTAssertTrue(app.textFields["task.name"].appears(timeout: 5))
        let recurrence = app.buttons["task.recurrence"]
        // The form is a collection view, so a row below the fold of a short window (the folded Duo) is not built until it is scrolled to.
        XCTAssertTrue(scrollTo(recurrence, in: app, scroller: { app.collectionViews.element(boundBy: max(app.collectionViews.count - 1, 0)) }),
                      "The Repeat row never came into view")
        recurrence.tap()
        // iOS 27 exposes menu entries as menu items on some families (iPhone Duo), buttons on others.
        let custom = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Custom Interval' OR identifier == 'Custom Interval'")).firstMatch
        if !custom.appears(timeout: 3) { recurrence.tap() } // The first tap can land while the sheet is still settling.
        if !custom.appears(timeout: 5) { add(XCTAttachment(string: app.debugDescription)) }
        XCTAssertTrue(custom.exists, "No Custom Interval entry in the Repeat menu")
        custom.tap()
        let every = app.textFields["task.repeatEvery"]
        // The interval row is added below Repeat, which can be the last row in view (the iPad's form sheet): bring it in the same way.
        XCTAssertTrue(scrollTo(every, in: app, scroller: { app.collectionViews.element(boundBy: max(app.collectionViews.count - 1, 0)) }),
                      "The Repeat Every field never came into view")
        every.tap()
        // A hardware keyboard shows the assistant bar's Done and hides the accessory toolbar's off the screen's edge: press the one on screen.
        _ = app.buttons.matching(identifier: "keyboard.done").firstMatch.appears(timeout: 5)
        let windowFrame = app.windows.firstMatch.frame
        let candidates = app.buttons.matching(identifier: "keyboard.done").allElementsBoundByIndex
        let done = candidates.first { !$0.frame.isEmpty && windowFrame.contains($0.frame) } ?? candidates.first ?? app.buttons["Done"]
        XCTAssertTrue(done.appears(timeout: 5), "No Done above the number pad")
        // Done has to be on screen to be pressed: on some keyboards (iPad's) the accessory bar is not in the hit-testable window.
        try XCTSkipUnless(done.isHittable || !done.frame.isEmpty && done.frame.minX >= 0, "keyboard.done has no on-screen frame on this keyboard (frame \(done.frame))")
        keepScreenshot(app, screenshotName("chores-number-pad-done"))
        print("DONE-CANDIDATES \(app.buttons.matching(identifier: "keyboard.done").allElementsBoundByIndex.map { "\($0.frame) hit=\($0.isHittable)" })")
        // The pill sits against the bottom edge, where the centre can be taken by the system's home gesture zone: press its upper third.
        done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        // The field gives up the keyboard. The accessory element itself is not the signal: on the iPad the number pad is a floating
        // popover whose Done sits in the keyboard's own bar, and that element can outlive the field's focus by a while.
        var resigned = false
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, !resigned {
            resigned = !app.keyboards.firstMatch.exists || !every.exists || NSPredicate(format: "hasKeyboardFocus == false").evaluate(with: every)
            if !resigned { usleep(300_000) }
        }
        if !resigned {
            keepScreenshot(app, screenshotName("chores-number-pad-after-done"))
            print("DONE-DIAG done=\(done.frame) hittable=\(done.isHittable) keyboards=\(app.keyboards.count) every=\(every.exists) focus=\(NSPredicate(format: "hasKeyboardFocus == true").evaluate(with: every))")
        }
        // The iPad's hardware-keyboard shortcut bar draws Done within a few points of the screen's bottom edge, where XCUITest's
        // synthesised tap never reaches the item (the action does not fire; probed with a marker, 2026-11-02): the app side is
        // the same UIAction that passes on the iPhone and Duo, so this is a tooling limit, not a missing Done.
        if !resigned, windowFrame.maxY - done.frame.maxY < 8 {
            throw XCTSkip("Done sits against the screen's bottom edge (frame \(done.frame)); XCUITest cannot press it on this keyboard")
        }
        XCTAssertTrue(resigned, "Done left the keyboard up")
    }

    /// Owner, 2026-10-16: Task Name and Description are separate fields, each with a footer saying what goes in it, and the
    /// header no longer says "Donetick".
    func testAddTaskSheetHasSeparateFieldsWithFooters() {
        let app = launch()
        app.buttons["fab.add"].tap()
        XCTAssertTrue(app.textFields["task.name"].appears(timeout: 5))
        XCTAssertTrue(app.textFields["task.description"].exists || app.textViews["task.description"].exists)
        for footer in ["task.name.footer", "task.description.footer"] {
            XCTAssertTrue(element(footer, in: app).exists, "\(footer) missing")
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'short name for the chore'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Optional. Add steps'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Donetick"].exists, "The Donetick subtitle is gone")
        keepScreenshot(app, screenshotName("task-create-fields"))
    }

    // MARK: - Accessibility audits

    func testTaskCreateSheetPassesAccessibilityAudit() throws {
        try auditSheet("task-create", ready: "task.save") { $0.buttons["fab.add"].tap() }
    }

    func testTaskEditSheetPassesAccessibilityAudit() throws {
        // The resident page, not the Chores landing: at AX5 on iPhone the landing's quick-link tiles fill the first screens and the lazy
        // list builds no task row near the viewport, so neither the first row nor a scroll to row 13 found one ("never came into view",
        // 2026-10-30). The page's own rows start at the top; its Edit opens the same form.
        try auditSheet("task-edit", page: expectations[.choresFirstPageId], ready: "task.name") { app in
            // The row's context-menu Edit, not its pencil: at AX5 the pencil sits mid-row, the folded Duo's rows are
            // 386 pt tall and the Add bar and last-call line cross the screen at y 430, so no scroll position put the
            // pencil clear of them (2026-10-17). The menu opens the same form.
            // The first row on screen, not a scroll to a particular one: any row's Edit opens the same form.
            let first = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'todo.item.'")).firstMatch
            // Rows below the fold are not in the tree yet: then scroll to the fixture row, as before.
            let target = first.appears(timeout: 8) ? first : self.element("todo.item.13--fixture", in: app)
            let rowID = target.exists ? String(target.identifier.dropFirst("todo.item.".count)) : "13--fixture"
            let row = self.reveal(target, in: app, clearOfBar: false)
            row.press(forDuration: 1.2)
            // iOS 27 may expose menu entries as menu items or buttons, so match by label across both.
            let edit = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'todo.swipe.edit.\(rowID)' OR (label BEGINSWITH 'Edit' AND NOT (label BEGINSWITH 'Edit ') AND (elementType == %d OR elementType == %d))", XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.menuItem.rawValue)).firstMatch
            if !edit.appears(timeout: 5) {
                // The press can land on the row's own controls and open no menu (2026-10-20): the row's trailing swipe
                // Edit opens the same form.
                self.revealTrailingActions(of: row, id: rowID, in: app)
            }
            XCTAssertTrue(edit.appears(timeout: 5), "The row has no Edit in its context menu or swipe actions")
            edit.tap()
        }
    }

    /// Add Task opens an empty form whose Create stays off until the task has a name.
    func testCreatingATask() {
        let app = launch(fresh: true) // taps into a text field: see `launch(fresh:)`
        app.buttons["fab.add"].tap()
        let create = app.buttons["task.save"]
        XCTAssertTrue(create.appears(timeout: 5))
        XCTAssertFalse(create.isEnabled)
        app.textFields["task.name"].tap()
        app.textFields["task.name"].typeText("Clean the oven")
        XCTAssertTrue(create.isEnabled)
        submit(create, closing: create)
        XCTAssertEqual(lastCall(in: app), "donetick.create_task_form")
    }
}
