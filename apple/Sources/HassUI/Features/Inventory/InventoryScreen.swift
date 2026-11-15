import HassCore
import HassDesign
import SwiftUI

extension InventoryEditorModel: @MainActor Identifiable {
    public var id: String { itemId }
}
