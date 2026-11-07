import Foundation
@testable import HassCore
import Testing

/// Serves canned items and records calls; set `failure` to make the next calls throw.
@MainActor
final class MockTodoService: TodoServicing {
    var items: [String: [TodoItem]] = [:]
    var calls: [String] = []
    var failure: (any Error)?
    var response: JSONValue = .null
    var uploads: [AdminTodoUpload] = []
    /// Suspends `todoItems` until resumed, to test overlapping loads.
    var gate: CheckedContinuation<Void, Never>?
    var holdsLoads = false

    struct Failure: Error, LocalizedError {
        var errorDescription: String? { "Server said no" }
    }

    func todoItems(entityId: String) async throws -> [TodoItem] {
        if holdsLoads { await withCheckedContinuation { continuation in MainActor.assumeIsolated { gate = continuation } } }
        if let failure { throw failure }
        return items[entityId, default: []]
    }

    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        calls.append("\(domain).\(service)")
        if let failure { throw failure }
        return response
    }

    func uploadAdminTodo(_ upload: AdminTodoUpload, accessToken: String) async throws {
        if let failure { throw failure }
        uploads.append(upload)
    }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        let described = data.keys.sorted().map { "\($0)=\(data[$0]!)" }.joined(separator: ",")
        calls.append("\(domain).\(service) \(described)")
        if let failure { throw failure }
    }
}

@MainActor
struct TodoListControllerTests {
    private let list = "todo.demo_list"

    private func controller(_ service: MockTodoService, cached: [TodoItem]? = nil, onChange: @escaping (String, [TodoItem]) -> Void = { _, _ in }) -> TodoListController {
        TodoListController(entityId: list, service: service, cached: cached, onItemsChange: onChange)
    }

    @Test func loadSortsAndReportsChanges() async {
        let service = MockTodoService()
        service.items[list] = [TodoItem(uid: "b", summary: "B"), TodoItem(uid: "a", summary: "A", due: "2026-01-01")]
        var changes = 0
        let controller = controller(service) { _, _ in changes += 1 }
        #expect(controller.items == nil)
        #expect(controller.id == list)
        await controller.load()
        #expect(controller.items?.map(\.identity) == ["a", "b"])
        await controller.load()
        #expect(changes == 1, "An unchanged reload does not republish")
    }

    @Test func loadErrorKeepsItems() async {
        let service = MockTodoService()
        let controller = controller(service, cached: [TodoItem(uid: "a", summary: "A")])
        service.failure = MockTodoService.Failure()
        await controller.load()
        #expect(controller.error == "Server said no")
        #expect(controller.items?.count == 1)
        service.failure = nil
        await controller.load()
        #expect(controller.error == nil)
    }

    @Test func messageFallsBackForPlainErrors() {
        struct Plain: Error {}
        #expect(TodoListController.message(Plain(), fallback: "Unable") == "Unable")
    }

    @Test func overlappingLoadsKeepTheNewest() async {
        let service = MockTodoService()
        service.items[list] = [TodoItem(uid: "old", summary: "Old")]
        service.holdsLoads = true
        let controller = controller(service)
        let first = Task { await controller.load() }
        while service.gate == nil { await Task.yield() }
        let firstGate = service.gate
        service.gate = nil
        service.items[list] = [TodoItem(uid: "new", summary: "New")]
        let second = Task { await controller.load() }
        while service.gate == nil { await Task.yield() }
        service.gate?.resume()
        await second.value
        firstGate?.resume()
        await first.value
        #expect(controller.items?.map(\.identity) == ["new"])
    }

