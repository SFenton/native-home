import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// A chores service that records every call with its data and can be told to refuse, over the gallery's fixture lists.
@MainActor
final class RecordingChoresService: TodoServicing {
    let inner: ChoresFixtureService
    var refuses = false
    private(set) var calls: [(name: String, data: [String: any Sendable])] = []
    var names: [String] { calls.map(\.name) }

    init(inner: ChoresFixtureService) { self.inner = inner }

    func todoItems(entityId: String) async throws -> [TodoItem] { try await inner.todoItems(entityId: entityId) }
    func uploadAdminTodo(_ upload: AdminTodoUpload, accessToken: String) async throws {
        calls.append(("upload", ["item": upload.item, "images": upload.images.count]))
        if refuses { throw ChoresFixtureService.Refused() }
        try await inner.uploadAdminTodo(upload, accessToken: accessToken)
    }
    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        calls.append(("\(domain).\(service)", data))
        if refuses { throw ChoresFixtureService.Refused() }
        return try await inner.callServiceForResponse(domain, service, data: data)
    }
    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        calls.append(("\(domain).\(service)", data))
        if refuses { throw ChoresFixtureService.Refused() }
        try await inner.callService(domain, service, data: data)
    }
}

/// The to-do forms: add grocery, add admin to-do, rename, and the DoneTick task form with its recurrence rows, save, failure and
/// delete, each in a sheet on a host page.
@MainActor
final class UKHostedChoresFormsTests: DemoHouseTestCase {
    private struct Rig {
        let service: RecordingChoresService
        let model: ChoresModel
        let host: UIViewController
        let window: UIWindow
    }

    private func rig(refuses: Bool = false) -> Rig {
        let store = EntityStore()
        let inner = ChoresFixtureService(store: store, lists: ChoresFixtures.lists())
        store.replaceAll(inner.entityStates())
        let service = RecordingChoresService(inner: inner)
        service.refuses = refuses
        let model = ChoresModel(service: service, todos: TodoStore(service: service), viewerUserId: ChoresConfig.Resident.resident1.haUserId)
        let host = UIViewController()
        let window = HostedPage.show(host, size: CGSize(width: 393, height: 2400))
        return Rig(service: service, model: model, host: host, window: window)
    }

    private func present(_ form: UKTodoFormController, on rig: Rig) async -> UKHassModalController {
        let modal = UKHassModalController(root: form, options: UKHassModalOptions(title: form.title))
        rig.host.present(modal, animated: false)
        await FeatureHost.settleAsync(0.8)
        // The form focuses its field as it appears. A soft keyboard would cover this bottom-placed sheet in the tall test window (the
        // sheet's content sits above `keyboardLayoutGuide`, so it collapses); on a device the sheet rises above the keyboard.
        modal.view.endEditing(true)
        await FeatureHost.settleAsync(0.2)
        return modal
    }

    private func textView(in root: UIView) -> UITextView? {
        if let view = root as? UITextView, !view.isHidden { return view }
        for sub in root.subviews { if let hit = textView(in: sub) { return hit } }
        return nil
    }

    private func type(_ text: String, into view: UITextView) {
        view.text = text
        view.delegate?.textViewDidChange?(view)
    }

    private func choose(_ title: String, from identifier: String, in root: UIView, file: StaticString = #filePath, line: UInt = #line) {
        guard let button = FeatureHost.view(identifier, in: root) as? UIButton, let menu = button.menu else {
            return XCTFail("\(identifier) has no menu", file: file, line: line)
        }
        guard let action = menu.children.compactMap({ $0 as? UIAction }).first(where: { $0.title == title }) else {
            return XCTFail("\(identifier) offers \(menu.children.map(\.title))", file: file, line: line)
        }
        action.performWithSender(nil, target: nil)
    }

    // MARK: Grocery

