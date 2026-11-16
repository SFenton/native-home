import Foundation
import Observation

// MARK: - Draft-owned media

/// Media stays native and memory-only; downloaded field values never contain data or authorization.
@MainActor
public protocol ServerUIAttachmentFormSession: ServerUIFormSession {
    var images: [AdminTodoUpload.Image] { get }
    func beginReadingImages() throws
    func finishReadingImages(_ images: [AdminTodoUpload.Image]?, failure: String?) throws
}

@MainActor @Observable
private final class ServerUIAttachmentDraft {
    var images: [AdminTodoUpload.Image] = []
    var reading = false
    var error: String?
}

/// The real Admin To-Do upload uses the canonical upload validation and service boundary.
@MainActor
public final class ServerUIAdminTodoForm: ServerUIAttachmentFormSession {
    private let media: ServerUIAttachmentDraft
    private let draft: ServerUIValueForm

    /// Creates a server uiadmin todo form.
    public init(provider: ServerUITodoProvider, accessToken: @escaping @MainActor () async throws -> String) throws {
        guard provider.configuration.canAdd, provider.configuration.allowsAttachments else {
            throw ServerUITodoProvider.Failure.forbidden
        }
        let media = ServerUIAttachmentDraft()
        self.media = media
        draft = try ServerUIValueForm(identity: .init(ownerId: provider.configuration.entityId, recordId: "new"),
            fields: [
                .init(key: "name", label: "Task", control: .multiline, rule: .string(maxLength: 1000), value: .string(""), required: true),
                .text("images", "Images", "", control: .attachment),
            ]) { values in
                try await provider.add(name: values.formString("name"), images: media.images, accessToken: accessToken)
            }
    }

    public var identity: ServerUIDraft.Identity { draft.identity }
    public var groups: [ServerUIFormGroup] { draft.groups }
    public var hasChanges: Bool { draft.hasChanges || !media.images.isEmpty }
    public var isBusy: Bool { draft.isBusy || media.reading }
    public var canSave: Bool { draft.canSave && !media.reading }
    public var error: String? { media.error ?? draft.error }
    public var images: [AdminTodoUpload.Image] { media.images }
    /// Sets a field value in the draft.
    public func set(_ value: ServerUICompositionDocument.LocalValue, group: String, field: String) throws {
        guard !isBusy else { throw ServerUIRecordFailure.busy }
        guard field == "name" else { throw ServerUIRecordFailure.invalidField }
        try draft.set(value, group: group, field: field)
    }
    /// Marks that image attachments are being read.
    public func beginReadingImages() throws {
        guard !isBusy else { throw ServerUIRecordFailure.busy }
        media.reading = true
    }
    /// Records the images read, or the failure that stopped it.
    public func finishReadingImages(_ images: [AdminTodoUpload.Image]?, failure: String?) throws {
        guard media.reading else { throw ServerUIRecordFailure.staleSelection }
        defer { media.reading = false }
        if let failure { media.error = failure; return }
        guard let images else { return }
        if let problem = AdminTodoUpload.validationError(count: images.count, sizes: images.map(\.data.count), mimeTypes: images.map(\.mimeType)) {
            media.error = problem
            throw ServerUIRecordFailure.unavailable(problem)
        }
        try draft.set(.string(images.isEmpty ? "" : UUID().uuidString), group: identity.recordId, field: "images")
        media.images = images
        media.error = nil
    }
    /// Saves the draft to Home Assistant.
    public func save() async throws {
        guard !media.reading else { throw ServerUIRecordFailure.busy }
        try await draft.save()
        media.images = []
        media.error = nil
    }
    /// Discards edits and restores the initial draft.
    public func reset() throws {
        guard !media.reading else { throw ServerUIRecordFailure.busy }
        try draft.reset()
        media.images = []; media.error = nil
    }
    /// Abandons the draft.
    public func discard() throws {
        guard !media.reading else { throw ServerUIRecordFailure.busy }
        try draft.discard()
        media.images = []; media.error = nil
    }
}
