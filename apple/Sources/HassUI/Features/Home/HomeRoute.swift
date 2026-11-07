import HassCore
import HassDesign
import SwiftUI

// MARK: - Registry

/// Pages pushed under Home: the room pages and the pages Quick Links opens (web `HOME_SUB_ROUTE_PATHS`,
/// `ha-sfenton-react-dash@9ac2a46:src/constants/routes.ts:90`).
///
/// This is the one route registry (owned by the Rooms lane). A feature lane adds its page by replacing its
/// placeholder in ``HomeRouteDestination``; it does not add a second navigation mechanism. Screens push a route
/// with `.navigationDestination(item:)` (``View/homeRouteDestination(_:)``), which works in a plain stack and in
/// the shell's path-driven stacks alike.
enum HomeRoute: Hashable, Identifiable, Codable, Sendable {
    /// A config-driven room page (`RoomsConfig.pages`), by web path.
    case room(String)
    /// `/media` (Media lane).
    case media
    /// `/custom-lights` (Media lane).
    case customLights
    /// `/sprinklers` (Media lane).
    case sprinklers
    /// `/vacuums` (Vacuums lane).
    case vacuums
    /// `/food` (Food lane).
    case food
    /// `/grocery-list` (Chores and To-Do lane), from the Kitchen's Groceries section.
    case groceryList

    var id: String { path }

    /// The web route path.
    var path: String {
        switch self {
        case let .room(id): id
        case .media: "media"
        case .customLights: "custom-lights"
        case .sprinklers: "sprinklers"
        case .vacuums: "vacuums"
        case .food: "food"
        case .groceryList: "grocery-list"
        }
    }

    /// The route for a web path, if the app has one.
    init?(path: String) {
        let path = path.split(separator: "/").last.map(String.init) ?? path
        switch path {
        case "media": self = .media
        case "custom-lights": self = .customLights
        case "sprinklers": self = .sprinklers
        case "vacuums": self = .vacuums
        case "food": self = .food
        case "grocery-list": self = .groceryList
        default:
            guard RoomsConfig.page(id: path) != nil else { return nil }
            self = .room(path)
        }
    }

    /// The route a notification link opens: this route's own paths, and the Food detail pages (`recipes`,
    /// `all-food` and the storage pages), which open on the Food hub.
    init?(pushPath path: String) {
        if let route = HomeRoute(path: path) {
            self = route
        } else if Self.foodDetailPaths.contains(path) {
            self = .food
        } else {
            return nil
        }
    }

    /// Food pages under the hub (web `HOME_FOOD_DETAIL_ROUTE_PATHS`, `routes.ts:120`).
    static let foodDetailPaths: Set<String> = ["recipes", "all-food", "pantry", "fridge", "freezer", "spice-rack", "cabinet"]

    /// The navigation title (web `DASHBOARD_ROUTES`).
    var title: String {
        switch self {
        case let .room(id): RoomsConfig.page(id: id)?.title ?? id
        case .media: "Media"
        case .customLights: "Custom Lights"
        case .sprinklers: "Sprinklers"
        case .vacuums: "Vacuums"
        case .food: "Food & Recipes"
        case .groceryList: "Grocery List"
        }
    }

    /// The web icon.
    var mdiIcon: String {
        switch self {
        case let .room(id): RoomNavigation.item(for: id)?.icon ?? "mdi:home"
        case .media: "mdi:remote"
        case .customLights: "mdi:lightbulb-group"
        case .sprinklers: "mdi:sprinkler-variant"
        case .vacuums: "mdi:robot-vacuum"
        case .food: "mdi:food-fork-drink"
        case .groceryList: "mdi:cart"
        }
    }
}
