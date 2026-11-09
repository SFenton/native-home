#if DEBUG
import HassDesign
import SwiftUI

/// Every dial state the Climate page will need, from fixture values.
struct ThermostatDialGallery {
    /// A fixture and its title.
    struct Fixture: Identifiable {
        var id: String
        var name: String
        var configuration: ThermostatDialConfiguration
    }

    static let fixtures: [Fixture] = [
        Fixture(id: "heating", name: "Heating", configuration: .init(
            title: "Living Room", current: 68.5, targets: .single(72), action: "heating")),
        Fixture(id: "range", name: "Heat and cool range", configuration: .init(
            title: "Whole Home", current: 71, targets: .range(low: 68, high: 75), action: "idle")),
        Fixture(id: "cooling", name: "Cooling", configuration: .init(
            title: "Office", current: 76.5, targets: .single(73), action: "cooling")),
        Fixture(id: "off", name: "Off", configuration: .init(
            title: "Guest Room", current: 64, targets: .single(66), action: "off", isOff: true)),
        Fixture(id: "unavailable", name: "Unavailable", configuration: .init(
            title: "Garage", current: nil, targets: nil, action: "unavailable", isUnavailable: true)),
    ]



    /// `single 72.5` or `range 68-75`, for the last-commit line UI tests read.
    static func describe(_ targets: ThermostatTargets) -> String {
        switch targets {
        case let .single(value): "single \(ThermostatDialConfiguration.compact(value))"
        case let .range(low, high): "range \(ThermostatDialConfiguration.compact(low))-\(ThermostatDialConfiguration.compact(high))"
        }
    }
}
#endif
