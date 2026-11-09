import CoreGraphics

/// Fixed flyout geometry.
enum NavigationFlyoutMetrics {
    /// Panel width at the default text size; the web rail is 248 px, widened for 44 pt rows and Dynamic Type.
    static let panelWidth: CGFloat = 300
    /// The share of the window the panel may take once it has grown with the text, when the window is wide enough to keep
    /// a scrim beside it.
    static let maxShare: CGFloat = 0.8
    /// Below this window width a panel that has outgrown its share takes the whole width (the folded iPhone Duo at
    /// accessibility sizes): a scrim strip too narrow to tap is worth less than the room for the words.
    static let fullWidthBelow: CGFloat = 600

    /// The panel's width: `preferred` (``panelWidth`` scaled with the text), kept to ``maxShare`` of the window, or the
    /// whole window when that leaves a window narrower than ``fullWidthBelow`` (same drawer, no new sheet).
    /// - Parameters:
    ///   - preferred: ``panelWidth`` scaled with Dynamic Type.
    ///   - available: The window's width.
    static func panelWidth(preferred: CGFloat, available: CGFloat) -> CGFloat {
        let ceiling = available < fullWidthBelow ? available : available * maxShare
        return Swift.min(preferred, ceiling)
    }
    /// Width of the leading-edge strip that opens the flyout with a swipe.
    static let edgeSwipeWidth: CGFloat = 20
    /// Horizontal travel that opens the flyout.
    static let edgeSwipeDistance: CGFloat = 60

    /// Whether a drag from the leading edge should open the flyout.
    /// - Parameters:
    ///   - startX: Where the drag began, from the leading edge.
    ///   - translation: Total movement.
    static func edgeSwipeOpens(startX: CGFloat, translation: CGSize) -> Bool {
        startX <= edgeSwipeWidth
            && translation.width >= edgeSwipeDistance
            && abs(translation.width) > abs(translation.height)
    }
}

