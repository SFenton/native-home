import Foundation

// MARK: - Shared once a second reader asks

/// Logic that becomes a ``DerivedValue`` when a second observation reads it, and stays plain until then.
///
/// A derived value pays for itself when several readers share it. For logic only one observation reads (most authored expressions are
/// used once) it is an extra run and an extra object on every change. So the first observation to read a key evaluates it where it is,
/// inside its own run, exactly as before; the second distinct observation makes the key one derived value, and every reader that
/// runs again after that reads it. The first reader moves over on its next run, which its own inputs trigger, so nothing is evaluated
/// less than before and no reader waits for the move.
///
/// Observations are told apart by their ``DerivedReaders``; a read outside any observation (a one-off) is evaluated plainly.
@MainActor
public final class SharedLogic<Key: Hashable, Value: Equatable> {
    private struct First { weak var readers: DerivedReaders? }

    private let values = DerivedValues<Key, Value>()
    private var firsts: [Key: First] = [:]

    /// Creates an empty set.
    public init() {}

    /// The answer for `key`.
    /// - Parameters:
    ///   - key: What the logic is.
    ///   - read: The logic; it runs inside the reader's run (tracked there) or, once shared, inside the derived value.
    public func value(for key: Key, read: @escaping @MainActor () -> Value) -> Value {
        guard let reader = DerivedReaders.current else { return read() }
        if let shared = values.existing(for: key) { return shared.current }
        if let first = firsts[key]?.readers, first !== reader { return values.value(for: key, read: read).current }
        if firsts[key]?.readers == nil {
            if firsts.count >= Self.sweepAt { firsts = firsts.filter { $0.value.readers != nil } }
            firsts[key] = First(readers: reader)
        }
        return read()
    }

    /// How many keys are shared right now.
    public var sharedCount: Int { values.liveCount }

    /// The size at which keys whose first reader has gone are dropped.
    private static var sweepAt: Int { 256 }
}
