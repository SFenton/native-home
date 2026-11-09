import Foundation

/// A run of tiles in a room's detail page, under an optional heading.
public struct RoomDetailSection: Equatable, Sendable, Identifiable {
    public var title: String?
    public var items: [RoomGroupItem]
    public var id: String { title ?? "items" }
}
