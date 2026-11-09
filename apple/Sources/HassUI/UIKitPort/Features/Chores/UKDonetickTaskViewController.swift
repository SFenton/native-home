#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// Create or edit a DoneTick task (``DonetickTaskSheet``, web `CreateDonetickTaskSheet` + `DonetickTaskFormPage`).
///
/// Creating sends `donetick.create_task_form`; editing loads the task with `donetick.get_task`, saves with
/// `donetick.update_task_form` and can delete it (`todo.remove_item`) after a confirmation. Present it in a
/// ``UKHassModalController`` (the todo page does) or push it into another sheet with `isPushed` (Edit Task from Your Summary, owner
/// 2026-10-24, `sheet-stacking-close`): no sheet of its own, a guarded Back in place of Cancel. Call `modal.push(controller)` so the
/// modal chrome applies.
///
/// ```swift
/// let task = UKDonetickTaskViewController(model: model, mode: .edit(target), connection: context.connection, onSaved: reload, isPushed: true)
/// task.closeForm = { modal.popViewController(animated: true) }
/// modal.push(task)
/// ```
@MainActor
final class UKDonetickTaskViewController: UKTodoFormController {
    typealias Mode = DonetickTaskSheet.Mode

    private let mode: Mode
    private let onSaved: () -> Void
    private let isPushed: Bool
    private let connection: HassConnection?

    private var taskForm: DonetickTaskForm
    private var initialForm: DonetickTaskForm
    private var loaded: Bool
    private var taskName = ""
    /// A Try Again is running: the failed state stays and its button shows the arc.
    private var retrying = false
    private var loadError: String?
    private var busyKind: Busy?
    private enum Busy { case saving, deleting }

    // Persistent row views, so a field keeps its focus across a rebuild.
    private let nameField = UKTodoTextField(placeholder: "Task Name", identifier: "task.name")
    private let descriptionView = UKTodoTextView(placeholder: "Description", identifier: "task.description", lines: 3...8)
    private let assigneeRow = UKTodoPickerRow(title: "Assignee", identifier: "task.assignee")
    private let priorityRow = UKTodoPickerRow(title: "Priority", identifier: "task.priority")
    private let recurrenceRow = UKTodoPickerRow(title: "Repeat", identifier: "task.recurrence")
    private let unitRow = UKTodoPickerRow(title: "Interval Unit", identifier: "task.recurrenceUnit")
    /// The page load gate around the form and the failure message (owner, 2026-10-30; ``ContentGate``): the arc fades in, fades out
    /// when the task is ready, and the form fades in. Created ready for a new task, a restored draft and a reopened form.
    private var gate: UKContentGateView?
    private let gateContent = UIView()
    private var failureView: UIView?

    /// What the Task Name field is for.
    static let nameFooter = DonetickTaskFormFields.nameFooter
    /// What the Description field is for.
    static let descriptionFooter = DonetickTaskFormFields.descriptionFooter

    init(model: ChoresModel, mode: Mode, connection: HassConnection? = nil, onSaved: @escaping () -> Void = {}, isPushed: Bool = false) {
        self.mode = mode
        self.onSaved = onSaved
        self.isPushed = isPushed
        self.connection = connection
        let initial: DonetickTaskForm
        if case let .create(defaultAssignee) = mode { initial = DonetickTaskForm(defaultAssignee: defaultAssignee) } else { initial = DonetickTaskForm() }
        taskForm = initial
        initialForm = initial
        loaded = mode.editTarget == nil
        super.init(model: model)
        title = mode.editTarget == nil ? "New Task" : "Edit Task"
        if isPushed { UKHassModal.hidesSystemBack(self) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Base hooks

    override var cancelIdentifier: String { "task.cancel" }
    override var confirmTitle: String { mode.editTarget == nil ? "Create" : "Save" }
    override var busyTitle: String { mode.editTarget == nil ? "Creating" : "Saving" }
    override var confirmIdentifier: String { "task.save" }
    /// The form differs from what it opened with (a task still loading has none).
    override var hasEdits: Bool { loaded && taskForm != initialForm }
    /// A new task needs a name; an edit also needs a change (``SheetEditState``).
    override var canConfirm: Bool {
        SheetEditState.canConfirm(isValid: loaded && !taskForm.trimmedName.isEmpty,
                                  hasChanges: mode.editTarget == nil || taskForm != initialForm, isBusy: busyKind != nil)
    }

    override func makeLeadingItem() -> UIBarButtonItem {
        guard isPushed else { return super.makeLeadingItem() }
        return UKSheetItems.back(identifier: "task.cancel", hasChanges: hasEdits, isEnabled: busyKind == nil, presenter: self) { [weak self] in self?.close() }
    }

    override func formDidLoad() {
        configureControls()
        if case let .donetick(savedForm, savedInitial, savedName)? = drafts.draft {
            taskForm = savedForm
            initialForm = savedInitial
            taskName = savedName
            loaded = true
        } else if !loaded {
            Task { await load() }
        }
    }

    private func configureControls() {
        nameField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.taskForm.name = self.nameField.text ?? ""
            self.formChanged()
        }, for: .editingChanged)
        descriptionView.onChange = { [weak self] value in
            self?.taskForm.description = value
            self?.formChanged()
        }
        descriptionView.onHeightChange = { [weak self] in self?.remeasureRows() }

    }

