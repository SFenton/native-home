import Foundation
import HassCore
import HassDesign
import SwiftUI

/// The reconnecting sign: a 20 pt white arc spinner in the header, left of Quick Links, that fades in once the connection has
/// been down for ``ReconnectingPolicy/delay`` and fades out when it is live again (owner, 2026-10-23, replacing the
/// "Reconnecting…" chip; `.agents/design/reconnecting-spinner.md`). No text: it is a status, so it has no tap action, and
/// VoiceOver reads its label.
///
/// ``ReconnectingIndicator`` decides when the arc is a bar item and when it is lit. The arc fades to `isLit` with a cross-fade
/// (opacity is not motion, so Reduce Motion keeps it; the spinner itself turns at half speed then, like every ``ArcSpinner``).
struct ReconnectingArc {
    /// What VoiceOver says.
    static let label = "Reconnecting to Home Assistant"
    /// What VoiceOver says for the first connect, before any state has arrived.
    static let connectingLabel = "Connecting to Home Assistant"

    /// How the arc sits in the bar.
    enum Metrics {
        /// The arc's diameter (``ArcSpinner/Size/compact``).
        static let diameter: CGFloat = 20
        /// The narrowest cell the bar gives a bar item (44 pt), which centres the arc: measured on the iPhone 17 Pro simulator
        /// (iOS 27), an arc with its trailing padding cancelled sat 19 pt from Quick Links, not 12, because the cell was 44 wide.
        static let cellWidth: CGFloat = HassTokens.minTarget

        /// How far the arc is drawn right of the middle of its cell so it ends at the cell's trailing edge, the way Profile's
        /// disc fills its cell: the gap to Quick Links is then the bar's own spacer, the same as Quick Links to Profile.
        ///
        /// On iOS 26.5 the bar gives Profile's hidden-glass cell 8 pt more, so Quick Links to Profile is 16 pt there
        /// (`direction-g.md`, "iOS 26.5 differs"); measured on the iPad simulator (26.5), the arc then sat 12 pt from Quick Links,
        /// so it is drawn 4 pt less far right to match.
        static var trailingShift: CGFloat { trailingShift(scale: 1) }

        /// The most the arc grows with Dynamic Type (HIG Typography; `.agents/design/reconnecting-spinner.md`): the bar
        /// item stays in a 44 pt cell, so the arc stops at 1.5× its default diameter.
        static let maxScale: CGFloat = 1.5

        /// ``trailingShift`` for an arc drawn `scale` times its default diameter: a larger arc ends at the same edge.
        static func trailingShift(scale: CGFloat) -> CGFloat {
            let base = (cellWidth - diameter * scale) / 2
            return ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0))
                ? base : base - 4
        }
    }

    let indicator: ReconnectingIndicator
    /// Quick Links follows the arc in the bar, so the arc is drawn to the trailing edge of its cell to sit Quick Links' gap away
    /// (iOS 26 and later, where the bar sizes the cell). On the Duo's rail the arc is alone in the page header and stays centred.
    let besideQuickLinks: Bool


}
