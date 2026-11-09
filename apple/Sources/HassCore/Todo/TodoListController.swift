import Foundation
import Observation

// MARK: - Optimistic statuses

/// Checked-off state shown before Home Assistant confirms it (web `useTodoOptimisticStatuses`).
///
/// A pending status stays until a reload shows the item with that status (or without the item), the call
/// fails, or ``revertDelay`` passes.
public struct TodoOptimisticStatuses: Equatable, Sendable {
    struct Pending: Equatable, Sendable {
        var requestId: Int
        var status: TodoItem.Status
    }

    private(set) var pending: [String: Pending] = [:]
    private var lastRequestId = 0

    /// How long an unconfirmed status shows (web `TODO_OPTIMISTIC_REVERT_MS`).
    public static let revertDelay: Duration = .seconds(15)

    public init() {}

    /// Shows `status` for `identity` and returns the request id that owns it.
    public mutating func commit(_ identity: String, _ status: TodoItem.Status) -> Int {
        lastRequestId += 1
        pending[identity] = Pending(requestId: lastRequestId, status: status)
        return lastRequestId
    }

    /// Drops the pending status, only if `requestId` (when given) still owns it.
    public mutating func clear(_ identity: String, requestId: Int? = nil) {
        guard let current = pending[identity], requestId == nil || current.requestId == requestId else { return }
        pending[identity] = nil
    }

    /// Drops statuses the server now reports, or whose item is gone.
    public mutating func confirm(_ items: [TodoItem]) {
        for (identity, status) in pending {
            if let live = items.first(where: { $0.identity == identity }), live.status != status.status { continue }
            pending[identity] = nil
        }
    }

    /// `items` with pending statuses applied.
    public func apply(to items: [TodoItem]) -> [TodoItem] {
        guard !pending.isEmpty else { return items }
        return items.map { item in
            guard let status = pending[item.identity]?.status else { return item }
            var item = item
            item.status = status
            return item
        }
    }
}

// MARK: - List controller

/// One `todo` list's items: loading, optimistic check-off and errors (web `TodoListPanel`).
@MainActor
@Observable
public final class TodoListController: Identifiable {
    /// The list entity.
    public let entityId: String
    /// Items in due order, or `nil` until the first load (or cached copy).
    public private(set) var items: [TodoItem]?
    /// The last load or update error, in the web's words.
    public private(set) var error: String?
    /// Pending check-offs.
    public private(set) var optimistic = TodoOptimisticStatuses()
    /// Items checked off within the last ``undoGrace``: still listed, in their done look, with an Undo button (HIG
    /// Undo and redo: an easy action that removes content needs a way back; owner, 2026-10-24).
    public var recentlyCompleted: Set<String> { Set(recent.keys) }

    /// A just-ticked item as it was, and where it sat, so the row stays put (and stays at all) when the next reload no
    /// longer lists it: Home Assistant may drop a completed item, and the Admin To-Do script archives it.
    struct Recent: Equatable {
        var item: TodoItem
        var index: Int
    }

    private(set) var recent: [String: Recent] = [:]

    public nonisolated var id: String { entityId }

    private let service: any TodoServicing
    private let onItemsChange: (String, [TodoItem]) -> Void
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored var revertDelay = TodoOptimisticStatuses.revertDelay
    @ObservationIgnored var undoGrace = TodoListController.undoGrace.value
    /// Waits out a delay (the undo grace and the optimistic revert). Tests replace it with a clock they advance by hand.
    @ObservationIgnored var sleeper: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    @ObservationIgnored private var graceTasks: [String: Task<Void, Never>] = [:]

    /// How long a checked-off item stays listed with Undo (5 s; the `value` is writable so hosted accessibility tests, whose
    /// tree queries take seconds, can lengthen it before they open a page).
    public static let undoGrace = UndoGrace()

    /// The grace period, shared by controllers created after it changes.
    public final class UndoGrace: @unchecked Sendable {
        public var value: Duration = .seconds(5)
        init() {}
    }

    /// Creates a controller, optionally seeded with cached items.
    public init(entityId: String, service: any TodoServicing, cached: [TodoItem]? = nil,
                onItemsChange: @escaping (String, [TodoItem]) -> Void = { _, _ in }) {
        self.entityId = entityId
        self.service = service
        self.items = cached
        self.onItemsChange = onItemsChange
    }

    /// Items with pending check-offs applied, completed ones dropped when `hideCompleted` (except those checked off in the
    /// last ``undoGrace``, which stay for Undo).
    public func visibleItems(hideCompleted: Bool) -> [TodoItem] {
        let shown = optimistic.apply(to: items ?? [])
        guard hideCompleted else { return shown }
        var visible = shown.filter { $0.status != .completed || recent[$0.identity] != nil }
        for (identity, entry) in recent.sorted(by: { $0.value.index < $1.value.index }) where !shown.contains(where: { $0.identity == identity }) {
            var item = entry.item
            item.status = .completed
            visible.insert(item, at: min(entry.index, visible.count))
        }
        return visible
    }

    /// Whether `item` was just checked off and still offers Undo.
    public func offersUndo(_ item: TodoItem) -> Bool {
        recent[item.identity] != nil
    }

