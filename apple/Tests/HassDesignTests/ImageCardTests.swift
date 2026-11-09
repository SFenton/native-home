@testable import HassDesign
import Testing

/// ``ImageCard``: the title and scrim rules the UIKit card follows.
struct ImageCardTests {
    @Test func titleLinesTruncateOrWrap() {
        #expect(ImageCard.titleLines(accessibilitySize: false) == 1...3)
        #expect(ImageCard.titleLines(accessibilitySize: true) == 1...100)
        #expect(ImageCard.titleLineLimit(accessibilitySize: false) == 3)
        #expect(ImageCard.titleLineLimit(accessibilitySize: true) == 0)
    }

    @Test func theScrimDarkensTowardTheFootAndTheThumbnailIsFixed() {
        let stops = ImageCard.scrimStops
        #expect(stops.first?.opacity == 0)
        #expect(stops.map(\.opacity) == stops.map(\.opacity).sorted())
        #expect(stops.map(\.location) == stops.map(\.location).sorted())
        #expect(stops.last?.location == 1)
        #expect(ImageCard.thumbnailSide == 72)
        #expect(abs(ImageCard.aspectRatio - 1 / 0.78) < 0.0001)
    }
}
