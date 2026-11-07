import Foundation
import HassCore
import HassDesign
import SwiftUI

extension InventoryModels {
    private struct Entry {
        weak var connection: HassConnection?
        var models: InventoryModels
    }

    private static var registry: [ObjectIdentifier: Entry] = [:]

    /// The signed-in connection's page models, created on first use. Every stack and the Summary sheet's Expired Food tab
    /// read the same ones, so a page keeps its rows between visits and an edit made in one shows in the others.
    static func shared(for connection: HassConnection) -> InventoryModels {
        registry = registry.filter { $0.value.connection != nil }
        let key = ObjectIdentifier(connection)
        if let entry = registry[key] { return entry.models }
        let created = InventoryModels(client: EverShelfClient(caller: connection))
        registry[key] = Entry(connection: connection, models: created)
        return created
    }
}