    func testAGroceryThatCannotBeAddedSaysSoAndStaysOpen() async throws {
        let r = rig(refuses: true)
        defer { r.window.isHidden = true }
        let form = UKAddGroceryItemController(model: r.model, entityId: ChoresConfig.groceryEntityId)
        let modal = await present(form, on: r)
        // The field takes focus as the form appears, and while the soft keyboard is up the list has no height and realises no cell
        // (see `present`). How long the keyboard takes to leave after `endEditing` depends on what ran before, so wait for the
        // field's row to be laid out rather than for a fixed time.
        await FeatureHost.settleAsync(until: { FeatureHost.view("grocery.item", in: form.view) is UITextField })
        let field = try XCTUnwrap(FeatureHost.view("grocery.item", in: form.view) as? UITextField,
                                  "the Item field is on the form: \(FeatureHost.describeLists(in: modal.view)) keyboard guide=\(modal.view.keyboardLayoutGuide.layoutFrame)")
        field.text = "  Oat milk  "
        field.sendActions(for: .editingChanged)
        XCTAssertTrue(form.canConfirm)
        XCTAssertTrue(field.delegate?.textFieldShouldReturn?(field) == false, "Return adds the item rather than inserting a line")
        await FeatureHost.settleAsync(0.3)
        XCTAssertEqual(r.service.calls.last?.data["item"] as? String, "Oat milk", "the name is trimmed")
        // The failure is a row of the form, with its own identifier. The soft keyboard the field focuses covers this bottom-placed
        // sheet in the tall test window (the list sits above `keyboardLayoutGuide`, so it has no height and realises no cell), so the
        // row is read from the form's sections rather than from a cell.
        XCTAssertEqual(form.error, "Unable to add grocery item")
        let errorRow = form.form.sections.flatMap(\.rows).first { $0.identifier == "todoSheet.error" }
        XCTAssertNotNil(errorRow, "the failure is shown on the form: \(form.form.sections.map(\.id))")
        XCTAssertNotNil(r.host.presentedViewController, "the form stays open")
        XCTAssertNotNil(modal)
    }

    // MARK: Admin to-do

    func testAddingAnAdminTodoSendsTheTrimmedTaskAndCloses() async throws {
        let r = rig()
        defer { r.window.isHidden = true }
        let form = UKAddAdminTodoController(model: r.model, entityId: ChoresConfig.adminTodoEntityId)
        _ = await present(form, on: r)
        let view = try XCTUnwrap(textView(in: form.view))
        type("  Fix the porch light  ", into: view)
        await FeatureHost.settleAsync(0.3)
        XCTAssertTrue(form.canConfirm)
        XCTAssertTrue(form.hasEdits)
        form.confirmTapped()
        await FeatureHost.settleAsync(1.0)
        XCTAssertEqual(r.service.calls.last?.name, "todo.add_item")
        XCTAssertEqual(r.service.calls.last?.data["item"] as? String, "Fix the porch light")
        XCTAssertNil(r.host.presentedViewController, "the sheet closes once it is added")
    }

    func testAnAdminTodoIsCappedAtAThousandCharacters() async throws {
        let r = rig()
        defer { r.window.isHidden = true }
        let form = UKAddAdminTodoController(model: r.model, entityId: ChoresConfig.adminTodoEntityId)
        _ = await present(form, on: r)
        let view = try XCTUnwrap(textView(in: form.view))
        type(String(repeating: "x", count: 1200), into: view)
        XCTAssertEqual(view.text.count, 1000)
    }

    func testAnAdminTodoThatFailsToSaveExplains() async throws {
        let r = rig(refuses: true)
        defer { r.window.isHidden = true }
        let form = UKAddAdminTodoController(model: r.model, entityId: ChoresConfig.adminTodoEntityId)
        _ = await present(form, on: r)
        type("Replace the fuse", into: try XCTUnwrap(textView(in: form.view)))
        form.confirmTapped()
        await FeatureHost.settleAsync(0.8)
        XCTAssertEqual(form.error, "Unable to add this task. Try again.")
        XCTAssertNotNil(FeatureHost.view("todoSheet.error", in: form.view))
        XCTAssertTrue(form.canConfirm, "and it can be tried again")
    }

    func testAnImageRowNamesTheFileAndRemovesIt() async {
        var removed = 0
        let image = AdminTodoUpload.Image(data: Data(), filename: "photo-1.jpg", mimeType: "image/jpeg")
        let row = UKAdminTodoImageRowView(image: image) { removed += 1 }
        let window = HostedPage.show(UIViewController())
        defer { window.isHidden = true }
        row.frame = CGRect(x: 0, y: 0, width: 360, height: 60)
        window.rootViewController?.view.addSubview(row)
        row.layoutIfNeeded()
        XCTAssertTrue(HostedPage.labels(in: row).contains("photo-1.jpg"))
        let remove = row.subviewsRecursive.compactMap { $0 as? UIButton }.first
        XCTAssertEqual(remove?.accessibilityLabel, "Remove photo-1.jpg")
        remove?.sendActions(for: .touchUpInside)
        XCTAssertEqual(removed, 1)
    }

