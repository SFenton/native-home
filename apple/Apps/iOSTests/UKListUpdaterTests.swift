import HassDesign
import UIKit
import XCTest
@testable import HassUI

/// The applier behind every diffable list (`UKListUpdater`): which applies animate, what a person-caused removal announces and where focus
/// lands, with an injected apply closure so no window or screen reader is needed.
@MainActor
final class UKListUpdaterTests: XCTestCase {
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Int, String>

    private var clock: TimeInterval = 100
    private var spoken: [String] = []
    private var focused: [IndexPath?] = []
    private var animatedApplies: [Bool] = []
    private var generation = 1

    private func makeUpdater(generation: (() -> Int?)? = nil, holdsOnlyForRemovals: Bool = false) -> UKListUpdater<Int, String> {
        let updater = UKListUpdater<Int, String>(surface: "Test", collectionView: nil, dataSource: nil, generation: generation,
                                                 holdsOnlyForRemovals: holdsOnlyForRemovals)
        updater.hooks.now = { [unowned self] in clock }
        updater.hooks.reduceMotion = { false }
        updater.hooks.announce = { [unowned self] in spoken.append($0) }
        updater.hooks.focus = { [unowned self] _, path in focused.append(path) }
        return updater
    }

    private func snapshot(_ ids: [String]) -> Snapshot {
        var snapshot = Snapshot()
        snapshot.appendSections([0])
        snapshot.appendItems(ids)
        return snapshot
    }

    private func apply(_ updater: UKListUpdater<Int, String>, _ ids: [String], from old: [String], cause: ListUpdateCause = .live, window: Bool = true) {
        updater.run(snapshot(ids), old: snapshot(old), cause: cause, hasWindow: window) { [unowned self] _, animated, done in
            animatedApplies.append(animated)
            done()
        }
    }

    /// An updater that has already shown its first snapshot.
    private func primed(generation: (() -> Int?)? = nil) -> UKListUpdater<Int, String> {
        let updater = makeUpdater(generation: generation)
        apply(updater, ["a", "b"], from: [])
        animatedApplies.removeAll()
        return updater
    }

    func testFirstApplyNeverAnimates() {
        let updater = makeUpdater()
        apply(updater, ["a", "b"], from: [])
        XCTAssertEqual(animatedApplies, [false])
        XCTAssertEqual(updater.lastPlan?.transition, ListUpdateTransition.none)
    }

    func testALiveRemovalOnScreenAnimatesAndSaysNothing() {
        let updater = primed()
        apply(updater, ["a"], from: ["a", "b"])
        XCTAssertEqual(animatedApplies, [true])
        XCTAssertEqual(updater.lastPlan?.cause, .live)
        XCTAssertTrue(spoken.isEmpty)
        XCTAssertTrue(focused.isEmpty)
    }

    func testATicketedRemovalAnimatesAnnouncesAndMovesFocus() {
        let updater = primed()
        updater.expectRemoval(of: ["a"], title: "Honey")
        apply(updater, ["b"], from: ["a", "b"])
        XCTAssertEqual(animatedApplies, [true])
        XCTAssertEqual(updater.lastPlan?.cause, .person)
        XCTAssertEqual(spoken, ["Honey deleted"])
        XCTAssertEqual(focused.count, 1)
    }

    func testAReapplyNeverAnimatesEvenForATicket() {
        var counter = 1
        let updater = primed { counter }
        counter = 2 // the store handed its state back (a reconnect)
        updater.expectRemoval(of: ["a"], title: "Honey")
        apply(updater, ["b"], from: ["a", "b"])
        XCTAssertEqual(animatedApplies, [false])
        clock += 3 // the window closes
        apply(updater, ["b", "c"], from: ["b"])
        XCTAssertEqual(animatedApplies, [false, true])
    }

    func testAResetNeverAnimates() {
        let updater = primed()
        apply(updater, ["a"], from: ["a", "b"], cause: .reset)
        XCTAssertEqual(animatedApplies, [false])
    }

    func testAListOffScreenNeverAnimates() {
        let updater = primed()
        apply(updater, ["a"], from: ["a", "b"], window: false)
        XCTAssertEqual(animatedApplies, [false])
    }

    func testAnExpiredTicketAnnouncesNothing() {
        let updater = primed()
        updater.expectRemoval(of: ["a"], title: "Honey")
        clock += 11
        apply(updater, ["b"], from: ["a", "b"])
        XCTAssertTrue(spoken.isEmpty)
        XCTAssertTrue(focused.isEmpty)
    }

