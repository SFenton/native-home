import Foundation

/// Formats an APNs device token.
public enum PushToken {
    /// The token as lowercase hex, the form the relay expects.
    public static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}
