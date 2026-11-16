#if os(iOS) && DEBUG
import HassCore
import UIKit

/// `FENTON_GALLERY=<page>` in the port: the same fixture page as ``ComponentGallery``, drawn by UIKit. Each lane owns one
/// `UKGallery.<lane>(_:)` in `Gallery/UK<Lane>Gallery.swift` that returns its pages' controllers and nil for any other
/// page; the router asks each in turn. Debug builds only, like the SwiftUI galleries.
@MainActor
enum UKGalleryRouter {
    /// The root controller for the requested gallery page, or nil when no gallery was requested.
    static func requested() -> UIViewController? {
        if !ServerUIPreviewLaunch.isEnabled() { UKServerUIPreview.discardEnvironmentCredential() }
        if GalleryFixtureLaunch.isEnabled() {
            do {
                try GalleryFixtureLaunch.prepare()
            } catch {
                NSLog("Gallery fixture launch failed; the saved account remains isolated.")
                let failure = UKGalleryNoteViewController(title: "Fixture configuration unavailable")
                failure.view.accessibilityIdentifier = "gallery.fixture.failure"
                return failure
            }
        }
        if ServerUIPreviewLaunch.isEnabled() {
            return UKServerUIPreview()
        }
        guard let page = ComponentGallery.requested else { return nil }
        GalleryHouse.install()
        let lanes: [(ComponentGallery.Page) -> UIViewController?] = [
            UKGallery.design, UKGallery.designLists, UKGallery.designControls, UKGallery.shell, UKGallery.components, UKGallery.setup, UKGallery.liveActivity,
        ]
        for lane in lanes {
            if let controller = lane(page) { return controller }
        }
        return UINavigationController(rootViewController: UKGalleryNoteViewController(title: "Gallery: \(page.rawValue)"))
    }
}

/// The lanes' gallery pages (one extension file per lane).
@MainActor
enum UKGallery {}
#endif
