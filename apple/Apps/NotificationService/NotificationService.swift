import Foundation
import HassCore
import UserNotifications

/// Finishes a Fenton Push notification before the system shows it (contract v1, rule 3;
/// `.agents/platforms/apple/push.md`), with ``PushEnrichment``:
///
/// - replaces the relay's `fenton.dynamic` placeholder with a category built from the payload's buttons
///   (``PushCategory``), registered next to the categories already there;
/// - threads it by `group`;
/// - attaches the camera snapshot (`/api/camera_proxy/<entity_id>`) or the image, video or file, fetched with the
///   signed-in user's token from the Keychain item the app shares through the app group.
///
/// Anything that fails leaves the notification as the relay sent it. `xcrun simctl push` never runs service
/// extensions; the app's debug local preview (`FENTON_PUSH_PREVIEW`) runs the same enrichment instead.
final class NotificationService: UNNotificationServiceExtension {
    private let state = DeliveryState()

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent,
              let payload = PushPayload(userInfo: content.userInfo) else {
            contentHandler(request.content)
            return
        }
        let trace = PushTrace.shared
        let store = KeychainTokenStore(accessGroup: KeychainTokenStore.sharedAccessGroup)
        let credentials = store.load()
        let plan = PushEnrichment(payload: payload, categoryIdentifier: content.categoryIdentifier,
                                  threadIdentifier: content.threadIdentifier, server: credentials?.server)
        plan.apply(to: content)
        trace.record("service: category \(content.categoryIdentifier), \(payload.actions.count) actions, "
            + "entity \(payload.entityID ?? "-"), signed in \(credentials != nil), attachment \(plan.attachment?.url.path ?? "-")")
        state.begin(content, handler: contentHandler)
        let state = state
        state.task = Task {
            if let category = plan.category {
                let center = UNUserNotificationCenter.current()
                center.setNotificationCategories(category.merged(into: await center.notificationCategories()))
            }
            if let source = plan.attachment {
                let token = source.needsAuthorization && credentials != nil ? try? await TokenManager(store: store).validAccessToken() : nil
                if let file = await PushAttachmentLoader(trace: trace).load(source, accessToken: token) {
                    do {
                        let attachment = try UNNotificationAttachment(identifier: source.kind.rawValue, url: file)
                        state.update { $0.attachments = [attachment] }
                        trace.record("service: attached \(file.pathExtension)")
                    } catch {
                        trace.record("service: attachment rejected \((error as NSError).code)")
                    }
                }
            }
            state.finish()
        }
    }

    override func serviceExtensionTimeWillExpire() {
        PushTrace.shared.record("service: time expired")
        state.task?.cancel()
        state.finish()
    }
}

/// The content being finished and its handler, shared between the work task and the expiry callback; the
/// handler runs once.
private final class DeliveryState: @unchecked Sendable {
    private let lock = NSLock()
    private var content: UNMutableNotificationContent?
    private var handler: ((UNNotificationContent) -> Void)?
    var task: Task<Void, Never>?

    func begin(_ content: UNMutableNotificationContent, handler: @escaping (UNNotificationContent) -> Void) {
        lock.withLock {
            self.content = content
            self.handler = handler
        }
    }

    func update(_ change: (UNMutableNotificationContent) -> Void) {
        lock.withLock { content.map(change) }
    }

    func finish() {
        let (content, handler) = lock.withLock {
            defer { self.handler = nil }
            return (self.content, self.handler)
        }
        if let content, let handler { handler(content) }
    }
}
