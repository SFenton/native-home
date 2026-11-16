#if os(iOS)
import HassCore
import HassDesign
import HassTelemetry
import UIKit

// MARK: - Plan

/// What one change of a state-styled tile does, layer by layer: only the layers that changed are listed, so the view touches nothing else
/// (`.agents/design/state-styled-tile.md`, Layers and Transitions). Built by ``UKStateTileTransition`` and carried out by the tile.
struct UKStateTilePlan: Equatable {
    /// The look to show.
    var look: StateTileLook
    /// The look on screen before, or nil for a first render or a reapply.
    var previous: StateTileLook?
    /// The layers that differ. Empty for a reapply.
    var changes: StateTileLook.Changes
    /// How the glyph changes; a replace becomes a plain set under Reduce Motion.
    var icon: StateTileLook.IconChange
    /// The disc and the arc cross-fade (on `MotionTokens.quick`, also under Reduce Motion).
    var slot: StateTileLook.SlotChange
    /// The colour cross-fade: `state`, or `stateReduced` under Reduce Motion; nil when the colour is untouched or this is a reapply.
    var colourFade: UKMotion.Token?
    /// A held effect to stop.
    var stopsEffect: Bool
    /// A held effect to start now, or a once-only effect to play after ``effectDelay``.
    var effect: StateTileLook.Indicator?
    /// Seconds before ``effect`` starts: the disc's fade-in when the arc leaves, so the wiggle plays on a visible disc.
    var effectDelay: TimeInterval
    /// Whether nothing animates: a first render, a cold launch or a reconnect reapply.
    var isInstant: Bool
}

// MARK: - Transition

/// The one component that moves a state-styled tile from one look to the next (`.agents/design/state-styled-tile.md`, Transitions).
///
/// It compares each layer's resolved value with the one on screen and hands the tile a ``UKStateTilePlan`` naming only what changed. It also
/// holds the flap guard (the in-progress look stays at least ``MotionTokens/StateTile/minimumInProgress``, states arriving meanwhile coalesce
/// and the latest wins), plays once-only effects after the disc fades in, and speaks the three announcements and no others. A first render, a
/// cold launch and a reconnect reapply (`reapply: true`) set every layer at once: no transition, no effect, no flap guard, no announcement.
@MainActor
final class UKStateTileTransition {
    /// Carries a plan out: the tile's views take the layers it names.
    var render: (UKStateTilePlan) -> Void = { _ in }
    /// Plays a once-only or held effect on the tile's glyph.
    var playEffect: (StateTileLook.Indicator) -> Void = { _ in }
    /// Speaks to VoiceOver with focus unmoved.
    var announce: (String) -> Void = { Announcer.announce($0) }
    /// The error haptic.
    var errorHaptic: () -> Void = { UKTapFeedback.failure() }
    /// Whether the tile's page is on screen: an off-screen tile announces nothing.
    var isPageVisible: () -> Bool = { true }
    /// Whether Reduce Motion is on. Tests override it.
    var reduceMotion: () -> Bool = { UKDesign.reduceMotion }
    /// Seconds on a monotonic clock. Tests override it.
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    /// Opens the `LayoutChange` signpost for one animated change (`reduced` names the Reduce Motion variant) and returns what ends it.
    /// Tests override it to count begin and end.
    var beginSignpost: (_ reduced: Bool) -> () -> Void = { reduced in
        let interval = Telemetry.begin(Telemetry.Name.layoutChange, page: "StateTile", reduced ? "reduced" : "animated")
        return { Telemetry.end(interval) }
    }
    /// Runs `work` on the main actor once `seconds` have passed: when the fade is due to settle. Tests override it to fire by hand.
    var afterSettle: (_ seconds: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Void = { seconds, work in
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            work()
        }
    }

    /// Test-only: the scheduler a transition built without one uses, so a hosted test fires the flap guard's release by hand.
    /// Nil in production, which uses ``TaskRevertScheduler``.
    static var schedulerOverride: (any RevertScheduler)?

    private let scheduler: any RevertScheduler
    private let title: () -> String

    /// What ``apply(_:reapply:)`` did with a look.
    enum Outcome { case rendered, held, unchanged }

    /// The look on screen.
    private(set) var shown: StateTileLook?
    /// The look waiting out the flap guard, if any; the latest one wins.
    private(set) var held: StateTileLook?
    private var inProgressSince: TimeInterval?
    private var releaseTimer: (any ScheduledWork)?
    private var effectTimer: (any ScheduledWork)?
    private var ownRequest = false
    private var openSpan: SignpostSpan?

    /// One open signpost interval; the settle timer holds it, so the interval ends even when the tile is gone first.
    private final class SignpostSpan {
        private var end: (() -> Void)?
        init(end: @escaping () -> Void) { self.end = end }
        func finish() { end?(); end = nil }
    }

    /// - Parameters:
    ///   - scheduler: Runs the flap guard's release and the effect's delay; nil takes ``schedulerOverride``, then the production scheduler.
    ///   - title: The tile's title, which an announcement leads with.
    init(scheduler: (any RevertScheduler)? = nil, title: @escaping () -> String) {
        self.scheduler = scheduler ?? Self.schedulerOverride ?? TaskRevertScheduler()
        self.title = title
    }

