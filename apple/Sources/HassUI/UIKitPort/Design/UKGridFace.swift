#if os(iOS)
import UIKit

// MARK: - The face a tile draws, for a grid grouped by state

/// The three faces a tile draws, and so the three states a grid group holds (`sh.grid-state-groups@1`).
enum UKGridFace: Equatable {
    /// Lit, filled, or tinted active.
    case active
    /// Off, or a state that draws no activity.
    case idle
    /// Cannot be used now.
    case unavailable
}

extension Notification.Name {
    /// Posted by a ``UKGlassTileView`` when the face it draws changed (its object is the tile), so a grouped grid can move it.
    static let ukTileFaceChanged = Notification.Name("UKTileFaceChanged")
}

extension UIView {
    /// The face this view draws: the first tile in it that is shown, or `idle` when it holds none (a child that draws no state).
    var ukGridFace: UKGridFace {
        if let tile = self as? UKGlassTileView { return tile.gridFace }
        for child in subviews where !child.isHidden {
            if let tile = child as? UKGlassTileView { return tile.gridFace }
            let nested = child.ukGridFace
            if nested != .idle { return nested }
        }
        return .idle
    }
}
#endif
