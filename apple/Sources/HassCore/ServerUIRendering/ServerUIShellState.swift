import Foundation
import Observation

// MARK: - Scene-local state

/// Scene-owned local values survive compatible publications. This is not an entity store.
@MainActor @Observable
public final class ServerUILocalState {
    /// Why a local-state or draft operation was refused.
    public enum Failure: Error, Equatable { case invalidField, invalidValue, interactionBlocked, staleCommand }
    /// The current value of each field by id.
    private(set) public var values: [String: ServerUICompositionDocument.LocalValue]
    private var fields: [ServerUICompositionDocument.LocalField]

    /// Creates the state with every field at its initial value, or throws for repeated ids or an invalid definition.
    public init(fields: [ServerUICompositionDocument.LocalField]) throws {
        try Self.validate(fields)
        self.fields = fields
        values = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.initial) })
    }

    /// Stores a value the field's rule accepts. Writing the stored value again changes nothing.
    public func set(_ value: ServerUICompositionDocument.LocalValue, for id: String) throws {
        guard let field = fields.first(where: { $0.id == id }) else { throw Failure.invalidField }
        guard field.accepts(value) else { throw Failure.invalidValue }
        if values[id] != value { values[id] = value }
    }

    /// Removing a changed selection or narrowing its range is an explicit interaction blocker.
    public func validateReplacement(_ next: [ServerUICompositionDocument.LocalField]) throws {
        try Self.validate(next)
        for field in fields {
            guard let value = values[field.id] else { throw Failure.invalidField }
            if let replacement = next.first(where: { $0.id == field.id }) {
                guard replacement.accepts(value) else { throw Failure.interactionBlocked }
            } else if value != field.initial {
                throw Failure.interactionBlocked
            }
        }
    }

    /// Adopts a compatible publication's fields, keeping edited values. Throws before any change when one would be lost.
    public func apply(_ next: [ServerUICompositionDocument.LocalField]) throws {
        try validateReplacement(next)
        let merged = Dictionary(uniqueKeysWithValues: next.map { ($0.id, values[$0.id] ?? $0.initial) })
        if merged != values { values = merged }
        if next != fields { fields = next }
    }

    private static func validate(_ fields: [ServerUICompositionDocument.LocalField]) throws {
        guard fields.count <= 100, Set(fields.map(\.id)).count == fields.count,
              fields.allSatisfy(\.isValidDefinition) else {
            throw Failure.invalidField
        }
    }
}

// MARK: - Native draft interface

/// A domain adapter owns this draft and its save closure. Publication cannot serialize a command.
@MainActor @Observable
public final class ServerUIDraft {
    /// The owner and record a draft saves to.
    public struct Identity: Equatable, Sendable {
        /// The owning provider or collection.
        public let ownerId: String
        /// The record within the owner.
        public let recordId: String
        /// Creates an identity.
        public init(ownerId: String, recordId: String) { self.ownerId = ownerId; self.recordId = recordId }
    }
    /// One pinned save: the exact target and values captured when it began.
    public struct Save: Equatable, Sendable {
        /// The ticket id; only this ticket may complete the save.
        public let id: UUID
        /// The pinned target.
        public let identity: Identity
        /// The pinned values.
        public let values: [String: ServerUICompositionDocument.LocalValue]
    }
    /// The record this draft edits.
    public let identity: Identity
    private let state: ServerUILocalState
    /// The current values.
    public var values: [String: ServerUICompositionDocument.LocalValue] { state.values }
    private var baseline: [String: ServerUICompositionDocument.LocalValue]
    /// The save in flight, or `nil`.
    private(set) public var pending: Save?
    /// Fixed copy for the last failed save, or `nil`.
    private(set) public var failure: String?
    /// Whether any value differs from the last saved baseline.
    public var hasChanges: Bool { state.values != baseline }
    /// Whether leaving would lose edits or abandon a save.
    public var blocksExit: Bool { hasChanges || pending != nil }

    /// Creates a draft, or throws for a blank identity or invalid fields.
    public init(identity: Identity, fields: [ServerUICompositionDocument.LocalField]) throws {
        guard [identity.ownerId, identity.recordId].allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf16.count <= 240
        }) else { throw ServerUILocalState.Failure.invalidField }
        self.identity = identity
        state = try ServerUILocalState(fields: fields)
        baseline = state.values
    }

    /// Edits a field. Throws while a save is pending.
    public func set(_ value: ServerUICompositionDocument.LocalValue, for id: String) throws {
        guard pending == nil else { throw ServerUILocalState.Failure.interactionBlocked }
        try state.set(value, for: id)
        failure = nil
    }

    /// The exact target and values are pinned until the caller resolves this ticket.
    public func beginSave() throws -> Save {
        guard pending == nil, hasChanges else { throw ServerUILocalState.Failure.interactionBlocked }
        let ticket = Save(id: UUID(), identity: identity, values: state.values)
        pending = ticket
        failure = nil
        return ticket
    }

    /// Resolves the pending save: a failure keeps the edits for retry, success makes them the baseline.
    public func complete(_ ticket: Save, failure message: String? = nil) throws {
        guard pending == ticket else { throw ServerUILocalState.Failure.staleCommand }
        if let message {
            guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ServerUILocalState.Failure.invalidValue
            }
            failure = message
        } else {
            baseline = ticket.values
            failure = nil
        }
        pending = nil
    }

    /// A native discard confirmation must precede this method for a dirty draft.
    public func discard() throws {
        guard pending == nil else { throw ServerUILocalState.Failure.interactionBlocked }
        for (id, value) in baseline { try state.set(value, for: id) }
        failure = nil
    }
}

// MARK: - Keyed native collection interface

/// A domain store projects rows through this value boundary, without creating another connection.
public struct ServerUIRowItem: Equatable, Sendable {
    /// The row's stable key.
    public let id: String
    /// The row's main text.
    public let title: String
    /// Secondary text, if any.
    public let subtitle: String?
    /// Trailing value text, if any.
    public let value: String?
    /// Creates a row.
    public init(id: String, title: String, subtitle: String? = nil, value: String? = nil) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.value = value
    }
}

/// Last-good rows stay visible on refresh, reconnect, failure and unavailable responses.
@MainActor @Observable
public final class ServerUIRowCollection {
    /// Where a collection is in loading its rows.
    public enum Phase: String, Sendable { case loading, ready, stale, failed, unavailable }
    /// Rows that break the collection's limits.
    public enum Failure: Error, Equatable { case invalidRows }
    /// The rows currently shown; last-good rows survive a refresh or failure.
    private(set) public var rows: [ServerUIRowItem] = []
    /// Where the collection is in loading.
    private(set) public var phase: Phase = .loading

    /// Creates an empty collection in its loading phase.
    public init() {}

    /// `nil` means retain data; an explicit empty array is a successful, empty result only.
    public func apply(_ items: [ServerUIRowItem]?, phase: Phase) throws {
        if let items {
            guard phase == .ready || phase == .stale, items.count <= 100,
                  Set(items.map(\.id)).count == items.count,
                  items.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.id.utf16.count <= 240
                      && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && $0.title.utf16.count <= 2_000
                      && ($0.subtitle?.utf16.count ?? 0) <= 2_000 && ($0.value?.utf16.count ?? 0) <= 2_000 }) else {
                throw Failure.invalidRows
            }
            if rows != items { rows = items }
        } else if phase == .ready {
            throw Failure.invalidRows
        }
        if self.phase != phase { self.phase = phase }
    }
}
