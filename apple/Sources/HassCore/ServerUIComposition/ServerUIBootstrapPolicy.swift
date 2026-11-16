import Foundation

// MARK: - Trusted post-authentication bootstrap

/// Optional publisher-owned copy and ordering, used only after account-scoped publication acceptance.
/// Authentication fields, credentials, permission decisions and system-alert actions remain native.
public struct ServerUIBootstrapPolicy: Equatable, Sendable {
    public let arrivalAnnouncement: String
    public let recovery: Recovery
    public let setup: [PermissionExplanation]

    /// The authored recovery.
    public struct Recovery: Equatable, Sendable {
        public let loadingTitle: String
        public let unavailableTitle: String
        public let unavailableMessage: String
        public let retryLabel: String
    }

    /// The authored permission choices.
    public enum Permission: String, CaseIterable, Sendable {
        case notifications
        case timeSensitive = "time-sensitive"
        case location
    }

    /// The authored permission explanation.
    public struct PermissionExplanation: Equatable, Sendable {
        public let permission: Permission
        public let explanation: String?
    }
}
