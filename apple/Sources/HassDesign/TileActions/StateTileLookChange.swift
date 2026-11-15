import Foundation

// MARK: - Layer diff

extension StateTileLook {
    /// The layers whose resolved value differs from the one on screen.
    public struct Changes: OptionSet, Sendable {
        public let rawValue: Int
        /// Creates a changes.
        public init(rawValue: Int) { self.rawValue = rawValue }
        /// The glyph differs.
        public static let icon = Changes(rawValue: 1)
        /// The face or ink differs.
        public static let colour = Changes(rawValue: 2)
        /// The indicator differs, or the disc gained or lost its action.
        public static let indicator = Changes(rawValue: 4)
        /// The words differ.
        public static let text = Changes(rawValue: 8)
    }

    /// How the glyph changes.
    public enum IconChange: Equatable, Sendable {
        /// The same glyph: the view is not touched.
        case none
        /// The system symbol replace, on a visible disc.
        case replace
        /// Set with no effect: the disc is hidden behind the arc, or fading in from behind it.
        case silent
    }

    /// What happens in the disc's slot.
    public enum SlotChange: Equatable, Sendable {
        /// Nothing: the same arc keeps turning (in-progress to in-progress), or the disc stays.
        case none
        /// The disc fades out and the arc fades in on `MotionTokens.quick`.
        case arcIn
        /// The arc fades out and the disc fades in.
        case arcOut
    }

    /// The layers that differ between this look, on screen, and `next`. Words are compared as given; an equal layer is never touched, so a
    /// running effect or a turning arc keeps its phase.
    public func changes(to next: StateTileLook) -> Changes {
        var changes: Changes = []
        if icon != next.icon { changes.insert(.icon) }
        if colour != next.colour { changes.insert(.colour) }
        if indicator != next.indicator || hasAction != next.hasAction { changes.insert(.indicator) }
        if text != next.text { changes.insert(.text) }
        return changes
    }

    /// How the glyph changes on the way to `next`: a replace only when the disc is visible before and after; a hidden disc takes its
    /// glyph with no effect.
    public func iconChange(to next: StateTileLook) -> IconChange {
        guard icon != next.icon else { return .none }
        return showsArc || next.showsArc ? .silent : .replace
    }

    /// What the slot does on the way to `next`: the arc and the disc cross-fade; an arc to an arc is left alone.
    public func slotChange(to next: StateTileLook) -> SlotChange {
        switch (showsArc, next.showsArc) {
        case (false, true): .arcIn
        case (true, false): .arcOut
        default: .none
        }
    }

    /// The symbol effect to start on the way to `next`, or nil. A once-only effect (bounce, wiggle) starts only on arrival, when the
    /// indicator changes; a held one (pulse, breathe) starts if it is not already running.
    public func effectToStart(for next: StateTileLook) -> Indicator? {
        guard next.indicator.isSymbolEffect, next.indicator != indicator else { return nil }
        return next.indicator
    }

    /// Whether a held effect running now stops on the way to `next`.
    public func stopsEffect(for next: StateTileLook) -> Bool {
        indicator.isSymbolEffect && !indicator.playsOnce && next.indicator != indicator
    }
}

// MARK: - Announcements

extension StateTileLook {
    /// What VoiceOver is told about a change, with focus unmoved. Only these are announced.
    public enum Announcement: Equatable, Sendable {
        /// Nothing.
        case none
        /// The person's own request started.
        case requestStarted
        /// The state arrived at resting after in-progress or error.
        case arrivedAtResting
        /// The state arrived at error.
        case arrivedAtError
    }

    /// The announcement for a change from `old` to `new` on a visible page. Nothing is announced for a first render, a reconnect or a cold
    /// launch (`old` is nil), for an in-progress to in-progress change, a warning, or unknown.
    /// - Parameters:
    ///   - old: The class on screen, or nil on a first render and a reapply.
    ///   - ownRequest: The person's own tap started the change.
    public static func announcement(from old: Class?, to new: Class, ownRequest: Bool) -> Announcement {
        guard let old, old != new else { return .none }
        switch new {
        case .inProgress: return old == .resting && ownRequest ? .requestStarted : .none
        case .resting: return old == .inProgress || old == .error ? .arrivedAtResting : .none
        case .error: return .arrivedAtError
        case .warning, .unknown: return .none
        }
    }

    /// Whether the error haptic plays: on arrival at error after the person's own request.
    public static func playsErrorHaptic(from old: Class?, to new: Class, ownRequest: Bool) -> Bool {
        old != nil && old != .error && new == .error && ownRequest
    }

    /// The value VoiceOver reads for the tile: the state's words, then "in progress", "warning" or "error" unless the words already say it.
    public func spokenValue() -> String { Self.spokenValue(text: text, stateClass: stateClass) }

    /// ``spokenValue()`` for words and a class that are not yet a look.
    public static func spokenValue(text: String, stateClass: Class) -> String {
        let suffix: String? = switch stateClass {
        case .inProgress: "in progress"
        case .warning: "warning"
        case .error: "error"
        case .resting, .unknown: nil
        }
        guard let suffix, !text.lowercased().contains(suffix) else { return text }
        return text.isEmpty ? suffix : "\(text), \(suffix)"
    }
}
