import Foundation
@preconcurrency import HAKit

/// Applies Home Assistant's compressed `subscribe_entities` messages to the house's states, so each message costs work in
/// proportion to what it changed (`.agents/platforms/apple/connection-lifecycle.md`, "Live delivery path").
///
/// **Why it exists.** HAKit's own states cache rebuilds a `Set<HAEntity>` of the whole house for every message and hands it
/// over, and the diff against the previous set compared every entity again. `HAEntity ==` includes `lastUpdated`, which HAKit
/// fills with `Date()` when Home Assistant omits `lu` (it does whenever `lu` equals `lc`), so after any full resend nearly every
/// entity looked changed and was converted and compared on the main thread. This engine keeps one ``EntityState`` per entity,
/// merges the message into it, and reports an entity only when its state, attributes or `lastChanged` really differ.
///
/// The merge follows HAKit's `HACacheKeyStates` and `home-assistant-js-websocket`'s `entities.ts`: `a` adds (or refreshes) whole
/// entities, `r` removes, `c` changes with `+` (state and `lc` replaced, attributes merged by key) and `-` (attribute keys
/// removed). `lu` and the context are not kept: nothing in the app reads them.
///
/// Not thread-safe: ``HassConnection`` touches it only on its delta queue.
struct EntityDeltaEngine {
    /// What one message changed.
    struct Change: Equatable, Sendable {
        /// New or changed entities. The whole house on the first message ever received.
        var upserts: [EntityState]
        /// Entity ids that are gone.
        var removed: [String]
        /// This message was the full set a (re)started subscription sends first, not a diff.
        var isReplacement: Bool
        /// No set had been received before: ``upserts`` is the full house.
        var isFirst: Bool
    }

    /// Every entity as of the last message.
    private(set) var entities: [String: EntityState] = [:]
    private var replacementPending = false
    private var hasReceivedSet = false

    init() {}

    /// The subscription (re)started on a socket: the next message is the full set, and any entity it lacks is gone.
    mutating func subscriptionStarted() { replacementPending = true }

    /// Merges one message.
    /// - Parameters:
    ///   - update: The decoded `subscribe_entities` event.
    ///   - now: Stands in for `lastChanged` on a new entity that arrives without one.
    /// - Returns: The entities that really changed.
    mutating func apply(_ update: HACompressedStatesUpdates, now: Date = Date()) -> Change {
        let isReplacement = replacementPending || !hasReceivedSet
        let isFirst = !hasReceivedSet
        replacementPending = false
        hasReceivedSet = true

        var changed: [String: EntityState] = [:]
        var removed: [String] = []

        for (id, addition) in update.add ?? [:] {
            guard let merged = Self.merged(entities[id], id: id, addition: addition, now: now) else { continue }
            if merged != entities[id] {
                entities[id] = merged
                changed[id] = merged
            }
        }
        if isReplacement {
            // A full set is the whole house: what it lacks was removed while the socket was down.
            let incoming = update.add ?? [:]
            for id in entities.keys where incoming[id] == nil {
                entities[id] = nil
                removed.append(id)
            }
        }
        for id in update.remove ?? [] where entities.removeValue(forKey: id) != nil {
            changed[id] = nil
            removed.append(id)
        }
        for (id, diff) in update.change ?? [:] {
            guard var entity = entities[id] else { continue }
            if let additions = diff.additions { Self.add(additions, to: &entity) }
            if let subtractions = diff.subtractions { Self.subtract(subtractions, from: &entity) }
            if entity != entities[id] {
                entities[id] = entity
                changed[id] = entity
            }
        }
        return Change(upserts: isFirst ? Array(entities.values) : Array(changed.values), removed: removed,
                      isReplacement: isReplacement, isFirst: isFirst)
    }

    // MARK: - Merging

    /// The entity after an `a` entry: state, attributes and `lastChanged` replaced by what the entry carries, the rest kept.
    /// Nil for a new entity without a state, which HAKit also drops.
    private static func merged(_ old: EntityState?, id: String, addition: HACompressedEntityState, now: Date) -> EntityState? {
        guard let state = addition.state ?? old?.state else { return nil }
        return EntityState(
            entityId: id,
            state: state,
            attributes: addition.attributes.map(convert) ?? old?.attributes ?? [:],
            lastChanged: addition.lastChanged ?? old?.lastChanged ?? now
        )
    }

    /// A `c` entry's `+`: the state and `lastChanged` replaced when present, attributes merged key by key.
    private static func add(_ addition: HACompressedEntityState, to entity: inout EntityState) {
        if let state = addition.state { entity.state = state }
        if let lastChanged = addition.lastChanged { entity.lastChanged = lastChanged }
        if let attributes = addition.attributes {
            for (key, value) in attributes { entity.attributes[key] = JSONValue(any: value) }
        }
    }

    /// A `c` entry's `-`: the listed attribute keys removed.
    private static func subtract(_ subtraction: HACompressedEntityStateRemove, from entity: inout EntityState) {
        for key in subtraction.attributes ?? [] { entity.attributes[key] = nil }
    }

    private static func convert(_ attributes: [String: Any]) -> [String: JSONValue] {
        attributes.mapValues { JSONValue(any: $0) }
    }
}

/// The changes of one or more messages waiting for the main thread, merged so a burst costs one hop and the newest value of each
/// entity wins. Touched only on the delta queue.
struct EntityDeltaBatch: Sendable {
    private(set) var changed: [String: EntityState] = [:]
    private(set) var removed: Set<String> = []
    private(set) var isFirst = false
    private(set) var isReplacement = false
    /// Entities in the house after the newest merged message.
    private(set) var houseCount = 0

    init() {}

    /// Nothing to hand over: no entity changed or went, and no first set to mark live.
    var isEmpty: Bool { changed.isEmpty && removed.isEmpty && !isFirst }

    /// Folds one message in.
    /// - Parameters:
    ///   - change: What the message changed.
    ///   - houseCount: Entities in the house after it.
    mutating func merge(_ change: EntityDeltaEngine.Change, houseCount: Int) {
        isFirst = isFirst || change.isFirst
        isReplacement = isReplacement || change.isReplacement
        self.houseCount = houseCount
        for state in change.upserts {
            changed[state.entityId] = state
            removed.remove(state.entityId)
        }
        for id in change.removed {
            changed[id] = nil
            removed.insert(id)
        }
    }

    /// What the main thread applies.
    var applied: HassConnection.Applied {
        HassConnection.Applied(changed: Array(changed.values), removed: Array(removed), isFirst: isFirst,
                               houseCount: houseCount)
    }
}
