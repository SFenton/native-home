import Foundation
import Observation

/// A configured list adapter. The shell owns its lifetime, presentation and drafts.
@MainActor
@Observable
public final class ServerUITodoProvider {
    // MARK: - Provider

    /// A failed or stale interaction must be reported by the host. Descriptions are fixed copy: a service failure's
    /// own text is carried for diagnostics but never described.
    public enum Failure: Error, Equatable, LocalizedError {
        case invalidTarget, invalidItem, staleConfirmation, busy, forbidden, emptyName, invalidAttachment(String), service(String)

        /// Fixed copy for each failure.
        public var errorDescription: String? {
            switch self {
            case .invalidTarget: "Invalid todo target"
            case .invalidItem: "This task is no longer available"
            case .staleConfirmation: "This task changed; confirm again"
            case .busy: "A task action is already in progress"
            case .forbidden: "This action is not available"
            case .emptyName: "Enter a task name"
            case .invalidAttachment(let message): message
            // The server's own text is never shown; the controller keeps it for diagnostics only.
            case .service: "The task service could not complete this action"
            }
        }
    }

    /// Immutable target and permissions selected by the author.
    public struct Configuration: Equatable, Sendable {
        /// The `todo` entity this provider reads and writes.
        public let entityId: String
        /// The script that completes a row, or `nil` for the stock `todo.update_item`. It must be the script the house
        /// document declares for this list; a document cannot introduce another.
        public let completionScript: String?
        /// Whether completed rows are hidden.
        public let hideCompleted: Bool
        /// Whether rows may be renamed.
        public let canRename: Bool
        /// Whether rows may be deleted after confirmation.
        public let canDelete: Bool
        /// Whether plain items may be added.
        public let canAdd: Bool
        /// Whether DoneTick tasks may be created.
        public let canCreateTask: Bool
        /// Whether DoneTick tasks may be edited.
        public let canEditTask: Bool
        /// Whether an added item may carry images; requires `canAdd`.
        public let allowsAttachments: Bool

        /// Creates a configuration, or throws ``Failure/invalidTarget`` for a non-`todo` entity, a completion script the house document does not declare for this list, or attachments without add.
        public init(entityId: String, completionScript: String? = nil, hideCompleted: Bool = true,
                    canRename: Bool = false, canDelete: Bool = false, canAdd: Bool = false,
                    canCreateTask: Bool = false, canEditTask: Bool = false, allowsAttachments: Bool = false) throws {
            guard Self.valid(entityId, domain: "todo"),
                  completionScript.map({ Self.valid($0, domain: "script") }) ?? true,
                  !allowsAttachments || canAdd else { throw Failure.invalidTarget }
            self.entityId = entityId
            self.completionScript = completionScript
            self.hideCompleted = hideCompleted
            self.canRename = canRename
            self.canDelete = canDelete
            self.canAdd = canAdd
            self.canCreateTask = canCreateTask
            self.canEditTask = canEditTask
            self.allowsAttachments = allowsAttachments
        }

        private static func valid(_ value: String, domain: String) -> Bool {
            value.utf16.count <= 160 &&
                value.range(of: "^\(domain)\\.[a-z0-9_]+$", options: .regularExpression) == value.startIndex..<value.endIndex
        }
    }

    /// A one-use confirmation pinned to the exact visible item and provider.
    public struct DeleteTicket: Equatable, Sendable {
        fileprivate let provider: UUID
        fileprivate let nonce: UUID
        fileprivate let item: TodoItem
    }

    /// A loaded DoneTick task and its original values, pinned to its list and row.
    public struct TaskEdit: Equatable, Sendable {
        fileprivate let provider: UUID
        fileprivate let nonce: UUID
        fileprivate let item: TodoItem
        /// The DoneTick task's id.
        public let taskId: Int
        /// The form as loaded, against which changes are diffed.
        public let initial: DonetickTaskForm
    }

