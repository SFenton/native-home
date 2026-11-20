import Foundation

// MARK: - Path

/// How an answer was produced.
public enum AskAnswerPath: String, Codable, Sendable, CaseIterable {
    /// A fixed sentence refusing an action or an off-topic question.
    case fixedDecline
    /// A fixed sentence: nothing matches.
    case fixedNone
    /// A fixed sentence: the thing or set exists but the configuration does not cover it.
    case fixedNotConfigured
    /// A fixed sentence: several match, which one?
    case fixedSeveral
    /// A fixed sentence: the entity is unavailable.
    case fixedUnavailable
    /// A fixed sentence: the answer needs the phone unlocked.
    case fixedLocked
    /// A fixed sentence: security state is withheld by ``AskConfiguration/withholdSecurityState``; open the app.
    case fixedWithheld
    /// A sentence written in code from facts code already holds.
    case code
    /// Phrased by the model from a slice.
    case model
}

// MARK: - Facts

/// What code gathered to answer: durations, causes, last times.
struct AskFacts: Sendable {
    var durations: [String: AskDuration] = [:]
    var causes: [String: AskCauseResult] = [:]
    var lastTimes: [String: AskLastTime] = [:]
}

// MARK: - Result

/// Everything one answer produced, for the caller and for the scorer to inspect.
public struct AskResult: Sendable {
    /// The question as asked.
    public var question: String
    /// How the resolver read it.
    public var resolution: AskResolution
    /// How the answer was produced.
    public var path: AskAnswerPath
    /// The answer to say.
    public var answer: String
    /// The sentence code wrote (the answer when no model ran; the fallback when it did).
    public var draft: String
    /// The lines the answer was built from.
    public var facts: [String]
    /// Whether the model phrased the answer.
    public var usedModel: Bool
    /// Whether this answer wanted the model but none was available (the draft stands in).
    public var modelSkipped: Bool
    /// The estimated or counted input tokens of the slice, when one was built.
    public var inputTokens: Int?
    /// The most private class among the entities the answer reads.
    public var sensitivity: AskSensitivity
    /// How long each stage took.
    public var timings: Timings
    /// A description of an error that forced the fallback, if any.
    public var error: String?

    /// Stage timings, in milliseconds.
    public struct Timings: Sendable, Equatable {
        /// Resolving the question.
        public var resolveMs: Double = 0
        /// Reading history and logbook.
        public var dataMs: Double = 0
        /// The model call.
        public var phraseMs: Double = 0
        /// Everything.
        public var totalMs: Double = 0

        /// Creates zeroed timings.
        public init() {}
    }
}
