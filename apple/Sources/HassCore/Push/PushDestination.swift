import Foundation

/// The app page a dashboard route opens (web `primaryNavPathForRoute`, `routes.ts:156`).
public enum PushDestination: Equatable, Sendable {
    /// The root of a section: `overview` (Home), `security`, `thermostat` (Climate), `chores` and its sub-routes,
    /// `settings` and its sub-routes.
    case section(PushSection)
    /// A page pushed under Home, by web path (rooms, Food, Groceries, Vacuums, Media ...).
    case homePage(String)

    /// The destination for a dashboard route.
    /// - Parameter path: The web route path.
    public init(dashboardPath path: String) {
        switch path {
        case "overview", "home", "": self = .section(.home)
        case "security": self = .section(.security)
        case "thermostat", "climate": self = .section(.climate)
        case "chores", "groceries": self = .section(.chores)
        case _ where path.hasSuffix("-chores"): self = .section(.chores)
        case "settings", "admin", "guests-staying-over", "mach-e", "solo-trip", "special-device-modes", "to-do",
             "vacation", "vacation-mode":
            self = .section(.settings)
        default: self = .homePage(path)
        }
    }
}
