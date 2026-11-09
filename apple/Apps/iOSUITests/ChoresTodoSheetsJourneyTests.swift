import XCTest

/// The Groceries and admin To-Do sheets: adding and checking off groceries, renaming an admin to-do and completing it with its
/// script, and each sheet's accessibility audit (area H of the Chores split).
@MainActor
final class ChoresTodoSheetsJourneyTests: ChoresJourneyTestCase {
    func testGroceriesAddAndCheckOff() {
        let app = launch(page: "groceries", fresh: true) // types into a text field: see `launch(fresh:)`
        XCTAssertEqual(app.buttons["fab.add"].label, "Add Groceries")
        app.buttons["fab.add"].tap()
        let field = app.textFields["grocery.item"]
        XCTAssertTrue(field.appears(timeout: 5))
        field.typeText("Eggs")
        submit(app.buttons["grocery.add"], closing: field)
        let eggs = app.buttons.matching(NSPredicate(format: "label == 'Eggs'")).firstMatch
        XCTAssertTrue(eggs.appears(timeout: 5), "New grocery not listed")
        element("todo.item.g1", in: app).tap()
        XCTAssertTrue(element("todo.item.g1", in: app).disappears(timeout: 10))
        XCTAssertFalse(element("todo.edit.g2", in: app).exists, "Groceries are not editable")
    }

    func testAdminTodoRenamesAndCompletesWithItsScript() {
        let app = launch(page: "to-do", fresh: true) // taps into a text field: see `launch(fresh:)`
        XCTAssertTrue(app.navigationBars["To-Do"].appears(timeout: 5))
        element("todo.edit.a1", in: app).tap()
        let name = app.textFields["renameTodo.name"]
        XCTAssertTrue(name.appears(timeout: 5))
        XCTAssertFalse(app.buttons["renameTodo.save"].isEnabled)
        name.tap()
        name.typeText(" now")
        // On iPad the first tap can only end editing in the focused field.
        submit(app.buttons["renameTodo.save"], closing: name)
        XCTAssertEqual(lastCall(in: app), "todo.update_item a1")
        element("todo.item.a2", in: app).tap()
        XCTAssertTrue(element("todo.item.a2", in: app).disappears(timeout: 10))
        XCTAssertEqual(lastCall(in: app), "\(expectations[.choresAdminTodoCompletionScript]) a2")
    }

    // MARK: - Accessibility audits

    func testGroceryAddSheetPassesAccessibilityAudit() throws {
        try auditSheet("grocery-add", page: "groceries", ready: "grocery.add") { $0.buttons["fab.add"].tap() }
    }

    func testAdminTodoAddSheetPassesAccessibilityAudit() throws {
        try auditSheet("admin-todo-add", page: "to-do", ready: "adminTodo.add") { $0.buttons["fab.add"].tap() }
    }

    func testAdminTodoRenameSheetPassesAccessibilityAudit() throws {
        try auditSheet("admin-todo-rename", page: "to-do", ready: "renameTodo.save") { $0.descendants(matching: .any)["todo.edit.a1"].firstMatch.tap() }
    }
}
