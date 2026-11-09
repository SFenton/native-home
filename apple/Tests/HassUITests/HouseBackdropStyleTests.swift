import CoreGraphics
import Foundation
import SwiftUI
@testable import HassUI
import Testing

/// The wallpaper's layers: the base colour, the black scrim from top to bottom, and the photo shifted with its page.
struct HouseBackdropStyleTests {
    @Test func aPageSlidingOutDoesNotPullThePhotoOffTheEdgeThatStillShows() {
        #expect(HouseBackdropStyle.shift(origin: CGPoint(x: -120, y: 30)) == CGPoint(x: 0, y: 30))
        #expect(HouseBackdropStyle.shift(origin: CGPoint(x: 40, y: -8)) == CGPoint(x: 40, y: 0))
        #expect(HouseBackdropStyle.shift(origin: CGPoint(x: 12, y: 7)) == CGPoint(x: 12, y: 7))
    }

    @Test func theScrimGetsDenserTowardsTheTabBarAndNeverDropsBelowWhatTheWhiteTitlesNeed() {
        let values = HouseBackdropStyle.scrimOpacities.map(\.value)
        #expect(values == values.sorted(), "denser downwards")
        #expect(values.min() ?? 0 >= 0.44, "the title and the first section headers stay readable")
        #expect(HouseBackdropStyle.scrimOpacities.map(\.location) == [0, 0.28, 0.50, 0.75, 1])
        #expect(HouseBackdropStyle.scrimStops.count == values.count)
        #expect(HouseBackdropStyle.scrimStops(increasedContrast: false).map(\.location) == HouseBackdropStyle.scrimStops.map(\.location))
    }

    @Test func increaseContrastMakesEveryStopDenserByTheSameBoost() {
        let normal = HouseBackdropStyle.scrimOpacities.map(\.value)
        let boosted = HouseBackdropStyle.scrimStops(increasedContrast: true)
        #expect(boosted.count == normal.count)
        for (stop, base) in zip(boosted, normal) {
            let resolved = stop.color.resolve(in: EnvironmentValues())
            #expect(abs(Double(resolved.opacity) - (base + HouseBackdropStyle.increasedContrastBoost)) < 0.01)
        }
        _ = HouseBackdropStyle.scrim
        _ = HouseBackdropStyle.scrimView(increasedContrast: true)
    }

    #if DEBUG
    @Test func theFixturePhotoIsBrightAndWideEnoughToShowABlur() throws {
        let photo = try #require(HouseBackdropStore.fixturePhoto())
        #expect(photo.width == 960 && photo.height == 640)
    }
    #endif
}
