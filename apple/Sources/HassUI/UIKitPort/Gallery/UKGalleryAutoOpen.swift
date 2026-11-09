#if DEBUG
import Foundation

/// The decision logic for a gallery page that presents a sheet by itself (a launch setting such as `FENTON_GALLERY_MODAL_OPEN`).
///
/// A reused journey app resets the gallery by dismissing every sheet without animation, emptying the tree for
/// ``GalleryReset/blankInterval`` and embedding a new page. On a slow host the new page's `viewDidAppear` can come before the window
/// has the page or while the old sheet is still leaving, and a `present` then is dropped: the journey waited 20 s for a sheet that
/// never came (hosted Smoke, iPad and Duo, 2026-11-08). ``UKGalleryAutoOpener`` starts from `viewDidAppear`, asks ``step(_:)`` on
/// every turn, presents when it says so, and asks again after ``verifyInterval`` to see that the sheet came up. Only Foundation, so
/// the host tests run it.
struct UKGalleryAutoOpen: Equatable {
    /// What the page looks like on one turn.
    struct Snapshot: Equatable {
        /// The page is in a window.
        var hasWindow: Bool
        /// The page or its navigation controller is mid-transition.
        var isTransitioning: Bool
        /// The page presents a view controller.
        var isPresenting: Bool
        /// That presented controller is leaving (an old sheet a reset is still dismissing).
        var isDismissing: Bool
    }

    /// What the page does next.
    enum Decision: Equatable {
        /// Present the sheet now, then ask again after ``UKGalleryAutoOpen/verifyInterval``.
        case present
        /// Ask again after ``UKGalleryAutoOpen/retryInterval``.
        case wait
        /// A sheet is up: done.
        case stop
        /// The attempts ran out without a sheet: log it and stop.
        case giveUp
    }

    /// Seconds between turns while waiting.
    static let retryInterval = 0.25

    /// Seconds after a present before the page checks that the sheet came up.
    static let verifyInterval = 0.5

    /// Turns before giving up (worst case about 12 s, inside the journeys' 20 s wait).
    static let maxAttempts = 24

    /// Turns taken so far.
    private(set) var attempts = 0

    /// Whether a present was issued (so a turn that finds no sheet is a dropped present).
    private(set) var didPresent = false

    /// How many presents were dropped and issued again.
    private(set) var retriedPresents = 0

    /// Takes one turn.
    mutating func step(_ page: Snapshot) -> Decision {
        guard attempts < Self.maxAttempts else { return .giveUp }
        attempts += 1
        if page.isPresenting { return page.isDismissing ? .wait : .stop }
        guard page.hasWindow, !page.isTransitioning else { return .wait }
        if didPresent { retriedPresents += 1 }
        didPresent = true
        return .present
    }
}
#endif
