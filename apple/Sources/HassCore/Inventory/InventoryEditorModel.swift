import Foundation
import Observation

/// The item editor: one card's batches with quantity, expiry and prepared-food edits
/// (web `useInventoryItemDetails`, `EverShelfInventoryPanel.tsx:927`).
///
/// One commit model (HIG Entering data; owner, 2026-10-24): quantity, expiry and prepared food are drafts that wait for
/// Save and are dropped by Cancel. Only Delete, which asks first, applies at once.
///
/// Home Assistant owns every change. Saves and deletes run their service calls, then refresh the page;
/// a prepared-food change shows the expected batches at once and keeps them until a fresh, unfiltered read
/// confirms the same batches (or gives up after ``preparedDeadline`` and shows what the server has).
@MainActor
@Observable
public final class InventoryEditorModel {
    // MARK: - Types

    /// The action in flight.
    public enum Busy: Equatable, Sendable {
        case save(String)
        case delete(String)
        case prepared(String)

        /// Saves and deletes block dismissing the editor until they finish.
        public var blocksDismissal: Bool {
            if case .prepared = self { return false }
            return true
        }
    }

    /// A prepared-food change waiting for Save: `amount` units of the batch whose rows are `rowIds` become prepared
    /// (`makePrepared`) or plain again.
    public struct PreparedDraft: Equatable, Sendable {
        public var amount: Double
        public var rowIds: Set<Int>
        public var makePrepared: Bool
        /// The batch's key and expiry when the draft was made, to find the batch again after an expiry change.
        public var batchKey: String
        public var expiryDate: String
    }

    // MARK: - State

    /// The card's id (lowercased name).
    public let itemId: String
    /// Name for the title and labels.
    public let title: String
    /// The action in flight.
    public private(set) var busy: Busy?
    /// The last action's error.
    public private(set) var error: String?
    /// Set when the editor should close (a save finished, or the last stock was deleted).
    public private(set) var isFinished = false

    /// Edited quantities by batch key; missing means unchanged.
    public private(set) var quantityDrafts: [String: Double] = [:]
    /// Edited expiry dates (`YYYY-MM-DD` or empty) by batch key; missing means unchanged.
    public private(set) var expiryDrafts: [String: String] = [:]

    /// Prepared-food changes by batch key; missing means unchanged.
    public private(set) var preparedDrafts: [String: PreparedDraft] = [:]

    /// How often a prepared-food change re-reads the inventory (`PREPARED_REFRESH_RETRY_MS`).
    @ObservationIgnored public var preparedRetry: Duration = .seconds(1)
    /// How long a prepared-food projection is shown without confirmation (`PREPARED_OPTIMISTIC_REVERT_MS`).
    @ObservationIgnored public var preparedDeadline: Duration = .seconds(10)

    @ObservationIgnored private let list: InventoryListModel
    @ObservationIgnored private let initial: InventoryDisplayItem
    /// A fresh unfiltered read installed by a prepared-food change, until the page catches up.
    private var authorityOverride: InventoryDisplayItem?
    /// Batches shown instead of the server's: a prepared projection or the rest after a partial delete.
    private var batchOverride: [InventoryBatch]?

    // MARK: - Init

    /// Opens the editor on a card from `list`.
    public init(item: InventoryDisplayItem, list: InventoryListModel) {
        itemId = item.id
        title = item.name
        initial = item
        self.list = list
    }

    // MARK: - Derived

    /// The card as Home Assistant last reported it.
    public var authority: InventoryDisplayItem { authorityOverride ?? list.displayItem(id: itemId) ?? initial }

    /// Batches shown, soonest first.
    public var batches: [InventoryBatch] {
        batchOverride ?? InventoryCatalog.batches(authority, fallbackPhrase: list.space.phrase, calendar: list.calendar)
    }

    /// The page's calendar, for date pickers.
    public var calendar: InventoryCalendar { list.calendar }

    /// More than one batch: each gets a date heading and qualified labels.
    public var multipleBatches: Bool { batches.count > 1 }

    /// Words that make a batch's control labels unique.
    public func qualifier(_ batch: InventoryBatch) -> String {
        InventoryCatalog.batchQualifier(batch, multipleBatches: multipleBatches, calendar: list.calendar)
    }

    /// The batch's heading: its expiry when there are several batches, else the item name.
    public func heading(_ batch: InventoryBatch) -> String {
        multipleBatches ? InventoryCatalog.expiryInfo(batch.expiryDate.isEmpty ? nil : batch.expiryDate, calendar: list.calendar).label : title
    }

    /// `In the Fridge`, plus `· Prepared` (Title Case: direction G, Copy).
    public func locationLine(_ batch: InventoryBatch) -> String {
        let place = "In the \(batch.locationPhrase.capitalized)"
        return batch.preparedFood ? "\(place) · Prepared" : place
    }

