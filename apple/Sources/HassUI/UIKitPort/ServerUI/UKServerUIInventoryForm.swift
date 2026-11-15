#if os(iOS)
import Foundation
import HassCore
import Observation
import UIKit

// MARK: - Inventory draft adapter

/// Reuses the batch editor's commit model, including partial-save failure and prepared-food drafts.
@MainActor @Observable
public final class ServerUIInventoryForm: ServerUIFormSession {
    public let identity: ServerUIDraft.Identity
    public let model: InventoryEditorModel
    private var saving = false
    private var prompting = false

    init(sourceID: String, model: InventoryEditorModel) {
        identity = .init(ownerId: sourceID, recordId: model.itemId)
        self.model = model
    }
    public var hasChanges: Bool { !model.changedBatches.isEmpty }
    public var isBusy: Bool { saving || prompting || model.busy != nil }
    public var canSave: Bool { hasChanges && !isBusy }
    public var error: String? { model.error }
    public var groups: [ServerUIFormGroup] {
        model.batches.map { batch in
            var expiry = ServerUIFormValue.text("expiry", "Expires", model.expiry(batch), control: .date)
            expiry.visible = !model.expiry(batch).isEmpty
            var fields: [ServerUIFormValue] = [
                .number("quantity", "Quantity", model.quantity(batch), minimum: model.minimumQuantity(batch), maximum: InventoryCatalog.maxQuantity),
                .toggle("hasExpiry", "Expiration Date", !model.expiry(batch).isEmpty), expiry,
                .toggle("prepared", "Prepared Food", model.showsPrepared(batch)),
            ]
            for index in fields.indices { fields[index].enabled = batch.addressable }
            return .init(id: batch.key, title: model.header(batch),
                         footer: [model.locationLine(batch), model.hint(batch), model.preparedHint(batch)].compactMap { $0 }.joined(separator: "\n"),
                         fields: fields)
        }
    }
    /// Sets a field value in the draft.
    public func set(_ value: ServerUICompositionDocument.LocalValue, group: String, field: String) throws {
        guard !isBusy else { throw ServerUIRecordFailure.busy }
        guard let batch = model.batches.first(where: { $0.key == group }), batch.addressable,
              let descriptor = groups.first(where: { $0.id == group })?.fields.first(where: { $0.key == field }),
              descriptor.accepts(value) else { throw ServerUIRecordFailure.invalidField }
        switch (field, value) {
        case ("quantity", .number(let value)): model.setQuantity(value, for: batch)
        case ("hasExpiry", .boolean(let value)):
            model.setExpiry(value ? model.calendar.isoString(model.calendar.today) : "", for: batch)
        case ("expiry", .string(let value)):
            guard InventoryCalendar.isValidInput(value) else { throw ServerUIRecordFailure.invalidValue }
            model.setExpiry(value, for: batch)
        case ("prepared", .boolean(let value)):
            if value != model.showsPrepared(batch) { model.togglePreparedDraft(batch) }
        default: throw ServerUIRecordFailure.invalidField
        }
    }
    /// Saves the draft to Home Assistant.
    public func save() async throws {
        guard canSave else { throw ServerUIRecordFailure.invalidValue }
        saving = true
        defer { saving = false }
        await model.saveChanges()
        if let error = model.error { throw ServerUIRecordFailure.unavailable(error) }
    }
    /// Discards edits and restores the initial draft.
    public func reset() throws {
        guard !isBusy else { throw ServerUIRecordFailure.busy }
        model.resetChanges()
    }
    /// Abandons the draft.
    public func discard() throws { try reset() }