    func testACancelledTicketAnnouncesNothing() {
        let updater = primed()
        updater.expectRemoval(of: ["a"], title: "Honey")
        updater.cancelExpectation(of: ["a"])
        apply(updater, ["b"], from: ["a", "b"])
        XCTAssertTrue(spoken.isEmpty)
    }

    func testAnInsertionComingBackAnimatesWithoutAnAnnouncement() {
        let updater = primed()
        updater.expectInsertion(of: ["c"])
        apply(updater, ["a", "b", "c"], from: ["a", "b"])
        XCTAssertEqual(animatedApplies, [true])
        XCTAssertTrue(spoken.isEmpty)
    }

    func testReduceMotionFadesInsteadOfSliding() {
        let updater = primed()
        updater.hooks.reduceMotion = { true }
        apply(updater, ["a"], from: ["a", "b"])
        XCTAssertEqual(updater.lastPlan?.transition, .fade)
        XCTAssertEqual(animatedApplies, [false], "the change itself applies at once; the leaving cells fade first")
    }

    func testARedrawInPlaceNeverAnimates() {
        let updater = primed()
        var next = snapshot(["a", "b"])
        next.reconfigureItems(["a"])
        updater.run(next, old: snapshot(["a", "b"]), cause: .live, hasWindow: true) { [unowned self] _, animated, done in
            animatedApplies.append(animated)
            done()
        }
        XCTAssertEqual(animatedApplies, [false])
    }

    // MARK: A removal is not cut short

    /// A removal whose animation is still playing (its completion is held), then another apply.
    private func removalInFlight(_ updater: UKListUpdater<Int, String>, held: inout [() -> Void]) {
        var completions: [() -> Void] = []
        updater.run(snapshot(["a"]), old: snapshot(["a", "b"]), cause: .live, hasWindow: true) { [unowned self] _, animated, done in
            animatedApplies.append(animated)
            completions.append(done)
        }
        held = completions
    }

    func testAnApplyDuringTheRemovalWaitsForItToFinish() {
        let updater = primed()
        var held: [() -> Void] = []
        removalInFlight(updater, held: &held)
        XCTAssertEqual(animatedApplies, [true], "the removal animates")
        XCTAssertTrue(updater.isAnimating)
        // The server's answer redraws the same rows with a reconfigure while the rows are still collapsing.
        var redraw = snapshot(["a"])
        redraw.reconfigureItems(["a"])
        updater.run(redraw, old: snapshot(["a"]), cause: .live, hasWindow: true) { [unowned self] _, animated, done in
            animatedApplies.append(animated)
            done()
        }
        XCTAssertEqual(animatedApplies, [true], "no second apply lands mid-animation: it would cut the system animation short and read as a snap")
        held.forEach { $0() }
        XCTAssertEqual(animatedApplies, [true, false], "it runs, unanimated, once the removal has finished")
        XCTAssertFalse(updater.isAnimating)
    }

    /// UIKit's completion arriving after the watchdog let the list go must not end the signpost interval a second time (a trap in
    /// `Telemetry.end`, verifier 2026-11-06).
    func testTheCompletionAfterTheWatchdogDoesNotEndThePlayTwice() async {
        let updater = primed()
        updater.watchdogSeconds = 0.05
        var held: [() -> Void] = []
        removalInFlight(updater, held: &held)
        XCTAssertTrue(updater.isAnimating)
        var ran = false
        var redraw = snapshot(["a"])
        redraw.reconfigureItems(["a"])
        updater.run(redraw, old: snapshot(["a"]), cause: .live, hasWindow: true, completion: { ran = true }) { _, _, done in done() }
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(updater.isAnimating, "the watchdog let the list go")
        XCTAssertTrue(ran, "and the waiting apply ran")
        held.forEach { $0() } // The late completion arrives.
        XCTAssertFalse(updater.isAnimating)
    }

    func testAnApplyThatChangesNothingIsNotAppliedAtAll() {
        let updater = primed()
        apply(updater, ["a", "b"], from: ["a", "b"])
        XCTAssertTrue(animatedApplies.isEmpty, "the same rows again touch nothing")
    }

