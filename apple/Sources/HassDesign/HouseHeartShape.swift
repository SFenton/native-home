import SwiftUI

/// The app icon's house and heart as one `Shape`, with no tile behind it (`.agents/platforms/apple/live-activities-per-job.md`
/// §8, "Corner mark"). It is the same geometry as ``AppIconArtwork``, filled with one colour.
///
/// The heart sits in a ring cut out of the house, so the ring shows whatever is behind the shape: a card's background,
/// plain or tinted. That is the "heart knock-out" the icon draws as the glass itself; here it is real transparency,
/// which stays right on a gradient where a painted ring would not.
///
/// A `Shape` rather than a `Canvas`, because widgets and Live Activities draw shapes reliably.
public struct HouseHeartShape: Shape {
    /// Creates the shape.
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let unit = side / 100
        let place = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2).scaledBy(x: unit, y: unit)
        let heartPlace = CGAffineTransform(translationX: 55, y: 60).scaledBy(x: 0.40, y: 0.40).concatenating(place)
        let heart = AppIconArtwork.heart.applying(heartPlace)
        // The ring is the heart grown by 16 icon units (scaled 0.40 with the heart), joined with the heart itself.
        let ring = heart.strokedPath(StrokeStyle(lineWidth: 16 * 0.40 * unit, lineJoin: .round)).union(heart)
        var path = AppIconArtwork.house.applying(place).subtracting(ring, eoFill: true)
        path.addPath(heart)
        return path
    }
}
