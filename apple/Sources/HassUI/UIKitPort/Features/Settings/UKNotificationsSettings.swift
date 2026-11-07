#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// Settings → Notifications (`NotificationsSettingsSection`): the same ask as the Home banner and a way to Settings once it was
/// refused. Once notifications are allowed it shows two rows, Notifications and Time Sensitive Notifications, each with its real
/// status; both open this app's notification page in iOS Settings, because the app can change neither value.
///
/// The rows carry a chevron although they leave the app (owner exception, 2026-10-27, to the "chevron means push" rule), and say
/// "Opens Settings" in their hint. The Time Sensitive row is hidden where the system has none (`TimeSensitiveSetting.notSupported`).
@MainActor
enum UKNotificationsSettings {
    /// The section for the push coordinator's current answers.
    /// - Parameters:
    ///   - push: The notification coordinator.
    ///   - openURL: Opens a URL in iOS Settings; a gallery records it instead of leaving the app.
    static func section(push: PushCoordinator, openURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) }) -> UKSettingsListSection {
        section(authorization: push.authorization, timeSensitive: push.timeSensitive,
                turnOn: { Task { await push.enableNotifications() } }, openURL: openURL)
    }

    /// The section for given answers.
    static func section(authorization: PushAuthorization, timeSensitive: TimeSensitiveSetting, turnOn: @escaping () -> Void,
                        openURL: @escaping (URL) -> Void) -> UKSettingsListSection {
        var rows: [UKSettingsListRow] = []
        switch authorization {
        case .notDetermined:
            rows = [UKSettingsRows.button(id: "notifications.turnOn", identifier: "settings.notifications.turnOn",
                                          title: NotificationPermissionCopy.turnOn, action: turnOn)]
        case .granted:
            rows.append(UKSettingsRows.link(
                id: "notifications", identifier: "settings.notifications", title: "Notifications",
                subtitle: TimeSensitiveCopy.notificationsRowStatus, symbol: "bell.fill", showsChevron: true, hint: "Opens Settings",
                traits: [.button, .link]) { if let url = SystemSettingsLink.notifications { openURL(url) } })
            if timeSensitive != .notSupported {
                let isOn = timeSensitive == .enabled
                rows.append(UKSettingsRows.link(
                    id: "notifications.timeSensitive", identifier: "settings.notifications.timeSensitive", title: TimeSensitiveCopy.statusLabel,
                    subtitle: TimeSensitiveCopy.rowStatus(isOn: isOn), symbol: isOn ? "bell.fill" : "bell.slash", showsChevron: true,
                    hint: "Opens Settings", traits: [.button, .link]) { if let url = SystemSettingsLink.notifications { openURL(url) } })
            }
        case .denied:
            rows = [UKSettingsRows.button(id: "notifications.openSettings", identifier: "settings.notifications.openSettings",
                                          title: "Open Settings to allow notifications") { if let url = SystemSettingsLink.app { openURL(url) } }]
        }
        // The granted state explains itself in its rows; the other two keep the reason to turn them on.
        return UKSettingsListSection(id: "notifications", header: .title("Notifications"),
                                     footer: authorization == .granted ? nil : NotificationPermissionCopy.message, rows: rows)
    }
}
#endif
