import Foundation

/// One authored route that Spotlight can open.
public struct SpotlightEntry: Equatable, Sendable, Identifiable {
    /// Stable identifier handed back to the app when the result is tapped (`route.<route id>`).
    public var id: String
    /// The route's own id, without the prefix.
    public var routeID: String
    /// The result's title.
    public var title: String
    /// The second line of the result.
    public var summary: String
    /// Words that find this page, besides its title.
    public var keywords: [String]
    /// The SF Symbol the route is authored with, which the indexer draws as the result's thumbnail.
    public var symbol: String
    /// Where tapping the result goes.
    public var request: RouteRequest

    public init(id: String, routeID: String, title: String, summary: String, keywords: [String], symbol: String,
                request: RouteRequest) {
        self.id = id
        self.routeID = routeID
        self.title = title
        self.summary = summary
        self.keywords = keywords
        self.symbol = symbol
        self.request = request
    }
}
