import Foundation
import HassTestSupport
import Testing
@testable import HassCore

@Suite @MainActor struct ServerUITodoTests {
    private let item = TodoItem(uid: "task-1", summary: "First")

    private func provider(_ service: MockTodoService, canDelete: Bool = true, canRename: Bool = true,
                          attachments: Bool = true, script: String? = nil) throws -> ServerUITodoProvider {
        let configuration = try ServerUITodoProvider.Configuration(entityId: "todo.example", completionScript: script,
                                                                   canRename: canRename, canDelete: canDelete,
                                                                   canAdd: true, canCreateTask: true, canEditTask: true,
                                                                   allowsAttachments: attachments)
        return ServerUITodoProvider(configuration: configuration, store: TodoStore(service: service), service: service)
    }

    @Test func cachedControllerAndCompletionKeepCanonicalUndoAndScript() async throws {
        let service = MockTodoService()
        service.items["todo.example"] = [item]
        let source = try provider(service, script: "script.demo_finish")
        #expect(source.items == nil)
        try await source.load()
        try await source.toggle(expected: item)
        #expect(service.calls.last == "script.demo_finish item=task-1")
        #expect(source.items?.first?.status == .completed)
        try await source.undo(expected: try #require(source.items?.first))
        #expect(service.calls.last == "todo.update_item entity_id=todo.example,item=task-1,status=needs_action")
    }

    @Test func destructiveTicketRevalidatesAndIsSingleUse() async throws {
        let service = MockTodoService()
        service.items["todo.example"] = [item]
        let source = try provider(service)
        try await source.load()
        let stale = try source.deleteTicket(expected: item)
        #expect(source.isPinned)
        service.items["todo.example"] = [TodoItem(uid: item.uid, summary: "Changed")]
        try await source.load()
        await #expect(throws: ServerUITodoProvider.Failure.staleConfirmation) { try await source.delete(confirmed: stale) }
        #expect(!source.isPinned)
        let ticket = try source.deleteTicket(expected: try #require(source.items?.first))
        try await source.delete(confirmed: ticket)
        await #expect(throws: ServerUITodoProvider.Failure.staleConfirmation) { try await source.delete(confirmed: ticket) }
        #expect(service.calls == ["todo.remove_item entity_id=todo.example,item=task-1"])
    }

    @Test func cancelledConfirmationReleasesItsPinWithoutCallingService() async throws {
        let service = MockTodoService()
        service.items["todo.example"] = [item]
        let source = try provider(service)
        try await source.load()
        let ticket = try source.deleteTicket(expected: item)
        try source.cancelDelete(ticket)
        #expect(!source.isPinned)
        #expect(service.calls.isEmpty)
        #expect(throws: ServerUITodoProvider.Failure.staleConfirmation) { try source.cancelDelete(ticket) }
    }

    @Test func ambiguousIdentityAndFailuresAreExplicit() async throws {
        let service = MockTodoService()
        service.items["todo.example"] = [item, item]
        let source = try provider(service)
        try await source.load()
        #expect(throws: ServerUITodoProvider.Failure.invalidItem) { try source.deleteTicket(expected: item) }
        service.failure = MockTodoService.Failure()
        await #expect(throws: ServerUITodoProvider.Failure.service("Server said no")) { try await source.load() }
        #expect(source.items?.count == 2)
        #expect(!source.hasPendingIntent)
    }

    @Test func renameAddAttachmentsAndFormUseCanonicalCalls() async throws {
        let service = MockTodoService()
        service.items["todo.example"] = [item]
        let source = try provider(service)
        try await source.load()
        try await source.rename(identity: item.identity, name: "  Renamed  ")
        try await source.add(name: "  Grocery  ", accessToken: { throw CancellationError() })
        let image = AdminTodoUpload.Image(data: Data([1]), filename: "image.png", mimeType: "image/png")
        try await source.add(name: " Picture ", images: [image], accessToken: { "synthetic" })
        #expect(service.calls == ["todo.update_item entity_id=todo.example,item=task-1,rename=Renamed",
                                  "todo.add_item entity_id=todo.example,item=Grocery"])
        #expect(service.uploads.first?.item == "Picture")
        #expect(service.uploads.first?.images == [image])
        await #expect(throws: ServerUITodoProvider.Failure.invalidAttachment("Select no more than four images.")) {
            try await source.add(name: "Picture", images: Array(repeating: image, count: 5), accessToken: { "synthetic" })
        }
        var form = DonetickTaskForm()
        form.name = "Task"
        try await source.saveTask(form)
        #expect(service.calls.last?.hasPrefix("donetick.create_task_form ") == true)
    }

    @Test func taskEditorPinsIdentityAndOriginalAssignee() async throws {
        let service = MockTodoService()
        service.items["todo.example"] = [TodoItem(uid: "42--2026-01-01", summary: "Task")]
        service.response = .object(["id": .number(42), "name": .string("Task"), "assigned_to": .number(1)])
        let source = try provider(service)
        try await source.load()
        let edit = try await source.editTask(identity: "42--2026-01-01")
        var form = edit.initial
        form.name = "Changed"
        try await source.saveTask(form, editing: edit)
        let call = try #require(service.calls.last)
        #expect(call.contains("donetick.update_task_form"))
        #expect(!call.contains("assignees="))
        await #expect(throws: ServerUITodoProvider.Failure.invalidItem) { try await source.saveTask(form, editing: edit) }
    }

    @Test func taskFormDeletionRetainsTheExactTicketOnFailureAndConsumesItOnSuccess() async throws {
        let service = MockTodoService()
        let item = TodoItem(uid: "42--2026-01-01", summary: "Task")
        service.items["todo.example"] = [item]
        service.response = .object(["id": .number(42), "name": .string("Task"), "assigned_to": .number(1)])
        let source = try provider(service)
        try await source.load()
        let people = try ServerUITodoPeople(people: [], anyone: "Anyone", viewer: "You", unknownPrefix: "Person")
        let form = try await source.taskForm(identity: item.identity, people: people)
        try form.set(.string("Unsaved Rename"), group: item.identity, field: "name")
        #expect(form.deletion?.name == "Task")
        #expect(!form.canReset && source.isPinned)
        service.failure = MockTodoService.Failure()
        await #expect(throws: ServerUITodoProvider.Failure.service("Server said no")) { try await form.delete() }
        #expect(form.hasChanges && source.isPinned)
        service.failure = nil
        try await form.delete()
        #expect(!form.hasChanges && !source.isPinned)
        #expect(service.calls.last == "todo.remove_item entity_id=todo.example,item=42--2026-01-01")
        await #expect(throws: ServerUIRecordFailure.invalidValue) { try await form.delete() }
        try form.discard()
    }

    @Test func scalarRenameRejectsChangedSnapshotAndTaskDiscardReleasesOwnership() async throws {
        let service = MockTodoService()
        service.items["todo.example"] = [item]
        let source = try provider(service)
        try await source.load()
        let form = try source.textForm(identity: item.identity)
        try form.set(.string("Draft"), group: item.identity, field: "name")
        service.items["todo.example"] = [TodoItem(uid: item.uid, summary: "Someone Else's Change")]
        try await source.load()
        await #expect(throws: ServerUITodoProvider.Failure.invalidItem) { try await form.save() }
        #expect(form.hasChanges && form.error != nil)
        #expect(service.calls.isEmpty)
    }

    @Test func adminAttachmentDraftPinsPickerAndPreservesImagesOnInvalidReplacement() async throws {
        let service = MockTodoService()
        let source = try provider(service)
        let form = try ServerUIAdminTodoForm(provider: source, accessToken: { "synthetic" })
        let image = AdminTodoUpload.Image(data: Data([1]), filename: "image.png", mimeType: "image/png")
        try form.set(.string("Task"), group: "new", field: "name")
        try form.beginReadingImages()
        #expect(form.isBusy && !form.canSave)
        #expect(throws: ServerUIRecordFailure.busy) { try form.discard() }
        try form.finishReadingImages([image], failure: nil)
        try form.beginReadingImages()
        #expect(throws: ServerUIRecordFailure.self) { try form.finishReadingImages(Array(repeating: image, count: 5), failure: nil) }
        #expect(form.images == [image])
        #expect(!form.isBusy && form.error != nil)
        try await form.save()
        #expect(service.uploads.first?.images == [image])
        #expect(!form.hasChanges)
    }

    @Test func rejectsInvalidConfigurationAndUnauthorizedOperations() async throws {
        #expect(throws: ServerUITodoProvider.Failure.invalidTarget) {
            try ServerUITodoProvider.Configuration(entityId: "switch.demo_not_todo")
        }
        #expect(throws: ServerUITodoProvider.Failure.invalidTarget) {
            try ServerUITodoProvider.Configuration(entityId: "todo.example", completionScript: "script.demo_good\n")
        }
        let service = MockTodoService()
        service.items["todo.example"] = [item]
        let source = try provider(service, canDelete: false, canRename: false, attachments: false)
        try await source.load()
        #expect(throws: ServerUITodoProvider.Failure.forbidden) { try source.deleteTicket(expected: item) }
        await #expect(throws: ServerUITodoProvider.Failure.forbidden) { try await source.rename(identity: item.identity, name: "Name") }
        await #expect(throws: ServerUITodoProvider.Failure.emptyName) {
            try await source.add(name: "  ", accessToken: { "synthetic" })
        }
    }

    @Test func authoredCountsDoNotTurnMissingOrInvalidStatesIntoZero() {
        let config = ServerUICompositionDocument.TodoCounts(
            lists: [.init(entityId: "todo.demo_a", overdue: true), .init(entityId: "todo.demo_b", overdue: false)],
            openSuffix: "open", overdueSuffix: "late", separator: " / ", zeroText: "All clear",
            loadingText: "Loading", unavailableText: "Unavailable")
        var states = ["todo.demo_a": "2", "todo.demo_b": "1"]
        #expect(ServerUITodoCounts.text(configuration: config) { states[$0] } == "3 open / 2 late")
        states["todo.demo_a"] = "0"
        #expect(ServerUITodoCounts.text(configuration: config) { states[$0] } == "1 open")
        states["todo.demo_b"] = "0"
        #expect(ServerUITodoCounts.text(configuration: config) { states[$0] } == "All clear")
        states["todo.demo_b"] = "unavailable"
        #expect(ServerUITodoCounts.text(configuration: config) { states[$0] } == nil)
        states["todo.demo_a"] = "9007199254740991"
        states["todo.demo_b"] = "1"
        #expect(ServerUITodoCounts.text(configuration: config) { states[$0] } == nil)
    }

    @Test func configuredPeopleKeepOrderViewerAndUnknownAssignee() throws {
        let people = try ServerUITodoPeople(
            people: [.init(userId: "user-1", assignee: "1", name: "Alex"),
                     .init(userId: "user-2", assignee: "2", name: "Sam"),
                     .init(userId: nil, assignee: "3", name: "Projects")],
            anyone: "Anyone", viewer: "You", unknownPrefix: "Person")
        #expect(people.options(viewerUserId: "user-2", selected: "7") == [
            .init("Anyone", ""), .init("Alex", "1"), .init("You", "2"), .init("Projects", "3"), .init("Person 7", "7")
        ])
        #expect(throws: ServerUITodoPeople.Failure.invalidPerson) {
            try ServerUITodoPeople(people: [.init(userId: "same", assignee: "1", name: "A"),
                                            .init(userId: "same", assignee: "2", name: "B")],
                                   anyone: "Anyone", viewer: "You", unknownPrefix: "Person")
        }
    }
}
