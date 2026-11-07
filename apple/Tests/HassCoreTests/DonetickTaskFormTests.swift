import Foundation
@testable import HassCore
import HassTestSupport
import Testing

@Suite(.demoHouse)
struct DonetickTaskFormTests {
    @Test func newFormsUseTheWebDefaults() {
        let form = DonetickTaskForm(defaultAssignee: "2")
        #expect(form.assignee == "2")
        #expect(form.priority == "critical")
        #expect(form.recurrence == "no_repeat")
        #expect(form.hideOnVacation)
        #expect(!form.showsCustomInterval && !form.showsRecurrenceDays)
    }

    @Test func assigneesNameTheViewerYou() {
        var form = DonetickTaskForm()
        #expect(form.assignees(viewer: .resident2).map(\.label) == ["Anyone", "Alex", "You", "Home Improvement"])
        #expect(form.assignees(viewer: nil).map(\.value) == ["", "1", "2", "3"])
        form.assignee = "9"
        #expect(form.assignees(viewer: nil).last == .init("User 9", "9"))
        #expect(form.assignees(viewer: nil).last?.id == "9")
    }

    @Test func recurrenceEditingRules() {
        var form = DonetickTaskForm()
        #expect(DonetickTaskForm.recurrences(editing: false).count == 7)
        #expect(DonetickTaskForm.recurrences(editing: true).last?.value == "adaptive")
        form.setRecurrence("days_of_the_week")
        form.toggleDay("friday")
        form.toggleDay("monday")
        #expect(form.recurrenceDays == ["monday", "friday"])
        form.toggleDay("friday")
        #expect(form.recurrenceDays == ["monday"])
        form.setRecurrence("days_of_the_week")
        #expect(form.recurrenceDays == ["monday"])
        form.setRecurrence("weekly")
        #expect(form.recurrenceDays.isEmpty)
    }

    @Test func repeatEveryKeepsDigitsAndClamps() {
        var form = DonetickTaskForm()
        form.setRepeatEvery("4a0")
        #expect(form.recurrenceInterval == "40")
        form.setRepeatEvery("999")
        form.normalizeRepeatEvery()
        #expect(form.recurrenceInterval == "365")
        form.setRepeatEvery("")
        form.normalizeRepeatEvery()
        #expect(form.recurrenceInterval == "1")
        form.setRepeatEvery("0")
        form.normalizeRepeatEvery()
        #expect(form.recurrenceInterval == "1")
    }

    @Test func dueValueCombinesDateAndTime() {
        var form = DonetickTaskForm()
        #expect(form.dueValue == "")
        form.dueTime = "08:30"
        #expect(form.dueValue == "08:30:00")
        form.dueDate = "2026-10-11"
        #expect(form.dueValue == "2026-10-11T08:30:00")
        form.dueTime = ""
        #expect(form.dueValue == "2026-10-11T12:00:00")
        form.dueTime = "08:30:15"
        #expect(form.dueValue == "2026-10-11T08:30:15")
    }

    @Test func createDataSendsEveryField() {
        var form = DonetickTaskForm(defaultAssignee: "1")
        form.name = "  Mow  "
        form.setRecurrence("interval")
        form.setRepeatEvery("3")
        form.recurrenceUnit = "weeks"
        let data = form.serviceData()
        #expect(data["name"] as? String == "Mow")
        #expect(data["assignees"] as? String == "1")
        #expect(data["recurrence_interval"] as? Int == 3)
        #expect(data["recurrence_unit"] as? String == "weeks")
        #expect((data["recurrence_days"] as? [String])?.isEmpty == true)
        #expect(data["task_id"] == nil)
        #expect(data["hide_on_vacation"] as? Bool == true)
        form.priority = ""
        form.recurrence = ""
        #expect(form.serviceData()["priority"] as? String == "none")
        #expect(form.serviceData()["recurrence"] as? String == "no_repeat")
        #expect(form.serviceData()["recurrence_interval"] as? Int == 1)
    }

    @Test func editDataSendsAssigneesOnlyWhenChanged() {
        var form = DonetickTaskForm(defaultAssignee: "1")
        form.setRecurrence("days_of_the_week")
        form.toggleDay("sunday")
        let initial = form
        let unchanged = form.serviceData(initial: initial, taskId: 7, configEntryId: "todo.demo_x")
        #expect(unchanged["assignees"] == nil)
        #expect(unchanged["task_id"] as? Int == 7)
        #expect(unchanged["config_entry_id"] as? String == "todo.demo_x")
        #expect(unchanged["recurrence_days"] as? [String] == ["sunday"])
        form.assignee = ""
        #expect(form.serviceData(initial: initial, taskId: 7)["assignees"] as? String == "")
        form.recurrenceUnit = ""
        form.setRecurrence("interval")
        #expect(form.serviceData()["recurrence_unit"] as? String == "days")
    }

    @Test func loadsATaskFromGetTask() throws {
        let response = JSONValue.object(["response": .object([
            "id": .number(42), "name": .string("Mow"), "description": .string("Front"),
            "assignees": .array([.number(2), .string("3"), .bool(true)]), "assigned_to": .null,
            "frequency": .number(2), "frequency_type": .string("days_of_the_week"),
            "frequency_metadata": .object(["days": .array([.string("monday"), .string("funday")]), "unit": .string("weeks")]),
            "hide_on_vacation": .bool(false), "next_due_date": .string("2026-10-11T15:30:00Z"), "priority": .number(9),
        ])])
        let task = try DonetickTask(response: response)
        #expect(task.assignees == [2, 3])
        #expect(task.priority == 4)
        let form = DonetickTaskForm(task: task, timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        #expect(form.assignee == "2")
        #expect(form.priority == "critical")
        #expect(form.recurrence == "days_of_the_week")
        #expect(form.recurrenceDays == ["monday"])
        #expect(form.recurrenceUnit == "weeks")
        #expect(form.recurrenceInterval == "2")
        #expect(form.dueDate == "2026-10-11")
        #expect(form.dueTime == "08:30")
        #expect(!form.hideOnVacation)
    }

    @Test func taskDefaultsAndWrappers() throws {
        let minimal = try DonetickTask(response: .object(["service_response": .object([
            "id": .string("5"), "name": .string("Dust"), "assigned_to": .string("1"), "frequency_type": .string("once"),
            "frequency_metadata": .object(["unit": .string("fortnights")]), "priority": .number(-2),
        ])]))
        #expect(minimal.frequency == 1)
        #expect(minimal.hideOnVacation)
        #expect(minimal.nextDueDate == nil)
        let form = DonetickTaskForm(task: minimal)
        #expect(form.assignee == "1")
        #expect(form.recurrence == "no_repeat")
        #expect(form.recurrenceUnit == "days")
        #expect(form.priority == "none")
        #expect(form.dueDate.isEmpty)
        let bare = try DonetickTask(response: .object(["id": .number(1), "name": .string("A"), "frequency_type": .string("hourly")]))
        #expect(DonetickTaskForm(task: bare).recurrence == "no_repeat")
        #expect(DonetickTaskForm(task: bare).assignee == "")
        #expect(throws: DonetickTask.InvalidResponse.self) { _ = try DonetickTask(response: .object(["name": .string("No id")])) }
        #expect(throws: DonetickTask.InvalidResponse.self) { _ = try DonetickTask(response: .null) }
        #expect(DonetickTask.InvalidResponse().errorDescription == "DoneTick returned an incomplete task response")
    }
}
