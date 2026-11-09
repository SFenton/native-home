import HassCore

/// Quantity prompts (the web's `window.prompt`s, as alerts with a field).
enum InventoryPrompt: Identifiable {
    case shopping(InventoryDisplayItem)
    case delete(InventoryDisplayItem, Double)

    var id: String {
        switch self {
        case let .shopping(item): "shop-\(item.id)"
        case let .delete(item, _): "delete-\(item.id)"
        }
    }

    var title: String {
        switch self {
        case let .shopping(item): "Add \(item.name) to Groceries"
        case let .delete(item, _): "Delete \(item.name)"
        }
    }

    var message: String {
        switch self {
        case let .shopping(item): "Quantity of \(item.name) to add to the grocery cart."
        case let .delete(item, stocked): "Choose how many \(item.name) to delete. Enter a number from 1 to \(InventoryFormat.quantity(stocked))."
        }
    }

    var confirmTitle: String {
        switch self {
        case .shopping: "Add"
        case .delete: "Delete"
        }
    }
}
