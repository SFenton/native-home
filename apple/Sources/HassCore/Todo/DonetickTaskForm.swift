import Foundation

/// The DoneTick task form's state and the data it sends (web `donetickTaskForm.ts`, `useDonetickTaskForm.ts`).
public struct DonetickTaskForm: Equatable, Sendable {
    /// A picker option.
    public struct Option: Hashable, Sendable, Identifiable {
        public var label: String
        public var value: String
        public var id: String { value }

        public init(_ label: String, _ value: String) {
            self.label = label
            self.value = value
        }
    }

    // MARK: Fields

    public var name = ""
    /// DoneTick user id as a string; "" is Anyone.
    public var assignee = ""
    public var description = ""
    /// `yyyy-MM-dd` or "".
    public var dueDate = ""
    /// `HH:mm` or "".
    public var dueTime = ""
    public var hideOnVacation = true
    public var priority = "critical"
    public var recurrence = "no_repeat"
    public var recurrenceDays: [String] = []
    public var recurrenceInterval = "1"
    public var recurrenceUnit = "days"

    /// A new task's form (web `initialDonetickTaskFormState`).
    public init(defaultAssignee: String = "") {
        assignee = defaultAssignee
    }

    // MARK: Options

    public static let priorities: [Option] = [
        Option("None", "none"), Option("P1", "low"), Option("P2", "medium"), Option("P3", "high"), Option("P4", "critical"),
    ]

    /// Recurrence options; editing adds Adaptive, which only DoneTick itself can set up.
    public static func recurrences(editing: Bool) -> [Option] {
        var options = [
            Option("No Recurrence", "no_repeat"), Option("Daily", "daily"), Option("Weekly", "weekly"),
            Option("Monthly", "monthly"), Option("Yearly", "yearly"), Option("Custom Interval", "interval"),
            Option("Specific Days of Week", "days_of_the_week"),
        ]
        if editing { options.append(Option("Adaptive", "adaptive")) }
        return options
    }

    public static let recurrenceUnits: [Option] = [Option("Days", "days"), Option("Weeks", "weeks"), Option("Months", "months"), Option("Years", "years")]

    public static let weekdays: [Option] = [
        Option("Monday", "monday"), Option("Tuesday", "tuesday"), Option("Wednesday", "wednesday"), Option("Thursday", "thursday"),
        Option("Friday", "friday"), Option("Saturday", "saturday"), Option("Sunday", "sunday"),
    ]

    /// Anyone, the household (the viewer as "You"), Home Improvement, plus the task's own assignee if unknown.
    public func assignees(viewer: ChoresConfig.Resident?) -> [Option] {
        var options = [Option("Anyone", "")]
        for resident in ChoresConfig.Resident.allCases {
            options.append(Option(resident == viewer ? "You" : resident.name, resident.taskAssignee))
        }
        options.append(Option("Home Improvement", "3"))
        if !assignee.isEmpty, !options.contains(where: { $0.value == assignee }) {
            options.append(Option("User \(assignee)", assignee))
        }
        return options
    }

    public var showsCustomInterval: Bool { recurrence == "interval" }
    public var showsRecurrenceDays: Bool { recurrence == "days_of_the_week" }
    /// The trimmed name; the form can't be sent without one.
    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Changes recurrence, clearing the chosen days unless it stays "Specific Days of Week".
    public mutating func setRecurrence(_ value: String) {
        recurrence = value
        if value != "days_of_the_week" { recurrenceDays = [] }
    }

    /// Keeps only digits while typing (web `updateRepeatEvery`).
    public mutating func setRepeatEvery(_ value: String) {
        recurrenceInterval = value.filter(\.isNumber)
    }

    /// Clamps to 1...365 when editing ends (web `donetickRepeatEveryValue`).
    public mutating func normalizeRepeatEvery() {
        guard let amount = Int(recurrenceInterval), amount >= 1 else { recurrenceInterval = "1"; return }
        recurrenceInterval = String(min(amount, 365))
    }

    /// Adds or removes a weekday, keeping week order.
    public mutating func toggleDay(_ day: String) {
        if recurrenceDays.contains(day) {
            recurrenceDays.removeAll { $0 == day }
        } else {
            recurrenceDays = Self.weekdays.map(\.value).filter { recurrenceDays.contains($0) || $0 == day }
        }
    }

    // MARK: Service data

    /// The `due_date` field: date and time, noon when only a date is set, or just the time.
    public var dueValue: String {
        let time = dueTime.isEmpty ? "" : (dueTime.count == 5 ? "\(dueTime):00" : dueTime)
        if !dueDate.isEmpty { return "\(dueDate)T\(time.isEmpty ? "12:00:00" : time)" }
        return time
    }

