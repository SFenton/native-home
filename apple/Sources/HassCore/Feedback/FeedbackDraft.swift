import Foundation

/// The editable form state, with the title prefix rule and submit validation.
public struct FeedbackDraft: Sendable, Equatable {
    public let kind: FeedbackKind
    /// Always starts with ``FeedbackKind/titlePrefix``; set through ``setTitle(_:)``.
    public private(set) var title: String
    public var description = ""
    public var reproSteps = ""
    public var expectedBehavior = ""

    /// A blank form with the prefix pre-filled.
    /// - Parameter kind: Bug report or feature request.
    public init(kind: FeedbackKind) {
        self.kind = kind
        title = kind.titlePrefix
    }

    /// Stores an edited title, keeping the prefix the person cannot remove.
    /// - Parameter raw: The text field's new value.
    public mutating func setTitle(_ raw: String) {
        title = Self.prefixedTitle(raw, kind: kind)
    }

    /// Re-applies the prefix to an edited title.
    ///
    /// Deleting into the prefix restores it; text typed over a selected prefix is kept after it; a
    /// prefix typed without its space gains one.
    ///
    /// - Parameters:
    ///   - raw: Edited title text.
    ///   - kind: Form whose prefix applies.
    /// - Returns: `prefix + remainder`, the remainder with leading whitespace trimmed.
    public static func prefixedTitle(_ raw: String, kind: FeedbackKind) -> String {
        let prefix = kind.titlePrefix
        if raw.hasPrefix(prefix) { return raw }
        let bare = prefix.trimmingCharacters(in: .whitespaces)
        let remainder: Substring
        if raw.hasPrefix(bare) {
            remainder = raw.dropFirst(bare.count)
        } else if prefix.hasPrefix(raw) {
            remainder = ""
        } else {
            remainder = Substring(raw)
        }
        return prefix + remainder.drop(while: \.isWhitespace)
    }

    /// The title without its prefix, trimmed.
    public var titleBody: String {
        String(title.dropFirst(kind.titlePrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether dismissing would lose anything the person typed (title beyond the prefix or any box).
    /// Attachments are checked by the caller.
    public var hasTypedInput: Bool {
        !titleBody.isEmpty || boxes.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The first problem that blocks Submit, or nil when the draft can be sent.
    public var validationIssue: FeedbackValidationIssue? {
        if titleBody.isEmpty { return .missingTitle }
        if title.utf16.count > FeedbackLimits.titleCharacters { return .titleTooLong }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missingDescription }
        if boxes.contains(where: { $0.utf16.count > FeedbackLimits.bodyCharacters }) { return .textTooLong }
        return nil
    }

    /// The boxes this kind shows.
    private var boxes: [String] {
        kind.includesReproduction ? [description, reproSteps, expectedBehavior] : [description]
    }
}
