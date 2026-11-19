import Foundation

// MARK: - The spoken cue of kept text (T-text-keep, options B and C)

/// The words VoiceOver adds to the value of an element that is showing kept text (`sh.text-keep@1`): the last text a slot was answered
/// with, drawn while its value is unavailable.
///
/// The cue goes in the element's *value*, once per element however many of its slots are kept, appended to a spoken value the element
/// already has ("on, off in 12 minutes, locked, last known"). A hint describes an action and can be turned off; staleness is state.
public enum ServerUIKeptTextCue {
    /// The words, joined to the value by a comma.
    public static let words = "last known"
    /// What follows the value.
    public static let suffix = ", " + words

    /// The value an element speaks.
    /// - Parameters:
    ///   - spoken: The value the element speaks already (an authored spoken value), or `nil` when it speaks what it draws.
    ///   - drawn: The text the element draws, spoken when `spoken` is `nil` and the element is kept.
    ///   - kept: Whether any of the element's slots draws kept text.
    /// - Returns: `spoken` unchanged when nothing is kept; otherwise the value with the cue appended once.
    public static func value(spoken: String?, drawn: String, kept: Bool) -> String? {
        guard kept else { return spoken }
        return append(to: spoken ?? drawn)
    }

    /// The value of an element whose text is read in its label, not its value (a row's title and subtitle).
    /// - Returns: `spoken` unchanged when nothing is kept; the cue alone when the element has no value; otherwise `spoken` with the cue appended.
    public static func value(appendingTo spoken: String?, kept: Bool) -> String? {
        guard kept else { return spoken }
        return spoken.map(append(to:)) ?? words
    }

    /// `value` with the cue appended, unless it already ends with it.
    public static func append(to value: String) -> String {
        value.hasSuffix(suffix) ? value : value + suffix
    }

    /// `value` without a trailing cue: what an announcement compares, so moving between live and kept (the text did not change) says nothing.
    public static func stripped(_ value: String?) -> String? {
        guard let value, value.hasSuffix(suffix) else { return value }
        return String(value.dropLast(suffix.count))
    }
}
