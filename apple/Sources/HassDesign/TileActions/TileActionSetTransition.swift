import SwiftUI

/// What a tile does when its action set changes shape (an off remote's Power beside the chevron becoming a playing remote's
/// transport and volume below). The owner-approved exception to motion.md §6 ("live updates never move layout"), pattern:
/// `.agents/patterns/action-tiles.md`, "Availability". The rules live here, pure and tested; ``GlassTile`` only applies them.
public enum TileActionSetTransition: Equatable, Sendable {
    /// Apply at once: nothing changed shape, or a guard rail forbids motion.
    case none
    /// Hold the old discs and wait for scrolling to stop, then animate.
    case deferred
    /// Fade the old discs out with ``MotionTokens/quick``, animate the height with ``MotionTokens/standard``, fade the new in.
    case animate
    /// Reduce Motion: no height animation; the new discs cross-fade in over 0.2 s.
    case crossFade

    /// How long after a reapply (a snapshot restore, a first live set, a reconnect) a change still counts as part of it. The
    /// reconnect's full set arrives a moment after the socket reports ready.
    public static let reapplyWindow: Duration = .seconds(2)

    /// Decides what a change of shape does.
    ///
    /// Order matters, and each rule has a test:
    /// 1. An unchanged shape never animates (live values must not).
    /// 2. A reapply (reconnect, cold launch from the snapshot) applies at once: No reload on reopen.
    /// 3. Only a tile spanning its full row animates; others apply instantly (nothing reflows sideways).
    /// 4. While the page scrolls the change waits (``deferred``) and is decided again when scrolling ends.
    /// 5. Reduce Motion cross-fades; everything else animates.
    public static func decide(
        old: TileActionShape,
        new: TileActionShape,
        isFullRow: Bool,
        isScrolling: Bool,
        isReapply: Bool,
        reduceMotion: Bool
    ) -> TileActionSetTransition {
        guard old != new else { return .none }
        if isReapply { return .none }
        if !isFullRow { return .none }
        if isScrolling { return .deferred }
        return reduceMotion ? .crossFade : .animate
    }

    /// Whether a change `elapsed` after the last reapply is part of it (nil: none happened).
    public static func isReapply(elapsedSinceReapply elapsed: Duration?) -> Bool {
        guard let elapsed else { return false }
        return elapsed < reapplyWindow
    }
}

// MARK: - Environment

public extension EnvironmentValues {
    /// A counter that changes each time the whole state is handed back at once (`EntityStore.reapplyGeneration`: snapshot, first
    /// live set, reconnect). A tile whose actions change in the moments after it applies them without animation.
    @Entry var tileReapplyGeneration = 0
    /// Whether the tile spans its whole row, so it may animate a change of action set. Set by ``SwiftUICore/View/tileSpansFullRow(_:)``.
    @Entry var tileSpansFullRow = false
}

public extension View {
    /// Tells tiles inside that they span their whole row (a section's lead tile), so a change of action set animates their height.
    /// Other tiles apply the change at once, because a height change would move what sits beside and below them.
    func tileSpansFullRow(_ spans: Bool = true) -> some View {
        environment(\.tileSpansFullRow, spans)
    }
}