    /// The provider's target and permissions.
    public let configuration: Configuration
    /// The shared controller that owns items, optimism and Undo.
    public let controller: TodoListController
    private let service: any TodoServicing
    private let providerID = UUID()
    private var tickets: Set<UUID> = []
    private var taskEdits: Set<UUID> = []
    /// Whether a command is in flight.
    public private(set) var hasPendingIntent = false
    /// A publication must not remove or retarget this provider while a command, confirmation or editor owns it.
    public var isPinned: Bool { hasPendingIntent || !tickets.isEmpty || !taskEdits.isEmpty }

    /// Creates a provider over the shared store and service.
    public init(configuration: Configuration, store: TodoStore, service: any TodoServicing) {
        self.configuration = configuration
        self.controller = store.controller(for: configuration.entityId)
        self.service = service
    }

    // MARK: - Reading

    /// Nil until the first load or cache; items retain the controller's optimistic and Undo behavior.
    public var items: [TodoItem]? {
        guard controller.items != nil else { return nil }
        return controller.visibleItems(hideCompleted: configuration.hideCompleted)
    }

    /// A host can show the controller's retained load/command failure alongside cached content.
    public var error: String? { controller.error }

    /// Loads the list. Throws the controller's failure with its cached rows still shown.
    public func load() async throws {
        try begin()
        defer { end() }
        await controller.load()
        try checkControllerError()
    }

    /// Reads a unique current row, rather than trusting a captured stale row or ambiguous key.
    private func current(_ identity: String) throws -> TodoItem {
        guard !identity.isEmpty, let items else { throw Failure.invalidItem }
        let matches = items.filter { $0.identity == identity }
        guard matches.count == 1, let item = matches.first else { throw Failure.invalidItem }
        return item
    }

    /// Validates a rendered row immediately before announcing or beginning an action.
    public func validate(expected: TodoItem) throws {
        guard !hasPendingIntent else { throw Failure.busy }
        guard try current(expected.identity) == expected else { throw Failure.invalidItem }
    }

    // MARK: - Row actions

    /// Completes or reopens the exact visible row, running the completion script when completing.
    public func toggle(expected: TodoItem) async throws {
        try begin()
        defer { end() }
        let item = try current(expected.identity)
        guard item == expected else { throw Failure.invalidItem }
        await controller.toggle(item, completionScript: configuration.completionScript)
        try checkControllerError()
    }

    /// Reverts a recent completion of the exact visible row.
    public func undo(expected: TodoItem) async throws {
        try begin()
        defer { end() }
        let item = try current(expected.identity)
        guard item == expected, controller.offersUndo(item) else { throw Failure.invalidItem }
        await controller.undo(item)
        try checkControllerError()
    }

    /// Issues a one-use confirmation for the exact visible row.
    public func deleteTicket(expected: TodoItem) throws -> DeleteTicket {
        guard configuration.canDelete else { throw Failure.forbidden }
        guard !hasPendingIntent else { throw Failure.busy }
        let item = try current(expected.identity)
        guard item == expected else { throw Failure.invalidItem }
        let ticket = DeleteTicket(provider: providerID, nonce: UUID(), item: item)
        tickets.insert(ticket.nonce)
        return ticket
    }

    /// Release a cancelled confirmation without issuing a command.
    public func cancelDelete(_ ticket: DeleteTicket) throws {
        guard ticket.provider == providerID, tickets.remove(ticket.nonce) != nil else { throw Failure.staleConfirmation }
    }

    /// Call only after the native destructive confirmation; revalidates the item and consumes the ticket.
    public func delete(confirmed ticket: DeleteTicket) async throws {
        try begin()
        defer { end() }
        guard configuration.canDelete, ticket.provider == providerID, tickets.remove(ticket.nonce) != nil,
              (try? current(ticket.item.identity)) == ticket.item else { throw Failure.staleConfirmation }
        await controller.remove(ticket.item)
        try checkControllerError()
    }

    /// Rename requires the stable server UID, matching the canonical admin editor.
    public func rename(identity: String, name: String) async throws {
        try begin()
        defer { end() }
        guard configuration.canRename else { throw Failure.forbidden }
        let item = try current(identity)
        guard let uid = item.uid, !uid.isEmpty else { throw Failure.invalidItem }
        let name = try Self.trimmed(name)
        try await service.callService("todo", "update_item", data: ["entity_id": configuration.entityId, "item": uid, "rename": name])
    }