    func testSeveralQueuedAppliesRunInOrder() {
        let updater = primed()
        var held: [() -> Void] = []
        removalInFlight(updater, held: &held)
        var order: [String] = []
        for name in ["one", "two"] {
            var next = snapshot(["a"])
            next.reconfigureItems(["a"])
            updater.run(next, old: snapshot(["a"]), cause: .live, hasWindow: true, completion: { order.append(name) }) { _, _, done in done() }
        }
        XCTAssertTrue(order.isEmpty)
        held.forEach { $0() }
        XCTAssertEqual(order, ["one", "two"])
    }

    func testAnApplyQueuedBehindAnAnimationLandsOnTheRowsTheModelHas() {
        let updater = primed()
        var shown = snapshot(["a", "b"])
        var held: [() -> Void] = []
        func perform(_ next: Snapshot, _ animated: Bool, _ done: @escaping () -> Void) {
            animatedApplies.append(animated)
            shown = next
            if animated { held.append(done) } else { done() }
        }
        // b leaves and the animation is still playing (its completion is held) ...
        updater.run(snapshot(["a"]), current: { shown }, cause: .live, hasWindow: true, perform: perform)
        XCTAssertTrue(updater.isAnimating)
        // ... when c arrives and then goes again. Both were asked for while the list showed [a], so compared with that list the second one
        // looked like "nothing changed" and c stayed.
        updater.run(snapshot(["a", "c"]), current: { shown }, cause: .live, hasWindow: true, perform: perform)
        updater.run(snapshot(["a"]), current: { shown }, cause: .live, hasWindow: true, perform: perform)
        XCTAssertEqual(shown.itemIdentifiers, ["a"], "nothing is applied while the animation plays")
        held.forEach { $0() }
        XCTAssertEqual(shown.itemIdentifiers, ["a"], "the list ends on the rows the model has, not on the first queued snapshot")
    }

    func testAnApplyQueuedBehindAnAnimationKeepsWhatTheOlderOneAskedToRedraw() {
        let updater = primed()
        var shown = snapshot(["a", "b", "c"])
        var held: [() -> Void] = []
        var redrawn: [[String]] = []
        func perform(_ next: Snapshot, _ animated: Bool, _ done: @escaping () -> Void) {
            animatedApplies.append(animated)
            redrawn.append(next.reconfiguredItemIdentifiers.sorted())
            shown = next
            if animated { held.append(done) } else { done() }
        }
        updater.run(snapshot(["a", "c"]), current: { shown }, cause: .live, hasWindow: true, perform: perform)
        var older = snapshot(["a", "c"])
        older.reconfigureItems(["a"])
        updater.run(older, current: { shown }, cause: .live, hasWindow: true, perform: perform)
        var newer = snapshot(["a", "c"])
        newer.reconfigureItems(["c"])
        updater.run(newer, current: { shown }, cause: .live, hasWindow: true, perform: perform)
        held.forEach { $0() }
        XCTAssertEqual(redrawn.last, ["a", "c"], "both redraws survive the fold into the newest snapshot")
    }

    // MARK: A redraw does not replace a queued removal

    /// A list of three whose `c` is leaving (the animation is playing, its completion held); behind it a person's removal of `b` is queued,
    /// then a redraw-only request. Returns what the list shows once the animation ends.
    private func removalThenRedraw(redrawing matches: @escaping (String) -> Bool) -> (shown: [String], redrawn: [String], order: [String]) {
        let updater = makeUpdater()
        var shown = snapshot(["a", "b", "c"])
        var held: [() -> Void] = []
        var redrawn: [String] = []
        var order: [String] = []
        func perform(_ next: Snapshot, _ animated: Bool, _ done: @escaping () -> Void) {
            animatedApplies.append(animated)
            shown = next
            redrawn = next.reconfiguredItemIdentifiers.sorted()
            if animated { held.append(done) } else { done() }
        }
        updater.run(shown, old: nil, current: { shown }, cause: .reset, hasWindow: true, perform: perform) // the first apply
        updater.run(snapshot(["a", "b"]), current: { shown }, cause: .live, hasWindow: true, completion: { order.append("playing") }, perform: perform)
        XCTAssertTrue(updater.isAnimating)
        updater.expectRemoval(of: ["b"], title: "Bee")
        updater.run(snapshot(["a"]), current: { shown }, cause: .live, hasWindow: true, completion: { order.append("removal") }, perform: perform)
        // The redraw builds on the list as it stands (the one with b still in it); it must not put b back.
        updater.redraw(where: matches, current: { shown }, hasWindow: true, completion: { order.append("redraw") }, perform: perform)
        XCTAssertEqual(shown.itemIdentifiers, ["a", "b"], "nothing is applied while the animation plays")
        held.removeFirst()()
        while !held.isEmpty { held.removeFirst()() }
        return (shown.itemIdentifiers, redrawn, order)
    }

