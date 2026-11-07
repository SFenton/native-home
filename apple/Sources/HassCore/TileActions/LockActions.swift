import Foundation

/// A lock's one action (front door, the car): Unlock when locked, Lock when unlocked (owner, option B). Explicit
/// `lock.lock` / `lock.unlock`, never `toggle`; the service follows ``SecurityConfig/lockService(for:)``.
///
/// | state | verb | symbol | isOn | phase |
/// |---|---|---|---|---|
/// | `locked` | Unlock | `lock.fill` | false | ready |
/// | `unlocked`, `open` | Lock | `lock.open` | true | ready |
/// | `locking` | Unlock | `lock.fill` | false | inFlight |
/// | `unlocking` | Lock | `lock.open` | true | inFlight |
/// | `jammed` | Lock | `lock.trianglebadge.exclamationmark` (error) | true | ready |
/// | missing, `unavailable`, `unknown` | Unlock | `lock.fill` | false | unavailable |
///
/// `isOn` means *unlocked or moving toward it*: the filled face, solid white disc. Feedback is ``TileActionSpec/Feedback/tracked``:
/// the transitional state comes from the entity (`locking`, `unlocking`), so there are no optimistic intents.
public struct LockActions: TileActionProviding {
    /// The lock entity.
    public var entityId: String

    /// Creates the provider.
    public init(entityId: String) {
        self.entityId = entityId
    }

    /// The action's id in every state.
    public static let actionId = "lock"

    public func actions(for state: EntityState?) -> [TileActionSpec] {
        let value = state?.state
        let unavailable = EntityState.isUnavailable(value)
        // A jammed lock offers Lock (owner decision doc); every other state follows today's `lockServiceForState`.
        let service = value == "jammed" ? "lock" : SecurityConfig.lockService(for: value)
        let call = ServiceCall("lock", service, target: entityId)
        let locks = service == "lock"
        let jammed = value == "jammed"
        let symbol = jammed ? "lock.trianglebadge.exclamationmark" : (locks ? "lock.open" : "lock.fill")
        let phase: TileActionSpec.Phase = unavailable ? .unavailable : (value == "locking" || value == "unlocking" ? .inFlight : .ready)
        return [TileActionSpec(
            id: Self.actionId, verb: locks ? "Lock" : "Unlock", symbol: unavailable ? "lock.fill" : symbol,
            isOn: !unavailable && value != "locked" && value != "locking",
            phase: phase, feedback: .tracked, call: call, isError: jammed
        )]
    }

    public var stateTextCandidates: [String] {
        ["Locked", "Unlocked", "Locking", "Unlocking", "Jammed", "Open", "Unavailable", "Didn't Respond"]
    }

    /// Whether the tile draws filled: anything but locked (unlocked, open, locking, unlocking, jammed). Today's
    /// `LockTile.isActive`, as a pure rule.
    public static func isFilled(_ state: String?) -> Bool {
        guard let state, !EntityState.isUnavailable(state) else { return false }
        return state != "locked"
    }
}
