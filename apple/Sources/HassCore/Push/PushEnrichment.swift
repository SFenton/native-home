import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// What the notification service extension changes on a notification before it shows (contract v1, rule 3;
/// `.agents/platforms/apple/push.md`). Pure, so the extension and the debug local-notification preview share it.
public struct PushEnrichment: Equatable, Sendable {
    /// The category to register and use; nil when the payload has no buttons.
    public var category: PushCategory?
    /// Clear the relay's `fenton.dynamic` placeholder (no buttons).
    public var clearsPlaceholderCategory: Bool
    /// Thread id to set (`group`), when the notification has none.
    public var threadIdentifier: String?
    /// The file to attach.
    public var attachment: PushAttachmentSource?

    /// Plans the changes.
    /// - Parameters:
    ///   - payload: The `fenton` block.
    ///   - categoryIdentifier: The notification's category now.
    ///   - threadIdentifier: The notification's thread now.
    ///   - server: The signed-in server, if any (attachments need it).
    public init(payload: PushPayload, categoryIdentifier: String, threadIdentifier: String, server: HassServer?) {
        category = payload.entityID?.hasPrefix("camera.") == true
            ? PushCategory(cameraActions: payload.actions)
            : PushCategory(actions: payload.actions)
        clearsPlaceholderCategory = category == nil && categoryIdentifier == PushPayload.dynamicCategory
        self.threadIdentifier = threadIdentifier.isEmpty ? payload.group : nil
        attachment = server.flatMap { PushAttachmentSource.resolve(payload, server: $0) }
    }
}

#if canImport(UserNotifications)
extension PushEnrichment {
    /// Applies the category and thread to content (the attachment is added by the caller once loaded).
    public func apply(to content: UNMutableNotificationContent) {
        if let category { content.categoryIdentifier = category.identifier }
        if clearsPlaceholderCategory { content.categoryIdentifier = "" }
        if let threadIdentifier { content.threadIdentifier = threadIdentifier }
    }
}
#endif