    /// The draft quantity.
    public func quantity(_ batch: InventoryBatch) -> Double { quantityDrafts[batch.key] ?? batch.quantity }
    /// The draft expiry (`YYYY-MM-DD` or empty).
    public func expiry(_ batch: InventoryBatch) -> String { expiryDrafts[batch.key] ?? batch.expiryDate }
    /// Lowest quantity the stepper allows (`min(1, quantity)`).
    public func minimumQuantity(_ batch: InventoryBatch) -> Double { min(1, batch.quantity) }

    /// Stock change the draft would make.
    public func quantityDelta(_ batch: InventoryBatch) -> Double { quantity(batch) - batch.quantity }
    /// The draft differs from the batch.
    public func hasChanges(_ batch: InventoryBatch) -> Bool {
        quantityDelta(batch) != 0 || expiry(batch) != batch.expiryDate || preparedDrafts[batch.key] != nil
    }

    /// Whether the Prepared Food switch reads on: the batch's state, flipped by a draft that covers all of it.
    public func showsPrepared(_ batch: InventoryBatch) -> Bool {
        guard let draft = preparedDrafts[batch.key], draft.amount >= batch.quantity else { return batch.preparedFood }
        return draft.makePrepared
    }

    /// `Saving marks 2 as Prepared.`, when a prepared-food change waits.
    public func preparedHint(_ batch: InventoryBatch) -> String? {
        guard let draft = preparedDrafts[batch.key] else { return nil }
        let count = InventoryFormat.quantity(draft.amount)
        return draft.makePrepared ? "Saving marks \(count) as Prepared." : "Saving unmarks \(count) as Prepared."
    }

    /// `Saving adds 2 items to the fridge.`, when the quantity changed.
    public func hint(_ batch: InventoryBatch) -> String? {
        let delta = quantityDelta(batch)
        return delta == 0 ? nil : InventoryCatalog.quantityChangeHint(delta: delta, phrase: batch.locationPhrase)
    }

    /// Controls for a batch are disabled.
    public func isDisabled(_ batch: InventoryBatch) -> Bool { busy != nil || !batch.addressable }

    /// Saves and deletes block dismissing the editor.
    public var dismissalBlocked: Bool { busy?.blocksDismissal ?? false }

    // MARK: - Drafts

    /// Sets a batch's draft quantity, clamped to the stepper's range.
    public func setQuantity(_ value: Double, for batch: InventoryBatch) {
        quantityDrafts[batch.key] = min(max(value, minimumQuantity(batch)), InventoryCatalog.maxQuantity)
    }

    /// Sets a batch's draft expiry (`YYYY-MM-DD`, or empty for none).
    public func setExpiry(_ value: String, for batch: InventoryBatch) {
        expiryDrafts[batch.key] = value
    }

    /// Drafts flipping `quantity` of a batch (all of it when `nil`) to prepared food, or back; a second call drops the draft.
    public func togglePreparedDraft(_ batch: InventoryBatch, quantity: Double? = nil) {
        guard batch.addressable else { return }
        if preparedDrafts[batch.key] != nil {
            preparedDrafts[batch.key] = nil
            return
        }
        let amount = min(max(quantity ?? batch.quantity, 0), batch.quantity)
        guard amount > 0 else { return }
        preparedDrafts[batch.key] = PreparedDraft(amount: amount, rowIds: batch.rowIds, makePrepared: !batch.preparedFood,
                                                  batchKey: batch.key, expiryDate: batch.expiryDate)
    }

    /// Puts a batch's drafts back and clears the error.
    public func reset(_ batch: InventoryBatch) {
        quantityDrafts[batch.key] = nil
        expiryDrafts[batch.key] = nil
        preparedDrafts[batch.key] = nil
        error = nil
    }

    private func clearDrafts() {
        quantityDrafts = [:]
        expiryDrafts = [:]
        preparedDrafts = [:]
    }

    // MARK: - Save

    /// Applies a batch's drafts: removes stock row by row, moves each remaining unit to the new date, then
    /// adds stock to the batch. Closes the editor when done.
    public func save(_ batch: InventoryBatch) async {
        guard batch.addressable, busy == nil else { return }
        let expiry = expiry(batch).trimmingCharacters(in: .whitespaces)
        guard InventoryCalendar.isValidInput(expiry) else {
            error = "Use YYYY-MM-DD or clear the date."
            return
        }
        let delta = quantityDelta(batch)
        let expiryChanged = expiry != batch.expiryDate
        guard delta != 0 || expiryChanged else { return }
        if delta > 0, batch.sample.location == nil {
            error = "Home Assistant did not report a storage location for \(title), so more cannot be added."
            return
        }
        busy = .save(batch.key)
        error = nil
        do {
            let decrease = delta < 0
                ? InventoryCatalog.decreaseSteps(batch.rows, amount: -delta)
                : (steps: [InventoryDeleteStep](), remaining: batch.rows)
            try await list.client.delete(decrease.steps)
            if expiryChanged {
                for row in decrease.remaining {
                    for _ in 0..<Int(row.quantity.rounded(.up)) {
                        try await list.client.updateExpiry(inventoryId: row.inventoryId, expiryDate: expiry)
                    }
                }
            }
            if delta > 0 {
                try await list.client.restock(InventoryCatalog.restockData(batch.sample, quantity: delta, expiryDate: expiry))
            }
            busy = nil
            await refreshPage()
            isFinished = true
        } catch {
            busy = nil
            self.error = ServiceErrorText.message(for: error, fallback: "Unable to update item")
        }
    }

