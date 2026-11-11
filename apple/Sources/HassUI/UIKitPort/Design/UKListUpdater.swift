#if os(iOS)
import HassDesign
import HassTelemetry
import UIKit

/// Tests only: receives the removal announcements instead of VoiceOver. Held here, in HassUI, because a hosted test and the code under
/// test share this module's statics but not necessarily HassDesign's.
@MainActor
enum UKListAnnouncements {
    static var sink: ((String) -> Void)?
}

/// The one way a diffable list applies a snapshot (`.agents/patterns/list-row-removal.md`). It asks ``ListUpdateLedger`` what the apply
/// is, then plays it: the system list animation for a removal or insertion that is on screen (a person's, or one from elsewhere), a
/// fade under Reduce Motion, and nothing for a first apply, a reapply (reconnect, cold launch), an off-screen list or a reset.
///
/// A person-caused removal is registered first (a *ticket*), so the apply can say "<title> deleted" to VoiceOver and move focus to the
/// next row. Each animated apply is bracketed by a `LayoutChange` signpost (`page: ListRowRemoval.<surface>`) for
/// `tools/ios_motionperf.sh`. Cost: one O(n) id diff per apply on the main thread, no per-frame work.
///
/// ```swift
/// let updater = UKListUpdater(surface: "Chores", collectionView: collectionView, dataSource: dataSource) { store.reapplyGeneration }
/// updater.expectRemoval(of: [id], title: item.title)      // the person confirmed the delete
/// updater.apply(snapshot)                                  // instead of dataSource.apply(snapshot, animatingDifferences:)
/// ```
@MainActor
final class UKListUpdater<Section: Hashable & Sendable, Item: Hashable & Sendable> {
    /// What the apply touches, injected so a host test needs no screen reader or clock.
    @MainActor struct Hooks {
        var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
        var reduceMotion: () -> Bool = { UKMotion.reduceMotion }
        var announce: (String) -> Void = { UKListAnnouncements.sink?($0) ?? Announcer.announce($0) }
        var focus: (UICollectionView?, IndexPath?) -> Void = { collectionView, path in
            let target: Any? = path.flatMap { collectionView?.cellForItem(at: $0) } ?? collectionView
            UIAccessibility.post(notification: .layoutChanged, argument: target)
        }
    }

    /// An apply held back until the playing one ends.
    private struct Pending {
        /// The queued list; nil while only redraws are waiting (they build on the list as it stands when they run).
        var snapshot: NSDiffableDataSourceSnapshot<Section, Item>?
        var current: (() -> NSDiffableDataSourceSnapshot<Section, Item>)?
        /// nil while only redraws are waiting; a redraw never decides the motion.
        var cause: ListUpdateCause?
        var hasWindow: Bool
        var cornerNeighbours: [Item] = []
        /// Redraw-only requests: rows to reconfigure in whatever list ends up on screen.
        var redraws: [(Item) -> Bool] = []
        var completions: [() -> Void]
        var perform: Perform

        /// Folds a later arrival in. A redraw-only request joins the queued one, which keeps its snapshot, its ticketed removals and
        /// their announcement; a later snapshot replaces the queued one, keeping the rows the older one asked to redraw (reconfigure,
        /// reload) and its corner neighbours where they are still in the list. Every completion still runs, in order. A reset beats a
        /// person's change beats a live one.
        mutating func fold(_ newer: Pending) {
            completions += newer.completions
            redraws += newer.redraws
            hasWindow = newer.hasWindow
            current = newer.current ?? current
            perform = newer.perform
            guard var merged = newer.snapshot else { return }
            if let older = snapshot {
                let items = Set(merged.itemIdentifiers)
                let sections = Set(merged.sectionIdentifiers)
                merged.reconfigureItems(older.reconfiguredItemIdentifiers.filter { items.contains($0) })
                merged.reloadItems(older.reloadedItemIdentifiers.filter { items.contains($0) })
                merged.reloadSections(older.reloadedSectionIdentifiers.filter { sections.contains($0) })
            }
            snapshot = merged
            let causes = [cause, newer.cause].compactMap { $0 }
            cause = causes.contains(.reset) ? .reset : (causes.contains(.person) ? .person : .live)
            cornerNeighbours += newer.cornerNeighbours.filter { !cornerNeighbours.contains($0) }
        }
    }

    /// The `data source apply` the decision wraps: the snapshot, whether to animate, and a completion.
    typealias Perform = (NSDiffableDataSourceSnapshot<Section, Item>, Bool, @escaping () -> Void) -> Void

