import HassCore
import HassDesign
import SwiftUI

extension InventoryEditorModel {
    /// The item name plus the batch's qualifier (`Black Beans expiring Oct 14, 2026`), as the web's
    /// `${title}${qualifier}` in control labels and prompts.
    func batchName(_ batch: InventoryBatch) -> String {
        title + qualifier(batch)
    }

    /// The sheet's subtitle (mockup n6-item-editor): `Quantity 3 · In the Pantry`, without the place when the batches
    /// sit in different places.
    var summary: String {
        let quantity = "Quantity \(InventoryFormat.quantity(batches.reduce(0) { $0 + $1.quantity }))"
        let places = Set(batches.map(\.locationPhrase))
        guard places.count == 1, let place = places.first else { return quantity }
        return "\(quantity) · In the \(place.capitalized)"
    }

    /// A batch's group header: `Expires Jun 9, 2027 · In the Pantry` with several batches, the place alone with one
    /// (the sheet title already names the item).
    func header(_ batch: InventoryBatch) -> String {
        multipleBatches ? "\(heading(batch)) · \(locationLine(batch))" : locationLine(batch)
    }

    /// Batches with a quantity or expiry draft.
    var changedBatches: [InventoryBatch] { batches.filter(hasChanges) }

    /// Saves every changed batch in turn (the edit sheet's one Save), stopping at the first error, then applies the
    /// prepared-food drafts. Each batch runs the same calls its own Save made before direction G; ``isFinished`` is set by
    /// the first that succeeds.
    func saveChanges() async {
        for batch in changedBatches {
            await save(batch)
            if error != nil { return }
        }
        await savePrepared()
    }

    /// Under the editor's first group and the Add Item review's details (mockups n6-item-editor, n6-scan-review).
    static let preparedFoodNote = "Prepared Food marks an item that does not need classification."

    /// Puts every batch's drafts back (Reset Changes).
    func resetChanges() {
        for batch in changedBatches { reset(batch) }
    }
}

/// How many of a batch a delete or prepared-food change applies to.
enum EditorPrompt: Identifiable {
    case delete(InventoryBatch, qualifier: String)
    case prepared(InventoryBatch, qualifier: String)

    var batch: InventoryBatch {
        switch self {
        case let .delete(batch, _), let .prepared(batch, _): batch
        }
    }

    var id: String {
        switch self {
        case let .delete(batch, _): "delete-\(batch.key)"
        case let .prepared(batch, _): "prepared-\(batch.key)"
        }
    }

    var title: String {
        switch self {
        case let .delete(_, qualifier): "Delete \(qualifier)"
        case let .prepared(batch, qualifier): batch.preparedFood ? "Unmark \(qualifier) as Prepared" : "Mark \(qualifier) as Prepared"
        }
    }

    var message: String {
        let max = InventoryFormat.quantity(batch.quantity)
        switch self {
        case .delete: return "Choose how many to delete. Enter a number from 1 to \(max)."
        case .prepared: return "Choose how many to change. Enter a number from 1 to \(max)."
        }
    }

    var confirmTitle: String {
        switch self {
        case .delete: "Delete"
        case .prepared: "Change"
        }
    }

    /// Applies the prompt to the entered quantity (1 to the batch's quantity), or reports it as invalid.
    @MainActor
    func submit(_ text: String, to model: InventoryEditorModel) async {
        guard let quantity = InventoryFormat.parseQuantity(text), quantity >= 1, quantity <= batch.quantity else {
            model.reportInvalidQuantity(max: batch.quantity)
            return
        }
        switch self {
        case .delete: await model.delete(batch, quantity: quantity)
        case .prepared: model.togglePreparedDraft(batch, quantity: quantity)
        }
    }

    /// Delete on a batch: the prompt asking how many when it holds more than one; otherwise deletes it and
    /// returns `nil`.
    @MainActor
    static func delete(_ batch: InventoryBatch, in model: InventoryEditorModel) async -> EditorPrompt? {
        guard batch.quantity <= 1 else { return .delete(batch, qualifier: model.batchName(batch)) }
        await model.delete(batch)
        return nil
    }

    /// Prepared food flipped on a batch: the prompt asking how many when it holds more than one; otherwise
    /// drafts the change (saved with Save) and returns `nil`.
    @MainActor
    static func prepared(_ batch: InventoryBatch, in model: InventoryEditorModel) async -> EditorPrompt? {
        guard batch.quantity <= 1 else { return .prepared(batch, qualifier: model.batchName(batch)) }
        model.togglePreparedDraft(batch)
        return nil
    }
}
