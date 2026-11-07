#if DEBUG
import Foundation
import HassCore
import HassDesign
import SwiftUI

/// Fixture todo lists keyed by entity id, due dates relative to now.
enum ChoresFixtures {
    static func iso(_ offset: TimeInterval, from now: Date = .now) -> String {
        ISO8601DateFormatter().string(from: now.addingTimeInterval(offset))
    }

    /// The page whose lists ``lists(now:extra:)`` pads with extra chores: the demo house's first resident.
    static let firstResidentPageId = "alexs-chores"

    /// - Parameter extra: More chores for each list of the first resident's page (a house as long as a real one, for the scroll cost probe).
    static func lists(now: Date = .now, extra: Int = 0) -> [String: [TodoItem]] {
        let hour = 3600.0, day = 86_400.0
        func task(_ id: Int, _ summary: String, due: TimeInterval?, description: String? = nil) -> TodoItem {
            TodoItem(uid: "\(id)--fixture", summary: summary, description: description, due: due.map { iso($0, from: now) })
        }
        var lists: [String: [TodoItem]] = [
            "todo.demo_todo_3": [task(11, "Take out the recycling", due: -3 * hour), task(12, "Clean the gutters", due: -9 * day)],
            "todo.demo_todo_4": [task(13, "Run the dishwasher", due: 5 * hour)],
            "todo.demo_todo_8": [
                task(14, "Replace battery", due: nil, description: "Front door lock battery is at 18%. Maintenance reference: BATT-FD01"),
            ],
            "todo.demo_todo_14": [task(15, "Water the plants", due: 2 * day)],
            "todo.demo_todo_2": [
                TodoItem(uid: "g1", summary: "Oat milk"), TodoItem(uid: "g2", summary: "Coffee beans"), TodoItem(uid: "g3", summary: "Lemons"),
            ],
            // A resident's page reads the `_with_unassigned` views, which hold the same chores here.
            "todo.demo_todo_16": [task(13, "Run the dishwasher", due: 5 * hour)],
            "todo.demo_todo_17": [task(15, "Water the plants", due: 2 * day)],
            "todo.demo_todo_19": [task(21, "Fold laundry", due: 3 * hour)],
            "todo.demo_todo_20": [task(22, "Book the vet", due: 30 * day)],
            "todo.demo_todo_9": [task(21, "Fold laundry", due: 3 * hour)],
            "todo.demo_todo_15": [task(22, "Book the vet", due: 30 * day)],
            "todo.demo_todo_21": [task(31, "Vacuum the stairs", due: -2 * day)],
            "todo.demo_todo_24": [task(32, "Organize the garage", due: nil)],
            "todo.demo_todo_27": [task(41, "Paint the deck", due: 75 * day)],
            "todo.demo_todo_1": [TodoItem(uid: "a1", summary: "Port the Chores page"), TodoItem(uid: "a2", summary: "Check the backup job")],
        ]
        let paddedKeys = Set(ChoresConfig.page(firstResidentPageId)?.lists.map(\.entityId) ?? [])
        for key in lists.keys where extra > 0 && paddedKeys.contains(key) {
            // Alternating overdue and upcoming, so the page shows both due-label tones.
            lists[key, default: []] += (0..<extra).map { n in
                task(1000 + n, "Fixture chore \(n + 1)", due: n.isMultiple(of: 2) ? -Double(n + 1) * day : Double(n + 1) * day)
            }
        }
        return lists
    }

    /// A `donetick.get_task` response for a fixture task.
    static func task(id: Int, name: String) -> JSONValue {
        .object([
            "id": .number(Double(id)), "name": .string(name), "description": .string("Fixture task"),
            "assignees": .array([.number(1)]), "assigned_to": .number(1), "frequency": .number(1),
            "frequency_type": .string("weekly"), "frequency_metadata": .object([:]), "hide_on_vacation": .bool(true),
            "next_due_date": .string(iso(2 * 86_400)), "priority": .number(3),
        ])
    }
}

/// Serves fixture lists and records calls, applying check-offs, adds and renames like Home Assistant would.
@MainActor
@Observable
final class ChoresFixtureService: TodoServicing {
    private(set) var lastCall = "none"
    private var lists: [String: [TodoItem]]
    private let store: EntityStore
    private var nextId = 100
    /// Check-offs fail after 4 s (the optimistic rollback journey).
    private let failsCompletion: Bool

