import Foundation

// MARK: - Spec

/// One thing a tile can do, decided from entity state alone (pattern: `.agents/patterns/action-tiles.md`).
///
/// A provider (``TileActionProviding``) returns specs; the view maps them onto the presentational action item and runs
/// ``call`` through `OptimisticActions` / `HassConnection.callService`. Field names are parallel to HassDesign's
/// `TileActionItem`: `id`, `verb`, `symbol`, `isOn`, `phase`, `feedback`, `isError`, `isEmphasized`.
public struct TileActionSpec: Identifiable, Equatable, Sendable {
    /// Whether the action can be run now.
    public enum Phase: Equatable, Sendable {
        /// Runnable.
        case ready
        /// Waiting for the house: the disc shows an arc spinner and neither it nor the tile body takes taps.
        case inFlight
        /// The entity cannot be reached: the disc dims in place (it never disappears).
        case unavailable
    }

    /// How the action answers a tap (owner, 2026-10-26; `.agents/design/action-navigation-tiles.md`).
    public enum Feedback: Equatable, Sendable {
        /// Next, previous, dock: press highlight and the tap haptic, nothing else. Never ``Phase/inFlight``.
        case momentary
        /// Play/pause, fan, towel rack, guest toggles: the glyph swaps at once and animates back on failure.
        case optimistic
        /// Lock, garage door, PC power: animates to the transitional state and out to the final glyph.
        case tracked
    }

    /// A question asked before the action runs (owner, 2026-10-27: a disc keeps today's confirmation where one exists). The tile
    /// presents it for a disc tap *and* for a body tap that runs this action, and sends the call only on confirm.
    public struct Confirmation: Equatable, Sendable {
        /// How the question is presented (``AlertCopy`` in the app: an alert for a state change, a dialog anchored to the tile
        /// for turning a thing off that was chosen as an act of loss).
        public enum Style: Equatable, Sendable {
            /// A centred alert.
            case alert
            /// A confirmation dialog attached to the tile (an action sheet on iPhone, a popover on iPad).
            case dialog
        }

        /// The question: "Disarm the Security System?".
        public var title: String
        /// The explanation under it, if any.
        public var message: String?
        /// The confirming button: "Disarm".
        public var confirmVerb: String
        /// The confirming button takes the destructive role (data or the session is lost); otherwise it is plain and bold.
        public var isDestructive: Bool
        /// Alert or dialog.
        public var style: Style

        /// Creates a confirmation.
        public init(title: String, message: String? = nil, confirmVerb: String, isDestructive: Bool = false, style: Style = .alert) {
            self.title = title
            self.message = message
            self.confirmVerb = confirmVerb
            self.isDestructive = isDestructive
            self.style = style
        }
    }

    /// What a tile that *chooses* shows in its disc (owner, 2026-10-27, option C of selection-tiles). The tile fills in its family
    /// colour when chosen; VoiceOver reads the "selected" trait, never "switch".
    public enum Selection: Equatable, Sendable {
        /// One of several: a white `checkmark` disc when chosen, an empty `circle` when not.
        case single(isSelected: Bool)
        /// One of an ordered set (vacuum rooms): the cleaning order in the disc when chosen (1-based), an empty `circle` when
        /// `position` is nil.
        case ordered(position: Int?)

        /// Whether the tile is chosen.
        public var isSelected: Bool {
            switch self {
            case let .single(isSelected): isSelected
            case let .ordered(position): position != nil
            }
        }

        /// The place in the order, for an ordered selection that is chosen.
        public var position: Int? {
            if case let .ordered(position) = self { return position }
            return nil
        }
    }

    /// Stable across states (`"lock"` whether it would lock or unlock), so the view keeps identity and the symbol
    /// transition survives. The accessibility identifier suffix is `<tile-id>.action.<id>`.
    public var id: String
    /// The VoiceOver label and hint: "Unlock", "Pause", "Turn On". The view appends the tile's title.
    public var verb: String
    /// An SF Symbol: the *state* glyph for a toggle-styled action (``isOn`` non-nil), the *action* glyph for a
    /// momentary one (pause while playing, play while paused).
    public var symbol: String
    /// Toggle-styled actions fill when on; `nil` is momentary-styled.
    public var isOn: Bool?
    /// Whether the action can run now.
    public var phase: Phase
    /// How the action answers a tap.
    public var feedback: Feedback
    /// The service call; `nil` only for a custom action (opens something, or a slider).
    public var call: ServiceCall?
    /// Values shown until Home Assistant confirms (empty for ``Feedback/momentary`` and ``Feedback/tracked``).
    public var optimistic: [OptimisticIntent]
    /// The disc takes the error shape (a jammed lock's `lock.trianglebadge.exclamationmark`).
    public var isError: Bool
    /// The disc is drawn with emphasis (play/pause on a playing remote).
    public var isEmphasized: Bool
    /// The whole VoiceOver label when "verb title" is not it ("Turn Off TV" on a source tile, "Cancel Hot Flash Mode"). Nil: the
    /// view appends the tile's title to ``verb``.
    public var label: String?
    /// Asked before the call runs; nil runs it at once.
    public var confirmation: Confirmation?
    /// Non-nil draws the selection face's disc (a check, a number or a ring) instead of a toggle's.
    public var selection: Selection?
    /// Values held while a ``Feedback/tracked`` action is in flight, through `OptimisticActions` (the way a tapped lock shows
    /// "Unlocking…"): the view commits these when it runs the call and the entity's live change clears them. Empty for the rest.
    public var tracking: [OptimisticIntent]

    /// Creates a spec.
    public init(id: String, verb: String, symbol: String, isOn: Bool? = nil, phase: Phase = .ready,
                feedback: Feedback, call: ServiceCall? = nil, optimistic: [OptimisticIntent] = [],
                isError: Bool = false, isEmphasized: Bool = false, label: String? = nil, confirmation: Confirmation? = nil,
                selection: Selection? = nil, tracking: [OptimisticIntent] = []) {
        self.id = id
        self.verb = verb
        self.symbol = symbol
        self.isOn = isOn
        self.phase = phase
        self.feedback = feedback
        self.call = call
        self.optimistic = optimistic
        self.isError = isError
        self.isEmphasized = isEmphasized
        self.label = label
        self.confirmation = confirmation
        self.selection = selection
        self.tracking = tracking
    }

    /// A copy that asks `confirmation` before it runs.
    public func with(confirmation: Confirmation?) -> TileActionSpec {
        var copy = self
        copy.confirmation = confirmation
        return copy
    }

    /// A copy with a different phase.
    public func with(phase: Phase) -> TileActionSpec {
        var copy = self
        copy.phase = phase
        return copy
    }
}
