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
    /// What is known about a key: which observation read it first, the shared value once there is one, and whether it is ever worth sharing.
    private struct Slot {
        weak var first: DerivedReaders?
        weak var shared: DerivedValue<Value>?
        var never = false
    }

    private let values = DerivedValues<Key, Value>()
    private var slots: [Key: Slot] = [:]

    /// Creates an empty set.
    public init() {}

    /// The answer for `key`. A read that has been seen before costs one dictionary lookup.
    /// - Parameters:
    ///   - key: What the logic is.
    ///   - eligible: Whether the logic is worth sharing at all (asked once per key; `false` is remembered).
    ///   - read: The logic; it runs inside the reader's run (tracked there) or, once shared, inside the derived value.
    public func value(for key: Key, eligible: @autoclosure () -> Bool = true, read: @escaping @MainActor () -> Value) -> Value {
        guard let reader = DerivedReaders.current else { return read() }
        guard var slot = slots[key] else {
            if slots.count >= Self.sweepAt { slots = slots.filter { $0.value.first != nil || $0.value.shared != nil || $0.value.never } }
            slots[key] = eligible() ? Slot(first: reader) : Slot(never: true)
            return read()
        }
        if slot.never { return read() }
        if let shared = slot.shared { return shared.current }
        if let first = slot.first, first !== reader {
            let made = values.value(for: key, read: read)
            slot.shared = made
            slots[key] = slot
            return made.current
        }
        if slot.first == nil { slot.first = reader; slots[key] = slot }
        return read()
    }

    /// How many keys are shared right now.
    public var sharedCount: Int { values.liveCount }

    /// The size at which keys whose first reader has gone are dropped.
    private static var sweepAt: Int { 256 }
}
