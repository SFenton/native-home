import Foundation
import HassTestSupport
import Testing
@testable import HassCore

// MARK: - Todo draft forms

/// The add, rename and task forms: what each submits, what each refuses, and what a failed save leaves behind.
@Suite @MainActor struct ServerUITodoFormsTests {
    private let item = TodoItem(uid: "task-1", summary: "First")

    private func provider(_ service: MockTodoService, canAdd: Bool = true, canRename: Bool = true,
                          canCreateTask: Bool = true, canDelete: Bool = true) throws -> ServerUITodoProvider {
        let configuration = try ServerUITodoProvider.Configuration(entityId: "todo.example", canRename: canRename,
                                                                   canDelete: canDelete, canAdd: canAdd,
                                                                   canCreateTask: canCreateTask, canEditTask: true)
        return ServerUITodoProvider(configuration: configuration, store: TodoStore(service: service), service: service)
    }

    private func people() throws -> ServerUITodoPeople {
        try ServerUITodoPeople(people: [], anyone: "Anyone", viewer: "You", unknownPrefix: "Person")
    }

    @Test func aNewEntryIsAddedByName() async throws {
        let service = MockTodoService()
        let source = try provider(service)
        let form = try source.textForm()
        #expect(!form.canSave, "a name is required")
        try form.set(.string("Milk"), group: "new", field: "name")
        try await form.save()
        #expect(service.calls == ["todo.add_item entity_id=todo.example,item=Milk"])
    }

    @Test func aRenameChecksTheItemIsUnchangedThenRenames() async throws {
        let service = MockTodoService()
        service.items["todo.example"] = [item]
        let source = try provider(service)
        try await source.load()
        let form = try source.textForm(identity: item.identity)
        try form.set(.string("Second"), group: item.identity, field: "name")
        try await form.save()
        #expect(service.calls == ["todo.update_item entity_id=todo.example,item=task-1,rename=Second"])
    }

    @Test func formsRefuseWhatTheListDoesNotAllow() async throws {
        let service = MockTodoService()
        service.items["todo.example"] = [item]
        let locked = try provider(service, canAdd: false, canRename: false, canCreateTask: false)
        try await locked.load()
        #expect(throws: ServerUITodoProvider.Failure.forbidden) { try locked.textForm() }
        #expect(throws: ServerUITodoProvider.Failure.invalidItem) { try locked.textForm(identity: item.identity) }
        await #expect(throws: ServerUITodoProvider.Failure.forbidden) { try await locked.taskForm(people: try people()) }
        let open = try provider(service)
        try await open.load()
        #expect(throws: ServerUITodoProvider.Failure.invalidItem) { try open.textForm(identity: "missing") }
    }

    @Test func aNewTaskSubmitsItsDueDateTimeAndRepeat() async throws {
        let service = MockTodoService()
        let source = try provider(service)
        let form = try await source.taskForm(people: try people())
        #expect(form.deletion == nil)
        try form.set(.string("Water plants"), group: "new", field: "name")
        try form.set(.boolean(true), group: "new", field: "hasDueDate")
        try form.set(.string("2026-03-05"), group: "new", field: "dueDate")
        try form.set(.boolean(true), group: "new", field: "hasDueTime")
        try form.set(.string("09:30"), group: "new", field: "dueTime")
        try form.set(.string("interval"), group: "new", field: "recurrence")
        try form.set(.number(3), group: "new", field: "recurrenceInterval")
        try form.set(.string("weeks"), group: "new", field: "recurrenceUnit")
        try await form.save()
        let call = try #require(service.calls.last)
        #expect(call.hasPrefix("donetick.create_task_form "))
        #expect(call.contains("Water plants"))
    }

    @Test func aTaskRepeatingOnWeekdaysKeepsThemInCalendarOrder() async throws {
        let service = MockTodoService()
        let source = try provider(service)
        let form = try await source.taskForm(people: try people())
        try form.set(.string("Bins"), group: "new", field: "name")
        try form.set(.string("days_of_the_week"), group: "new", field: "recurrence")
        try form.set(.string("friday,monday"), group: "new", field: "recurrenceDays")
        try await form.save()
        #expect(service.calls.last?.hasPrefix("donetick.create_task_form ") == true)
    }

    @Test func anInvalidDateTimeOrWeekdayKeepsTheEditsAndSaysSo() async throws {
        let service = MockTodoService()
        let source = try provider(service)
        let form = try await source.taskForm(people: try people())
        try form.set(.string("Bins"), group: "new", field: "name")
        try form.set(.boolean(true), group: "new", field: "hasDueDate")
        try form.set(.string("next week"), group: "new", field: "dueDate")
        await #expect(throws: ServerUIRecordFailure.invalidValue) { try await form.save() }
        try form.set(.string("2026-03-05"), group: "new", field: "dueDate")
        try form.set(.boolean(true), group: "new", field: "hasDueTime")
        try form.set(.string("25:00"), group: "new", field: "dueTime")
        await #expect(throws: ServerUIRecordFailure.invalidValue) { try await form.save() }
        try form.set(.string("09:00"), group: "new", field: "dueTime")
        try form.set(.string("days_of_the_week"), group: "new", field: "recurrence")
        try form.set(.string("someday"), group: "new", field: "recurrenceDays")
        await #expect(throws: ServerUIRecordFailure.invalidValue) { try await form.save() }
        #expect(form.hasChanges && form.error != nil)
        #expect(service.calls.isEmpty)
    }
}