    /// The surface named in the signpost.
    let surface: String
    var hooks = Hooks()
    /// What the last apply decided (tests).
    private(set) var lastPlan: ListUpdateLedger<Item>.Plan?
    /// True while an animated apply is playing: cells redrawn then animate their module-card corners (``UKModuleRowBackgroundView``).
    var isAnimating: Bool { activePlays > 0 }
    /// Whether a new apply waits: for any animated apply, or (``holdsOnlyForRemovals``) only for a person's removal.
    private var isHolding: Bool { holdsOnlyForRemovals ? removalPlays > 0 || fadePlays > 0 : activePlays > 0 }
    private var activePlays = 0
    private var removalPlays = 0
    /// Under Reduce Motion a fade applies the snapshot it was started with once the cells have faded, so nothing may apply in between
    /// (it would be overwritten by the older list), even in a form.
    private var fadePlays = 0
    /// A form applies its section changes as they come, as the system does; only a person's removal, which moves focus and is announced,
    /// holds back what follows it. A list holds back anything that follows an animated apply.
    let holdsOnlyForRemovals: Bool
    /// Tests only: stands in for the cell fade of a Reduce Motion removal, so a test can hold the fade open and finish it by hand.
    var fadeOut: (([UICollectionViewCell], @escaping () -> Void) -> Void)?
    /// How long an animated apply may wait for UIKit's completion before the list is let go (scaled by the window's animation speed).
    var watchdogSeconds = 3.0

    private weak var collectionView: UICollectionView?
    private weak var dataSource: UICollectionViewDiffableDataSource<Section, Item>?
    private let generation: (() -> Int?)?
    private var ledger = ListUpdateLedger<Item>()
    private var hasApplied = false
    /// The apply that arrived while an animated one was playing. A second apply landing mid-animation (the server's answer redrawing the
    /// same rows, a reconfigure) would cut the system animation short and read as a snap, so it waits for the animation to end. Later
    /// arrivals fold into it: the newest snapshot is the truth, and what the older ones asked to redraw is carried over.
    private var pending: Pending?

    /// - Parameter generation: reads `EntityStore.reapplyGeneration`; nil for a list that is not fed by the store. The list should read it
    ///   inside the observation that renders it, so a reconnect applies while its window is open.
    init(surface: String, collectionView: UICollectionView?, dataSource: UICollectionViewDiffableDataSource<Section, Item>?,
         generation: (() -> Int?)? = nil, holdsOnlyForRemovals: Bool = false) {
        self.holdsOnlyForRemovals = holdsOnlyForRemovals
        self.surface = surface
        self.collectionView = collectionView
        self.dataSource = dataSource
        self.generation = generation
    }

    // MARK: Tickets

    /// A person is removing `ids`: they animate, are announced as "<title> deleted" and hand focus to the next row.
    func expectRemoval(of ids: [Item], title: String? = nil) {
        ledger.expectRemoval(of: ids, title: title, now: hooks.now())
    }

    /// A person is bringing `ids` back (undo, a failed action).
    func expectInsertion(of ids: [Item]) {
        ledger.expectInsertion(of: ids, now: hooks.now())
    }

    /// The call failed and the rows stay: no motion, no announcement.
    func cancelExpectation(of ids: [Item]) {
        ledger.cancelExpectation(of: ids)
    }

    // MARK: Apply

    /// Applies `snapshot`.
    /// - Parameters:
    ///   - cause: ``ListUpdateCause/live`` by default; ``ListUpdateCause/reset`` for search, sort, filter or a page switch.
    ///   - cornerNeighbours: rows whose card only changes corners (they became the first or last). They are redrawn in the same apply,
    ///     so their radius animates with the delete.
    ///   - completion: called when the apply, and any follow-up redraw, has finished.
    func apply(_ snapshot: NSDiffableDataSourceSnapshot<Section, Item>, cause: ListUpdateCause = .live, cornerNeighbours: [Item] = [],
               completion: (() -> Void)? = nil) {
        guard let dataSource else { return }
        run(snapshot, old: nil, current: { dataSource.snapshot() }, cause: cause, hasWindow: collectionView?.window != nil,
            cornerNeighbours: cornerNeighbours, completion: completion) { next, animated, done in
            dataSource.apply(next, animatingDifferences: animated, completion: done)
        }
    }

