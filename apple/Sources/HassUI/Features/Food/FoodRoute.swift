import HassCore
import SwiftUI

/// An inventory page pushed from the Food hub: the Inventory lane's page with the stack's ``InventoryModels``
/// (the gallery's fixture server, else the signed-in connection), the same way ``inventoryDestinations()``
/// builds it.
struct FoodInventoryScreen {
    let space: InventorySpace


    /// The inventory page for one of the hub's EverShelf locations (`FoodConfig.spaces`).
    static func space(forLocation location: String) -> InventorySpace? {
        switch location {
        case "dispensa": .pantry
        case "frigo": .fridge
        case "freezer": .freezer
        case "spice_rack": .spiceRack
        case "cabinet": .cabinet
        default: nil
        }
    }
}
