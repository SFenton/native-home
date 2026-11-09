import HassCore
import HassDesign
import SwiftUI

// MARK: - Colors

/// Colors for the away pages, from the web's card colors, checked at 4.5:1 for text.
enum AwayTint {
    /// Vacation Mode on (web `SWITCH_ACTIVE_COLOR` 67,160,71).
    static let vacation = Color(vacationToken)
    static let vacationToken = HassRGB(red: 0.26, green: 0.63, blue: 0.28)
    /// Vacation pending confirmation (web `SECURITY_COLOR` 30,136,229).
    static let pending = Color(pendingToken)
    static let pendingToken = HassRGB(red: 0.12, green: 0.53, blue: 0.90)
    /// Solo Trip (web `SOLO_TRIP_COLOR` 91,141,239).
    static let soloTrip = Color(soloTripToken)
    static let soloTripToken = HassRGB(red: 0.36, green: 0.55, blue: 0.94)
    /// A checked pre-vacation task: the green the mockups use for done (n5-vacation-mode), deeper on a light sheet.
    static let checked = HassTokens.Ink.success
}
