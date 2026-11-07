import SwiftUI

/// What tapping the tile does (web `ControlSemantics`).
public enum GlassTileKind: Equatable, Sendable {
    /// An on/off switch: `.isToggle`, value On/Off.
    case toggle
    /// Opens a page or sheet: chevron.
    case navigate
    /// Fires a command.
    case command
    /// One of a set of choices: `.isSelected` while chosen (web `aria-pressed`).
    case selection(isSelected: Bool)
    /// Shows a state only: not a button, never dimmed as disabled.
    case state

    /// Whether a tap plays ``TapFeedback/tap``: switches, commands and choices do; a tile that opens a page does not,
    /// because the transition is its feedback (owner, 2026-10-24).
    public var playsTapFeedback: Bool {
        switch self {
        case .toggle, .command, .selection: true
        case .navigate, .state: false
        }
    }
}

extension GlassTileKind {
    /// The behaviour a `kind:` tile maps to: toggle, command and selection run the body's action (a placeholder id, since
    /// they carry no action items), navigate opens, state is read-only.
    var behavior: TileBehavior {
        switch self {
        case .toggle, .command, .selection: .perform("")
        case .navigate: .navigate
        case .state: .inert
        }
    }
}