    @Test func toggleShowsOptimisticStatusThenConfirms() async {
        let service = MockTodoService()
        let item = TodoItem(uid: "a", summary: "A")
        service.items[list] = [item]
        let controller = controller(service)
        await controller.load()
        controller.undoGrace = .milliseconds(20)
        await controller.toggle(item)
        #expect(service.calls == ["todo.update_item entity_id=todo.demo_list,item=a,status=completed"])
        #expect(controller.visibleItems(hideCompleted: true).first?.status == .completed, "Listed for the undo grace")
        for _ in 0..<200 where !controller.visibleItems(hideCompleted: true).isEmpty { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.visibleItems(hideCompleted: true).isEmpty, "Gone once the grace ends")
        #expect(controller.visibleItems(hideCompleted: false).first?.status == .completed)
        service.items[list] = [TodoItem(uid: "a", summary: "A", status: .completed)]
        await controller.load()
        #expect(controller.optimistic.pending.isEmpty)
        // Unchecking a completed item sends needs_action.
        await controller.toggle(controller.items![0])
        #expect(service.calls.last == "todo.update_item entity_id=todo.demo_list,item=a,status=needs_action")
    }

    @Test func completionScriptRunsInsteadOfUpdate() async {
        let service = MockTodoService()
        let controller = controller(service)
        await controller.toggle(TodoItem(uid: "a", summary: "A"), completionScript: "script.demo_script_1")
        await controller.toggle(TodoItem(uid: "b", summary: "B"), completionScript: "demo_finish")
        #expect(service.calls == ["script.demo_script_1 item=a", "script.demo_finish item=b"])
        await controller.toggle(TodoItem(uid: "c", summary: "C", status: .completed), completionScript: "demo_finish")
        #expect(service.calls.last == "todo.update_item entity_id=todo.demo_list,item=c,status=needs_action")
    }

    @Test func failedToggleRevertsAndShowsError() async {
        let service = MockTodoService()
        service.failure = MockTodoService.Failure()
        let item = TodoItem(uid: "a", summary: "A")
        let controller = controller(service, cached: [item])
        await controller.toggle(item)
        #expect(controller.visibleItems(hideCompleted: true) == [item])
        #expect(controller.error == "Server said no")
    }

    /// A swipe-to-delete removes the row at once, calls `todo.remove_item` and caches the shorter list.
    @Test func removeDropsTheRowAndCallsRemoveItem() async {
        let service = MockTodoService()
        let a = TodoItem(uid: "a", summary: "A"), b = TodoItem(uid: "b", summary: "B")
        var cached: [TodoItem] = []
        let controller = controller(service, cached: [a, b]) { _, items in cached = items }
        await controller.remove(a)
        #expect(controller.items == [b])
        #expect(cached == [b])
        #expect(service.calls == ["todo.remove_item entity_id=todo.demo_list,item=a"])
        #expect(controller.error == nil)
    }

    /// A rejected delete puts the row back with the error, like a rejected check-off.
    @Test func failedRemoveBringsTheRowBack() async {
        let service = MockTodoService()
        service.failure = MockTodoService.Failure()
        let a = TodoItem(uid: "a", summary: "A")
        let controller = controller(service, cached: [a])
        await controller.remove(a)
        #expect(controller.items == [a])
        #expect(controller.error == "Server said no")
        await controller.remove(TodoItem(uid: nil, summary: nil))
        #expect(service.calls.count == 1, "An item without an identity sends nothing")
    }

    @Test func toggleIgnoresItemsWithoutIdentity() async {
        let service = MockTodoService()
        await controller(service).toggle(TodoItem(uid: nil, summary: nil))
        #expect(service.calls.isEmpty)
    }

    /// A checked-off item stays listed, done, with Undo for the grace period; Undo reopens it.
    @Test func aTickedItemStaysListedWithUndo() async {
        let service = MockTodoService()
        let item = TodoItem(uid: "a", summary: "A"), other = TodoItem(uid: "b", summary: "B", status: .completed)
        service.items[list] = [item, other]
        let controller = controller(service)
        await controller.load()
        await controller.toggle(item)
        #expect(controller.offersUndo(item))
        #expect(!controller.offersUndo(other), "An item completed elsewhere has no Undo")
        #expect(controller.visibleItems(hideCompleted: true).map(\.identity) == ["a"])
        await controller.undo(item)
        #expect(!controller.offersUndo(item))
        #expect(service.calls.last == "todo.update_item entity_id=todo.demo_list,item=a,status=needs_action")
        #expect(controller.visibleItems(hideCompleted: true).first?.status == .needsAction)
        await controller.undo(item)
        #expect(service.calls.count == 2, "Undo on an open item sends nothing")
    }

