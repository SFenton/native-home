import Foundation

/// One page of the app that Spotlight can open: a root section or a room.
public struct SpotlightEntry: Equatable, Sendable, Identifiable {
    /// Stable identifier handed back to the app when the result is tapped (`section.climate`, `room.living-room`).
    public var id: String
    /// The result's title.
    public var title: String
    /// The second line of the result.
    public var summary: String
    /// Words that find this page, besides its title.
    public var keywords: [String]
    /// The web icon the page uses, which the indexer draws as the result's thumbnail.
    public var mdiIcon: String
    /// Where tapping the result goes.
    public var destination: PushDestination
}
