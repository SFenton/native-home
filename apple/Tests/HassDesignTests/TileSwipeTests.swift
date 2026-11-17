@testable import HassDesign
import CoreGraphics
import Testing

/// The maths of swiping a tile to adjust a number (`sh.tile-swipe@1`, `.agents/patterns/tile-swipe.md`).
struct TileSwipeTests {
    private let light = TileSwipe.brightness
    private let setpoint = TileSwipe(min: 60, max: 85, step: 0.5, detent: 5)

    // MARK: Mapping

    @Test(arguments: [150.0, 170, 179, 192])
    func theValueFollowsTheFingerAcrossTheTileAtEveryWidth(width: Double) {
        let w = CGFloat(width)
        #expect(light.value(atX: 0, width: w) == 0)
        #expect(light.value(atX: w / 2, width: w) == 50)
        #expect(light.value(atX: w, width: w) == 100)
        #expect(light.value(atX: w * 0.255, width: w) == 26, "it snaps to the step")
    }

    @Test func aFingerPastEitherEdgeClamps() {
        #expect(light.value(atX: -40, width: 150) == 0)
        #expect(light.value(atX: 400, width: 150) == 100)
        #expect(light.value(atX: 10, width: 0) == 0)
    }

    @Test func halfStepsSnapToHalves() {
        #expect(setpoint.value(atX: 75, width: 150) == 72.5)
        #expect(setpoint.snapped(72.74) == 72.5)
        #expect(setpoint.snapped(72.76) == 73)
        #expect(setpoint.snapped(59) == 60)
        #expect(setpoint.snapped(99) == 85)
    }

    @Test func rightToLeftMirrorsTheMapSoTheMinimumStaysLeading() {
        #expect(light.value(atX: 0, width: 150, isRightToLeft: true) == 100)
        #expect(light.value(atX: 150, width: 150, isRightToLeft: true) == 0)
        #expect(light.value(atX: 37.5, width: 150, isRightToLeft: true) == 75)
        #expect(light.edge(of: 25, width: 200) == 50)
        #expect(light.edge(of: 25, width: 200, isRightToLeft: true) == 150)
    }

    @Test func fractionIsWhereTheValueSitsInTheRange() {
        #expect(setpoint.fraction(of: 60) == 0)
        #expect(setpoint.fraction(of: 72.5) == 0.5)
        #expect(setpoint.fraction(of: 90) == 1)
    }

    // MARK: Detents

    @Test func aDetentLineCrossedInEitherDirectionTicksOnce() {
        #expect(light.crossesDetent(from: 8, to: 12))
        #expect(light.crossesDetent(from: 12, to: 8))
        #expect(!light.crossesDetent(from: 11, to: 19))
        #expect(light.crossesDetent(from: 0, to: 100), "a fast flick is one tick, not ten: the sample decides, not the distance")
    }

    @Test func theTwoEndsAreLines() {
        #expect(light.crossesDetent(from: 95, to: 100))
        #expect(light.crossesDetent(from: 12, to: 0))
        #expect(!light.crossesDetent(from: 3, to: 0), "0 and 3 are both past line 0 and before line 10")
        #expect(light.lines.first == 0 && light.lines.last == 100)
        #expect(light.lines.count == 11)
        let uneven = TileSwipe(min: 0, max: 25, step: 1, detent: 10)
        #expect(uneven.lines == [0, 10, 20, 25], "the maximum is a line though it is not a multiple of the detent")
        #expect(uneven.crossesDetent(from: 22, to: 25))
    }

    @Test func theFirstSampleNeverTicks() {
        #expect(!light.crossesDetent(from: nil, to: 50))
        #expect(!light.crossesDetent(from: 50, to: 50))
    }

    @Test func adjustingMovesOneDetentAndStopsAtTheEnds() {
        #expect(light.adjusted(45, up: true) == 55)
        #expect(light.adjusted(45, up: false) == 35)
        #expect(light.adjusted(95, up: true) == 100)
        #expect(light.adjusted(100, up: true) == 100)
        #expect(light.adjusted(4, up: false) == 0)
        #expect(setpoint.adjusted(72, up: true) == 77)
        #expect(setpoint.adjusted(84, up: true) == 85)
    }

    // MARK: Release

    @Test func aReleaseAtTheShownValueSendsNothing() {
        #expect(light.commit(40, shown: 40) == nil)
        #expect(light.commit(41, shown: 40) == 41)
        #expect(setpoint.commit(72.5, shown: 72.5) == nil)
    }

    // MARK: Words

    @Test func theBubbleSaysOffAtZeroOnALightAndTheFormatElsewhere() {
        #expect(light.bubbleText(0, format: "{value}%", zeroWord: "Off") == "Off")
        #expect(light.bubbleText(45, format: "{value}%", zeroWord: "Off") == "45%")
        #expect(light.bubbleText(0, format: "{value}%") == "0%")
        #expect(setpoint.bubbleText(72.5, format: "{value}°") == "72.5°")
        #expect(setpoint.bubbleText(72, format: "{value}°") == "72.0°")
        #expect(light.bubbleText(7, format: nil) == "7")
    }

    // MARK: The bubble

