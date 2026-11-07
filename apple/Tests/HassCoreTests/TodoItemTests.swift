import Foundation
@testable import HassCore
import Testing

struct TodoItemTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(due: TimeInterval?) -> TodoItem {
        TodoItem(uid: "1", summary: "Task", due: due.map { ISO8601DateFormatter().string(from: now.addingTimeInterval($0)) })
    }

    @Test func parsesTheWebsocketShape() throws {
        let json = JSONValue.object([
            "uid": .string("42--2026-10-11"), "summary": .string("Mow"), "status": .string("completed"),
            "description": .string("Front"), "due": .string("2026-10-11"),
        ])
        let parsed = try #require(TodoItem(json: json))
        #expect(parsed == TodoItem(uid: "42--2026-10-11", summary: "Mow", status: .completed, description: "Front", due: "2026-10-11"))
        #expect(parsed.donetickTaskId == 42)
        #expect(parsed.id == "42--2026-10-11")
        #expect(TodoItem(json: .string("x")) == nil)
        let preferDateTime = TodoItem(json: .object(["summary": .string("A"), "due_datetime": .string("2026-10-11T08:00:00Z"), "due": .string("2026-10-11")]))
        #expect(preferDateTime?.due == "2026-10-11T08:00:00Z")
        #expect(TodoItem(json: .object(["due_date": .string("2026-10-12")]))?.due == "2026-10-12")
        #expect(TodoItem(json: .object(["status": .string("weird")]))?.status == .needsAction)
    }

    @Test func identityFallsBackToSummary() {
        #expect(TodoItem(uid: nil, summary: "Milk").identity == "Milk")
        #expect(TodoItem(uid: nil, summary: nil).identity == "")
        #expect(TodoItem(uid: "abc", summary: "Milk").donetickTaskId == nil)
        #expect(TodoItem(uid: "0--x", summary: nil).donetickTaskId == nil)
        #expect(TodoItem(uid: nil, summary: nil).donetickTaskId == nil)
        #expect(TodoItem.Status.completed.toggled == .needsAction)
        #expect(TodoItem.Status.needsAction.toggled == .completed)
    }

    @Test func parsesDueShapes() throws {
        let utcMidnight = try #require(TodoItem.parseDue("2026-10-11"))
        #expect(utcMidnight == ISO8601DateFormatter().date(from: "2026-10-11T00:00:00Z"))
        #expect(TodoItem.parseDue("2026-10-11T08:00:00.250Z") != nil)
        #expect(TodoItem.parseDue("2026-10-11T08:00:00-07:00") == ISO8601DateFormatter().date(from: "2026-10-11T15:00:00Z"))
        #expect(TodoItem.parseDue("2026-10-11T08:00:00") != nil)
        #expect(TodoItem.parseDue("2026-xx-11") == nil)
        #expect(TodoItem.parseDue("tomorrow") == nil)
    }

    @Test func dueLabelsMatchTheWeb() {
        let hour = 3600.0, day = 86_400.0
        #expect(item(due: nil).dueLabel(now: now) == nil)
        #expect(item(due: 3 * hour).dueLabel(now: now)?.text == "Due in 3 hours")
        #expect(item(due: 3 * hour).dueLabel(now: now)?.tone == .future)
        #expect(item(due: 1 * day).dueLabel(now: now)?.text == "Due in 1 day")
        #expect(item(due: -2 * hour).dueLabel(now: now)?.text == "2 hours overdue")
        #expect(item(due: -2 * hour).dueLabel(now: now)?.tone == .overdueHours)
        #expect(item(due: -9 * day).dueLabel(now: now)?.text == "9 days overdue")
        #expect(item(due: -9 * day).dueLabel(now: now)?.tone == .overdueLong)
        #expect(item(due: 30 * day).dueLabel(now: now)?.text == "Due in 4 weeks")
        #expect(item(due: 75 * day).dueLabel(now: now)?.text == "Due in 3 months")
        #expect(item(due: 60).dueLabel(now: now)?.text == "Due in 1 hour")
    }

    @Test func batteryTasksShowTheirLevel() {
        let description = "Front door lock battery is at 18%. Maintenance reference: BATT-FD01"
        #expect(TodoItem(uid: "1", summary: "replace BATTERY", description: description).displayTitle == "replace Battery · 18%")
        #expect(TodoItem(uid: "1", summary: "Replace batteries (18%)", description: description).displayTitle == "Replace Batteries (18%)")
        #expect(TodoItem(uid: "1", summary: "Battery · 18%", description: description).displayTitle == "Battery · 18%")
        #expect(TodoItem(uid: "1", summary: "Replace battery", description: "battery is at 18%").displayTitle == "Replace battery")
        #expect(TodoItem(uid: "1", summary: "  ", description: nil).displayTitle == "Untitled task")
        #expect(TodoItem(uid: "1", summary: "Check", description: "Maintenance reference: BATT-X1").displayTitle == "Check")
    }

    @Test func sortsByDueWithUndatedLast() {
        let undatedA = TodoItem(uid: "a", summary: "A")
        let late = item(due: 100)
        let early = TodoItem(uid: "e", summary: "E", due: ISO8601DateFormatter().string(from: now))
        let undatedB = TodoItem(uid: "b", summary: "B")
        let sameAsLate = TodoItem(uid: "s", summary: "S", due: late.due)
        #expect(TodoItem.sortedByDue([undatedA, late, undatedB, early, sameAsLate]).map(\.identity) == ["e", "1", "s", "a", "b"])
    }
}

/// ``TodoItem/DueDateCache``: each due string is parsed once (a scrolling page asked for them every pass).
struct DueDateCacheTests {
    @Test func parsesOncePerStringAndAgreesWithTheParser() {
        let cache = TodoItem.DueDateCache()
        let value = "2026-10-11T08:30:00Z"
        #expect(cache.date(for: value) == TodoItem.parseDue(value))
        #expect(cache.date(for: value) == TodoItem.parseDue(value))
        #expect(cache.count == 1)
        #expect(cache.date(for: "not a date") == nil)
        #expect(cache.date(for: "not a date") == nil)
        #expect(cache.count == 2, "A string that doesn't parse is remembered too")
    }

    @Test func startsOverWhenTheTimeZoneChanges() {
        let cache = TodoItem.DueDateCache()
        _ = cache.date(for: "2026-10-11T08:00:00", zone: "Europe/London")
        _ = cache.date(for: "2026-10-12T08:00:00", zone: "Europe/London")
        #expect(cache.count == 2)
        _ = cache.date(for: "2026-10-11T08:00:00", zone: "America/Los_Angeles")
        #expect(cache.count == 1, "zone-less date-times read in the new zone, so the old parses are dropped")
    }

    @Test func startsOverWhenItOutgrowsItsLimit() {
        let cache = TodoItem.DueDateCache()
        for day in 0...TodoItem.DueDateCache.limit { _ = cache.date(for: "2026-01-01T00:00:\(day)Z") }
        #expect(cache.count <= TodoItem.DueDateCache.limit)
    }
}
