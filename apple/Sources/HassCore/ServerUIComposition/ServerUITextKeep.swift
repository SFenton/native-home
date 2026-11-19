import Foundation

// MARK: - Keeping unavailable text (sh.text-keep@1)

/// What a text slot draws while its value is unavailable (`sh.text-keep@1`).
public enum ServerUIUnavailablePolicy: String, CaseIterable, Equatable, Sendable {
    /// The slot's fallback, or its usual empty or unknown text when none is authored. The default.
    case fallback
    /// The last text the slot was answered with, if it has one; before any answer, the same as ``fallback``.
    case keep

    /// The policy an authored word names; an absent or unrecognised word is ``fallback`` (the shape refuses unrecognised words earlier).
    public init(_ word: String?) { self = word.flatMap(Self.init(rawValue:)) ?? .fallback }
}

/// What one slot instance has been answered with, so a `keep` slot can draw it again while its value is unavailable.
///
/// One instance of a slot owns one memory (a repeat's cells each own theirs); the document's slot is shared, the memory is not. It is a
/// plain value the render site keeps beside the view it draws into, written only when the slot's policy is ``ServerUIUnavailablePolicy/keep``
/// and only inside the evaluation that already ran, so it adds no shared state and no work that grows with the house.
///
/// An answer is text the slot's value gave (an empty string counts). Drawing the fallback, or drawing the remembered text, is not an answer.
public struct ServerUITextMemory: Equatable, Sendable {
    /// The last answered text, or `nil` before the first answer.
    public private(set) var answered: String?

    /// A memory that has not been answered yet.
    public init() {}

    /// A memory that was last answered with `text`.
    public init(answered text: String?) { answered = text }

    /// The text to draw for `result` (the slot's value before any fallback), updating the memory.
    ///
    /// - Parameters:
    ///   - result: What the slot's value gave, evaluated with no fallback.
    ///   - fallback: The slot's authored fallback text.
    ///   - policy: What the slot draws while unavailable.
    /// - Returns: The text to draw, "not yet" (`loading`: the slot keeps what it showed) or `unavailable` (the slot draws its own words).
    public mutating func resolve(_ result: ServerUIReadResult, fallback: String?, policy: ServerUIUnavailablePolicy) -> ServerUIReadResult {
        let plain = ServerUIStringResolver.text(of: result, fallback: nil)
        switch plain {
        case .loading:
            return .loading
        case .value(let value):
            if policy == .keep, case .string(let text) = value { answered = text }
            return plain
        case .unavailable:
            if policy == .keep, let answered { return .value(.string(answered)) }
            return fallback.map { .value(.string($0)) } ?? .unavailable
        }
    }
}

public extension ServerUIStringResolver {
    /// As ``resolve(_:read:in:)``, but a `keep` slot draws the last text it was answered with while its value is unavailable
    /// (`sh.text-keep@1`). `memory` is this slot instance's, and is updated.
    static func resolve(_ value: ServerUICompositionDocument.StringValue, read: (ServerUICompositionDocument.Read) -> ServerUIReadResult,
                        in environment: some ServerUIReading, memory: inout ServerUITextMemory) -> ServerUIReadResult {
        switch value {
        case .literal(let text):
            return .value(.string(text))
        case .read(let source, let fallback, let policy):
            return memory.resolve(read(source), fallback: fallback, policy: policy)
        case .expression(let operand, let fallback, let policy):
            return memory.resolve(operand.evaluate(environment), fallback: fallback, policy: policy)
        }
    }

    /// As ``text(of:fallback:)``, for a caller that got the result another way, with a slot instance's `memory`.
    static func text(of result: ServerUIReadResult, fallback: String?, policy: ServerUIUnavailablePolicy,
                     memory: inout ServerUITextMemory) -> ServerUIReadResult {
        memory.resolve(result, fallback: fallback, policy: policy)
    }
}
