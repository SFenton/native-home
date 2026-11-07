import HassCore
import HassDesign
import SwiftUI

/// Sheets an inventory page presents.
enum InventorySheet: String, Identifiable {
    case sort, filter, scan
    var id: String { rawValue }
}

/// What an inventory page opens at launch.
enum InventoryLaunch: Equatable {
    case sheet(InventorySheet)
    /// The item editor for the card with this name.
    case editor(String)

    /// `sort`, `filter`, `scan` or `editor:<name>`.
    init?(_ raw: String) {
        if raw.hasPrefix("editor:") {
            self = .editor(String(raw.dropFirst("editor:".count)))
        } else if let sheet = InventorySheet(rawValue: raw) {
            self = .sheet(sheet)
        } else {
            return nil
        }
    }
}
