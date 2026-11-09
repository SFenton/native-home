#if os(iOS) && DEBUG
import HassCore
import UIKit

/// `HomePageGallery(kind: .sprinklers)` in UIKit: the Sprinklers page on the fixture state with the recording caller, for
/// `FENTON_GALLERY=sprinklers`. `FENTON_GALLERY_SPRINKLER=frontYard|backyard` opens a controller's sheet at once,
/// `FENTON_GALLERY_DETAIL=water-<zone>|schedule-<zone>` a page in it; `FENTON_GALLERY_CLEAN=1` leaves the last-call line out. The lead's
/// `UKGallery.rooms` returns this for the `sprinklers` page.
@MainActor
enum UKSprinklersGalleryPage {
    static func make() -> UIViewController {
        let (store, recorder) = UKRoomsLastCall.fixture()
        let context = UKGalleryChrome.context(store: store, caller: recorder)
        let environment = ProcessInfo.processInfo.environment
        let page = UKSprinklersViewController(context: context, openController: environment["FENTON_GALLERY_SPRINKLER"],
                                              detail: environment["FENTON_GALLERY_DETAIL"].flatMap(HomePageGallery.detail))
        return UKRoomsLastCall.container(wrapping: UKGalleryChrome.wrap(page, context: context), recorder: recorder)
    }
}
#endif
