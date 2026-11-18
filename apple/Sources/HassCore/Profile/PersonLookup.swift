import Foundation

// MARK: - The viewer's person

/// Remembers which `person.*` entity belongs to a user until the household's people change.
///
/// Finding it scans the whole house (``AvatarSyncPlan/personID(forUser:in:)``), and a `viewer` read can happen on every
/// evaluation of an authored rule. The answer depends only on the user id, the people revision (``EntityStore/peopleRevision``)
/// and the store, so it is recomputed when one of them differs and never for an unrelated entity change.
public struct PersonLookup {
    private var store: ObjectIdentifier?
    private var userID: String?
    private var revision = -1
    private var answer: String?

    /// How many times the house was scanned; a test reads it to prove a cache hit scans nothing.
    public private(set) var scans = 0

    /// Creates an empty lookup.
    public init() {}

    /// The person entity of `userID`, scanning `store` only when the user, the revision or the store differs from the last answer.
    /// - Parameters:
    ///   - userID: Home Assistant's user id.
    ///   - revision: The store's ``EntityStore/peopleRevision``, read by the caller inside its observation so it re-runs when people change.
    ///   - store: The store to scan.
    @MainActor
    public mutating func personID(forUser userID: String, revision: Int, in store: EntityStore) -> String? {
        let identity = ObjectIdentifier(store)
        if self.store == identity, self.userID == userID, self.revision == revision { return answer }
        scans += 1
        let found = AvatarSyncPlan.personID(forUser: userID, in: store.allValues.values)
        (self.store, self.userID, self.revision, answer) = (identity, userID, revision, found)
        return found
    }
}