    /// Marks the next change as the person's own request: its start is announced and a failure plays the error haptic.
    func noteOwnRequest() { ownRequest = true }

    /// Shows `look`.
    /// - Parameters:
    ///   - look: The resolved look for the state.
    ///   - reapply: A first render, a cold launch or a reconnect: every layer is set at once.
    /// - Returns: Whether the tile rendered the look, is holding it for the flap guard, or already shows it.
    @discardableResult
    func apply(_ look: StateTileLook, reapply: Bool = false) -> Outcome {
        if reapply || shown == nil {
            releaseTimer?.cancel()
            effectTimer?.cancel()
            finishSignpost()
            held = nil
            inProgressSince = nil
            shown = look
            render(UKStateTilePlan(look: look, previous: nil, changes: [], icon: .none, slot: .none, colourFade: nil, stopsEffect: false,
                                   effect: nil, effectDelay: 0, isInstant: true))
            return .rendered
        }
        guard look != (held ?? shown) else { return held == nil ? .unchanged : .held }
        if let since = inProgressSince, shown?.stateClass == .inProgress {
            let remaining = MotionTokens.StateTile.minimumInProgress - (now() - since)
            if remaining > 0 {
                // Hold the whole look, words included; the latest state that arrives wins. An error waits too.
                held = look
                if releaseTimer == nil {
                    releaseTimer = scheduler.schedule(after: .seconds(remaining)) { [weak self] in self?.release() }
                }
                return .held
            }
        }
        show(look)
        return .rendered
    }

    /// A warning pulses again each time its page becomes visible (a push or pop that reveals it, a tab switch, a sheet dismissal, a launch
    /// or a return to the app). Nothing else replays, and an error entry never does.
    func pageDidBecomeVisible() {
        guard let shown, shown.stateClass == .warning, shown.indicator.isSymbolEffect, !reduceMotion() else { return }
        playEffect(shown.indicator)
    }

    // MARK: Private

    private func release() {
        releaseTimer = nil
        guard let next = held else { return }
        held = nil
        show(next)
    }

    private func show(_ look: StateTileLook) {
        guard let previous = shown else { return }
        let reduced = reduceMotion()
        var changes = previous.changes(to: look)
        var icon = previous.iconChange(to: look)
        if reduced, icon == .replace { icon = .silent }
        let slot = previous.slotChange(to: look)
        let effect = reduced ? nil : previous.effectToStart(for: look)
        if previous.stateClass == .inProgress, look.stateClass != .inProgress { changes.insert(.indicator) }
        let plan = UKStateTilePlan(look: look, previous: previous, changes: changes, icon: icon, slot: slot,
                                   colourFade: changes.contains(.colour) ? (reduced ? .stateReduced : .state) : nil,
                                   stopsEffect: previous.stopsEffect(for: look), effect: effect,
                                   effectDelay: slot == .arcOut ? MotionTokens.quickDuration : 0, isInstant: false)
        shown = look
        if look.stateClass == .inProgress, previous.stateClass != .inProgress { inProgressSince = now() }
        else if look.stateClass != .inProgress { inProgressSince = nil }
        openSignpost(for: plan, reduced: reduced)
        render(plan)
        if let effect {
            effectTimer?.cancel()
            if plan.effectDelay > 0 {
                effectTimer = scheduler.schedule(after: .seconds(plan.effectDelay)) { [weak self] in self?.playEffect(effect) }
            } else {
                playEffect(effect)
            }
        }
        speak(from: previous.stateClass, to: look)
    }

    /// One `LayoutChange` interval per animated plan, from the change to the fade settling (the longer of the colour fade and the disc and arc
    /// cross-fade, or one frame when only the glyph or text changes), `XCTOSSignpostMetric` in `UKHostedStateTilePerformanceTests`. A change
    /// that lands mid-fade ends the open interval first, so intervals never nest. An instant plan opens none.
    private func openSignpost(for plan: UKStateTilePlan, reduced: Bool) {
        guard !plan.isInstant else { return }
        finishSignpost()
        let span = SignpostSpan(end: beginSignpost(reduced))
        openSpan = span
        let settle = max(plan.colourFade?.duration ?? 0, plan.slot == .none ? 0 : MotionTokens.quickDuration, 1.0 / 60)
        afterSettle(settle) { span.finish() }
    }

    private func finishSignpost() {
        openSpan?.finish()
        openSpan = nil
    }

    private func speak(from old: StateTileLook.Class, to look: StateTileLook) {
        let own = ownRequest
        if StateTileLook.playsErrorHaptic(from: old, to: look.stateClass, ownRequest: own) { errorHaptic() }
        if look.stateClass != .inProgress, look.stateClass != .warning { ownRequest = false }
        guard isPageVisible() else { return }
        switch StateTileLook.announcement(from: old, to: look.stateClass, ownRequest: own) {
        case .none: break
        case .requestStarted, .arrivedAtResting, .arrivedAtError: announce("\(title()), \(look.text)")
        }
    }
}
#endif
