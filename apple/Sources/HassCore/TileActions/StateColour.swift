import Foundation

/// The colour layer's closed list of tokens (`.agents/design/state-styles.md`, The Studio's style library). A token is cosmetic: it sets
/// the lit or unlit face of a state that is resting or in progress, and nothing else. The class, the words, the VoiceOver value, the
/// effects, the haptics and the announcements come from the state map alone, so a token on a warning, error or unknown state is
/// rejected. Nothing but a token is authorable: no RGB, no hex.
public enum StateColour: String, Equatable, Sendable, CaseIterable {
    /// The unlit face.
    case unlit
    /// The lit face (the family fill).
    case lit
}
