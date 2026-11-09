import HassCore
import HassDesign
import SwiftUI

/// The Summary sheet's Profile-tab Location section (`.agents/pages/settings/location.md`, Entry points): Share Location with the
/// permission state, which opens ``LocationPermissionView``, and why this iPhone isn't on its person yet, if it isn't.
///
/// ``YourSummarySheet``'s Profile tab shows it when the session has a ``LocationCoordinator``: on iPhone and, since
/// 2026-10-27, on iPad. An iPad reports to its own device but is never added to a person, so its footer says that and no
/// link notice shows.
/// HIG: [Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles) (there is no switch: reporting
/// follows the permission) and [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy)
/// (the permission screen, not the system alert, is the way in).
struct LocationAccountSection {



    /// What reporting does, under the row.
    static let footer = "Whenever location access is on, this iPhone reports to Home Assistant as its own device, "
        + "and Home Assistant follows it for the person you sign in as."

    /// What reporting does on an iPad, which Home Assistant never ties to a person.
    static let footerWithoutPerson = "Whenever location access is on, this iPad reports to Home Assistant as its own device. "
        + "It doesn't change whether you are home or away."

    /// Why nothing is sent; nil while location can be reported.
    /// - Parameter stage: The permission's stage.
    static func warning(stage: LocationPermission.Stage) -> String? {
        switch stage {
        case .notDetermined: "Location access isn't set, so nothing is sent. Open Share Location to allow it."
        case .denied: "Location access is off, so nothing is sent. Open Share Location to turn it on in Settings."
        case .reducedAccuracy: "Precise Location is off, so Home Assistant can't tell whether you're home."
        case .whenInUse, .always: nil
        }
    }

    /// Why this iPhone isn't on its person yet; nil when it is, or before the first attempt.
    /// - Parameter outcome: What the last link attempt did.
    static func linkNotice(_ outcome: PresenceLinkOutcome?) -> String? {
        switch outcome {
        case .needsAdmin: "Home Assistant lets only administrators add this iPhone to a person. Ask an administrator to add it to yours."
        case .noPerson: "No person in Home Assistant uses your account yet, so it can't follow this iPhone. Ask an administrator to add one."
        case .trackerMissing: "Home Assistant hasn't created this iPhone's device yet. It will try again at the next sign-in."
        case .failed: "Couldn't add this iPhone to your person. It will try again at the next connection."
        case .linked, .alreadyLinked, .compositeManaged, nil: nil
        }
    }
}
