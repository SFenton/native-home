#if DEBUG
import Foundation
import HassCore
import OSLog
import UserNotifications

/// Debug builds only: shows a Fenton Push payload as a local notification, finished by the same
/// ``PushEnrichment`` the service extension runs (`xcrun simctl push` never runs service extensions, so this is how
/// journeys check buttons and attachments on the simulator).
///
/// `FENTON_PUSH_PREVIEW` holds a base64 `.apns` file (`tools/push_fixtures/`); `FENTON_PUSH_PREVIEW_DELAY` is
/// the seconds before it shows (default 5), while the app stays open.
///
/// `FENTON_PUSH_COMMAND` holds a base64 background payload (`clear.apns`), run through
/// ``PushCoordinator/handleBackground(userInfo:)`` at launch: the simulator refuses content-available-only pushes
/// ("no user visible content"), so this is how journeys check `clear_notification`.
enum PushPreview {
    /// The background payload to run at launch, if any.
    static func command(environment: [String: String] = ProcessInfo.processInfo.environment) -> [AnyHashable: Any]? {
        guard let encoded = environment["FENTON_PUSH_COMMAND"], let data = Data(base64Encoded: encoded) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func scheduleIfRequested(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let encoded = environment["FENTON_PUSH_PREVIEW"], let data = Data(base64Encoded: encoded),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let payload = PushPayload(userInfo: object) else { return }
        let delay = environment["FENTON_PUSH_PREVIEW_DELAY"].flatMap(Double.init) ?? 5
        let aps = object["aps"] as? [String: Any] ?? [:]
        let alert = aps["alert"] as? [String: Any] ?? [:]
        let content = UNMutableNotificationContent()
        content.title = alert["title"] as? String ?? ""
        content.subtitle = alert["subtitle"] as? String ?? ""
        content.body = alert["body"] as? String ?? ""
        if aps["sound"] != nil { content.sound = .default }
        content.threadIdentifier = aps["thread-id"] as? String ?? ""
        content.categoryIdentifier = aps["category"] as? String ?? ""
        if aps["interruption-level"] as? String == "time-sensitive" { content.interruptionLevel = .timeSensitive }
        content.userInfo = [PushPayload.key: object[PushPayload.key] ?? [:]]
        let (server, accessToken) = credentials(environment)
        let plan = PushEnrichment(payload: payload, categoryIdentifier: content.categoryIdentifier,
                                  threadIdentifier: content.threadIdentifier, server: server)
        plan.apply(to: content)
        let identifier = payload.tag ?? UUID().uuidString
        let box = ContentBox(content)
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            // Waits in the app, then posts at once: the iOS 27 simulator refuses timed local requests ("Source is
            // not authorized", seen 2026-10-14). The app shows it as a banner over itself (`willPresent`).
            try? await Task.sleep(for: .seconds(delay))
            if let category = plan.category {
                center.setNotificationCategories(category.merged(into: await center.notificationCategories()))
            }
            if let source = plan.attachment {
                let token = source.needsAuthorization ? try? await accessToken?() : nil
                let file = await PushAttachmentLoader().load(source, accessToken: token)
                do {
                    guard let file else { throw URLError(.cannotLoadFromNetwork) }
                    box.content.attachments = [try UNNotificationAttachment(identifier: source.kind.rawValue, url: file)]
                } catch {
                    Logger(subsystem: "com.sfenton.home", category: "push").error(
                        "Preview attachment failed (token \(token != nil)): \(String(describing: error), privacy: .public)")
                }
            }
            do {
                try await center.add(UNNotificationRequest(identifier: identifier, content: box.content, trigger: nil))
            } catch {
                let settings = await center.notificationSettings()
                Logger(subsystem: "com.sfenton.home", category: "push").error(
                    "Preview not added (authorization \(settings.authorizationStatus.rawValue), alerts \(settings.alertSetting.rawValue)): \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// The test token launch's server and token, else the saved sign-in.
    private static func credentials(_ environment: [String: String]) -> (HassServer?, (@Sendable () async throws -> String)?) {
        if let token = environment["FENTON_HASS_TOKEN"], !token.isEmpty {
            let server = environment["FENTON_HASS_SERVER"].flatMap(URL.init(string:)).map(HassServer.init(baseURL:)) ?? HassServer.buildDefault()
            return (server, { token })
        }
        let store = KeychainTokenStore(accessGroup: KeychainTokenStore.sharedAccessGroup)
        guard let stored = store.load() else { return (nil, nil) }
        let manager = TokenManager(store: store)
        return (stored.server, { try await manager.validAccessToken() })
    }
}

/// Carries the content into the scheduling task.
private final class ContentBox: @unchecked Sendable {
    let content: UNMutableNotificationContent
    init(_ content: UNMutableNotificationContent) { self.content = content }
}
#endif