    /// The next reload may no longer list a completed item (the Admin To-Do script archives it); the row stays where it was.
    @Test func aTickedRowSurvivesAReloadThatDropsIt() async {
        let service = MockTodoService()
        let a = TodoItem(uid: "a", summary: "A"), b = TodoItem(uid: "b", summary: "B"), c = TodoItem(uid: "c", summary: "C")
        service.items[list] = [a, b, c]
        let controller = controller(service)
        await controller.load()
        await controller.toggle(b)
        service.items[list] = [a, c]
        await controller.load()
        #expect(controller.visibleItems(hideCompleted: true).map(\.identity) == ["a", "b", "c"])
        #expect(controller.visibleItems(hideCompleted: true)[1].status == .completed)
        await controller.undo(controller.visibleItems(hideCompleted: true)[1])
        #expect(controller.visibleItems(hideCompleted: true).map(\.identity) == ["a", "c"])
    }

    /// Rapid ticking keeps every row for its own grace period.
    @Test func eachTickKeepsItsOwnGrace() async throws {
        let service = MockTodoService()
        let a = TodoItem(uid: "a", summary: "A"), b = TodoItem(uid: "b", summary: "B")
        let controller = controller(service, cached: [a, b])
        controller.undoGrace = .milliseconds(60)
        await controller.toggle(a)
        try await Task.sleep(for: .milliseconds(30))
        await controller.toggle(b)
        #expect(controller.recentlyCompleted == ["a", "b"])
        for _ in 0..<300 where controller.recentlyCompleted.contains("a") { try await Task.sleep(for: .milliseconds(5)) }
        #expect(controller.recentlyCompleted == ["b"], "A's grace ended without ending B's")
        await controller.toggle(b)
        await controller.toggle(b)
        #expect(controller.offersUndo(b), "Ticking again restarts the grace")
    }

    /// The Admin To-Do completes through a script but Undo calls `todo.update_item` directly.
    @Test func undoAfterAScriptCompletionCallsUpdateItem() async {
        let service = MockTodoService()
        let item = TodoItem(uid: "a", summary: "A")
        let controller = controller(service, cached: [item])
        await controller.toggle(item, completionScript: "script.demo_script_1")
        #expect(controller.offersUndo(item))
        await controller.undo(item)
        #expect(service.calls == ["script.demo_script_1 item=a", "todo.update_item entity_id=todo.demo_list,item=a,status=needs_action"])
    }

    @Test func aFailedTickDoesNotOfferUndo() async {
        let service = MockTodoService()
        service.failure = MockTodoService.Failure()
        let item = TodoItem(uid: "a", summary: "A")
        let controller = controller(service, cached: [item])
        await controller.toggle(item)
        #expect(!controller.offersUndo(item))
    }