    // MARK: Rows with their own controls

    /// A new date row each time the row is built: it owns its picker and reads the form's value once.
    private func makeDateRow() -> UIView {
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .compact
        picker.accessibilityIdentifier = "task.dueDate"
        picker.accessibilityLabel = "Date"
        if let date = DonetickDueBinding.formatter("yyyy-MM-dd").date(from: taskForm.dueDate) { picker.date = date }
        picker.addAction(UIAction { [weak self, weak picker] _ in
            guard let self, let picker else { return }
            self.taskForm.dueDate = DonetickDueBinding.formatter("yyyy-MM-dd").string(from: picker.date)
            self.formChanged(rebuild: false)
        }, for: .valueChanged)
        return UKTodoLabeledRow(title: "Date", trailing: picker)
    }

    private func makeTimeRow() -> UIView {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .compact
        picker.accessibilityIdentifier = "task.dueTime"
        picker.accessibilityLabel = "Time"
        if let time = DonetickDueBinding.formatter("HH:mm").date(from: taskForm.dueTime) { picker.date = time }
        picker.addAction(UIAction { [weak self, weak picker] _ in
            guard let self, let picker else { return }
            self.taskForm.dueTime = DonetickDueBinding.formatter("HH:mm").string(from: picker.date)
            self.formChanged(rebuild: false)
        }, for: .valueChanged)
        return UKTodoLabeledRow(title: "Time", trailing: picker)
    }

