import Foundation

// MARK: - Which strings are entity ids

/// Remembers which strings are well-formed Home Assistant entity ids, so a read of a literal id is a dictionary hit.
///
/// An entity id is `domain.object_id`: a lowercase letter then lowercase letters, digits or underscores, a dot, then lowercase
/// letters, digits or underscores, at most 160 UTF-16 units. A regular-expression match on every read of every source is main-thread
/// time a house of hundreds of reads a turn pays for nothing, since the same few ids are read again and again; a string is
/// matched once and its verdict kept. The cache is bounded: an id that is read from live data and keeps changing cannot grow it
/// without end.
public struct EntityIDCache {
    /// The most ids remembered; past it the cache starts over rather than growing.
    public static let capacity = 2048

    private var verdicts: [String: Bool] = [:]

    /// How many strings were matched against the pattern; a test reads it to prove a repeat read matches nothing.
    public private(set) var matches = 0

    /// Creates an empty cache.
    public init() {}

    /// Whether `id` is a well-formed entity id, matched against the pattern the first time and remembered after.
    public mutating func isValid(_ id: String) -> Bool {
        if let known = verdicts[id] { return known }
        let verdict = Self.matchesPattern(id)
        matches += 1
        if verdicts.count >= Self.capacity { verdicts.removeAll(keepingCapacity: true) }
        verdicts[id] = verdict
        return verdict
    }

    /// The rule itself, with no cache: what ``isValid(_:)`` must always agree with.
    public static func matchesPattern(_ id: String) -> Bool {
        id.utf16.count <= 160
            && id.range(of: "^[a-z][a-z0-9_]*\\.[a-z0-9_]+$", options: .regularExpression) == id.startIndex..<id.endIndex
    }
}