    // MARK: Rename

    func testRenamingSendsTheNewNameAndCloses() async throws {
        let r = rig()
        defer { r.window.isHidden = true }
        let target = AdminTodoEditTarget(itemUid: "a1", originalTitle: "Port the Chores page", todoEntityId: ChoresConfig.adminTodoEntityId)
        let form = UKRenameTodoItemController(model: r.model, target: target)
        _ = await present(form, on: r)
        XCTAssertNil(FeatureHost.view("renameTodo.reset", in: form.view), "nothing to reset before an edit")
        let field = try XCTUnwrap(FeatureHost.view("renameTodo.name", in: form.view) as? UITextField)
        field.text = "Port the Chores page to UIKit"
        field.sendActions(for: .editingChanged)
        await FeatureHost.settleAsync(0.4)
        XCTAssertTrue(form.canConfirm)
        XCTAssertTrue(form.hasEdits)
        XCTAssertNotNil(FeatureHost.reveal("renameTodo.reset", in: form.view), "Reset to Original appears once the name differs: \(FeatureHost.describeLists(in: form.view)) \(FeatureHost.identifiers(in: form.view).sorted())")
        form.confirmTapped()
        await FeatureHost.settleAsync(1.0)
        XCTAssertEqual(r.service.calls.last?.name, "todo.update_item")
        XCTAssertEqual(r.service.calls.last?.data["rename"] as? String, "Port the Chores page to UIKit")
        XCTAssertEqual(r.service.calls.last?.data["item"] as? String, "a1")
        XCTAssertNil(r.host.presentedViewController)
    }

    func testResetToOriginalRestoresTheName() async throws {
        let r = rig()
        defer { r.window.isHidden = true }
        let target = AdminTodoEditTarget(itemUid: "a1", originalTitle: "Port the Chores page", todoEntityId: ChoresConfig.adminTodoEntityId)
        let form = UKRenameTodoItemController(model: r.model, target: target)
        _ = await present(form, on: r)
        let field = try XCTUnwrap(FeatureHost.view("renameTodo.name", in: form.view) as? UITextField)
        field.text = "Something else"
        field.sendActions(for: .editingChanged)
        await FeatureHost.settleAsync(0.4)
        XCTAssertTrue(FeatureHost.press("renameTodo.reset", in: form.view) || FeatureHost.tapRow("renameTodo.reset", in: form.view))
        await FeatureHost.settleAsync(0.4)
        XCTAssertEqual(field.text, "Port the Chores page")
        XCTAssertFalse(form.hasEdits)
        XCTAssertFalse(form.canConfirm)
    }

    func testARenameThatFailsOrHasNoIdentityExplains() async throws {
        let r = rig(refuses: true)
        defer { r.window.isHidden = true }
        let target = AdminTodoEditTarget(itemUid: "a1", originalTitle: "Port the Chores page", todoEntityId: ChoresConfig.adminTodoEntityId)
        let form = UKRenameTodoItemController(model: r.model, target: target)
        _ = await present(form, on: r)
        let field = try XCTUnwrap(FeatureHost.view("renameTodo.name", in: form.view) as? UITextField)
        field.text = "New title"
        field.sendActions(for: .editingChanged)
        form.confirmTapped()
        await FeatureHost.settleAsync(0.8)
        XCTAssertNotNil(form.error)
        XCTAssertNotNil(FeatureHost.view("todoSheet.error", in: form.view))
        r.host.dismiss(animated: false)
        await FeatureHost.settleAsync(0.3)

        let orphan = UKRenameTodoItemController(model: r.model, target: AdminTodoEditTarget(itemUid: nil, originalTitle: "Old", todoEntityId: ChoresConfig.adminTodoEntityId))
        _ = await present(orphan, on: r)
        XCTAssertTrue(HostedPage.labels(in: orphan.view).contains { $0.contains("Home Assistant identity is unavailable") })
        XCTAssertFalse(orphan.canConfirm)
    }

