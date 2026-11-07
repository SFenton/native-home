@testable import HassDesign
import SwiftUI
import Testing

struct BrightnessTileTests {
    @Test func dragPositionMapsAcrossTheTile() {
        #expect(BrightnessTile.percent(atX: 0, width: 200) == 0)
        #expect(BrightnessTile.percent(atX: 50, width: 200) == 25)
        #expect(BrightnessTile.percent(atX: 260, width: 200) == 100)
        #expect(BrightnessTile.percent(atX: -10, width: 200) == 0)
        #expect(BrightnessTile.percent(atX: 10, width: 0) == 0)
    }

    @Test func adjustStepsClamp() {
        #expect(BrightnessTile.stepped(45, by: BrightnessTile.step) == 55)
        #expect(BrightnessTile.stepped(95, by: 10) == 100)
        #expect(BrightnessTile.stepped(5, by: -10) == 0)
    }

    @Test func brightnessTileHints() {
        #expect(BrightnessTile.hint(percent: 0, isUnavailable: false, opensDetails: false) == "Double-tap to turn on. Swipe up or down to adjust brightness.")
        #expect(BrightnessTile.hint(percent: 40, isUnavailable: false, opensDetails: true) == "Double-tap for details. Swipe up or down to adjust brightness.")
        #expect(BrightnessTile.hint(percent: 40, isUnavailable: true, opensDetails: true).isEmpty)
    }

    @Test func statusReadsOffPercentOrUnavailable() {
        #expect(BrightnessTile.status(percent: 0, isUnavailable: false) == "Off")
        #expect(BrightnessTile.status(percent: 45, isUnavailable: false) == "45%")
        #expect(BrightnessTile.status(percent: 45, isUnavailable: true) == "Unavailable")
    }
}

struct BrightnessPowerDiscTests {
    @Test func theDiscIsTheToggleStyledPowerGlyphThatSaysWhatItWillDo() {
        let on = BrightnessTile.powerItem(percent: 60, isUnavailable: false)
        #expect(on.id == "power" && on.symbol == "power" && on.verb == "Turn Off" && on.isOn == true && on.phase == .ready && on.feedback == .optimistic)
        let off = BrightnessTile.powerItem(percent: 0, isUnavailable: false)
        #expect(off.verb == "Turn On" && off.isOn == false)
        #expect(BrightnessTile.powerItem(percent: 0, isUnavailable: true).phase == .unavailable)
        #expect(BrightnessTile.powerId == "power")
    }

    @Test func theStateCandidatesCoverEveryStatusLine() {
        for line in [BrightnessTile.status(percent: 0, isUnavailable: false), BrightnessTile.status(percent: 100, isUnavailable: false),
                     BrightnessTile.status(percent: 5, isUnavailable: true)] {
            #expect(BrightnessTile.stateCandidates.contains(line), "\(line)")
        }
    }
}

struct BrightnessInteractionTests {
    @Test func cancelledDragCommitsNothing() {
        var state = BrightnessInteraction()
        state.dragChanged(translation: CGSize(width: 20, height: 2), x: 60, width: 200)
        #expect(state.shown(live: 80) == 30)
        state.dragCancelled()
        #expect(state.shown(live: 80) == 80)
        #expect(state.dragEnded(x: 60, width: 200, live: 80) == nil)
    }

    @Test func tapTurnsOnShowingFullThenOff() {
        var state = BrightnessInteraction()
        #expect(state.flip(live: 0, isUnavailable: false) == .power(true))
        #expect(state.shown(live: 0) == 100)
        #expect(state.flip(live: 40, isUnavailable: false) == .power(false))
        #expect(state.shown(live: 40) == 0)
        state.pendingPercent = nil
        #expect(state.shown(live: 40) == 40)
    }

    @Test func unavailableIgnoresTapAndAdjust() {
        var state = BrightnessInteraction()
        #expect(state.flip(live: 0, isUnavailable: true) == nil)
        #expect(state.adjust(by: 10, live: 0, isUnavailable: true) == nil)
        #expect(state == BrightnessInteraction())
    }

    @Test func adjustStepsFromTheShownValueAndSkipsNoOps() {
        var state = BrightnessInteraction()
        #expect(state.adjust(by: 10, live: 45, isUnavailable: false) == .brightness(55))
        #expect(state.adjust(by: 10, live: 45, isUnavailable: false) == .brightness(65))
        #expect(state.adjust(by: 10, live: 100, isUnavailable: false) == .brightness(75))
        var full = BrightnessInteraction()
        #expect(full.adjust(by: 10, live: 100, isUnavailable: false) == nil)
        #expect(full.adjust(by: -10, live: 5, isUnavailable: false) == .brightness(0))
    }

    @Test func horizontalDragFollowsTheFingerAndCommitsOnRelease() {
        var state = BrightnessInteraction()
        state.dragChanged(translation: CGSize(width: 20, height: 3), x: 60, width: 200)
        #expect(state.dragAxis == .horizontal)
        #expect(state.shown(live: 0) == 30)
        state.dragChanged(translation: CGSize(width: 2, height: 40), x: 140, width: 200)
        #expect(state.shown(live: 0) == 70)
        #expect(state.dragEnded(x: 140, width: 200, live: 0) == .brightness(70))
        #expect(state.dragAxis == nil && state.dragPercent == nil)
        #expect(state.shown(live: 0) == 70)
    }

    @Test func verticalDragIsLeftToTheScrollView() {
        var state = BrightnessInteraction()
        state.dragChanged(translation: CGSize(width: 2, height: 30), x: 150, width: 200)
        #expect(state.dragAxis == .vertical && state.dragPercent == nil)
        #expect(state.dragEnded(x: 150, width: 200, live: 20) == nil)
        #expect(state.dragAxis == nil)
    }

    @Test func dragEndingAtTheLiveLevelSendsNothing() {
        var state = BrightnessInteraction()
        state.dragChanged(translation: CGSize(width: 10, height: 0), x: 100, width: 200)
        #expect(state.dragEnded(x: 100, width: 200, live: 50) == nil)
        #expect(state.pendingPercent == nil)
    }
}

struct BrightnessDraggerTests {
    @Test func hapticTicksOncePerTenPercent() {
        #expect(BrightnessTile.hapticStep(nil) == nil)
        #expect(BrightnessTile.hapticStep(0) == 0)
        #expect(BrightnessTile.hapticStep(9.9) == 0)
        #expect(BrightnessTile.hapticStep(10) == 1)
        #expect(BrightnessTile.hapticStep(100) == 10)
    }

    @Test func bubbleFollowsTheBandInsideTheTile() {
        #expect(BrightnessTile.bubbleCenter(percent: 50, width: 200) == 100)
        // Kept inside the tile at either end.
        #expect(BrightnessTile.bubbleCenter(percent: 0, width: 200) == BrightnessBubble.width / 2)
        #expect(BrightnessTile.bubbleCenter(percent: 100, width: 200) == 200 - BrightnessBubble.width / 2)
        // A tile narrower than the bubble centres it.
        #expect(BrightnessTile.bubbleCenter(percent: 80, width: 40) == 20)
    }
}
