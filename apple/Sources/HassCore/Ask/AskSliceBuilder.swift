import Foundation

// MARK: - Slice

/// The compact text a model phrases an answer from.
public struct AskSlice: Sendable, Equatable {
    /// The prompt: result header, entity lines, cause lines, then the question.
    public var prompt: String
    /// The estimated input tokens, instructions included.
    public var tokens: Int
    /// How many cause lines were dropped to fit.
    public var droppedCauseLines: Int
    /// Whether the entity lines were collapsed to a count plus a few names.
    public var collapsed: Bool
    /// Whether the slice still exceeds the cap after trimming.
    public var overCap: Bool
}

/// Builds a slice inside the token budget, trimming in a fixed order.
///
/// Order when over the cap: drop cause lines past the third, collapse the entity lines to a count plus the first names,
/// drop annotator lines to one; if it still does not fit, the answerer returns the fixed "name a room" sentence.
public struct AskSliceBuilder: Sendable {
    /// The budget.
    public let budget: AskBudget
    /// Counts the tokens of a string. The default is the characters-per-token estimate; pass the model's counter to be exact.
    public let tokenCount: @Sendable (String) -> Int

    /// Creates a builder.
    public init(budget: AskBudget, tokenCount: (@Sendable (String) -> Int)? = nil) {
        self.budget = budget
        let cpt = budget.charactersPerToken
        self.tokenCount = tokenCount ?? { Int((Double($0.count) / cpt).rounded(.up)) }
    }

    /// Builds the prompt.
    /// - Parameters:
    ///   - instructions: The instructions the model gets (counted against the cap).
    ///   - header: The `RESULT:` lines.
    ///   - entityLines: One line per entity.
    ///   - causeLines: `CAUSE` lines.
    ///   - annotatorLines: Integration annotator lines.
    ///   - question: The spoken question.
    public func build(
        instructions: String, header: [String], entityLines: [String], causeLines: [String], annotatorLines: [String], question: String
    ) -> AskSlice {
        var entities = Array(entityLines.prefix(budget.maxEntityLines))
        var causes = Array(causeLines.prefix(budget.maxCauseLines))
        var annotators = Array(annotatorLines.prefix(budget.maxAnnotatorLines))
        var dropped = max(0, causeLines.count - causes.count)
        var collapsed = entityLines.count > entities.count
        func prompt() -> String {
            (header + entities + annotators + causes + ["Question: \(question)"]).joined(separator: "\n")
        }
        func total() -> Int { tokenCount(instructions) + tokenCount(prompt()) }
        if total() > budget.inputCap, causes.count > 3 { dropped += causes.count - 3; causes = Array(causes.prefix(3)) }
        if total() > budget.inputCap, entities.count > budget.maxListedNames {
            let extra = entityLines.count - budget.maxListedNames
            entities = Array(entityLines.prefix(budget.maxListedNames)) + ["and \(extra) more"]
            collapsed = true
        }
        if total() > budget.inputCap, annotators.count > 1 { annotators = Array(annotators.prefix(1)) }
        let t = total()
        return AskSlice(prompt: prompt(), tokens: t, droppedCauseLines: dropped, collapsed: collapsed, overCap: t > budget.inputCap)
    }
}