    func prepared(group: String, from page: UIViewController, report: @escaping (any Error) -> Void) throws {
        guard !isBusy, let batch = model.batches.first(where: { $0.key == group }), batch.addressable else { throw ServerUIRecordFailure.busy }
        if batch.quantity <= 1 || model.preparedDrafts[batch.key] != nil {
            model.togglePreparedDraft(batch)
            return
        }
        prompting = true
        UKServerUIRecordPrompts.quantity(title: "Prepared Food: \(model.batchName(batch))", maximum: batch.quantity, from: page,
            cancel: { [weak self] in self?.prompting = false }, submit: { [self] quantity in
                prompting = false
                guard model.batches.first(where: { $0.key == group }) == batch else { throw ServerUIRecordFailure.staleSelection }
                model.togglePreparedDraft(batch, quantity: quantity)
            }, report: report)
    }

    func delete(group: String, from page: UIViewController, source: UIView, report: @escaping (any Error) -> Void) throws {
        guard !isBusy, let batch = model.batches.first(where: { $0.key == group }), batch.addressable else { throw ServerUIRecordFailure.busy }
        prompting = true
        let submit: (Double?) async throws -> Void = { [self] quantity in
            prompting = false
            guard model.batches.first(where: { $0.key == group }) == batch else { throw ServerUIRecordFailure.staleSelection }
            await model.delete(batch, quantity: quantity)
            if let error = model.error { throw ServerUIRecordFailure.unavailable(error) }
        }
        if batch.quantity > 1 {
            UKServerUIRecordPrompts.quantity(title: "Delete \(model.batchName(batch))", maximum: batch.quantity, from: page,
                cancel: { [weak self] in self?.prompting = false }, submit: { try await submit($0) }, report: report)
        } else {
            UKServerUIRecordPrompts.confirm(AlertCopy.delete("Item", named: model.batchName(batch),
                detail: "It will be removed from the \(batch.locationPhrase)."), from: page, source: source,
                cancel: { [weak self] in self?.prompting = false }, submit: { try await submit(nil) }, report: report)
        }
    }
}

extension InventoryCompositionProvider {
    /// Sort/filter controls edit a detached value until Apply.
    public func preferencesForm(sort: Bool) throws -> ServerUIValueForm {
        let current = draft
        var fields: [ServerUIFormValue] = sort ? [
            .choice("sort", "Sort By", current.sort.rawValue, InventorySortMode.allCases.map { .init($0.title, $0.rawValue) }, control: .options),
            .choice("direction", "Sort Direction", current.direction.rawValue, InventorySortDirection.allCases.map { .init($0.title, $0.rawValue) }, control: .options),
        ] : [
            .choice("filter", "Show", current.filter.rawValue, InventoryFilterMode.allCases.map { .init($0.title, $0.rawValue) }, control: .options),
        ]
        if sort {
            fields[0].optionDetails = Dictionary(uniqueKeysWithValues: InventorySortMode.allCases.map { ($0.rawValue, $0.subtitle) })
            fields[1].optionDetails = Dictionary(uniqueKeysWithValues: InventorySortDirection.allCases.map { ($0.rawValue, $0.hint) })
        } else {
            fields[0].optionDetails = Dictionary(uniqueKeysWithValues: InventoryFilterMode.allCases.map { ($0.rawValue, $0.subtitle) })
        }
        return try ServerUIValueForm(identity: .init(ownerId: sourceID, recordId: sort ? "sort" : "filter"), fields: fields,
            defaults: sort ? ["sort": .string(InventorySortMode.title.rawValue), "direction": .string(InventorySortDirection.ascending.rawValue)] : ["filter": .string(InventoryFilterMode.all.rawValue)],
            grouping: { fields in fields.map { .init(id: $0.key, title: $0.label, fields: [$0]) } }) { [self] values in
            var next = current
            if sort {
                guard let mode = try InventorySortMode(rawValue: values.formString("sort")),
                      let direction = try InventorySortDirection(rawValue: values.formString("direction")) else {
                    throw ServerUIRecordFailure.invalidValue
                }
                next.sort = mode; next.direction = direction
            } else {
                guard let filter = try InventoryFilterMode(rawValue: values.formString("filter")) else {
                    throw ServerUIRecordFailure.invalidValue
                }
                next.filter = filter
            }
            apply(next)
        }
    }
}
#endif