    func testAHeaderRedrawBehindAQueuedRemovalKeepsTheRemovalAndItsAnnouncementOnce() {
        let result = removalThenRedraw(redrawing: { $0 == "a" })
        XCTAssertEqual(result.shown, ["a"], "the row is gone")
        XCTAssertEqual(result.redrawn, ["a"], "and the redraw landed")
        XCTAssertEqual(spoken, ["Bee deleted"], "the announcement fires once")
    }

    func testASelectionRedrawBehindAQueuedRemovalKeepsTheRemovalAndItsAnnouncementOnce() {
        let result = removalThenRedraw(redrawing: { _ in true })
        XCTAssertEqual(result.shown, ["a"], "the row is gone")
        XCTAssertEqual(result.redrawn, ["a"], "and every row still listed was redrawn")
        XCTAssertEqual(spoken, ["Bee deleted"], "the announcement fires once")
    }

    func testCompletionsRunInOrderAcrossAFold() {
        let result = removalThenRedraw(redrawing: { _ in true })
        XCTAssertEqual(result.order, ["playing", "removal", "redraw"], "each completion runs once, in the order the updates were asked for")
    }

    func testARedrawWhenNothingIsPlayingAppliesAtOnceAndUnanimated() {
        let updater = primed()
        var shown = snapshot(["a", "b"])
        var redrawn: [String] = []
        updater.redraw(where: { $0 == "b" }, current: { shown }, hasWindow: true, perform: { [unowned self] next, animated, done in
            animatedApplies.append(animated)
            redrawn = next.reconfiguredItemIdentifiers
            shown = next
            done()
        })
        XCTAssertEqual(animatedApplies, [false])
        XCTAssertEqual(redrawn, ["b"])
        XCTAssertEqual(shown.itemIdentifiers, ["a", "b"])
    }

    // MARK: A reset is never skipped; a skipped update still completes

    func testAResetAlwaysAppliesAndCompletesOnce() {
        let updater = primed()
        var completions = 0
        updater.run(snapshot(["a", "b"]), old: snapshot(["a", "b"]), cause: .reset, hasWindow: true, completion: { completions += 1 }) { [unowned self] _, animated, done in
            animatedApplies.append(animated)
            done()
        }
        XCTAssertEqual(animatedApplies, [false], "the same rows again are still applied: a reset replaces the list")
        XCTAssertEqual(completions, 1)
    }

    func testASkippedUpdateStillCompletesOnce() {
        let updater = primed()
        var completions = 0
        updater.run(snapshot(["a", "b"]), old: snapshot(["a", "b"]), cause: .live, hasWindow: true, completion: { completions += 1 }) { [unowned self] _, animated, done in
            animatedApplies.append(animated)
            done()
        }
        XCTAssertTrue(animatedApplies.isEmpty, "nothing changed, nothing applied")
        XCTAssertEqual(completions, 1, "and the completion still runs, once")
    }

    func testASkippedUpdateQueuedBehindAnAnimationStillCompletesOnce() {
        let updater = primed()
        var held: [() -> Void] = []
        removalInFlight(updater, held: &held)
        var completions = 0
        updater.run(snapshot(["a"]), old: snapshot(["a"]), cause: .live, hasWindow: true, completion: { completions += 1 }) { [unowned self] _, animated, done in
            animatedApplies.append(animated)
            done()
        }
        XCTAssertEqual(completions, 0, "it waits for the animation")
        held.forEach { $0() }
        XCTAssertEqual(completions, 1, "then completes once")
    }

    // MARK: A form applies section changes as they come

