import Foundation
import HassCore
import Observation

/// A page to open, stamped so the same destination twice in a row still opens.
public struct PushNavigationRequest: Equatable, Sendable {
    /// Increases with each request.
    public var id: Int
    /// The page.
    public var destination: PushDestination
    /// The link's `#anchor`: the sheet to open on the page (a room card's `sheet`), or nil.
    public var anchor: String?

    public init(id: Int, destination: PushDestination, anchor: String? = nil) {
        self.id = id
        self.destination = destination
        self.anchor = anchor
    }
}
