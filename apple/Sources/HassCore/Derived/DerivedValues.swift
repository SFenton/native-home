import Foundation

// MARK: - One derived value per distinct logic

/// The derived values of one session, one per distinct key, so the same logic used in many places is evaluated once.
///
/// The key says what the logic is (an authored operand's whole tree, which is `Hashable`, or a name for native logic); asking for a
/// key that is alive returns the value that exists, and `read` is ignored. Entries are held weakly: a value ends when the last reader
/// that holds it goes, so an expression only a closed page used stops running with that page and costs nothing afterwards.
@MainActor
public final class DerivedValues<Key: Hashable, Value: Equatable> {
    private struct Entry { weak var value: DerivedValue<Value>? }

    private var entries: [Key: Entry] = [:]
    private var sinceSweep = 0

    /// How many entries are asked for between sweeps of the ones whose value has ended.
    private static var sweepInterval: Int { 64 }

    /// Creates an empty set.
    public init() {}

    /// The value for `key`: the live one, or a new one that runs `read` now.
    /// - Parameters:
    ///   - key: What the logic is.
    ///   - read: The logic, used only when no live value exists for `key`.
    public func value(for key: Key, read: @escaping @MainActor () -> Value) -> DerivedValue<Value> {
        if let live = entries[key]?.value { return live }
        let made = DerivedValue(read)
        entries[key] = Entry(value: made)
        sinceSweep += 1
        if sinceSweep >= Self.sweepInterval { sweep() }
        return made
    }

    /// The live value for `key`, if there is one.
    public func existing(for key: Key) -> DerivedValue<Value>? { entries[key]?.value }

    /// How many values are alive.
    public var liveCount: Int { entries.values.reduce(0) { $0 + ($1.value == nil ? 0 : 1) } }

    /// Drops the entries whose value has ended.
    public func sweep() {
        entries = entries.filter { $0.value.value != nil }
        sinceSweep = 0
    }
}
