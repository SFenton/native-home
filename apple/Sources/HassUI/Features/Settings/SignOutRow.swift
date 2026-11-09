import HassDesign
import SwiftUI

/// The Sign Out row, on the Your Summary sheet's Profile tab and in Home Assistant settings. Pressing it asks first
/// (``AlertCopy/signOut``); once confirmed it waits on the server, and the row itself answers: an inline arc and
/// "Signing Out" take the label's place, at full strength, while the rest of the screen is disabled by the caller
/// (HIG Progress indicators: show progress where the action was; owner decision 2026-10-24, `proposals/loading-states`
/// section 4).
///
/// Sign Out needs a connection by design: with Location on, the server has to unlink this phone from the person or the
/// phone would keep reporting presence for an account it left. Offline there is no local-only sign out; the failure
/// alert says why (``AlertCopy/signOutFailed``).
struct SignOutRow {
    /// Confirmed sign-out is waiting on the server.
    var isSigningOut: Bool
    var identifier: String
    var action: () -> Void

    /// What the row says and VoiceOver reads while busy.
    static let busyTitle = "Signing Out"

}
