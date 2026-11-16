import Foundation
import Observation

// MARK: - Retained scalar draft

/// A real draft transaction: validated edits, immutable target, pinned save and retryable failure.
@MainActor @Observable
public final class ServerUIValueForm: ServerUIDeletableFormSession {
    /// A field value.
    public typealias Value = ServerUICompositionDocument.LocalValue
    /// The record the form edits.
    public let identity: ServerUIDraft.Identity
    /// The delete confirmation copy, or `nil` when the record cannot be deleted.
    public let deletion: ServerUIFormDeletion?
    private let allowsReset: Bool
    private var fields: [ServerUIFormValue]
    private var baseline: [ServerUIFormValue]
    private let defaults: [ServerUIFormValue]
    private let grouping: (@MainActor ([ServerUIFormValue]) -> [ServerUIFormGroup])?
    /// Whether a save or delete is in flight.
    private(set) public var isBusy = false
    /// Fixed copy for the last failed save or delete, or `nil`.
    private(set) public var error: String?
    private var closed = false
    @ObservationIgnored private let submit: @MainActor ([String: Value]) async throws -> Void
    @ObservationIgnored private let release: @MainActor () throws -> Void
    @ObservationIgnored private let visibility: @MainActor (String, [String: Value]) -> Bool
    @ObservationIgnored private let deleteOperation: (@MainActor () async throws -> Void)?

    /// Creates a form, or throws when its fields or defaults are invalid.
    public init(identity: ServerUIDraft.Identity, fields: [ServerUIFormValue],
                defaults: [String: Value]? = nil,
                allowsReset: Bool = true,
                grouping: (@MainActor ([ServerUIFormValue]) -> [ServerUIFormGroup])? = nil,
                visibility: @escaping @MainActor (String, [String: Value]) -> Bool = { _, _ in true },
                release: @escaping @MainActor () throws -> Void = {},
                deletion: ServerUIFormDeletion? = nil,
                delete: (@MainActor () async throws -> Void)? = nil,
                submit: @escaping @MainActor ([String: Value]) async throws -> Void) throws {
        guard !fields.isEmpty, fields.count <= 32, Set(fields.map(\.key)).count == fields.count,
              fields.allSatisfy(\.isValidDescriptor),
              defaults.map({ Set($0.keys).isSubset(of: Set(fields.map(\.key))) }) ?? true,
              (deletion == nil) == (delete == nil) else { throw ServerUIRecordFailure.invalidField }
        self.identity = identity; self.fields = fields; baseline = fields
        self.grouping = grouping
        self.allowsReset = allowsReset; self.deletion = deletion; deleteOperation = delete
        self.defaults = try fields.map { field in
            var next = field
            if let value = defaults?[field.key] {
                guard field.accepts(value) else { throw ServerUIRecordFailure.invalidValue }
                next.value = value
            }
            return next
        }
        self.visibility = visibility; self.submit = submit; self.release = release
    }

    /// The current value of each field by key.
    public var values: [String: Value] { Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0.value) }) }
    /// The fields grouped for display, with conditional fields resolved.
    public var groups: [ServerUIFormGroup] {
        let values = values
        let visible = fields.map {
            var field = $0
            field.visible = field.visible && visibility(field.key, values)
            return field
        }
        return grouping?(visible) ?? [.init(id: identity.recordId, fields: visible)]
    }
    /// Whether any field differs from its saved baseline.
    public var hasChanges: Bool { fields != baseline }
    /// Whether Reset is available.
    public var canReset: Bool { allowsReset && !closed && !isBusy && fields != defaults }
    /// `Reset Changes` while editing the saved values, `Reset` once they differ from the defaults.
    public var resetLabel: String { defaults == baseline ? "Reset Changes" : "Reset" }
    /// Whether there are changes, no save is in flight and every visible required text field is filled.
    public var canSave: Bool {
        !closed && !isBusy && hasChanges && groups.flatMap(\.fields).allSatisfy {
            guard $0.required && $0.visible else { return true }
            if case .string(let value) = $0.value { return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return true
        }
    }

    /// Edits an enabled, visible field. Throws while busy or closed, or for a value the field rejects.
    public func set(_ value: Value, group: String, field key: String) throws {
        guard !isBusy, !closed else { throw ServerUIRecordFailure.busy }
        guard groups.contains(where: { $0.id == group && $0.fields.contains(where: { $0.key == key && $0.enabled && $0.visible }) }),
              let index = fields.firstIndex(where: { $0.key == key }), fields[index].enabled else {
            throw ServerUIRecordFailure.invalidField
        }
        guard fields[index].accepts(value) else { throw ServerUIRecordFailure.invalidValue }
        fields[index].value = value
        error = nil
    }

    /// Submits the current values. A failure keeps the edits and shows fixed copy; success closes the form.
    public func save() async throws {
        guard canSave else { throw ServerUIRecordFailure.invalidValue }
        let values = values
        try await commit { try await self.submit(values) }
    }

    /// Deletes the record after native confirmation. A failure keeps the form open.
    public func delete() async throws {
        guard !closed, !isBusy, let deleteOperation else { throw ServerUIRecordFailure.invalidValue }
        try await commit(deleteOperation)
    }

    private func commit(_ operation: @MainActor () async throws -> Void) async throws {
        isBusy = true
        let submitted = fields
        defer { isBusy = false }
        do {
            try await operation()
            baseline = submitted
            closed = true
            error = nil
        } catch {
            self.error = Self.presentable(error)
            throw error
        }
    }

    /// Fixed copy for what the form may show. Only the typed record and todo failures carry curated text; any other
    /// error (a transport or service description, say) is replaced so server text never reaches the screen.
    static func presentable(_ error: any Error) -> String {
        if error is ServerUIRecordFailure || error is ServerUITodoProvider.Failure,
           let message = (error as? any LocalizedError)?.errorDescription, !message.isEmpty { return message }
        return "The change could not be saved. Try again."
    }

    /// Restores the defaults.
    public func reset() throws {
        guard !isBusy, !closed else { throw ServerUIRecordFailure.busy }
        guard allowsReset else { throw ServerUIRecordFailure.invalidValue }
        fields = defaults
        error = nil
    }

    /// Closes the form, releasing its owner once, and drops unsaved edits.
    public func discard() throws {
        guard !isBusy else { throw ServerUIRecordFailure.busy }
        if !closed { try release() }
        fields = baseline
        error = nil
        closed = true
    }
}

// MARK: - Typed field access

extension Dictionary where Key == String, Value == ServerUICompositionDocument.LocalValue {
    /// The string value of `key`, or ``ServerUIRecordFailure/invalidField``.
    public func formString(_ key: String) throws -> String {
        guard case .string(let value)? = self[key] else { throw ServerUIRecordFailure.invalidField }
        return value
    }
    /// The number value of `key`, or ``ServerUIRecordFailure/invalidField``.
    public func formNumber(_ key: String) throws -> Double {
        guard case .number(let value)? = self[key] else { throw ServerUIRecordFailure.invalidField }
        return value
    }
    /// The boolean value of `key`, or ``ServerUIRecordFailure/invalidField``.
    public func formBoolean(_ key: String) throws -> Bool {
        guard case .boolean(let value)? = self[key] else { throw ServerUIRecordFailure.invalidField }
        return value
    }
}