    /// Data for `donetick.create_task_form` or, with `taskId`, `donetick.update_task_form`. Editing sends
    /// `assignees` only when it changed from `initial`, so DoneTick keeps multi-assignee tasks intact.
    public func serviceData(initial: DonetickTaskForm? = nil, taskId: Int? = nil, configEntryId: String? = nil) -> [String: any Sendable] {
        var data: [String: any Sendable] = [
            "description": description,
            "due_date": dueValue,
            "hide_on_vacation": hideOnVacation,
            "name": trimmedName,
            "priority": priority.isEmpty ? "none" : priority,
            "recurrence": recurrence.isEmpty ? "no_repeat" : recurrence,
            "recurrence_days": showsRecurrenceDays ? recurrenceDays : [String](),
            "recurrence_interval": showsCustomInterval ? (Int(recurrenceInterval) ?? 1) : 1,
            "recurrence_unit": showsCustomInterval ? (recurrenceUnit.isEmpty ? "days" : recurrenceUnit) : "days",
        ]
        if initial == nil || assignee != initial?.assignee { data["assignees"] = assignee }
        if let taskId { data["task_id"] = taskId }
        if let configEntryId { data["config_entry_id"] = configEntryId }
        return data
    }

    // MARK: Loading a task

    /// The form for a task from `donetick.get_task`, with its due time in `timeZone`.
    public init(task: DonetickTask, timeZone: TimeZone = .current) {
        name = task.name
        description = task.description
        hideOnVacation = task.hideOnVacation
        let selected = task.assignedTo ?? task.assignees.first
        assignee = selected.map(String.init) ?? ""
        let priorities = ["none", "low", "medium", "high", "critical"]
        priority = priorities.indices.contains(task.priority) ? priorities[task.priority] : "none"
        let frequency = task.frequencyType == "once" ? "no_repeat" : task.frequencyType
        recurrence = Self.recurrences(editing: true).contains { $0.value == frequency } ? frequency : "no_repeat"
        let days = task.frequencyMetadata["days"]?.array?.compactMap(\.string) ?? []
        recurrenceDays = days.filter { day in Self.weekdays.contains { $0.value == day } }
        recurrenceInterval = String(task.frequency)
        let unit = task.frequencyMetadata["unit"]?.string ?? ""
        recurrenceUnit = Self.recurrenceUnits.contains { $0.value == unit } ? unit : "days"
        if let due = task.nextDueDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            dueDate = formatter.string(from: due)
            formatter.dateFormat = "HH:mm"
            dueTime = formatter.string(from: due)
        }
    }
}

/// A DoneTick task as `donetick.get_task` returns it (web `donetickTaskFromServiceResult`).
public struct DonetickTask: Equatable, Sendable {
    public var id: Int
    public var name: String
    public var description: String
    public var assignees: [Int]
    public var assignedTo: Int?
    public var frequency: Int
    public var frequencyType: String
    public var frequencyMetadata: [String: JSONValue]
    public var hideOnVacation: Bool
    public var nextDueDate: Date?
    /// 0 (none) to 4 (P4).
    public var priority: Int

    /// Error for a response without an id and name.
    public struct InvalidResponse: Error, LocalizedError {
        public var errorDescription: String? { "DoneTick returned an incomplete task response" }
    }

    /// Parses the service response (the task itself, or wrapped in `response` / `service_response`).
    public init(response: JSONValue) throws {
        let task = response["response"] ?? response["service_response"] ?? response
        func int(_ key: String) -> Int? {
            if let number = task[key]?.number { return Int(number) }
            return task[key]?.string.flatMap { Int($0) }
        }
        guard let id = int("id"), id > 0, let name = task["name"]?.string, !name.isEmpty else { throw InvalidResponse() }
        self.id = id
        self.name = name
        description = task["description"]?.string ?? ""
        assignees = task["assignees"]?.array?.compactMap { $0.number.map { Int($0) } ?? $0.string.flatMap { Int($0) } } ?? []
        assignedTo = int("assigned_to")
        frequency = max(1, int("frequency") ?? 1)
        frequencyType = task["frequency_type"]?.string ?? "once"
        if case let .object(metadata)? = task["frequency_metadata"] { frequencyMetadata = metadata } else { frequencyMetadata = [:] }
        hideOnVacation = task["hide_on_vacation"]?.bool ?? true
        nextDueDate = task["next_due_date"]?.string.flatMap(TodoItem.parseDue)
        priority = max(0, min(4, int("priority") ?? 0))
    }
}
