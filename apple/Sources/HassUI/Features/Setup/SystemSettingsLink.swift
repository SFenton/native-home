import Foundation
#if os(iOS)
import UIKit
#endif

/// Where the app sends people in iOS Settings (`.agents/platforms/apple/push.md`).
enum SystemSettingsLink {
    /// The app's notification page in Settings (`UIApplication.openNotificationSettingsURLString`, iOS 16 and later),
    /// where Allow Notifications and Time Sensitive Notifications live; the app's Settings page when that is missing.
    /// Nil off iOS (the host test runner).
    static var notifications: URL? {
        #if os(iOS)
        URL(string: UIApplication.openNotificationSettingsURLString) ?? app
        #else
        nil
        #endif
    }

    /// The app's page in Settings (`UIApplication.openSettingsURLString`).
    static var app: URL? {
        #if os(iOS)
        URL(string: UIApplication.openSettingsURLString)
        #else
        nil
        #endif
    }
}