    /// The decision and its effects, around an injected `perform` (the data source's apply).
    /// - Parameters:
    ///   - old: the list as it stands now; nil reads `current` when the apply runs, because a queued apply must compare with the list as
    ///     it is after the animation, not as it was when the apply was asked for.
    ///   - current: reads the list as it stands; a test without a data source passes `old` instead.
    func run(_ snapshot: NSDiffableDataSourceSnapshot<Section, Item>, old: NSDiffableDataSourceSnapshot<Section, Item>? = nil,
             current: (() -> NSDiffableDataSourceSnapshot<Section, Item>)? = nil, cause: ListUpdateCause,
             hasWindow: Bool, cornerNeighbours: [Item] = [], completion: (() -> Void)? = nil, perform: @escaping Perform) {
        if isHolding {
            let held = Pending(snapshot: snapshot, current: current, cause: cause, hasWindow: hasWindow, cornerNeighbours: cornerNeighbours,
                               completions: completion.map { [$0] } ?? [], perform: perform)
            if pending == nil { pending = held } else { pending?.fold(held) }
            return
        }
        let old = old ?? current?() ?? snapshot
        let before = old.itemIdentifiers
        let after = snapshot.itemIdentifiers
        let remaining = Set(after)
        let was = Set(before)
        let removed = was.subtracting(remaining)
        let plan = ledger.plan(removed: removed, inserted: remaining.subtracting(was),
                               reloaded: !snapshot.reloadedSectionIdentifiers.isEmpty || !snapshot.reloadedItemIdentifiers.isEmpty, isFirstApply: !hasApplied, hasWindow: hasWindow,
                               cause: cause, reduceMotion: hooks.reduceMotion(), generation: generation.flatMap { $0() }, now: hooks.now())
        let wasApplied = hasApplied
        hasApplied = true
        lastPlan = plan
        // Nothing changed: no apply at all, so a redraw of the same rows cannot interrupt anything. A reset always applies: it replaces
        // the list, and the page on screen may have been redrawn around it.
        if plan.transition == .none, wasApplied, cause != .reset, survivors(cornerNeighbours, remaining).isEmpty, before == after, old.sectionIdentifiers == snapshot.sectionIdentifiers,
           snapshot.reconfiguredItemIdentifiers.isEmpty, snapshot.reloadedItemIdentifiers.isEmpty, snapshot.reloadedSectionIdentifiers.isEmpty {
            for title in plan.removedTitles { hooks.announce("\(title) deleted") }
            completion?()
            return
        }
        let neighbours = survivors(cornerNeighbours, remaining)
        var next = snapshot
        next.reconfigureItems(neighbours)
        let focusTarget = plan.removedByPerson ? Self.nextRow(removed: removed, before: before, after: after) : nil
        let finish: () -> Void = { [weak self] in
            guard let self else { return }
            if plan.removedByPerson { self.hooks.focus(self.collectionView, focusTarget.flatMap { self.dataSource?.indexPath(for: $0) }) }
            completion?()
        }
        // Said as the row starts to leave, not when its animation ends: VoiceOver should not wait on a transition.
        for title in plan.removedTitles { hooks.announce("\(title) deleted") }
        switch plan.transition {
        case .none:
            perform(next, false, finish)
        case .animate:
            play(next, person: plan.removedByPerson, perform: perform, finish: finish)
        case .fade:
            fade(next, leaving: removed, person: plan.removedByPerson, perform: perform, finish: finish)
        }
    }

    private func survivors(_ candidates: [Item], _ remaining: Set<Item>) -> [Item] { candidates.filter { remaining.contains($0) } }

    // MARK: Playing

    private func play(_ snapshot: NSDiffableDataSourceSnapshot<Section, Item>, person: Bool, perform: @escaping Perform, finish: @escaping () -> Void) {
        let play = begin(Play(Telemetry.begin(Telemetry.Name.layoutChange, page: "ListRowRemoval.\(surface)", "animated"), person: person))
        // If UIKit never reports the animation done, the list must not stay blocked. The wait follows the window's animation speed
        // (a slowed test run), so it never fires during a real animation.
        let speed = max(Double(collectionView?.window?.layer.speed ?? 1), 0.05)
        DispatchQueue.main.asyncAfter(deadline: .now() + watchdogSeconds / speed) { [weak self] in
            self?.endPlay(play)
        }
        perform(snapshot, true) { [weak self] in
            finish()
            self?.endPlay(play)
        }
    }