    func testAFormDoesNotHoldBackAnUnticketedAnimatedChange() {
        let updater = makeUpdater(holdsOnlyForRemovals: true)
        var shown = snapshot(["a", "b"])
        var held: [() -> Void] = []
        func perform(_ next: Snapshot, _ animated: Bool, _ done: @escaping () -> Void) {
            animatedApplies.append(animated)
            shown = next
            if animated { held.append(done) } else { done() }
        }
        updater.run(shown, old: nil, current: { shown }, cause: .reset, hasWindow: true, perform: perform)
        updater.run(snapshot(["a"]), current: { shown }, cause: .live, hasWindow: true, perform: perform)
        XCTAssertTrue(updater.isAnimating)
        updater.run(snapshot(["a", "c"]), current: { shown }, cause: .live, hasWindow: true, perform: perform)
        XCTAssertEqual(shown.itemIdentifiers, ["a", "c"], "the second change is applied while the first still plays")
        held.forEach { $0() }
        XCTAssertFalse(updater.isAnimating)
    }

    func testAFormStillHoldsBackWhatFollowsAPersonsRemoval() {
        let updater = makeUpdater(holdsOnlyForRemovals: true)
        var shown = snapshot(["a", "b"])
        var held: [() -> Void] = []
        func perform(_ next: Snapshot, _ animated: Bool, _ done: @escaping () -> Void) {
            animatedApplies.append(animated)
            shown = next
            if animated { held.append(done) } else { done() }
        }
        updater.run(shown, old: nil, current: { shown }, cause: .reset, hasWindow: true, perform: perform)
        updater.expectRemoval(of: ["b"], title: "Bee")
        updater.run(snapshot(["a"]), current: { shown }, cause: .live, hasWindow: true, perform: perform)
        updater.run(snapshot(["a", "c"]), current: { shown }, cause: .live, hasWindow: true, perform: perform)
        XCTAssertEqual(shown.itemIdentifiers, ["a"], "the removal keeps playing; what follows waits")
        held.forEach { $0() }
        XCTAssertEqual(shown.itemIdentifiers, ["a", "c"], "and lands when it ends")
        XCTAssertEqual(spoken, ["Bee deleted"])
    }

    // MARK: A fade never lets a stale list overwrite a newer one

    func testAFormFadeHoldsALaterResetSoItsStaleListCannotOverwriteIt() {
        let updater = makeUpdater(holdsOnlyForRemovals: true)
        updater.hooks.reduceMotion = { true }
        var shown = snapshot(["a", "b"])
        var finishFade: (() -> Void)?
        updater.fadeOut = { _, done in finishFade = done }
        var applied: [[String]] = []
        func perform(_ next: Snapshot, _ animated: Bool, _ done: @escaping () -> Void) {
            applied.append(next.itemIdentifiers)
            shown = next
            done()
        }
        updater.run(shown, old: nil, current: { shown }, cause: .reset, hasWindow: true, perform: perform)
        applied.removeAll()
        // b leaves under Reduce Motion: its cells fade (held open here), then the list changes.
        updater.run(snapshot(["a"]), current: { shown }, cause: .live, hasWindow: true, perform: perform)
        XCTAssertTrue(updater.isAnimating)
        // A reset arrives inside the fade window.
        updater.run(snapshot(["a", "c"]), current: { shown }, cause: .reset, hasWindow: true, perform: perform)
        XCTAssertTrue(applied.isEmpty, "nothing is applied while the fade plays")
        finishFade?()
        XCTAssertEqual(applied, [["a"], ["a", "c"]], "the fade's list lands first and the reset after it")
        XCTAssertEqual(shown.itemIdentifiers, ["a", "c"], "so the list ends on the newer rows")
        XCTAssertFalse(updater.isAnimating)
    }

    // MARK: The play counters

    func testALateCompletionAfterTheWatchdogLeavesTheCounterAtZero() async {
        let updater = primed()
        updater.watchdogSeconds = 0.05
        var held: [() -> Void] = []
        removalInFlight(updater, held: &held)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(updater.isAnimating, "the watchdog let the list go")
        held.forEach { $0() } // The late completion arrives and must not count a second time.
        XCTAssertFalse(updater.isAnimating)
        var again: [() -> Void] = []
        updater.run(snapshot(["b"]), old: snapshot(["a", "b"]), cause: .live, hasWindow: true) { [unowned self] _, animated, done in
            animatedApplies.append(animated)
            again.append(done)
        }
        XCTAssertTrue(updater.isAnimating, "a counter taken below zero would read as idle while this play runs")
        again.forEach { $0() }
        XCTAssertFalse(updater.isAnimating)
    }

