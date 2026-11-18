#if os(iOS)
import Observation

// MARK: - Screen presence

/// Whether a page is on screen: it appears when its view is about to show and goes when the view has left it (another tab selected, a page pushed over it).
///
/// It is an observable flag so a node that reads the second clock (`now-second`, `sh.countdown@1`) tracks it: while the page is away the node's
/// reads stay out of the tick, which stops one tick later, and when the page comes back the node runs again and starts it.
@MainActor
@Observable
final class UKServerUIScreenPresence {
    /// `true` from the page's `viewWillAppear` until its `viewDidDisappear`.
    var isOnScreen = false
}
#endif
