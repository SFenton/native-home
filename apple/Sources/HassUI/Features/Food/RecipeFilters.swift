import Foundation
import HassCore

/// The Filter sheet's values (web `RecipeFilterValues`).
struct RecipeFilters: Equatable, Sendable {
    var expiringOnly = false
    var expiringWithinDays = 7
    var minimumCoverage: Double = 0
    var availabilityWeight: Double = 100
    var expiryWeight: Double = 25

    /// Web `DEFAULT_RECIPE_FILTERS`.
    static let defaults = RecipeFilters()
    /// Expiry horizons offered (web `EXPIRY_HORIZONS`).
    static let horizons = [7, 30, 90]

    /// How many filters narrow the results: a minimum coverage and the expiring-only switch. The ranking weights only
    /// reorder results, so they are not counted.
    var activeCount: Int {
        (minimumCoverage > 0 ? 1 : 0) + (expiringOnly ? 1 : 0)
    }

    /// The Filter sheet's subtitle: "2 Filters On", or nil while none is on.
    var activeSummary: String? {
        switch activeCount {
        case 0: nil
        case 1: "1 Filter On"
        default: "\(activeCount) Filters On"
        }
    }

    /// The horizon's title and description.
    static func horizon(_ days: Int) -> (title: String, subtitle: String) {
        switch days {
        case 7: ("7 Days", "Use ingredients expiring within the next week.")
        case 30: ("30 Days", "Use ingredients expiring within the next month.")
        default: ("90 Days", "Use ingredients expiring within the next three months.")
        }
    }
}
