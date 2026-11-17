/// What a diffable list does when it applies a snapshot that adds or removes rows: the system animation, a fade under Reduce Motion,
/// or nothing. The rules live here, pure and tested; `UKListUpdater` only carries them out. Pattern:
/// `.agents/patterns/list-row-removal.md`; the reapply rule is the one ``TileActionSetTransition`` uses.
public enum ListUpdateTransition: Equatable, Sendable {
    /// Apply at once, with no motion.
    case none
    /// Apply with the system list animation (rows fade and collapse, the neighbours slide).
    case animate
    /// Reduce Motion: the leaving and arriving rows cross-fade; nothing slides.
    case fade

    /// How long after a reapply (a snapshot restore, a first live set, a reconnect) a change still counts as part of it.
    public static let reapplyWindow: Duration = .seconds(2)

    /// Decides what a snapshot does.
    ///
    /// Order matters, and each rule has a test:
    /// 1. A change that only redraws rows in place (nothing added, removed or moved) never animates.
    /// 2. No window (nothing to see), the first apply, and a reapply (reconnect, cold launch from the disk snapshot) apply at once:
    ///    No reload on reopen.
    /// 3. A ``ListUpdateCause/reset`` (search, sort, filter, page switch) replaces the list at once.
    /// 4. Live and person changes animate; Reduce Motion fades instead.
    public static func decide(
        hasWindow: Bool,
        isFirstApply: Bool,
        isReapply: Bool,
        isStructural: Bool,
        cause: ListUpdateCause,
        reduceMotion: Bool
    ) -> ListUpdateTransition {
        guard isStructural else { return .none }
        guard hasWindow, !isFirstApply, !isReapply else { return .none }
        guard cause != .reset else { return .none }
        return reduceMotion ? .fade : .animate
    }

    /// Whether a change `elapsed` after the last reapply is part of it (nil: none happened).
    public static func isReapply(elapsedSinceReapply elapsed: Duration?) -> Bool {
        guard let elapsed else { return false }
        return elapsed < reapplyWindow
    }
}
