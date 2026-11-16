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
