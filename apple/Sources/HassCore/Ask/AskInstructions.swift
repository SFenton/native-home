import Foundation

// MARK: - Instructions

/// The instructions the on-device model gets, and the slice grammar they describe.
///
/// The model only phrases: code has already chosen the entities, read the states and decided what the cause was. The
/// wording describes the lines ``AskSliceBuilder`` writes.
public enum AskInstructions {
    /// The instructions for a home called `houseName`.
    public static func text(houseName: String) -> String {
        """
        You answer questions about the home "\(houseName)". Use only the lines below. Reply in one or two plain sentences; never repeat the list. \
        Answer from the facts: the state, how long, and for a why question the CAUSE line (say what did it, and its trigger). Mention every item that matches the question. \
        RESULT lines are decided by code and are always right. \
        If RESULT says one group, answer for the whole group together; do not ask which. \
        If RESULT says several match, do not pick one and do not answer: ask which one they mean, naming the choices. \
        If RESULT says no such device, say you cannot find it and do not name or describe any other device. \
        Only if a CAUSE line says exactly "not recorded", say there is no record of why; never guess a cause. \
        Only if RESULT starts with "decline", politely say you can only answer questions about the home and cannot control anything.
        """
    }
}
