import Foundation

/// A titled run of room cards in an overview sheet ("Lights On", "Clear", "Rooms").
public struct RoomOverviewSection: Equatable, Sendable, Identifiable {
    public var title: String
    public var groups: [RoomGroup]
    public var id: String { title }

    public init(title: String, groups: [RoomGroup]) {
        self.title = title
        self.groups = groups
    }
}
