import SwiftUI

/// A pick held for its quiet period, and taken exactly once: by the delayed commit, or by the picker disappearing
/// first (a change that triggers a service call is never lost).
public struct UnsentPick: Equatable {
    public private(set) var value: Date?

    public init() {}

    /// Holds `date` until it is taken.
    public mutating func hold(_ date: Date) { value = date }

    /// Drops the held pick (the saved value moved).
    public mutating func discard() { value = nil }

    /// The held pick, once; later calls return `nil`.
    public mutating func take() -> Date? {
        defer { value = nil }
        return value
    }
}

