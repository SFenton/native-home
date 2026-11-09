import SwiftUI


/// A warning or error shown inline under the control it concerns (web `InlineAlert`): the one inline alert for every
/// page (pattern: `.agents/patterns/info-box.md`).
///
/// A warning is primary ink on an orange wash, read as "Warning: …". An error is red text with no box, read as
/// "Error: …" (web `InlineAlert` error severity on the Vacation and Solo Trip pages).
public enum InlineAlert {
    /// How serious the alert is.
    public enum Severity: Sendable {
        case warning
        case error
    }
}
