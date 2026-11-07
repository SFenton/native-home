#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// The item editor (``InventoryItemEditor``; web `InventoryItemDetailsModal`; direction G mockup n6-item-editor): one group per batch with
/// quantity, expiration date, prepared food and delete, under a header naming its expiry and place.
///
/// `.sheet` is an edit sheet (direction G, Sheets): circle x Cancel drops the drafts, the filled check saves every changed batch, and
/// Reset Changes is a list row. `.pane` draws it in the trailing half of a split window with its own header, Close, and Save Changes as a
/// list row. One commit model (owner, 2026-10-24): quantity, expiry and Prepared Food are drafts that wait for Save and that Cancel
/// drops; Delete sits in its own group, asks first and applies at once. Saves and deletes block closing until they finish.
final class UKInventoryEditorViewController: UKFormViewController {
    enum Style { case sheet, pane }

    let model: InventoryEditorModel
    private let style: Style
    private let onClose: () -> Void
    /// The pane's header Close follows this (a save or a busy edit holds it).
    var onBlockedChange: ((Bool) -> Void)?
    private var bundles: [String: BatchRows] = [:]
    private var isSavingAll = false
    private var closed = false
    private lazy var confirm = UKSheetConfirmItem("Save", isEnabled: false, busyTitle: "Saving", identifier: "inventory.editor.save") { [weak self] in self?.saveAll() }
    private let saveRow = UKFormActionRow(title: "Save Changes", ink: UKDesignInk.action, bold: true, identifier: "inventory.editor.save", busyLabel: "Saving")
    private let resetRow = UKFormActionRow(title: "Reset Changes", ink: UKDesignInk.action, identifier: "inventory.editor.reset")

    init(model: InventoryEditorModel, style: Style, context: UKContext, onClose: @escaping () -> Void) {
        self.model = model
        self.style = style
        self.onClose = onClose
        super.init(context: context)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The editor as an edit sheet (iPad: the form sheet), with Cancel and Save in its bar.
    static func presentSheet(model: InventoryEditorModel, from presenter: UIViewController, context: UKContext, onClose: @escaping () -> Void,
                             onDismissed: @escaping () -> Void) {
        let editor = UKInventoryEditorViewController(model: model, style: .sheet, context: context.with { $0.surface = .sheet }, onClose: onClose)
        var options = UKHassModalOptions(title: model.title)
        options.showsClose = false
        options.width = .form
        options.onDismissed = onDismissed
        UKHassModalController(root: editor, options: options).present(from: presenter)
    }

    // MARK: View

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityIdentifier = "inventory.editor"
        // In the pane the wallpaper shows through, as on the rest of the page (owner, 2026-11-01: no black ground).
        if style == .pane { view.backgroundColor = .clear }
        saveRow.addAction(UIAction { [weak self] _ in self?.saveAll() }, for: .touchUpInside)
        resetRow.addAction(UIAction { [weak self] _ in self?.model.resetChanges() }, for: .touchUpInside)
        bag.observe { [weak self] in self?.render() }
    }

    // MARK: Render

    /// Some batch has a draft and nothing is in flight.
    private var canSave: Bool { !model.changedBatches.isEmpty && model.busy == nil && !isSavingAll }

    private var isSaving: Bool {
        if isSavingAll { return true }
        if case .save = model.busy { return true }
        return false
    }

