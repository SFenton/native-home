/// The tone of a tinted notice with a title and optional message (pattern: `.agents/patterns/info-box.md`; web `InfoBox`),
/// drawn by `UKInfoBox`.
public enum InfoBox {
    /// The notice's tone.
    public enum Tone: Sendable {
        /// A confirmed, good state (green).
        case success
        /// Informational (gray).
        case neutral
    }
}
