import Foundation

/// Reads which item a Spotlight tap was for.
public enum SpotlightLink {
    /// The `userInfo` key Core Spotlight puts the tapped item's unique identifier under
    /// (`CSSearchableItemActivityIdentifier`); kept as text so this module needs no Core Spotlight import.
    public static let userInfoKey = "kCSSearchableItemActivityIdentifier"

    /// The tapped item's identifier.
    /// - Parameter userInfo: The `NSUserActivity.userInfo` of a `CSSearchableItemActionType` continuation.
    public static func identifier(in userInfo: [AnyHashable: Any]?) -> String? {
        userInfo?[userInfoKey] as? String
    }
}