    // MARK: DoneTick task

    private func taskForm(_ r: Rig, mode: DonetickTaskSheet.Mode, saved: @escaping () -> Void = {}) async -> UKDonetickTaskViewController {
        let form = UKDonetickTaskViewController(model: r.model, mode: mode, connection: nil, onSaved: saved)
        _ = await present(form, on: r)
        await FeatureHost.settleAsync(0.8)
        return form
    }

    func testANewCustomIntervalTaskSendsItsRecurrence() async throws {
        let r = rig()
        defer { r.window.isHidden = true }
        var saved = 0
        let form = await taskForm(r, mode: .create(defaultAssignee: ChoresConfig.Resident.resident1.taskAssignee)) { saved += 1 }
        let name = try XCTUnwrap(FeatureHost.view("task.name", in: form.view) as? UITextField)
        name.text = "Descale the kettle"
        name.sendActions(for: .editingChanged)
        textView(in: form.view).map { type("Use vinegar", into: $0) }
        await FeatureHost.settleAsync(0.3)
        choose("Custom Interval", from: "task.recurrence", in: form.view)
        await FeatureHost.settleAsync(0.5)
        let every = try XCTUnwrap(FeatureHost.view("task.repeatEvery", in: form.view) as? UITextField, "a custom interval asks how often")
        every.text = "3"
        every.sendActions(for: .editingChanged)
        every.text = ""
        every.sendActions(for: .editingChanged)
        every.sendActions(for: .editingDidEnd)
        XCTAssertEqual(every.text, "1", "an empty interval settles back to 1")
        every.text = "3"
        every.sendActions(for: .editingChanged)
        choose("Weeks", from: "task.recurrenceUnit", in: form.view)
        await FeatureHost.settleAsync(0.4)
        choose("P1", from: "task.priority", in: form.view)
        XCTAssertTrue(FeatureHost.flip("task.hasDueDate", in: form.view))
        await FeatureHost.settleAsync(0.4)
        let date = try XCTUnwrap(FeatureHost.view("task.dueDate", in: form.view) as? UIDatePicker)
        date.date = Date(timeIntervalSince1970: 1_800_000_000)
        date.sendActions(for: .valueChanged)
        XCTAssertTrue(FeatureHost.flip("task.hasDueTime", in: form.view))
        await FeatureHost.settleAsync(0.4)
        let time = try XCTUnwrap(FeatureHost.view("task.dueTime", in: form.view) as? UIDatePicker)
        time.sendActions(for: .valueChanged)
        XCTAssertTrue(FeatureHost.flip("task.hideOnVacation", in: form.view))
        form.confirmTapped()
        await FeatureHost.settleAsync(1.0)
        let call = try XCTUnwrap(r.service.calls.last { $0.name == "donetick.create_task_form" }, "\(r.service.names)")
        XCTAssertEqual(call.data["name"] as? String, "Descale the kettle")
        XCTAssertEqual(call.data["recurrence_unit"] as? String, "weeks")
        XCTAssertEqual(call.data["recurrence_interval"] as? Int, 3)
        XCTAssertEqual(call.data["priority"] as? String, "low", "P1 is DoneTick's low priority")
        XCTAssertEqual(saved, 1)
        XCTAssertNil(r.host.presentedViewController, "the sheet closes after a save")
    }

    func testSpecificDaysOfTheWeekAreToggledAsOptions() async throws {
        let r = rig()
        defer { r.window.isHidden = true }
        let form = await taskForm(r, mode: .create(defaultAssignee: ""))
        choose("Specific Days of Week", from: "task.recurrence", in: form.view)
        await FeatureHost.settleAsync(0.5)
        XCTAssertTrue(FeatureHost.tapRow("task.day.monday", in: form.view))
        XCTAssertTrue(FeatureHost.tapRow("task.day.friday", in: form.view))
        await FeatureHost.settleAsync(0.4)
        let name = try XCTUnwrap(FeatureHost.view("task.name", in: form.view) as? UITextField)
        name.text = "Bins"
        name.sendActions(for: .editingChanged)
        form.confirmTapped()
        await FeatureHost.settleAsync(0.8)
        let days = r.service.calls.last { $0.name == "donetick.create_task_form" }?.data["recurrence_days"] as? [String]
        XCTAssertEqual(Set(days ?? []), ["monday", "friday"])
    }