    /// Yields until `condition` holds, giving up after a bounded number of turns so a regression fails instead of hanging.
    private func spin(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<10_000 {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    /// Fails if: the optimistic status is dropped before the revert delay elapses, is never dropped once it does, or the
    /// undo grace and the revert delay are not waited out separately. Driven by a hand-advanced clock, so no wall time
    /// is involved and a busy machine cannot flip it.
    @Test func unconfirmedStatusRevertsAfterTheDelay() async {
        let service = MockTodoService()
        let item = TodoItem(uid: "a", summary: "A")
        let controller = controller(service, cached: [item])
        let clock = ManualSleeper()
        controller.sleeper = { await clock.sleep(for: $0) }
        controller.revertDelay = .seconds(15)
        controller.undoGrace = .seconds(5)
        await controller.toggle(item)
        #expect(await spin { clock.waiting.count >= 2 }, "the grace and the revert delay each park a sleep")
        #expect(Set(clock.waiting.map(\.duration)) == [.seconds(5), .seconds(15)])
        #expect(controller.visibleItems(hideCompleted: true).count == 1, "Within the grace the ticked row stays")
        clock.fire(duration: .seconds(5))
        #expect(await spin { !controller.offersUndo(item) }, "the grace ended")
        #expect(controller.visibleItems(hideCompleted: true).isEmpty, "The tick shows until the revert delay passes")
        clock.fire(duration: .seconds(15))
        #expect(await spin { !controller.visibleItems(hideCompleted: true).isEmpty }, "the revert brought the row back")
        #expect(controller.visibleItems(hideCompleted: true) == [item])
    }
}

/// A sleep the test finishes by hand: each call parks until ``fire(duration:)`` resumes it.
@MainActor
final class ManualSleeper {
    struct Waiter {
        var duration: Duration
        var continuation: CheckedContinuation<Void, Never>
    }

    private(set) var waiting: [Waiter] = []

    func sleep(for duration: Duration) async {
        await withCheckedContinuation { continuation in
            waiting.append(Waiter(duration: duration, continuation: continuation))
        }
    }

    /// Resumes every parked sleep of `duration`.
    func fire(duration: Duration) {
        let due = waiting.filter { $0.duration == duration }
        waiting.removeAll { $0.duration == duration }
        for waiter in due { waiter.continuation.resume() }
    }
}

struct TodoOptimisticStatusesTests {
    @Test func newerRequestsOwnTheStatus() {
        var statuses = TodoOptimisticStatuses()
        let first = statuses.commit("a", .completed)
        let second = statuses.commit("a", .needsAction)
        statuses.clear("a", requestId: first)
        #expect(statuses.pending["a"]?.status == .needsAction)
        statuses.clear("a", requestId: second)
        #expect(statuses.pending.isEmpty)
        _ = statuses.commit("b", .completed)
        statuses.clear("b")
        #expect(statuses.pending.isEmpty)
        statuses.clear("missing")
    }

    @Test func confirmDropsMatchedAndMissingItems() {
        var statuses = TodoOptimisticStatuses()
        _ = statuses.commit("done", .completed)
        _ = statuses.commit("waiting", .completed)
        _ = statuses.commit("gone", .completed)
        statuses.confirm([TodoItem(uid: "done", summary: nil, status: .completed), TodoItem(uid: "waiting", summary: nil)])
        #expect(Array(statuses.pending.keys) == ["waiting"])
        let applied = statuses.apply(to: [TodoItem(uid: "waiting", summary: nil), TodoItem(uid: "other", summary: nil)])
        #expect(applied.map(\.status) == [.completed, .needsAction])
        #expect(TodoOptimisticStatuses().apply(to: applied) == applied)
    }
}

@MainActor
struct TodoStoreTests {
    private func temporaryCache(server: HassServer? = .example) -> (TodoItemsCache, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: "todo-\(UUID()).json")
        return (TodoItemsCache(server: server, fileURL: url), url)
    }

    @Test func controllersAreSharedAndLoadsAreCached() async throws {
        let (cache, url) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: url) }
        let service = MockTodoService()
        service.items["todo.demo_a"] = [TodoItem(uid: "1", summary: "One")]
        let store = TodoStore(service: service, cache: cache)
        #expect(store.controller(for: "todo.demo_a") === store.controller(for: "todo.demo_a"))
        await store.controller(for: "todo.demo_a").load()
        #expect(cache.load()["todo.demo_a"]?.first?.summary == "One")
        // A new store (relaunch) starts from the cache.
        let relaunched = TodoStore(service: service, cache: cache)
        #expect(relaunched.controller(for: "todo.demo_a").items?.count == 1)
    }

    @Test func cacheIgnoresOtherServersAndClears() throws {
        let (cache, url) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: url) }
        try cache.save(["todo.demo_a": [TodoItem(uid: "1", summary: "One")]])
        #expect(cache.load().count == 1)
        let other = TodoItemsCache(server: HassServer(baseURL: URL(string: "https://example.com")!), fileURL: url)
        #expect(other.load().isEmpty)
        cache.clear()
        #expect(cache.load().isEmpty)
        #expect(TodoItemsCache.defaultURL.lastPathComponent == "TodoItems.json")
        #expect(TodoItemsCache().load() == TodoItemsCache().load())
    }
}
