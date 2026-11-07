import Foundation
import Observation

/// Observable holder for one entity, so a view that reads it redraws only when that entity changes.
@MainActor
@Observable
public final class EntityBox: Identifiable {
    /// The entity id this box tracks; stable for the box's life.
    public let id: String
    /// The latest state, or `nil` if the server doesn't know this entity.
    public internal(set) var state: EntityState?

    init(id: String, state: EntityState?) {
        self.id = id
        self.state = state
    }
}

/// The app's single source of entity state.
///
/// Updates are applied in place: a box is created once per entity id and only mutated when its value
/// actually changes, so reconnects and snapshot restores never make views reload.
@MainActor
@Observable
public final class EntityStore {
    /// Where the current values came from.
    public enum Freshness: Equatable, Sendable {
        /// Nothing loaded yet.
        case empty
        /// Restored from disk; live data not yet received.
        case snapshot(savedAt: Date)
        /// Receiving live updates.
        case live
    }

    /// Where the current values came from.
    public private(set) var freshness: Freshness = .empty

    /// Whether any state has arrived: a disk snapshot restored at launch or the first live set. False only on a first
    /// sign-in (nothing saved yet) until Home Assistant answers, and after ``reset()``.
    ///
    /// Screens use it to tell "not heard yet" from "Home Assistant says unavailable": before it flips, status pills show a
    /// muted placeholder and the header shows one "Connecting" arc (`EnvironmentValues.valuesPending`, pattern:
    /// connection-lifecycle). A launch from the snapshot is `true` from the first frame, so nothing is replaced by a
    /// placeholder on reopen. It is derived from ``freshness``, which is written once per change on the main actor by the
    /// delivery's apply (the delta queue has already diffed it), so reading it adds no work to the hot path.
    public var hasReceivedFirstState: Bool { freshness != .empty }

    /// Counts the moments the whole state was handed back at once: a disk snapshot restored at launch, the first live set that
    /// replaces it, and every reconnect (``noteReapply()``). Tiles that animate a layout change (a remote's action set) read it
    /// to apply what arrives meanwhile without motion: a reopen must never re-fade or reorder a screen (pattern:
    /// connection-lifecycle, "No reload on reopen"). Written once per such moment, so reading it adds nothing to the hot path.
    public private(set) var reapplyGeneration = 0

    /// Counts `person.*` entities appearing or disappearing, so a watcher of the household's people (``PersonAvatars``) notices
    /// someone new mid-session without observing every entity. It is written only on that rare change, once per delivery.
    public private(set) var peopleRevision = 0

    @ObservationIgnored private var boxes: [String: EntityBox] = [:]
    @ObservationIgnored private var values: [String: EntityState] = [:]

    /// Number of times a box value was replaced. Tests use it to prove unchanged entities are not republished.
    @ObservationIgnored public private(set) var publishedChangeCount = 0

    /// Creates an empty store.
    public init() {}

    // MARK: - Reading

    /// The observable box for an entity. Always returns the same box for the same id.
    public func entity(_ entityId: String) -> EntityBox {
        if let box = boxes[entityId] { return box }
        let box = EntityBox(id: entityId, state: values[entityId])
        boxes[entityId] = box
        return box
    }

    /// The current value without observation, for non-UI code.
    public func value(_ entityId: String) -> EntityState? { values[entityId] }

    /// All current values.
    public var allValues: [String: EntityState] { values }

    // MARK: - Writing

    /// Replaces the whole state with a full set (initial load or reconnect), diffing in place.
    /// - Parameters:
    ///   - states: Every entity the server reports.
    ///   - freshness: The resulting freshness.
    /// - Returns: The values this replaced, so the caller can release them off the main thread (freeing thousands of attribute
    ///   dictionaries is main-thread time).
    @discardableResult
    public func replaceAll(_ states: [EntityState], freshness: Freshness = .live) -> [EntityState] {
        var displaced: [EntityState] = []
        var incoming: [String: EntityState] = [:]
        incoming.reserveCapacity(states.count)
        for state in states { incoming[state.entityId] = state }
        var peopleChanged = false
        for removed in values.keys where incoming[removed] == nil {
            if let old = values[removed] { displaced.append(old) }
            values[removed] = nil
            publish(removed, nil)
            if removed.hasPrefix(Self.personPrefix) { peopleChanged = true }
        }
        for (id, state) in incoming where values[id] != state {
            if let old = values.updateValue(state, forKey: id) {
                displaced.append(old)
            } else if id.hasPrefix(Self.personPrefix) {
                peopleChanged = true
            }
            publish(id, state)
        }
        if peopleChanged { peopleRevision += 1 }
        if self.freshness != freshness { self.freshness = freshness }
        noteReapply()
        return displaced
    }

    /// Marks that the state is being handed back as a whole (a reconnect, or ``replaceAll(_:freshness:)``), so animated layout
    /// changes in the deliveries that follow apply without motion. See ``reapplyGeneration``.
    public func noteReapply() { reapplyGeneration &+= 1 }

    /// Applies individual changes (a state_changed event or a compressed diff).
    /// - Returns: The values this replaced (see ``replaceAll(_:freshness:)``).
    @discardableResult
    public func apply(_ changes: [EntityState]) -> [EntityState] {
        var displaced: [EntityState] = []
        var peopleChanged = false
        for state in changes where values[state.entityId] != state {
            if let old = values.updateValue(state, forKey: state.entityId) {
                displaced.append(old)
            } else if state.entityId.hasPrefix(Self.personPrefix) {
                peopleChanged = true
            }
            publish(state.entityId, state)
        }
        if peopleChanged { peopleRevision += 1 }
        return displaced
    }

    /// Applies changes and removals from a live delivery without touching unchanged entities.
    /// - Parameters:
    ///   - changes: New or changed entities.
    ///   - removed: Entity ids the server no longer reports.
    ///   - freshness: The resulting freshness.
    /// - Returns: The values this replaced (see ``replaceAll(_:freshness:)``).
    @discardableResult
    public func apply(_ changes: [EntityState], removing removed: [String], freshness: Freshness) -> [EntityState] {
        var displaced: [EntityState] = []
        var peopleRemoved = false
        for id in removed {
            guard let old = values[id] else { continue }
            displaced.append(old)
            values[id] = nil
            publish(id, nil)
            if id.hasPrefix(Self.personPrefix) { peopleRemoved = true }
        }
        if peopleRemoved { peopleRevision += 1 }
        displaced += apply(changes)
        if self.freshness != freshness { self.freshness = freshness }
        return displaced
    }

    /// Clears everything (sign out).
    public func reset() {
        let hadPeople = values.keys.contains { $0.hasPrefix(Self.personPrefix) }
        for id in values.keys { publish(id, nil) }
        if hadPeople { peopleRevision += 1 }
        values = [:]
        freshness = .empty
    }

    private static let personPrefix = "person."

    private func publish(_ id: String, _ state: EntityState?) {
        guard let box = boxes[id] else { return }
        box.state = state
        publishedChangeCount += 1
    }
}
