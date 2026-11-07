import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// The notification category for one set of buttons (contract v1, rule 3).
///
/// Automations choose buttons per notification, so there is no fixed category list. The service extension builds
/// a category from the payload's actions, registers it next to the existing ones, and points the notification at
/// it. The identifier is a stable hash of the buttons, so the same buttons reuse one category.
public struct PushCategory: Equatable, Sendable {
    /// Prefix of every built category.
    public static let prefix = "fenton.dynamic."
    /// How many built categories are kept; older ones are dropped when a new one is registered.
    public static let limit = 32

    /// How many buttons the system presents (HIG Notifications); extra ones are dropped, in order.
    public static let maxActions = 4

    /// What a locked screen shows instead of the body when the person hides previews.
    public static let hiddenPreviewsPlaceholder = "Notification"

    /// The category id.
    public let identifier: String
    /// The buttons, in order.
    public let actions: [PushAction]

    /// The fixed category of camera notifications: the notification content extension shows them with a live view
    /// when expanded, and sets their buttons itself (an extension serves only categories it lists in advance).
    public static let camera = "fenton.camera"

    /// The category for a payload's buttons; nil when it has none.
    public init?(actions: [PushAction]) {
        guard !actions.isEmpty else { return nil }
        self.actions = Array(actions.prefix(Self.maxActions))
        identifier = Self.prefix + Self.digest(actions)
    }

    /// The camera category with this notification's buttons (registered again for each camera notification, so
    /// the buttons also show where the content extension doesn't run).
    public init(cameraActions actions: [PushAction]) {
        self.actions = Array(actions.prefix(Self.maxActions))
        identifier = Self.camera
    }

    /// Category ids to register: every existing one, this one, and at most ``limit`` built ones (the oldest built
    /// ids go first; `existing` is in registration order).
    /// - Parameter existing: Ids registered now.
    public func identifiers(merging existing: [String]) -> [String] {
        let fixed = existing.filter { !$0.hasPrefix(Self.prefix) && $0 != identifier }
        let built = existing.filter { $0.hasPrefix(Self.prefix) && $0 != identifier }
        return fixed + built.suffix(Self.limit - 1) + [identifier]
    }

    /// A 64-bit FNV-1a hash of everything that changes how the buttons look or act.
    static func digest(_ actions: [PushAction]) -> String {
        let text = actions.map { action in
            [action.action, action.title, action.uri ?? "", action.symbol ?? "",
             action.authenticationRequired ? "a" : "", action.destructive ? "d" : "",
             action.activationMode.rawValue, action.isTextInput ? "t" : "",
             action.textInputButtonTitle ?? "", action.textInputPlaceholder ?? ""].joined(separator: "\u{1F}")
        }.joined(separator: "\u{1E}")
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}

#if canImport(UserNotifications)
extension PushAction {
    /// The system action options.
    var options: UNNotificationActionOptions {
        var options: UNNotificationActionOptions = []
        if authenticationRequired { options.insert(.authenticationRequired) }
        if destructive { options.insert(.destructive) }
        if activationMode == .foreground { options.insert(.foreground) }
        return options
    }

    /// The system action.
    public var notificationAction: UNNotificationAction {
        let icon = symbol.map(UNNotificationActionIcon.init(systemImageName:))
        guard isTextInput else {
            return UNNotificationAction(identifier: action, title: title, options: options, icon: icon)
        }
        return UNTextInputNotificationAction(identifier: action, title: title, options: options, icon: icon,
                                             textInputButtonTitle: textInputButtonTitle ?? "Send",
                                             textInputPlaceholder: textInputPlaceholder ?? "")
    }
}

extension PushCategory {
    /// The system category.
    public var notificationCategory: UNNotificationCategory {
        #if os(watchOS)
        // `hiddenPreviewsBodyPlaceholder` is unavailable on watchOS.
        UNNotificationCategory(identifier: identifier, actions: actions.map(\.notificationAction), intentIdentifiers: [],
                               options: [.customDismissAction])
        #else
        UNNotificationCategory(identifier: identifier, actions: actions.map(\.notificationAction), intentIdentifiers: [],
                               hiddenPreviewsBodyPlaceholder: Self.hiddenPreviewsPlaceholder,
                               options: [.customDismissAction])
        #endif
    }

    /// The categories to register: the existing set with this one added and old built ones trimmed.
    /// - Parameter existing: `getNotificationCategories()`.
    public func merged(into existing: Set<UNNotificationCategory>) -> Set<UNNotificationCategory> {
        let byID = Dictionary(existing.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let keep = identifiers(merging: byID.keys.sorted())
        return Set(keep.compactMap { $0 == identifier ? notificationCategory : byID[$0] })
    }
}
#endif
