import Foundation
import HassCore
import Observation

/// Where the person stands on notification permission.
public enum PushAuthorization: Sendable, Equatable {
    /// Never asked. The app explains first (Home banner, Settings row), then asks on a tap.
    case notDetermined
    /// Allowed (including provisional and ephemeral).
    case granted
    /// Refused; only the system Settings app can change it.
    case denied
}

/// The Time Sensitive Notifications switch in this app's iOS notification settings
/// (`UNNotificationSettings.timeSensitiveSetting`). The app can read it but never change it or ask for it: there is no
/// system alert, only the person's switch in Settings, Notifications, S+H.
public enum TimeSensitiveSetting: Sendable, Equatable {
    /// On: urgent notifications can break through a Focus.
    case enabled
    /// Turned off by the person.
    case disabled
    /// This build or this system has no Time Sensitive notifications (or notifications are not allowed).
    case notSupported
}

/// The system services the coordinator uses; the app supplies UIKit and UserNotifications, tests supply stubs.
public struct PushPlatform: Sendable {
    /// This phone's registration facts.
    public var device: @MainActor @Sendable () -> MobileAppDevice
    /// The stored answer, without asking.
    public var authorization: @Sendable () async -> PushAuthorization
    /// The Time Sensitive switch, without asking.
    public var timeSensitiveSetting: @Sendable () async -> TimeSensitiveSetting
    /// Asks for alert, sound and badge permission (once; later calls return the stored answer).
    public var requestAuthorization: @Sendable () async -> Bool
    /// `UIApplication.registerForRemoteNotifications()`.
    public var registerForRemoteNotifications: @MainActor @Sendable () -> Void
    /// Notifications in Notification Center now.
    public var deliveredNotifications: @Sendable () async -> [DeliveredNotification]
    /// Removes notifications from Notification Center.
    public var removeDelivered: @Sendable ([String]) -> Void
    /// Opens a web address outside the app.
    public var openExternal: @MainActor @Sendable (URL) -> Void

    /// Creates a platform.
    public init(device: @escaping @MainActor @Sendable () -> MobileAppDevice,
                authorization: @escaping @Sendable () async -> PushAuthorization = { .notDetermined },
                timeSensitiveSetting: @escaping @Sendable () async -> TimeSensitiveSetting = { .notSupported },
                requestAuthorization: @escaping @Sendable () async -> Bool,
                registerForRemoteNotifications: @escaping @MainActor @Sendable () -> Void,
                deliveredNotifications: @escaping @Sendable () async -> [DeliveredNotification],
                removeDelivered: @escaping @Sendable ([String]) -> Void,
                openExternal: @escaping @MainActor @Sendable (URL) -> Void) {
        self.device = device
        self.authorization = authorization
        self.timeSensitiveSetting = timeSensitiveSetting
        self.requestAuthorization = requestAuthorization
        self.registerForRemoteNotifications = registerForRemoteNotifications
        self.deliveredNotifications = deliveredNotifications
        self.removeDelivered = removeDelivered
        self.openExternal = openExternal
    }

    /// A platform that does nothing (previews, the debug gallery, and UI journeys that must not prompt).
    public static let inert = PushPlatform(
        device: { MobileAppDevice(marketingVersion: "0", build: "0", name: "Preview", model: "Preview", osVersion: "0",
                             deviceID: "preview", apnsEnvironment: .sandbox) },
        authorization: { .denied },
        timeSensitiveSetting: { .notSupported },
        requestAuthorization: { false },
        registerForRemoteNotifications: {},
        deliveredNotifications: { [] },
        removeDelivered: { _ in },
        openExternal: { _ in }
    )
}
