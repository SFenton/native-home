#if os(iOS)
import HassCore
import UIKit

extension UKScreens {
    /// The Vacuums page on the app's connection (`VacuumsScreen`).
    static func vacuums(_ context: UKContext) -> UIViewController {
        guard let connection = context.connection else { return UKPlaceholderViewController(title: "Vacuums", symbol: "fan") }
        return UKVacuumsViewController(context: context, caller: connection) { vacuum in
            makeSheetPage(vacuum: vacuum, connection: connection, context: context)
        }
    }

    /// A vacuum's sheet page on the app's connection; the Vacuums page and a room's vacuum card open the same one. Nil without a connection.
    static func sheetPage(for vacuum: VacuumConfig, context: UKContext) -> UKVacuumSheetViewController? {
        guard let connection = context.connection else { return nil }
        return makeSheetPage(vacuum: vacuum, connection: connection, context: context)
    }

    private static func makeSheetPage(vacuum: VacuumConfig, connection: HassConnection, context: UKContext) -> UKVacuumSheetViewController {
        let sheetContext = context.with { $0.surface = .sheet }
        return UKVacuumSheetViewController(controller: VacuumController(vacuum: vacuum, store: connection.store, caller: connection),
                                           loader: ValetudoMapLoader(), server: connection.server, catalog: connection, services: nil, context: sheetContext)
    }
}
#endif
