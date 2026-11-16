import Foundation

// MARK: - Todo draft adapters

extension ServerUITodoProvider {
    /// Plain grocery/admin add and rename retain the actual list target, never a row index.
    public func textForm(identity: String? = nil) throws -> ServerUIValueForm {
        let initial: String
        let expected: TodoItem?
        if let identity {
            guard configuration.canRename, let item = items?.first(where: { $0.identity == identity }),
                  item.uid != nil else { throw Failure.invalidItem }
            initial = item.summary ?? ""
            expected = item
        } else {
            guard configuration.canAdd else { throw Failure.forbidden }
            initial = ""
            expected = nil
        }
        return try ServerUIValueForm(identity: .init(ownerId: configuration.entityId, recordId: identity ?? "new"),
            fields: [.text("name", "Name", initial, required: true)], allowsReset: false) { [self] values in
                let name = try values.formString("name")
                if let identity, let expected {
                    try validate(expected: expected)
                    try await rename(identity: identity, name: name)
                }
                else {
                    try await add(name: name, accessToken: { throw Failure.forbidden })
                }
            }
    }

    /// Maps the generic controls back into the canonical DoneTick form and its changed-field service data.
    public func taskForm(identity: String? = nil, people: ServerUITodoPeople,
                         viewerUserId: String? = nil, defaultAssignee: String = "",
                         grouping: (@MainActor ([ServerUIFormValue]) -> [ServerUIFormGroup])? = nil) async throws -> ServerUIValueForm {
        let edit: TaskEdit?
        if let identity { edit = try await editTask(identity: identity) }
        else {
            guard configuration.canCreateTask else { throw Failure.forbidden }
            edit = nil
        }
        let initial = edit?.initial ?? DonetickTaskForm(defaultAssignee: defaultAssignee)
        let deletable = configuration.canDelete ? edit : nil
        let deleteAction: (@MainActor () async throws -> Void)?
        if let deletable { deleteAction = { [self] in try await deleteTask(deletable) } }
        else { deleteAction = nil }
        let day = InventoryCalendar.current.isoString(InventoryCalendar.current.today)
        let fields: [ServerUIFormValue] = [
            .text("name", "Task Name", initial.name, required: true),
            .choice("assignee", "Assign To", initial.assignee, people.options(viewerUserId: viewerUserId, selected: initial.assignee)),
            .text("description", "Description", initial.description, multiline: true),
            .toggle("hasDueDate", "Due Date", !initial.dueDate.isEmpty),
            .text("dueDate", "Date", initial.dueDate.isEmpty ? day : initial.dueDate, control: .date),
            .toggle("hasDueTime", "Due Time", !initial.dueTime.isEmpty),
            .text("dueTime", "Time", initial.dueTime.isEmpty ? "12:00" : initial.dueTime, control: .time),
            .toggle("hideOnVacation", "Hide on Vacation", initial.hideOnVacation),
            .choice("priority", "Priority", initial.priority, DonetickTaskForm.priorities),
            .choice("recurrence", "Repeat", initial.recurrence, DonetickTaskForm.recurrences(editing: edit != nil)),
            .number("recurrenceInterval", "Repeat Every", Double(initial.recurrenceInterval) ?? 1, minimum: 1, maximum: 365),
            .choice("recurrenceUnit", "Unit", initial.recurrenceUnit, DonetickTaskForm.recurrenceUnits),
            .text("recurrenceDays", "Days", initial.recurrenceDays.joined(separator: ","), control: .weekdays),
        ]
        do {
            return try ServerUIValueForm(identity: .init(ownerId: configuration.entityId, recordId: identity ?? "new"),
                fields: fields, allowsReset: false, grouping: grouping, visibility: { key, values in
                    switch key {
                    case "dueDate": return values["hasDueDate"] == .boolean(true)
                    case "dueTime": return values["hasDueTime"] == .boolean(true)
                    case "recurrenceInterval", "recurrenceUnit": return values["recurrence"] == .string("interval")
                    case "recurrenceDays": return values["recurrence"] == .string("days_of_the_week")
                    default: return true
                    }
                }, release: { [self] in if let edit { try closeTask(edit) } },
                deletion: deletable.map { .init(title: "Delete Task", noun: "Task", name: $0.initial.name) },
                delete: deleteAction,
                submit: { [self] values in
                    var form = initial
                    form.name = try values.formString("name")
                    form.assignee = try values.formString("assignee")
                    form.description = try values.formString("description")
                    form.dueDate = try values.formBoolean("hasDueDate") ? values.formString("dueDate") : ""
                    form.dueTime = try values.formBoolean("hasDueTime") ? values.formString("dueTime") : ""
                    guard InventoryCalendar.isValidInput(form.dueDate),
                          form.dueTime.isEmpty || form.dueTime.range(of: "^([01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil
                    else { throw ServerUIRecordFailure.invalidValue }
                    form.hideOnVacation = try values.formBoolean("hideOnVacation")
                    form.priority = try values.formString("priority")
                    form.setRecurrence(try values.formString("recurrence"))
                    form.recurrenceInterval = String(Int(try values.formNumber("recurrenceInterval")))
                    form.recurrenceUnit = try values.formString("recurrenceUnit")
                    let days = try values.formString("recurrenceDays").split(separator: ",").map(String.init)
                    guard Set(days).isSubset(of: Set(DonetickTaskForm.weekdays.map(\.value))) else {
                        throw ServerUIRecordFailure.invalidValue
                    }
                    form.recurrenceDays = form.showsRecurrenceDays ? DonetickTaskForm.weekdays.map(\.value).filter(days.contains) : []
                    try await saveTask(form, editing: edit)
                })
        } catch {
            if let edit { try closeTask(edit) }
            throw error
        }
    }
}

// MARK: - Native field values

extension ServerUIFormValue {
    /// A text field.
    public static func text(_ key: String, _ label: String, _ value: String, required: Bool = false,
                            multiline: Bool = false, control: ServerUICompositionDocument.Form.Control? = nil) -> Self {
        .init(key: key, label: label, control: control ?? (multiline ? .multiline : .text),
              rule: .string(maxLength: 16_384), value: .string(value), required: required)
    }
    /// A switch field.
    public static func toggle(_ key: String, _ label: String, _ value: Bool) -> Self {
        .init(key: key, label: label, control: .toggle, rule: .boolean, value: .boolean(value))
    }
    /// A number field.
    public static func number(_ key: String, _ label: String, _ value: Double,
                              minimum: Double = 0, maximum: Double = 1_000_000, step: Double = 1,
                              control: ServerUICompositionDocument.Form.Control = .number) -> Self {
        .init(key: key, label: label, control: control,
              rule: .number(minimum: minimum, maximum: maximum, step: step), value: .number(value))
    }
    /// A choice field.
    public static func choice(_ key: String, _ label: String, _ value: String, _ options: [DonetickTaskForm.Option],
                              control: ServerUICompositionDocument.Form.Control = .choice) -> Self {
        .init(key: key, label: label, control: control,
              rule: .choice(options: options.map { .init(id: $0.value, label: $0.label) }), value: .string(value))
    }
}