    private func makeRepeatRow() -> UIView {
        let field = UITextField()
        field.placeholder = "1"
        field.text = taskForm.recurrenceInterval
        field.textAlignment = .right
        field.keyboardType = .numberPad
        field.font = .ukFont(.body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UKDesignInk.primary
        field.accessibilityIdentifier = "task.repeatEvery"
        field.accessibilityLabel = "Repeat Every"
        field.ukAddKeyboardDone()
        field.addAction(UIAction { [weak self, weak field] _ in
            guard let self, let field else { return }
            self.taskForm.setRepeatEvery(field.text ?? "")
            if field.text != self.taskForm.recurrenceInterval { field.text = self.taskForm.recurrenceInterval }
            self.formChanged(rebuild: false)
        }, for: .editingChanged)
        field.addAction(UIAction { [weak self, weak field] _ in
            guard let self, let field else { return }
            self.taskForm.normalizeRepeatEvery()
            field.text = self.taskForm.recurrenceInterval
            self.formChanged(rebuild: false)
        }, for: .editingDidEnd)
        let minimumWidth = field.widthAnchor.constraint(greaterThanOrEqualToConstant: 60)
        minimumWidth.isActive = true
        return UKTodoLabeledRow(title: "Repeat Every", trailing: field)
    }

    // MARK: Sections

    override func sections() -> [UKFormSection] {
        guard loaded else { return [] }
        let editing = mode.editTarget != nil
        syncControls()
        var sections: [UKFormSection] = [
            // Two fields, each with its own header and footer saying what goes in it (owner, 2026-10-16).
            UKFormSection(id: "name", header: "Task Name", footer: Self.nameFooter, headerStyle: .system, footerIdentifier: "task.name.footer", rows: [
                UKFormRow(id: "name-field", identifier: "task.name", .custom { [nameField] in nameField.rowView }),
            ]),
            UKFormSection(id: "description", header: "Description", footer: Self.descriptionFooter, headerStyle: .system,
                          footerIdentifier: "task.description.footer", rows: [
                UKFormRow(id: "description-field", identifier: "task.description", .custom { [descriptionView] in descriptionView }),
            ]),
        ]
        let viewer = model.viewer
        assigneeRow.update(options: taskForm.assignees(viewer: viewer), selected: taskForm.assignee) { [weak self] value in
            self?.taskForm.assignee = value
            self?.formChanged()
        }
        priorityRow.update(options: DonetickTaskForm.priorities, selected: taskForm.priority) { [weak self] value in
            self?.taskForm.priority = value
            self?.formChanged()
        }
        sections.append(UKFormSection(id: "who", headerStyle: .system, rows: [
            UKFormRow(id: "assignee", identifier: "task.assignee", .custom { [assigneeRow] in assigneeRow }),
            UKFormRow(id: "priority", identifier: "task.priority", .custom { [priorityRow] in priorityRow }),
        ]))

        var whenRows: [UKFormRow] = [
            UKFormRow(id: "hasDueDate", identifier: "task.hasDueDate", .toggle(title: "Due Date", isOn: !taskForm.dueDate.isEmpty) { [weak self] on in
                guard let self else { return }
                self.taskForm.dueDate = on ? DonetickDueBinding.formatter("yyyy-MM-dd").string(from: .now) : ""
                self.formChanged()
            }),
        ]
        if !taskForm.dueDate.isEmpty {
            whenRows.append(UKFormRow(id: "dueDate", identifier: "task.dueDate", .custom { [weak self] in self?.makeDateRow() ?? UIView() }))
        }
        whenRows.append(UKFormRow(id: "hasDueTime", identifier: "task.hasDueTime", .toggle(title: "Due Time", isOn: !taskForm.dueTime.isEmpty) { [weak self] on in
            self?.taskForm.dueTime = on ? "12:00" : ""
            self?.formChanged()
        }))
        if !taskForm.dueTime.isEmpty {
            whenRows.append(UKFormRow(id: "dueTime", identifier: "task.dueTime", .custom { [weak self] in self?.makeTimeRow() ?? UIView() }))
        }
        // A pop-up menu anchored over the row (direction G, Controls: "Choosing one option").
        recurrenceRow.update(options: DonetickTaskForm.recurrences(editing: editing), selected: taskForm.recurrence) { [weak self] value in
            self?.taskForm.setRecurrence(value)
            self?.formChanged()
        }
        whenRows.append(UKFormRow(id: "recurrence", identifier: "task.recurrence", .custom { [recurrenceRow] in recurrenceRow }))
        sections.append(UKFormSection(id: "when", headerStyle: .system, rows: whenRows))

        if taskForm.showsCustomInterval {
            unitRow.update(options: DonetickTaskForm.recurrenceUnits, selected: taskForm.recurrenceUnit) { [weak self] value in
                self?.taskForm.recurrenceUnit = value
                self?.formChanged()
            }
            sections.append(UKFormSection(id: "interval", footer: "How often to repeat: every 1 to 365 days, weeks, months, or years.", headerStyle: .system, rows: [
                UKFormRow(id: "repeatEvery", identifier: "task.repeatEvery", .custom { [weak self] in self?.makeRepeatRow() ?? UIView() }),
                UKFormRow(id: "unit", identifier: "task.recurrenceUnit", .custom { [unitRow] in unitRow }),
            ]))
        }
        if taskForm.showsRecurrenceDays {
            sections.append(UKFormSection(id: "days", header: "Days of Week", headerStyle: .system, rows: DonetickTaskForm.weekdays.map { day in
                UKFormRow(id: "day-\(day.value)", identifier: "task.day.\(day.value)",
                          .option(title: day.label, subtitle: nil, swatch: [], isSelected: taskForm.recurrenceDays.contains(day.value)) { [weak self] in
                    self?.taskForm.toggleDay(day.value)
                    self?.formChanged()
                })
            }))
        }
        sections.append(UKFormSection(id: "vacation", footer: "This task will not show up in your chores lists while Vacation Mode is on.", headerStyle: .system, rows: [
            UKFormRow(id: "hideOnVacation", identifier: "task.hideOnVacation", .toggle(title: "Hide While On Vacation", isOn: taskForm.hideOnVacation) { [weak self] on in
                self?.taskForm.hideOnVacation = on
                self?.formChanged()
            }),
        ]))
        if editing {
            sections.append(UKFormSection(id: "delete", headerStyle: .system, rows: [
                UKFormRow(id: "delete", identifier: "task.delete", .custom { [weak self] in
                    let row = UKTodoButtonRow(title: "Delete Task", ink: UKDesignInk.danger, identifier: "task.delete") { }
                    row.button.addAction(UIAction { [weak self, weak row] _ in
                        guard let self, let row else { return }
                        UKAlerts.confirmationDialog(AlertCopy.delete("Task", named: self.taskName), from: self,
                                                    source: UKPopoverSource.view(row.button)) { Task { await self.delete() } }
                    }, for: .touchUpInside)
                    return row
                }),
            ]))
        }
        return sections
    }

    /// Writes the form's values into the persistent controls.
    private func syncControls() {
        if nameField.text != taskForm.name, !nameField.isFirstResponder { nameField.text = taskForm.name }
        if descriptionView.text != taskForm.description, !descriptionView.textView.isFirstResponder { descriptionView.text = taskForm.description }
    }

    /// The form changed: keeps the draft and rebuilds the rows.
    private func formChanged(rebuild: Bool = true) {
        if loaded { drafts.save(.donetick(form: taskForm, initial: initialForm, name: taskName)) }
        if rebuild { reload() } else { updateChrome() }
    }

    // MARK: Loading states

    override func reload(animated: Bool = true) {
        super.reload(animated: animated)
        updateLoadingViews()
    }

    /// The gate's content: the form with the failure message over it. The sheet has opened at its fixed size already, so the arc, the
    /// fade and the form all sit in the same frame.
    override func formHostView() -> UIView {
        form.view.translatesAutoresizingMaskIntoConstraints = false
        gateContent.addSubview(form.view)
        form.view.ukPin(to: gateContent)
        let gate = UKContentGateView(page: "Task", isReady: isTaskReady, timing: .page, label: "Loading task", content: gateContent)
        self.gate = gate
        return gate
    }

    /// The form can show: it loaded, the load failed (the failure message is the content), or a draft was restored.
    private var isTaskReady: Bool { loaded || loadError != nil || drafts.draft != nil }

    private func updateLoadingViews() {
        guard isViewLoaded else { return }
        form.view.isHidden = !loaded
        failureView?.removeFromSuperview()
        failureView = nil
        if !loaded, let loadError {
            let failure = LoadFailure.of("Task", reason: loadError, isOffline: connection?.isOffline ?? false)
            let state = UKStateMessageView(failure, identifier: "task.loadError", retryIdentifier: "task.retry", retrying: retrying) { [weak self] in
                Task { await self?.retryLoad() }
            }
            let content = UKCenteredStateMessageView(state)
            content.translatesAutoresizingMaskIntoConstraints = false
            gateContent.addSubview(content)
            content.ukPin(to: gateContent)
            failureView = content
        }
        gate?.isReady = isTaskReady
    }

    // MARK: Actions

    /// Try Again on the failed state: reloads the task, keeping the message up with a busy button until it answers.
    private func retryLoad() async {
        guard !retrying else { return }
        retrying = true
        updateLoadingViews()
        defer {
            retrying = false
            updateLoadingViews()
        }
        await load()
    }

    private func load() async {
        guard let target = mode.editTarget, !loaded else { return }
        do {
            let response = try await model.service.callServiceForResponse("donetick", "get_task", data: [
                "config_entry_id": target.todoEntityId, "task_id": target.taskId,
            ])
            let task = try DonetickTask(response: response)
            taskForm = DonetickTaskForm(task: task)
            initialForm = taskForm
            taskName = task.name
            loadError = nil
            loaded = true
            reload(animated: false)
        } catch {
            loadError = TodoListController.message(error, fallback: "Unable to load task")
            updateLoadingViews()
        }
    }

    override func confirmTapped() { Task { await save() } }

    private func save() async {
        guard canConfirm else { return }
        busyKind = .saving
        setBusy(true)
        error = nil
        defer {
            busyKind = nil
            setBusy(false)
        }
        do {
            if let target = mode.editTarget {
                try await model.service.callService("donetick", "update_task_form", data: taskForm.serviceData(
                    initial: initialForm, taskId: target.taskId, configEntryId: target.todoEntityId))
            } else {
                try await model.service.callService("donetick", "create_task_form", data: taskForm.serviceData())
            }
            onSaved()
            close()
        } catch {
            self.error = TodoListController.message(error, fallback: mode.editTarget == nil ? "Unable to create task" : "Unable to save task")
        }
    }

    private func delete() async {
        guard let target = mode.editTarget, busyKind == nil else { return }
        busyKind = .deleting
        setBusy(true)
        error = nil
        defer {
            busyKind = nil
            setBusy(false)
        }
        do {
            try await model.service.callService("todo", "remove_item", data: ["entity_id": target.todoEntityId, "item": target.itemUid])
            onSaved()
            close()
        } catch {
            self.error = TodoListController.message(error, fallback: "Unable to delete task")
        }
    }
}
#endif
