import SwiftUI

// MARK: - Item

/// One thing a tile can do, as the tile draws it: a presentational value with no service call in it.
///
/// HassDesign does not depend on HassCore, so the domain's `TileActionSpec` is mapped onto this in HassUI. Items are
/// `Equatable` so a tile diffs on values, and one `perform` closure on the tile receives the chosen ``id`` (pattern:
/// `.agents/patterns/action-tiles.md`).
public struct TileActionItem: Identifiable, Equatable, Sendable {
    /// Where an action is in its life.
    public enum Phase: Equatable, Sendable {
        /// Can be tapped.
        case ready
        /// Sent and waiting: the disc shows a progress arc and the disc and tile body are disabled.
        case inFlight
        /// Cannot run now: the disc dims in place (glyph at 50%, no fill) and is disabled; it never disappears.
        case unavailable
    }

    /// What the person sees while the action runs (owner, 2026-10-26).
    public enum Feedback: Equatable, Sendable {
        /// Next, previous, locate, dock: press highlight and the tap haptic, nothing else. Never a spinner.
        case momentary
        /// Play/pause, fan, towel rack: the glyph swaps at once and animates back on failure.
        case optimistic
        /// Lock, garage, PC: animates through the transitional state (arc in the disc) to the final glyph.
        case tracked
    }

    /// Stable across states ("lock" whether it would lock or unlock) so the symbol transition survives.
    public var id: String
    /// What the action does, for VoiceOver and the hint: "Unlock", "Pause".
    public var verb: String
    /// An SF Symbol: the STATE glyph of a toggle-styled action (lock.fill when locked), the ACTION glyph of a momentary
    /// one (pause while playing).
    public var symbol: String
    /// Toggle-styled discs fill when on; `nil` is momentary (not toggle-styled).
    public var isOn: Bool?
    /// Where the action is in its life.
    public var phase: Phase
    /// The feedback kind the provider declared.
    public var feedback: Feedback
    /// Draws the glyph in the error red (a jammed lock also passes a different symbol, so shape differs as well).
    public var isError: Bool
    /// The primary control of a set (play/pause on a playing remote).
    public var isEmphasized: Bool
    /// The whole VoiceOver label when "verb title" is not it ("Turn Off TV", "Cancel Hot Flash Mode"); nil appends the title.
    public var label: String?
    /// Asked before the action runs, for a disc tap and for a body tap that performs this action.
    public var confirmation: TileActionConfirmation?
    /// Non-nil draws the selection face's disc (a check, the order, or a ring) instead of a toggle's glyph.
    public var selection: TileSelection?

    /// Creates an item.
    public init(
        id: String,
        verb: String,
        symbol: String,
        isOn: Bool? = nil,
        phase: Phase = .ready,
        feedback: Feedback = .momentary,
        isError: Bool = false,
        isEmphasized: Bool = false,
        label: String? = nil,
        confirmation: TileActionConfirmation? = nil,
        selection: TileSelection? = nil
    ) {
        self.id = id
        self.verb = verb
        self.symbol = symbol
        self.isOn = isOn
        self.phase = phase
        self.feedback = feedback
        self.isError = isError
        self.isEmphasized = isEmphasized
        self.label = label
        self.confirmation = confirmation
        self.selection = selection
    }

    /// Whether the disc shows a progress arc instead of its glyph. A momentary item never does.
    public var showsProgress: Bool { phase == .inFlight && feedback != .momentary }
}

