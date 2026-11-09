#if os(iOS) && DEBUG
import HassCore
import UIKit

// Owned by the Settings lane. Pages: settings.
extension UKGallery {
    /// `FENTON_GALLERY=settings`: the Settings tab's root list under the shell's page chrome (house backdrop, header fade), on an
    /// empty store, so the scroll cost probe and journeys reach the tab without signing in (``SettingsGallery``). Reads
    /// `FENTON_BACKDROP_FIXTURE`, `FENTON_BACKDROP_BLUR`, `FENTON_GALLERY_CLEAN` and the port's `FENTON_GALLERY_FLYOUT` through
    /// ``UKGalleryChrome``. Rows that open a sheet or push do nothing here without the shell.
    static func settings(_ page: ComponentGallery.Page) -> UIViewController? {
        guard page == .settings else { return nil }
        let context = UKGalleryChrome.context()
        return UKGalleryChrome.wrap(UKSettingsViewController(context: context), context: context)
    }
}
#endif
