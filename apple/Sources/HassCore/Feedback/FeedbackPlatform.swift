import Foundation

/// The device family a report came from; it becomes the issue's platform label.
public enum FeedbackPlatform: String, Sendable, Codable, CaseIterable {
    case ios
    case ipados
    case iphoneDuo = "iphone-duo"

    /// Resolves the submitting device.
    ///
    /// - Parameters:
    ///   - isPad: True when the app runs with the iPad idiom.
    ///   - hasHinge: True once the device has reported a hinge (iPhone Duo, ``HingePresence``).
    /// - Returns: `iphone-duo`, `ipados` or `ios`, in that precedence.
    public static func resolve(isPad: Bool, hasHinge: Bool) -> FeedbackPlatform {
        if hasHinge { return .iphoneDuo }
        if isPad { return .ipados }
        return .ios
    }

    /// The GitHub label in the request repository.
    public var label: String {
        switch self {
        case .ios: "iOS"
        case .ipados: "iPadOS"
        case .iphoneDuo: "iPhone Duo"
        }
    }
}
