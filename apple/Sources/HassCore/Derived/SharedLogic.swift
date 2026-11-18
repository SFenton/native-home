import Foundation
import HassTelemetry

// MARK: - Shared once a second reader asks

/// Logic that becomes a ``DerivedValue`` when a second observation reads it, and stays plain until then.
///
/// A derived value pays for itself when several readers share it. For logic only one observation reads (most authored expressions are
/// used once) it is an extra run and an extra object on every change. So the first observation to read a key evaluates it where it is,
/// inside its own run, exactly as before. A second distinct observation asks for the shared value, which is made in the next main-actor
/// hop, outside any observation (Observation merges a nested scope into the one around it, so a value made inside a reader's run would
/// make that reader follow every input). Until then the second reader also evaluates in place. Every reader that runs again after that
/// reads the shared value and follows only its output; a reader moves over on its next run, which its own inputs trigger.
///
/// Observations are told apart by their ``DerivedReaders``; a read outside any observation (a one-off) is evaluated plainly.
@MainActor
public final class SharedLogic<Key: Hashable, Value: Equatable> {
    /// What is known about a key: which observation read it first, the shared value once there is one, and whether it is ever worth sharing.
    private struct Slot {
        weak var first: DerivedReaders?
        weak var shared: DerivedValue<Value>?
        var asked = false
        var madeOnce = false
        var never = false
    }

    private let values: DerivedValues<Key, Value>
    private var slots: [Key: Slot] = [:]
    /// Values made in a hop that no reader holds yet; a reader's read hands the value over, and the first reader's end lets go of it.
    private var unclaimed: [Key: DerivedValue<Value>] = [:]
    private var sinceSweep = 0

    /// Creates an empty set.
    /// - Parameter tally: The owner's tally, handed to every shared value (``DerivedValue/init(tally:_:)``).
    public init(tally: LogicCost.Tally? = nil) { values = DerivedValues(tally: tally) }

    /// The answer for `key`. A read that has been seen before costs one dictionary lookup.
    /// - Parameters:
    ///   - key: What the logic is.
    ///   - eligible: Whether the logic is worth sharing at all (asked once per key; `false` is remembered until the next sweep).
    ///   - read: The logic; it runs inside the reader's run (tracked there) or, once shared, inside the derived value.
    public func value(for key: Key, eligible: @autoclosure () -> Bool = true, read: @escaping @MainActor () -> Value) -> Value {
        guard let reader = DerivedReaders.current else { return read() }
        guard var slot = slots[key] else {
            noteInsert()
            slots[key] = eligible() ? Slot(first: reader) : Slot(never: true)
            return read()
        }
        if slot.never { return read() }
        if slot.madeOnce, slot.shared == nil { slot.asked = false; slot.madeOnce = false }   // it ended: ask again
        if let shared = slot.shared {
            let answer = shared.current
            if !unclaimed.isEmpty { unclaimed[key] = nil }
            return answer
        }
        if let first = slot.first, first !== reader {
            if !slot.asked {
                slot.asked = true
                slots[key] = slot
                Task { @MainActor [weak self] in self?.share(key, read) }
            }
            return read()
        }
        if slot.first == nil { slot.first = reader; slots[key] = slot }
        return read()
    }

    /// Makes the shared value, in a hop where no observation is running.
    private func share(_ key: Key, _ read: @escaping @MainActor () -> Value) {
        guard var slot = slots[key], !slot.never else { return }
        let made = values.value(for: key, read: read)
        slot.shared = made
        slot.madeOnce = true
        slots[key] = slot
        // Nobody left to read it: let it end. Otherwise hold it until a reader's next run claims it, or the first reader goes: a page that
        // closes before it ever runs again must not leave a value evaluating on every change.
        guard let first = slot.first else { return }
        if unclaimed.count >= Self.sweepAt { unclaimed.removeAll() }
        unclaimed[key] = made
        first.whenEnded(token: [ObjectIdentifier(self) as AnyHashable, key as AnyHashable] as [AnyHashable]) { [weak self, weak made] in
            self?.release(key, ifStill: made)
        }
    }

    /// Lets go of the unclaimed value for `key`, if it is still this one.
    private func release(_ key: Key, ifStill value: DerivedValue<Value>?) {
        guard let value, unclaimed[key] === value else { return }
        unclaimed[key] = nil
    }

    /// How many shared values wait for a reader to take them over; tests read it to prove a closed page leaves none.
    public var unclaimedCount: Int { unclaimed.count }

    /// How many keys are shared right now.
    public var sharedCount: Int { values.liveCount }

    /// How many keys are remembered, shared or not; tests read it to prove the memory is bounded.
    public var slotCount: Int { slots.count }

    /// Every ``sweepAt`` new keys, forgets the ones whose readers have gone and the ones judged not worth sharing (asking again is cheap).
    private func noteInsert() {
        sinceSweep += 1
        guard sinceSweep >= Self.sweepAt else { return }
        sinceSweep = 0
        slots = slots.filter { !$0.value.never && ($0.value.first != nil || $0.value.shared != nil) }
    }

    /// The number of new keys between sweeps, and the most values held for a reader that has not come yet.
    private static var sweepAt: Int { 256 }
}