    func testOnePlayEndingDoesNotEndAnotherThatIsStillPlaying() {
        let updater = makeUpdater(holdsOnlyForRemovals: true)
        var shown = snapshot(["a", "b", "c"])
        var held: [() -> Void] = []
        func perform(_ next: Snapshot, _ animated: Bool, _ done: @escaping () -> Void) {
            shown = next
            if animated { held.append(done) } else { done() }
        }
        updater.run(shown, old: nil, current: { shown }, cause: .reset, hasWindow: true, perform: perform)
        // A form applies two unticketed animated changes without waiting for the first.
        updater.run(snapshot(["a", "b"]), current: { shown }, cause: .live, hasWindow: true, perform: perform)
        updater.run(snapshot(["a"]), current: { shown }, cause: .live, hasWindow: true, perform: perform)
        XCTAssertEqual(held.count, 2, "both are playing at once")
        held.removeFirst()()
        XCTAssertTrue(updater.isAnimating, "the first ending leaves the second playing")
        held.removeFirst()()
        XCTAssertFalse(updater.isAnimating)
    }

    // MARK: A redraw queued before any snapshot

    private func removalPlaying(_ updater: UKListUpdater<Int, String>, shown: inout Snapshot, held: inout [() -> Void]) {
        var current = shown
        var pending: [() -> Void] = []
        updater.run(snapshot(["a"]), old: current, cause: .live, hasWindow: true) { next, _, done in
            current = next
            pending.append(done)
        }
        shown = current
        held = pending
    }

    func testARedrawQueuedBeforeAnySnapshotRedrawsTheListAsItStandsThen() {
        let updater = primed()
        var shown = snapshot(["a", "b"])
        var held: [() -> Void] = []
        removalPlaying(updater, shown: &shown, held: &held)
        XCTAssertTrue(updater.isAnimating)
        var last: Snapshot?
        updater.redraw(where: { $0 == "a" }, current: { self.snapshot(["a"]) }, hasWindow: true, perform: { next, _, done in
            last = next
            done()
        })
        XCTAssertNil(last, "it waits for the removal")
        held.forEach { $0() }
        XCTAssertEqual(last?.itemIdentifiers, ["a"])
        XCTAssertEqual(last?.reconfiguredItemIdentifiers, ["a"], "and then redraws the row")
    }

    func testARedrawQueuedBeforeASnapshotIsKeptWhenTheSnapshotArrives() {
        let updater = primed()
        var shown = snapshot(["a", "b"])
        var held: [() -> Void] = []
        removalPlaying(updater, shown: &shown, held: &held)
        var last: Snapshot?
        func record(_ next: Snapshot, _ animated: Bool, _ done: @escaping () -> Void) {
            last = next
            done()
        }
        updater.redraw(where: { $0 == "a" }, current: { self.snapshot(["a"]) }, hasWindow: true, perform: record)
        updater.run(snapshot(["a", "c"]), current: { self.snapshot(["a"]) }, cause: .live, hasWindow: true, perform: record)
        held.forEach { $0() }
        XCTAssertEqual(last?.itemIdentifiers, ["a", "c"], "the snapshot that arrived later is the list")
        XCTAssertEqual(last?.reconfiguredItemIdentifiers, ["a"], "and the earlier redraw is still in it")
    }

    func testFocusLandsOnTheRowThatTookThePlace() {
        XCTAssertEqual(UKListUpdater<Int, String>.nextRow(removed: ["b"], before: ["a", "b", "c"], after: ["a", "c"]), "c")
        XCTAssertEqual(UKListUpdater<Int, String>.nextRow(removed: ["c"], before: ["a", "b", "c"], after: ["a", "b"]), "b")
        XCTAssertNil(UKListUpdater<Int, String>.nextRow(removed: ["a"], before: ["a"], after: []))
    }

    func testTheModuleCardCornersAnimateOnlyOnScreen() {
        let card = UKModuleRowBackgroundView()
        card.frame = CGRect(x: 0, y: 0, width: 300, height: 60)
        card.configure(density: .dense, surface: .page, isFirst: false, isLast: true, selected: false)
        XCTAssertEqual(card.layer.maskedCorners, [.layerMinXMaxYCorner, .layerMaxXMaxYCorner])
        // Off screen the change is at once, whatever `animated` says.
        card.configure(density: .dense, surface: .page, isFirst: false, isLast: false, selected: false, animated: true)
        XCTAssertEqual(card.layer.cornerRadius, 0)
        XCTAssertTrue(card.layer.maskedCorners.isEmpty)
    }
}
