#if os(iOS) && DEBUG
import Foundation

/// When a gallery page may present the sheet its launch setting asks for (`FENTON_GALLERY_MODAL_OPEN`).
///
/// A reused journey app resets the gallery by dismissing every sheet without animation, emptying the tree for
/// ``GalleryReset/blankInterval`` and embedding a new page. On a slow host the new page's one `viewDidAppear` can come before the
/// window has it or while the old sheet's dismissal is still settling, and a `present` then is dropped: the journey waited 20 s for a
/// sheet that never came (hosted Smoke, iPad and Duo, 2026-11-08). The page asks this type on every chance and tries again.
enum UKGalleryAutoOpen {
    /// What the page does next.
    enum Decision: Equatable {
        /// Present the sheet now.
        case present
        /// Try again shortly: the page is not in a window, or a transition is in flight.
        case wait
        /// Stop: the sheet is already up or something else is presented.
        case stop
    }

    /// How long to wait between tries, in seconds.
    static let retryInterval = 0.25

    /// How many times to try before giving up.
    static let maxAttempts = 24

    /// The next step.
    /// - Parameters:
    ///   - hasWindow: The page is in a window.
    ///   - isTransitioning: The page or its parents are mid-transition (being presented, moved or dismissed).
    ///   - isPresenting: The page already presents a view controller.
    ///   - didOpen: The page has presented the requested sheet.
    static func decide(hasWindow: Bool, isTransitioning: Bool, isPresenting: Bool, didOpen: Bool) -> Decision {
        if didOpen || isPresenting { return .stop }
        return hasWindow && !isTransitioning ? .present : .wait
    }
}
#endif