    /// Fetches the list. Overlapping loads keep only the newest answer.
    public func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        do {
            let fetched = TodoItem.sortedByDue(try await service.todoItems(entityId: entityId))
            guard generation == loadGeneration else { return }
            error = nil
            if items != fetched {
                items = fetched
                onItemsChange(entityId, fetched)
            }
            optimistic.confirm(fetched)
        } catch {
            guard generation == loadGeneration else { return }
            self.error = Self.message(error, fallback: "Unable to load list")
        }
    }

    /// Checks an item off (or back on), running `completionScript` instead of `todo.update_item` when completing.
    public func toggle(_ item: TodoItem, completionScript: String? = nil) async {
        let identity = item.identity
        guard !identity.isEmpty else { return }
        let next = optimistic.apply(to: [item])[0].status.toggled
        let index = visibleItems(hideCompleted: true).firstIndex { $0.identity == identity } ?? Int.max
        let requestId = optimistic.commit(identity, next)
        scheduleRevert(identity, requestId: requestId)
        if next == .completed { startGrace(item, index: index) } else { endGrace(identity) }
        do {
            if next == .completed, let completionScript {
                let script = completionScript.hasPrefix("script.") ? String(completionScript.dropFirst("script.".count)) : completionScript
                try await service.callService("script", script, data: ["item": identity])
            } else {
                try await service.callService("todo", "update_item", data: ["entity_id": entityId, "item": identity, "status": next.rawValue])
            }
            error = nil
        } catch {
            optimistic.clear(identity, requestId: requestId)
            endGrace(identity)
            self.error = Self.message(error, fallback: "Unable to update task")
        }
    }

    /// Removes an item (`todo.remove_item`). The row leaves at once and returns, with the error, if the call fails.
    public func remove(_ item: TodoItem) async {
        let identity = item.identity
        guard !identity.isEmpty, let before = items else { return }
        items = before.filter { $0.identity != identity }
        do {
            try await service.callService("todo", "remove_item", data: ["entity_id": entityId, "item": identity])
            error = nil
            if let items { onItemsChange(entityId, items) }
        } catch {
            items = before
            self.error = Self.message(error, fallback: "Unable to delete task")
        }
    }

    /// Reopens a task checked off a moment ago. Always `todo.update_item` with `needs_action`, also on lists that
    /// complete through a script (Admin To-Do has no reopen script).
    public func undo(_ item: TodoItem) async {
        guard optimistic.apply(to: [item])[0].status == .completed else { return }
        await toggle(item)
    }

    private func startGrace(_ item: TodoItem, index: Int) {
        let identity = item.identity
        recent[identity] = Recent(item: item, index: index)
        graceTasks[identity]?.cancel()
        let grace = undoGrace
        let sleeper = sleeper
        graceTasks[identity] = Task { [weak self] in
            try? await sleeper(grace)
            guard !Task.isCancelled else { return }
            self?.endGrace(identity)
        }
    }

    private func endGrace(_ identity: String) {
        graceTasks.removeValue(forKey: identity)?.cancel()
        recent[identity] = nil
    }

    private func scheduleRevert(_ identity: String, requestId: Int) {
        let delay = revertDelay
        let sleeper = sleeper
        Task { [weak self] in
            try? await sleeper(delay)
            self?.optimistic.clear(identity, requestId: requestId)
        }
    }

    /// A readable message for a failed call.
    public nonisolated static func message(_ error: any Error, fallback: String) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty { return localized }
        return fallback
    }
}

// MARK: - Store

/// The app's todo lists, one controller per list entity, shared by every page so lists keep their items
/// across navigation and relaunches (``TodoItemsCache``).
@MainActor
public final class TodoStore {
    private let service: any TodoServicing
    private let cache: TodoItemsCache?
    private var controllers: [String: TodoListController] = [:]
    private var cachedItems: [String: [TodoItem]]

    /// Creates a store over a service, restoring cached items.
    public init(service: any TodoServicing, cache: TodoItemsCache? = nil) {
        self.service = service
        self.cache = cache
        self.cachedItems = cache?.load() ?? [:]
    }

    /// The controller for a list entity; always the same one for the same id.
    public func controller(for entityId: String) -> TodoListController {
        if let controller = controllers[entityId] { return controller }
        let controller = TodoListController(entityId: entityId, service: service, cached: cachedItems[entityId]) { [weak self] id, items in
            self?.didLoad(id, items)
        }
        controllers[entityId] = controller
        return controller
    }

    private func didLoad(_ entityId: String, _ items: [TodoItem]) {
        cachedItems[entityId] = items
        try? cache?.save(cachedItems)
    }

    // MARK: Shared

    private static var registry: [ObjectIdentifier: (service: WeakService, store: TodoStore)] = [:]

    private struct WeakService { weak var value: (any TodoServicing)? }

    /// The store for a connection, created on first use and cached on disk next to the entity snapshot.
    public static func shared(for connection: HassConnection) -> TodoStore {
        registry = registry.filter { $0.value.service.value != nil }
        let key = ObjectIdentifier(connection)
        if let entry = registry[key] { return entry.store }
        let store = TodoStore(service: connection, cache: TodoItemsCache(server: connection.server))
        registry[key] = (WeakService(value: connection), store)
        return store
    }
}

// MARK: - Disk cache

/// Saves the last loaded items of every list so a cold launch shows them before the first fetch.
public struct TodoItemsCache: Sendable {
    private struct File: Codable {
        var version: Int
        var server: URL?
        var lists: [String: [TodoItem]]
    }

    private let fileURL: URL
    private let server: URL?

    /// Creates a cache for a server.
    /// - Parameter fileURL: Defaults to `Application Support/TodoItems.json`.
    public init(server: HassServer? = nil, fileURL: URL? = nil) {
        self.server = server?.baseURL
        self.fileURL = fileURL ?? Self.defaultURL
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "TodoItems.json")
    }

    /// The cached lists, or empty when missing or from another server.
    public func load() -> [String: [TodoItem]] {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.version == 1, file.server == server else { return [:] }
        return file.lists
    }

    /// Writes every list atomically with file protection.
    public func save(_ lists: [String: [TodoItem]]) throws {
        let data = try JSONEncoder().encode(File(version: 1, server: server, lists: lists))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }

    /// Deletes the cache (sign out).
    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