    /// A call the fixture refuses.
    struct Refused: Error {}

    init(store: EntityStore, lists: [String: [TodoItem]], failsCompletion: Bool = false) {
        self.store = store
        self.lists = lists
        self.failsCompletion = failsCompletion
    }

    /// Entities other galleries keep alongside the lists (people, sensors, Vacation Mode), so a check-off's refresh of the
    /// list counts doesn't drop them. A state here replaces the default for the same entity id.
    var extraStates: [EntityState] = []

    /// One entity per configured list; its state is the open-item count, like Home Assistant's todo entities.
    func entityStates() -> [EntityState] {
        let ids = Set(ChoresConfig.pages.flatMap(\.lists).map(\.entityId))
            .union(ChoresConfig.Resident.allCases.flatMap { ProfileSummary.lists(for: $0).all.map(\.entityId) })
        let extras = Set(extraStates.map(\.entityId))
        let defaults = ids.filter { !extras.contains($0) }.map { EntityState(entityId: $0, state: String(openCount(entityId: $0))) }
            + (extras.contains(ChoresConfig.vacationModeEntityId) ? [] : [EntityState(entityId: ChoresConfig.vacationModeEntityId, state: "off")])
        return defaults + extraStates
    }

    /// Open items on a list.
    func openCount(entityId: String) -> Int {
        lists[entityId, default: []].filter { $0.status != .completed }.count
    }

    func todoItems(entityId: String) async throws -> [TodoItem] { lists[entityId, default: []] }

    func callServiceForResponse(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        lastCall = "\(domain).\(service)"
        // `FENTON_GALLERY_TASK_DELAY=<seconds>` slows `donetick.get_task`, so the Edit Task sheet's loading sequence can be watched.
        if let delay = ProcessInfo.processInfo.environment["FENTON_GALLERY_TASK_DELAY"].flatMap(Double.init), delay > 0 {
            try await Task.sleep(for: .seconds(delay))
        }
        let id = data["task_id"] as? Int ?? 0
        let name = lists.values.joined().first { $0.donetickTaskId == id }?.summary ?? "Task"
        return .object(["response": ChoresFixtures.task(id: id, name: name)])
    }

    func uploadAdminTodo(_ upload: AdminTodoUpload, accessToken: String) async throws {
        lastCall = "upload \(upload.item) (\(upload.images.count) images)"
        add(upload.item, to: upload.entityId)
    }

    func callService(_ domain: String, _ service: String, data: [String: any Sendable]) async throws {
        let entityId = data["entity_id"] as? String ?? ""
        let item = data["item"] as? String ?? ""
        lastCall = "\(domain).\(service) \(item)".trimmingCharacters(in: .whitespaces)
        switch (domain, service) {
        case ("todo", "update_item"):
            if failsCompletion, data["status"] as? String == "completed" {
                // Long enough for the row to be seen leaving before it comes back.
                try await Task.sleep(for: .seconds(4))
                lastCall += " failed"
                throw Refused()
            }
            if let status = (data["status"] as? String).flatMap(TodoItem.Status.init(rawValue:)) { update(entityId, item) { $0.status = status } }
            if let rename = data["rename"] as? String { update(entityId, item) { $0.summary = rename } }
        case ("todo", "add_item"):
            add(item, to: entityId)
        case ("todo", "remove_item"):
            lists[entityId]?.removeAll { $0.identity == item }
        case ("script", _):
            update(ChoresConfig.adminTodoEntityId, item) { $0.status = .completed }
        default:
            break
        }
        store.replaceAll(entityStates())
    }

    private func add(_ summary: String, to entityId: String) {
        nextId += 1
        lists[entityId, default: []].append(TodoItem(uid: "new-\(nextId)", summary: summary))
        store.replaceAll(entityStates())
    }

    private func update(_ entityId: String, _ identity: String, _ change: (inout TodoItem) -> Void) {
        guard let index = lists[entityId]?.firstIndex(where: { $0.identity == identity }) else { return }
        change(&lists[entityId]![index])
    }
}
#endif
