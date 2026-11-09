import HassCore
import HassDesign
import SwiftUI

/// Runs a ``ReconnectingIndicator`` from the connection and shares it with every page's header: one instance, so a page pushed in
/// the middle of an outage already shows the arc. The arc follows a connection that is retrying with a network path; with no
/// path the app is offline and the offline chip speaks (``OfflineOverlay``).
struct ReconnectingIndicatorHost {
    /// What is spoken when the arc lights (`true`) or clears.
    static func announcement(isLit: Bool, isFirstConnect: Bool = false) -> String {
        if isFirstConnect { return isLit ? "Connecting to Home Assistant." : "Connected to Home Assistant." }
        return isLit ? "Reconnecting to Home Assistant. Values may be out of date." : "Reconnected to Home Assistant."
    }
}
