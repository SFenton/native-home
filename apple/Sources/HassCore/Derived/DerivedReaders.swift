import Foundation

// MARK: - Keeping what a run read alive

/// Holds the derived values one observation's runs read, for as long as that observation lives.
///
/// An observation tracks a derived value through its registrar, which does not keep the value alive: with nothing else holding it,
/// the value would end and the reader would never hear of a change. So a run happens inside ``run(_:)``, and every
/// ``DerivedValue/current`` read in it is held by the collector until the observation's next run, which holds the ones it reads again
/// and lets go of the rest. An expression only a closed page used then ends with that page's observations (``DerivedValues`` keeps
/// its entries weakly).
@MainActor
public final class DerivedReaders {
    private static var active: DerivedReaders?
    private var held: [ObjectIdentifier: AnyObject] = [:]

    /// Creates an empty collector, one per observation.
    public init() {}

    /// How many values the last run read.
    public var count: Int { held.count }

    /// Runs `body`; the derived values it reads are held until the next run.
    public func run(_ body: () -> Void) {
        let before = held
        held = [:]
        let outer = Self.active
        Self.active = self
        defer {
            Self.active = outer
            _ = before
        }
        body()
    }

    /// Holds `value` in the run in progress, if one is collecting.
    static func note(_ value: AnyObject) { active?.held[ObjectIdentifier(value)] = value }
}