    /// One animated apply: its signpost interval, ended exactly once (the watchdog and UIKit's completion can both arrive).
    private final class Play {
        let interval: Telemetry.Interval
        /// Whether a person's removal is playing (it holds back what follows, even in a form).
        let person: Bool
        /// Whether this is a Reduce Motion fade, which applies a snapshot of its own after the fade.
        let fades: Bool
        var ended = false
        init(_ interval: Telemetry.Interval, person: Bool, fades: Bool = false) {
            self.interval = interval
            self.person = person
            self.fades = fades
        }
    }

    private func begin(_ play: Play) -> Play {
        activePlays += 1
        if play.person { removalPlays += 1 }
        if play.fades { fadePlays += 1 }
        return play
    }

    /// Ends a play once; a second call (the completion after the watchdog) ends nothing twice.
    private func endPlay(_ play: Play) {
        guard !play.ended else { return }
        play.ended = true
        activePlays -= 1
        if play.person { removalPlays -= 1 }
        if play.fades { fadePlays -= 1 }
        let interval = play.interval
        NextFrame.perform { Telemetry.end(interval) }
        drainQueued()
    }

    private func drainQueued() {
        guard !isHolding, let held = pending else { return }
        pending = nil
        let completions = held.completions
        let finish: () -> Void = { completions.forEach { $0() } }
        // The queued list, else (only redraws waited) the list as it stands now, with the redraws added.
        guard var next = held.snapshot ?? held.current?() else { finish(); return }
        next.reconfigureItems(next.itemIdentifiers.filter { item in held.redraws.contains { $0(item) } })
        run(next, old: nil, current: held.current, cause: held.cause ?? .reset, hasWindow: held.hasWindow, cornerNeighbours: held.cornerNeighbours,
            completion: finish, perform: held.perform)
    }

    // MARK: Redraw

    /// Redraws the rows `matches` selects, in place and unanimated, in the list as it stands. Used by a redraw that is not a change of
    /// rows (a header's height, a selection). While an animated apply plays it joins whatever is queued behind it, so it can neither cut
    /// the animation short nor replace a queued removal and lose its announcement.
    func redraw(where matches: @escaping (Item) -> Bool, completion: (() -> Void)? = nil) {
        guard let dataSource else { return }
        redraw(where: matches, current: { dataSource.snapshot() }, hasWindow: collectionView?.window != nil, completion: completion) { next, animated, done in
            dataSource.apply(next, animatingDifferences: animated, completion: done)
        }
    }

    /// ``redraw(where:completion:)`` around an injected `perform` and a reader of the list as it stands.
    func redraw(where matches: @escaping (Item) -> Bool, current: @escaping () -> NSDiffableDataSourceSnapshot<Section, Item>, hasWindow: Bool,
                completion: (() -> Void)? = nil, perform: @escaping Perform) {
        if isHolding {
            let held = Pending(snapshot: nil, current: current, cause: nil, hasWindow: hasWindow, redraws: [matches],
                               completions: completion.map { [$0] } ?? [], perform: perform)
            if pending == nil { pending = held } else { pending?.fold(held) }
            return
        }
        var next = current()
        next.reconfigureItems(next.itemIdentifiers.filter(matches))
        run(next, old: nil, current: current, cause: .reset, hasWindow: hasWindow, completion: completion, perform: perform)
    }

    /// Reduce Motion: the leaving rows fade out, then the list changes at once. Nothing slides.
    private func fade(_ snapshot: NSDiffableDataSourceSnapshot<Section, Item>, leaving: Set<Item>, person: Bool, perform: @escaping Perform,
                      finish: @escaping () -> Void) {
        let play = begin(Play(Telemetry.begin(Telemetry.Name.layoutChange, page: "ListRowRemoval.\(surface)", "reduced"), person: person, fades: true))
        let cells = leaving.compactMap { item in dataSource?.indexPath(for: item).flatMap { collectionView?.cellForItem(at: $0) } }
        let change = { [weak self] in
            perform(snapshot, false) {
                for cell in cells { cell.alpha = 1 }
                finish()
                self?.endPlay(play)
            }
        }
        if let fadeOut {
            fadeOut(cells, change)
        } else if cells.isEmpty {
            change()
        } else {
            UKMotion.animate(.quick, reduced: .quick, animations: { for cell in cells { cell.alpha = 0 } }, completion: { _ in change() })
        }
    }

    /// The row focus lands on after a removal: the first surviving row at or after the removed row's place, else the last one.
    static func nextRow(removed: Set<Item>, before: [Item], after: [Item]) -> Item? {
        guard let place = before.firstIndex(where: { removed.contains($0) }) else { return after.last }
        let survivors = Set(after)
        return before[place...].first(where: { survivors.contains($0) }) ?? after.last
    }
}
#endif
