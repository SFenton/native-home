#if DEBUG
import Foundation
import HassCore
import HassDesign
import SwiftUI

/// Gallery page for the location permission screen: presents it as the app will, over a plain page, starting at
/// one permission stage. Continue plays the system's answer (While Using, then Always) so journeys can walk the
/// steps; Open Settings and Close are recorded on the `Last action` line.
///
/// Environment (optional): `FENTON_GALLERY_LOCATION=not-determined|when-in-use|always|denied|reduced-accuracy`
/// (default `not-determined`), or `when-in-use-asked`: While Using after the Always alert was shown once.
struct LocationGallery {

    /// The extra gallery stage: While Using after iOS showed its one Always alert.
    static let askedStage = "when-in-use-asked"




    /// The permission after the person picks the highlighted option in the alert `permission` leads to.
    static func answer(to permission: LocationPermission) -> LocationPermission {
        switch permission.authorization {
        case .notDetermined: LocationPermission(authorization: .whenInUse)
        case .whenInUse: LocationPermission(authorization: .always)
        case .always, .denied, .restricted: permission
        }
    }

    /// The permission that shows `stage`.
    static func permission(for stage: LocationPermission.Stage) -> LocationPermission {
        switch stage {
        case .notDetermined: .notDetermined
        case .whenInUse: LocationPermission(authorization: .whenInUse)
        case .always: LocationPermission(authorization: .always)
        case .denied: LocationPermission(authorization: .denied)
        case .reducedAccuracy: LocationPermission(authorization: .always, isPrecise: false)
        }
    }
}
#endif
