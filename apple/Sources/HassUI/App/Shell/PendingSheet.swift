/// A sheet a link asked a room page to open.
struct PendingSheet: Equatable, Sendable {
    var page: String
    var anchor: String
}
