import HassCore
import HassDesign
import SwiftUI

/// What the thermostat sheet opens on: a tab and, optionally, a detail page pushed on it.
struct ClimateSheetRequest: Identifiable, Hashable {
    var tab: ClimateConfig.Tab
    var route: ClimateRoute?
    var id: String { "\(tab.rawValue)-\(String(describing: route))" }
}

/// The Climate page (web `ThermostatPage`, `ha-sfenton-react-dash@9ac2a46:src/pages/DashboardViewPage.tsx:7397`).
/// Spec: `.agents/pages/climate/spec.md`; direction G mockup n3. Whole Home's dial straight on the wallpaper (no card,
/// owner 2026-10-16) with the compact Thermostat Hub pill under it, any notices, open doors and windows, then the three
/// Advanced Controls rows that open the sheet on their tab.
struct ClimatePage {





    /// How much of the Whole Home dial's empty bottom the hub pill reclaims.
    static let dialBottomOverlap: CGFloat = 36

    /// The web fans a range set on the global thermostat out to every room (`useCommitThermostatTemperature`);
    /// the eco-away thermostat and single targets go to the dial's own entity.
    static func wholeHomeCommitIds(dialEntityId: String, targets: ThermostatTargets) -> [String] {
        if dialEntityId == ClimateConfig.globalThermostatEntityId, case .range = targets {
            return ClimateConfig.roomClimateEntityIds
        }
        return [dialEntityId]
    }
}
