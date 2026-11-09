#if os(iOS) && DEBUG
import HassCore
import UIKit

/// `HomePageGallery(kind: .customLights)` in UIKit: the Custom Lights page on the fixture state with the recording caller, for
/// `FENTON_GALLERY=custom-lights`. `FENTON_GALLERY_LIGHT=<entity>` opens a light's sheet at once; `FENTON_GALLERY_CLEAN=1` leaves the
/// last-call line out. The lead's `UKGallery.rooms` returns this for the `custom-lights` page.
@MainActor
enum UKCustomLightsGalleryPage {
    static func make() -> UIViewController {
        let (store, recorder) = UKRoomsLastCall.fixture()
        let context = UKGalleryChrome.context(store: store, caller: recorder)
        let environment = ProcessInfo.processInfo.environment
        let light = CustomLightsConfig.lights.first { $0.entityId == environment["FENTON_GALLERY_LIGHT"] }
        let page = UKCustomLightsViewController(context: context, openLight: light)
        return UKRoomsLastCall.container(wrapping: UKGalleryChrome.wrap(page, context: context), recorder: recorder)
    }
}
#endif