    // MARK: - Delete

    /// Deletes `quantity` of a batch (all of it when `nil`). Closes the editor when nothing is left.
    public func delete(_ batch: InventoryBatch, quantity: Double? = nil) async {
        guard batch.addressable, busy == nil else { return }
        let amount = quantity ?? batch.quantity
        let total = batches.reduce(0) { $0 + $1.quantity }
        let steps = amount < batch.quantity
            ? InventoryCatalog.decreaseSteps(batch.rows, amount: amount).steps
            : batch.rows.map { InventoryDeleteStep(inventoryId: $0.inventoryId) }
        busy = .delete(batch.key)
        error = nil
        do {
            try await list.client.delete(steps)
            let remaining = InventoryCatalog.batches(batches, after: steps)
            busy = nil
            if amount >= total {
                isFinished = true
                await refreshPage()
                return
            }
            batchOverride = remaining
            clearDrafts()
            await refreshPage()
        } catch {
            busy = nil
            self.error = ServiceErrorText.message(for: error, fallback: "Unable to delete item")
        }
    }

    /// Error for an out-of-range typed quantity (`delete.quantityError`).
    public func reportInvalidQuantity(max: Double) {
        error = "Enter a number from 1 to \(InventoryFormat.quantity(max))."
    }

    // MARK: - Prepared food

    /// Marks `quantity` of a batch as prepared food, or back. The editor shows the split at once.
    public func togglePrepared(_ batch: InventoryBatch, quantity: Double? = nil) async {
        guard batch.addressable, busy == nil else { return }
        let prepared = !batch.preparedFood
        let steps = InventoryCatalog.preparedSteps(batch.rows, amount: quantity ?? batch.quantity)
        let projected = InventoryCatalog.batches(batches, preparing: batch, steps: steps, to: prepared)
        let expected = InventoryCatalog.token(projected)
        batchOverride = projected
        clearDrafts()
        busy = .prepared(batch.key)
        error = nil
        let deadline = ContinuousClock.now.advanced(by: preparedDeadline)

        var mutationError: Error?
        do {
            for step in steps {
                try await list.client.setPreparedFood(inventoryId: step.inventoryId, prepared: prepared, quantity: step.quantity)
            }
        } catch {
            mutationError = error
        }

        var latest: InventoryDisplayItem?
        var readSucceeded = false
        var confirmed = false
        while true {
            if let fresh = try? await readAuthority() {
                readSucceeded = true
                latest = fresh.first
                // After a failed call, one read shows what actually changed.
                if mutationError != nil { break }
                if let item = fresh.first, InventoryCatalog.token(list.batches(for: item)) == expected {
                    confirmed = true
                    break
                }
            }
            guard ContinuousClock.now < deadline else { break }
            try? await Task.sleep(for: preparedRetry)
        }

        batchOverride = nil
        if readSucceeded { authorityOverride = latest }
        busy = nil
        if let mutationError {
            error = ServiceErrorText.message(for: mutationError, fallback: "Unable to update prepared food")
        } else if !confirmed {
            error = "Unable to update prepared food"
        }
        if confirmed { await refreshPage() }
    }

    /// Applies the prepared-food drafts, the last step of the editor's Save (after quantity and expiry, whose saves
    /// refresh the batches). Each draft finds its batch again by its rows, since an expiry change re-keys a batch. Closes the
    /// editor when every change succeeded; the first failure stays in ``error``.
    public func savePrepared() async {
        let drafts = preparedDrafts
        guard !drafts.isEmpty else { return }
        for draft in drafts.values {
            // Saving a new expiry can give the rows new ids, so a batch with the saved expiry also matches.
            let expiry = expiryDrafts[draft.batchKey] ?? draft.expiryDate
            guard let target = batches.first(where: {
                $0.preparedFood != draft.makePrepared && (!$0.rowIds.isDisjoint(with: draft.rowIds) || $0.expiryDate == expiry)
            }) else { continue }
            await togglePrepared(target, quantity: min(draft.amount, target.quantity))
            if error != nil { return }
        }
        preparedDrafts = [:]
        isFinished = true
    }

    /// A direct, unfiltered read of this card (`readAuthoritativeInventory`); empty when it's gone.
    private func readAuthority() async throws -> [InventoryDisplayItem] {
        let rows = try await list.client.pageItems(location: list.space.location, query: "")
        return InventoryCatalog.displayItems(rows.filter { $0.groupKey == itemId })
    }

    private func refreshPage() async {
        do {
            try await list.refresh()
            authorityOverride = nil
        } catch {
            if self.error == nil { self.error = ServiceErrorText.message(for: error, fallback: "Unable to update item") }
        }
    }
}
