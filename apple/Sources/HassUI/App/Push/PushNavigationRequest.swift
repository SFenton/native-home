import Foundation
import HassCore
import Observation

/// A page to open, stamped so the same route twice in a row still opens.
public struct PushNavigationRequest: Equatable, Sendable {
    /// Increases with each request.
    public var id: Int
    /// The route to open, resolved against the accepted publication when the shell opens it.
    public var route: RouteRequest
    /// The link the request was read from, kept while it can still change meaning: a link that arrives before the
    /// publication authors its `linkPrefixes` is read again once they are known (``PushCoordinator/updateLinkPrefixes(_:)``).
    /// Nil for a Spotlight result or a shortcut, which already carry a route.
    public var link: String?

    public init(id: Int, route: RouteRequest, link: String? = nil) {
        self.id = id
        self.route = route
        self.link = link
    }
}