    func testACreateThatFailsShowsTheMessage() async throws {
        let r = rig(refuses: true)
        defer { r.window.isHidden = true }
        let form = await taskForm(r, mode: .create(defaultAssignee: ""))
        let name = try XCTUnwrap(FeatureHost.view("task.name", in: form.view) as? UITextField)
        name.text = "Bins"
        name.sendActions(for: .editingChanged)
        form.confirmTapped()
        await FeatureHost.settleAsync(0.8)
        XCTAssertNotNil(FeatureHost.view("todoSheet.error", in: form.view))
        XCTAssertTrue(form.canConfirm, "the person can try again")
    }

    func testEditingSavesOnlyAfterAChangeAndDeletingAsksFirst() async throws {
        let r = rig()
        defer { r.window.isHidden = true }
        var saved = 0
        let target = DonetickEditTarget(itemUid: "11--fixture", taskId: 11, todoEntityId: ChoresConfig.page("alexs-chores")?.lists.first?.entityId ?? "")
        let form = await taskForm(r, mode: .edit(target)) { saved += 1 }
        XCTAssertTrue(r.service.names.contains("donetick.get_task"), "the task is fetched first")
        XCTAssertFalse(form.canConfirm)
        let description = try XCTUnwrap(textView(in: form.view))
        type("Updated notes", into: description)
        await FeatureHost.settleAsync(0.3)
        XCTAssertTrue(form.canConfirm)
        form.confirmTapped()
        await FeatureHost.settleAsync(0.8)
        let update = try XCTUnwrap(r.service.calls.last { $0.name == "donetick.update_task_form" })
        XCTAssertEqual(update.data["task_id"] as? Int, 11)
        XCTAssertEqual(saved, 1)
        XCTAssertNil(r.host.presentedViewController)
    }

    func testDeletingATaskConfirmsThenRemovesIt() async throws {
        let r = rig()
        defer { r.window.isHidden = true }
        var saved = 0
        let target = DonetickEditTarget(itemUid: "11--fixture", taskId: 11, todoEntityId: ChoresConfig.page("alexs-chores")?.lists.first?.entityId ?? "")
        let form = await taskForm(r, mode: .edit(target)) { saved += 1 }
        XCTAssertTrue(FeatureHost.press("task.delete", in: form.view))
        await FeatureHost.settleAsync(0.8)
        let alert = try XCTUnwrap(FeatureHost.alert(on: form), "Delete asks first")
        XCTAssertFalse(r.service.names.contains("todo.remove_item"), "nothing is removed before confirming")
        XCTAssertTrue(alert.actions.contains { $0.style == .destructive })
        let destructive = try XCTUnwrap(alert.actions.first { $0.style == .destructive }?.title)
        XCTAssertTrue(FeatureHost.answer(alert, destructive))
        await FeatureHost.settleAsync(0.8)
        XCTAssertEqual(r.service.calls.last { $0.name == "todo.remove_item" }?.data["item"] as? String, "11--fixture")
        XCTAssertEqual(saved, 1)
    }

    func testATaskThatCannotBeLoadedOffersTryAgain() async throws {
        let r = rig(refuses: true)
        defer { r.window.isHidden = true }
        let target = DonetickEditTarget(itemUid: "11--fixture", taskId: 11, todoEntityId: ChoresConfig.page("alexs-chores")?.lists.first?.entityId ?? "")
        let form = await taskForm(r, mode: .edit(target))
        XCTAssertNotNil(FeatureHost.view("task.loadError", in: form.view), "the failure is explained")
        r.service.refuses = false
        XCTAssertTrue(FeatureHost.press("task.retry", in: form.view))
        await FeatureHost.settleAsync(1.2)
        XCTAssertNotNil(FeatureHost.view("task.name", in: form.view), "Try Again loads the form")
        XCTAssertNil(FeatureHost.view("task.loadError", in: form.view))
    }
}

private extension UIView {
    var subviewsRecursive: [UIView] { subviews + subviews.flatMap(\.subviewsRecursive) }
}