    private func render() {
        let batches = model.batches
        let changed = model.changedBatches
        let blocked = model.dismissalBlocked || isSavingAll
        var sections: [UKFormSection] = []
        if let error = model.error {
            sections.append(UKFormSection(id: "error", rows: [UKFormRow(id: "error-\(error)", .custom {
                let alert = UKInlineAlertView(error, severity: .error)
                alert.accessibilityIdentifier = "inventory.editor.error"
                return alert
            })]))
        }
        for batch in batches {
            let rows = bundle(for: batch)
            rows.update(model: model, batch: batch)
            let notes = [model.hint(batch), model.preparedHint(batch), batch.id == batches.first?.id ? InventoryEditorModel.preparedFoodNote : nil].compactMap { $0 }
            var batchRows = [
                UKFormRow(id: "quantity-\(batch.key)", .custom { [rows] in rows.quantity }),
                UKFormRow(id: "hasExpiry-\(batch.key)", .custom { [rows] in rows.hasExpiry }),
            ]
            if !model.expiry(batch).isEmpty { batchRows.append(UKFormRow(id: "expiry-\(batch.key)", .custom { [rows] in rows.expiry })) }
            batchRows.append(UKFormRow(id: "prepared-\(batch.key)", .custom { [rows] in rows.prepared }))
            sections.append(UKFormSection(id: "batch-\(batch.key)", header: model.header(batch), footer: notes.isEmpty ? nil : notes.joined(separator: "\n"),
                                          headerStyle: .system, rows: batchRows))
            // Delete applies at once, so it sits apart from the drafts above (HIG Entering data: one commit model per form).
            sections.append(UKFormSection(id: "delete-\(batch.key)", footer: "Deleting asks first and applies at once. It is not part of Save.",
                                          headerStyle: .system, rows: [UKFormRow(id: "delete-row-\(batch.key)", .custom { [rows] in rows.delete })]))
        }
        if !changed.isEmpty {
            var rows: [UKFormRow] = []
            if style == .pane {
                saveRow.show(label: isSaving ? "Saving \(model.title)" : "Save \(model.title)", isBusy: isSaving, isEnabled: canSave)
                rows.append(UKFormRow(id: "save", .custom { [saveRow] in saveRow }))
            }
            resetRow.show(label: "Reset Changes to \(model.title)", isEnabled: !(model.busy != nil || isSaving))
            rows.append(UKFormRow(id: "reset", .custom { [resetRow] in resetRow }))
            sections.append(UKFormSection(id: "changes", headerStyle: .system, rows: rows))
        }
        setSections(sections, animated: false)

        switch style {
        case .sheet:
            // "Quantity 3 · In the Pantry" (iOS 26; the title alone before).
            UKSheetSubtitle.apply(model.summary, to: navigationItem)
            navigationItem.leftBarButtonItem = UKSheetItems.cancel(identifier: "inventory.editor.close", isEnabled: !blocked, hasChanges: !changed.isEmpty,
                                                                   presenter: self) { [weak self] in self?.onClose() }
            confirm.update(isEnabled: canSave, isBusy: isSaving)
            navigationItem.rightBarButtonItem = confirm.barButtonItem
            // Edited quantities and dates ask before a swipe down or Cancel drops them (`sheet-discard-guard`).
            UKDiscardGuard.apply(to: self, hasChanges: !changed.isEmpty, isBusy: blocked)
            navigationController?.sheetPresentationController?.prefersGrabberVisible = !model.dismissalBlocked
        case .pane:
            onBlockedChange?(blocked)
        }
        if model.isFinished, !isSavingAll, !closed {
            closed = true
            onClose()
        }
    }

    private func bundle(for batch: InventoryBatch) -> BatchRows {
        if let existing = bundles[batch.key] { return existing }
        let created = BatchRows(batch: batch, editor: self)
        bundles[batch.key] = created
        return created
    }

    // MARK: Save

    private func saveAll() {
        isSavingAll = true
        render()
        Task {
            await model.saveChanges()
            isSavingAll = false
            render()
            if model.isFinished, model.error == nil, !closed {
                closed = true
                onClose()
            }
        }
    }

    // MARK: Prompts

