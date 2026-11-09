import HassCore
import HassDesign
import SwiftUI

/// A detail page pushed inside the thermostat sheet (web `ThermostatModalDetail`).
enum ClimateRoute: Hashable {
    case room(String)
    case predictive
    case eco(ClimateConfig.EcoOption)
    case tracking(ClimateConfig.TrackingPage)

    /// The page title (web `thermostatModalDetailTitle`).
    var title: String {
        switch self {
        case let .room(key): ClimateConfig.room(key: key)?.title ?? "Room"
        case .predictive: "Predictive Comfort"
        case let .eco(option): option.title
        case let .tracking(page): page.title
        }
    }

    /// The tab the route belongs to.
    var tab: ClimateConfig.Tab {
        switch self {
        case .room: .rooms
        case .predictive, .eco: .automation
        case .tracking: .tracking
        }
    }

    /// `room:living_room`, `predictive`, `eco-critical`, `selected-rooms`… (gallery launch argument).
    init?(token: String) {
        if token.hasPrefix("room:") {
            let key = String(token.dropFirst(5))
            guard ClimateConfig.room(key: key) != nil else { return nil }
            self = .room(key)
        } else if token == "predictive" {
            self = .predictive
        } else if let option = ClimateConfig.EcoOption(rawValue: token) {
            self = .eco(option)
        } else if let page = ClimateConfig.TrackingPage(rawValue: token) {
            self = .tracking(page)
        } else {
            return nil
        }
    }
}