    @Test func theBubbleCentreFollowsTheBandAndStaysWholeInTheTile() {
        let m = TileSwipeBubble.regular
        let width = TileSwipeBubble.width(textWidth: 20, tileWidth: 150, metrics: m)
        #expect(width == 60)
        #expect(TileSwipeBubble.centerX(edge: 0, tileWidth: 150, bubbleWidth: width) == 30, "flush with the leading edge at the minimum")
        #expect(TileSwipeBubble.centerX(edge: 75, tileWidth: 150, bubbleWidth: width) == 75)
        #expect(TileSwipeBubble.centerX(edge: 150, tileWidth: 150, bubbleWidth: width) == 120, "flush with the trailing edge at the maximum")
        #expect(TileSwipeBubble.centerX(edge: 20, tileWidth: 50, bubbleWidth: 60) == 25, "a tile narrower than the bubble centres it")
    }

    @Test func theBubbleGrowsWithItsTextUpToTheTilesWidth() {
        let m = TileSwipeBubble.regular
        #expect(TileSwipeBubble.width(textWidth: 20, tileWidth: 150, metrics: m) == 60)
        #expect(TileSwipeBubble.width(textWidth: 70, tileWidth: 150, metrics: m) == 94)
        #expect(TileSwipeBubble.width(textWidth: 300, tileWidth: 150, metrics: m) == 150)
    }

    @Test func accessibilitySizesGetALargerBubbleThatKeepsItsGap() {
        let regular = TileSwipeBubble.metrics(isAccessibilitySize: false)
        let large = TileSwipeBubble.metrics(isAccessibilitySize: true)
        #expect((regular.height, regular.minimumWidth, regular.lift) == (32, 60, 24))
        #expect((large.height, large.minimumWidth, large.lift) == (44, 84, 30))
        #expect(regular.lift - regular.height / 2 == 8)
        #expect(large.lift - large.height / 2 == 8, "the capsule stays 8 pt clear of the tile")
    }

    @Test func nearTheTopOfTheScrollerTheBubbleComesDownOnlyAsFarAsItMust() {
        let m = TileSwipeBubble.regular
        #expect(TileSwipeBubble.topShift(tileTop: 200, metrics: m) == 0)
        #expect(TileSwipeBubble.topShift(tileTop: 44, metrics: m) == 0, "44 pt above the tile is the least that fits")
        #expect(TileSwipeBubble.topShift(tileTop: 30, metrics: m) == 14)
        #expect(TileSwipeBubble.topShift(tileTop: 0, metrics: m) == 44)
    }
}

// MARK: - Where a drag starts (C1)

/// Whether a drag that is about to begin is the tile's swipe or the page's scroll.
struct TileSwipeStartTests {
    /// A stroke at `degrees` above horizontal: its first-sample travel over `distance` points and a velocity of 120 points per second along it.
    private func stroke(_ degrees: Double, distance: CGFloat = 12) -> (CGPoint, CGPoint) {
        let radians = degrees * .pi / 180
        return (CGPoint(x: distance * cos(radians), y: -distance * sin(radians)), CGPoint(x: 120 * cos(radians), y: -120 * sin(radians)))
    }

    @Test(arguments: [0.0, 10, 30, 44])
    func aStrokeWiderThanItIsTallBegins(degrees: Double) {
        let (travel, speed) = stroke(degrees)
        #expect(TileSwipeStart.isHorizontal(translation: travel, velocity: speed))
    }

    @Test(arguments: [46.0, 50, 60, 75, 90])
    func aStrokeTallerThanItIsWideIsTheScrolls(degrees: Double) {
        let (travel, speed) = stroke(degrees)
        #expect(!TileSwipeStart.isHorizontal(translation: travel, velocity: speed))
    }

    @Test func aSidewaysFirstSampleCannotStartAStrokeThatWentUpThePage() {
        let (travel, _) = stroke(60)
        #expect(!TileSwipeStart.isHorizontal(translation: travel, velocity: CGPoint(x: 40, y: -10)), "the velocity alone said horizontal")
    }

    @Test func aTouchThatHasNotTravelledIsJudgedByItsVelocity() {
        #expect(TileSwipeStart.isHorizontal(translation: .zero, velocity: CGPoint(x: 90, y: 10)))
        #expect(!TileSwipeStart.isHorizontal(translation: .zero, velocity: CGPoint(x: 10, y: 90)))
        #expect(!TileSwipeStart.isHorizontal(translation: CGPoint(x: 0.4, y: -0.4), velocity: .zero), "no velocity at all never begins")
    }

    @Test func aSidewaysStrokeWithAVerticalFirstSampleIsAlsoRefused() {
        #expect(!TileSwipeStart.isHorizontal(translation: CGPoint(x: 14, y: 4), velocity: CGPoint(x: 20, y: 90)))
    }

    @Test func leftwardAndDownwardStrokesAreJudgedByTheirShapeNotTheirSign() {
        #expect(TileSwipeStart.isHorizontal(translation: CGPoint(x: -14, y: 5), velocity: CGPoint(x: -100, y: 30)))
        #expect(!TileSwipeStart.isHorizontal(translation: CGPoint(x: 6, y: 12), velocity: CGPoint(x: 30, y: 100)))
    }
}