    fileprivate func ask(_ prompt: EditorPrompt) {
        let alert = UIAlertController(title: prompt.title, message: prompt.message, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = "1"
            field.keyboardType = .decimalPad
            field.accessibilityIdentifier = "inventory.editor.prompt.field"
            field.accessibilityLabel = "Quantity"
            field.placeholder = "Quantity"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: prompt.confirmTitle, style: .default) { [model, weak alert] _ in
            let text = alert?.textFields?.first?.text ?? ""
            Task { await prompt.submit(text, to: model) }
        })
        present(alert, animated: true)
    }

    // MARK: Batch rows

    /// One batch's rows, made once and kept: Quantity, Expiration Date, Expires, Prepared Food and Delete.
    @MainActor
    final class BatchRows {
        let quantity: UKFormStepperRow
        let hasExpiry = UKFormSwitchRow(title: "Expiration Date", identifier: "inventory.editor.hasExpiry")
        let expiry: UKFormDateRow
        let prepared: UKFormSwitchRow
        let delete: UKFormActionRow
        private var batch: InventoryBatch
        private weak var editor: UKInventoryEditorViewController?

        init(batch: InventoryBatch, editor: UKInventoryEditorViewController) {
            self.batch = batch
            self.editor = editor
            quantity = UKFormStepperRow(title: "Quantity", identifier: "inventory.editor.quantity")
            expiry = UKFormDateRow(title: "Expires", identifier: "inventory.editor.expiry", accessibilityLabel: "Expires")
            // A draft like the fields above: it waits for Save, and a second tap drops it.
            prepared = UKFormSwitchRow(title: "Prepared Food", identifier: "inventory.editor.prepared", actionOnly: true, busyLabel: "Updating prepared food")
            delete = UKFormActionRow(title: "Delete", ink: UKDesignInk.danger, identifier: "inventory.editor.delete", busyLabel: "Deleting")
            quantity.onChange = { [weak self] value in
                guard let self, let editor = self.editor else { return }
                editor.model.setQuantity(value, for: self.batch)
            }
            hasExpiry.onToggle = { [weak self] on in
                guard let self, let editor = self.editor else { return }
                let calendar = editor.model.calendar
                editor.model.setExpiry(on ? calendar.isoString(calendar.today) : "", for: self.batch)
            }
            expiry.onChange = { [weak self] date in
                guard let self, let editor = self.editor else { return }
                editor.model.setExpiry(editor.model.calendar.isoString(date), for: self.batch)
            }
            prepared.onToggle = { [weak self] _ in
                guard let self, let editor = self.editor else { return }
                let batch = self.batch
                // Flipping prepared asks how many when the batch holds more than one; the switch stays put until it is confirmed.
                Task { if let prompt = await EditorPrompt.prepared(batch, in: editor.model) { editor.ask(prompt) } }
            }
            delete.addAction(UIAction { [weak self] _ in self?.deleteTapped() }, for: .touchUpInside)
        }

        func update(model: InventoryEditorModel, batch: InventoryBatch) {
            self.batch = batch
            let qualifier = model.batchName(batch)
            let disabled = model.isDisabled(batch)
            let amount = model.quantity(batch)
            quantity.show(current: amount, minimum: model.minimumQuantity(batch), maximum: InventoryCatalog.maxQuantity, display: InventoryFormat.quantity(amount),
                          isEnabled: !disabled, label: "Quantity of \(qualifier)")
            let hasDate = !model.expiry(batch).isEmpty
            hasExpiry.show(isOn: hasDate, isEnabled: !disabled, label: "Expiration date for \(qualifier)")
            expiry.show(date: model.calendar.date(fromISO: model.expiry(batch)) ?? model.calendar.today, isEnabled: !disabled, label: "Expires, \(qualifier)")
            var preparing = false
            if case .prepared(batch.key) = model.busy { preparing = true }
            prepared.show(isOn: model.showsPrepared(batch), isEnabled: !disabled, label: "Prepared food, \(qualifier)", isBusy: preparing)
            var deleting = false
            if case .delete(batch.key) = model.busy { deleting = true }
            delete.show(label: deleting ? "Deleting \(qualifier)" : "Delete \(qualifier)", symbol: "trash", isBusy: deleting, isEnabled: !disabled)
        }

        private func deleteTapped() {
            guard let editor else { return }
            let batch = self.batch
            // One unit asks first, with the page's dialog; several ask how many (the quantity prompt).
            if batch.quantity <= 1 {
                let spec = AlertCopy.delete("Item", named: editor.model.batchName(batch), detail: "It will be removed from the \(batch.locationPhrase).")
                UKInventoryAlerts.confirmDelete(spec, from: editor, source: .view(delete), confirmID: "inventory.editor.delete.confirm", onConfirm: {
                    Task { _ = await EditorPrompt.delete(batch, in: editor.model) }
                }, onCancel: {})
            } else {
                Task { if let prompt = await EditorPrompt.delete(batch, in: editor.model) { editor.ask(prompt) } }
            }
        }
    }
}

// MARK: - Pane

/// The editor in the trailing half of a split window: the same page (``UKInventoryEditorViewController``, `.pane`) under its own header
/// rather than a nested navigation stack, which took over the window's bar: the title, Close, a divider.
final class UKInventoryEditorPaneViewController: UKPaneViewController, UKColumnPopGuarding {
    let editor: UKInventoryEditorViewController
    var model: InventoryEditorModel { editor.model }
    private let columnTitle = UKColumnTitleHeader()
    /// A save or a busy edit holds Close and Back (the editor reports it); the edge pan does not start either.
    private(set) var isBlocked = false
    var columnPopDecision: UKColumnPopDecision { isBlocked ? .block : .allow }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        columnTitle.place()
    }

    /// The title and Close come from the column's navigation bar (``UKColumnsViewController``): the title is the item's, Close is the
    /// column's, in the Duo's rail. The pane draws only the editor and its leading hairline.
    init(model: InventoryEditorModel, context: UKContext, onClose: @escaping () -> Void) {
        editor = UKInventoryEditorViewController(model: model, style: .pane, context: context, onClose: onClose)
        super.init(nibName: nil, bundle: nil)
        title = model.title
        editor.onBlockedChange = { [weak self] blocked in
            guard let self, self.isBlocked != blocked else { return }
            self.isBlocked = blocked
            (self.parent as? UKColumnsViewController)?.pageStateChanged()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let leadingDivider = UIView()
        leadingDivider.backgroundColor = UKDesignSurface.separator
        leadingDivider.translatesAutoresizingMaskIntoConstraints = false
        addChild(editor)
        editor.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(editor.view)
        editor.didMove(toParent: self)
        view.addSubview(leadingDivider)
        NSLayoutConstraint.activate([
            editor.view.topAnchor.constraint(equalTo: view.topAnchor), editor.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            editor.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), editor.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            leadingDivider.topAnchor.constraint(equalTo: view.topAnchor), leadingDivider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leadingDivider.leadingAnchor.constraint(equalTo: view.leadingAnchor), leadingDivider.widthAnchor.constraint(equalToConstant: 0.5),
        ])
        // The item's name is the heading at the top of the editor's content, as for every column page.
        if let scroll = UKScrollToTop.mainScrollView(in: editor.view) { columnTitle.attach(to: scroll, in: self, host: view, title: title) }
    }
}
#endif