    /// Adds a plain todo or an admin attachment upload using the existing canonical service.
    public func add(name: String, images: [AdminTodoUpload.Image] = [],
                    accessToken: @MainActor () async throws -> String) async throws {
        try begin()
        defer { end() }
        guard configuration.canAdd else { throw Failure.forbidden }
        let name = try Self.trimmed(name)
        if images.isEmpty {
            try await service.callService("todo", "add_item", data: ["entity_id": configuration.entityId, "item": name])
        } else {
            guard configuration.allowsAttachments else { throw Failure.forbidden }
            if let error = AdminTodoUpload.validationError(count: images.count, sizes: images.map(\.data.count), mimeTypes: images.map(\.mimeType)) {
                throw Failure.invalidAttachment(error)
            }
            try await service.uploadAdminTodo(AdminTodoUpload(entityId: configuration.entityId, item: name, images: images),
                                              accessToken: try await accessToken())
        }
    }

    // MARK: - DoneTick tasks

    /// Loads a task using the row's DoneTick identity; no global configuration is consulted.
    public func editTask(identity: String) async throws -> TaskEdit {
        try begin()
        defer { end() }
        guard configuration.canEditTask else { throw Failure.forbidden }
        let item = try current(identity)
        guard let taskId = item.donetickTaskId else { throw Failure.invalidItem }
        let response = try await service.callServiceForResponse("donetick", "get_task", data: [
            "config_entry_id": configuration.entityId, "task_id": taskId,
        ])
        let task = try DonetickTask(response: response)
        guard task.id == taskId, (try? current(identity)) == item else { throw Failure.invalidItem }
        let edit = TaskEdit(provider: providerID, nonce: UUID(), item: item, taskId: taskId,
                            initial: DonetickTaskForm(task: task))
        taskEdits.insert(edit.nonce)
        return edit
    }

    /// Release a closed task editor after its draft has been saved or explicitly discarded.
    public func closeTask(_ edit: TaskEdit) throws {
        guard edit.provider == providerID, taskEdits.remove(edit.nonce) != nil else { throw Failure.invalidItem }
    }

    /// Deletes the exact edited task after native confirmation, retaining the ticket on failure.
    public func deleteTask(_ edit: TaskEdit) async throws {
        try begin()
        defer { end() }
        guard configuration.canDelete, edit.provider == providerID, taskEdits.contains(edit.nonce),
              (try? current(edit.item.identity)) == edit.item else { throw Failure.staleConfirmation }
        await controller.remove(edit.item)
        try checkControllerError()
        taskEdits.remove(edit.nonce)
    }

    /// The canonical DoneTick form owns field semantics and its changed-field diff.
    public func saveTask(_ form: DonetickTaskForm, editing: TaskEdit? = nil) async throws {
        try begin()
        defer { end() }
        guard !form.trimmedName.isEmpty else { throw Failure.emptyName }
        if let editing {
            guard configuration.canEditTask else { throw Failure.forbidden }
            guard editing.provider == providerID, taskEdits.contains(editing.nonce),
                  (try? current(editing.item.identity)) == editing.item, form != editing.initial else { throw Failure.invalidItem }
            try await service.callService("donetick", "update_task_form",
                                          data: form.serviceData(initial: editing.initial, taskId: editing.taskId, configEntryId: configuration.entityId))
            taskEdits.remove(editing.nonce)
        } else {
            guard configuration.canCreateTask else { throw Failure.forbidden }
            try await service.callService("donetick", "create_task_form", data: form.serviceData())
        }
    }

    private static func trimmed(_ value: String) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw Failure.emptyName }
        return result
    }

    private func begin() throws {
        guard !hasPendingIntent else { throw Failure.busy }
        hasPendingIntent = true
    }

    private func end() { hasPendingIntent = false }
    private func checkControllerError() throws {
        if let error = controller.error { throw Failure.service(error) }
    }
}
