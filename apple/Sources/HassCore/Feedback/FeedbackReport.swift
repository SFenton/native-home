import Foundation

/// The JSON report `POST /api/fenton_feedback/report` takes (`SFenton/ha-fenton-feedback` `report.py`). The
/// integration validates it and composes the issue, labels and marker, and adds the Home Assistant user who
/// sent it, as FestivalNativeApps' service does for its app.
public struct FeedbackReport: Encodable, Sendable, Equatable {
    /// One uploaded attachment.
    public struct Media: Encodable, Sendable, Equatable {
        public var name: String
        public var url: String
        public var video: Bool
    }

    public var kind: String
    public var platform: String
    public var title: String
    public var description: String
    /// Bug reports only; omitted when empty.
    public var repro: String?
    /// Bug reports only; omitted when empty.
    public var expected: String?
    /// `[label, value]` rows.
    public var diagnostics: [[String]]
    public var media: [Media]

    /// Builds the report for a valid draft.
    ///
    /// - Parameters:
    ///   - draft: The form's draft.
    ///   - platform: Device family.
    ///   - diagnostics: Device, app and Home Assistant details.
    ///   - media: Uploaded attachments in order, with their GitHub URLs.
    public init(draft: FeedbackDraft, platform: FeedbackPlatform, diagnostics: FeedbackDiagnostics,
                media: [(attachment: FeedbackAttachment, url: URL)]) {
        func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        func optional(_ text: String) -> String? {
            guard draft.kind.includesReproduction else { return nil }
            let value = trimmed(text)
            return value.isEmpty ? nil : value
        }
        kind = draft.kind.rawValue
        self.platform = platform.rawValue
        title = draft.kind.titlePrefix + draft.titleBody
        description = trimmed(draft.description)
        repro = optional(draft.reproSteps)
        expected = optional(draft.expectedBehavior)
        self.diagnostics = diagnostics.rows.map { [$0.label, $0.value] }
        self.media = media.map { Media(name: $0.attachment.filename, url: $0.url.absoluteString, video: $0.attachment.isVideo) }
    }
}
