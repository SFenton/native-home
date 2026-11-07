import Foundation
@testable import HassDesign
import SwiftUI
import Testing

/// The rules for a tile whose action set changes shape (owner, 2026-10-26: height `standard`, discs `quick`, full-row tiles only,
/// deferred while scrolling, never on a reapply, Reduce Motion cross-fades) and the volume slider's math. Pure: no view is built.
struct TileActionSetTransitionTests {
    private let off = TileActionShape(ids: ["power"])
    private let playing = TileActionShape(ids: ["previous", "play_pause", "next"], hasAccessory: true)

    private func decide(
        _ old: TileActionShape? = nil, _ new: TileActionShape? = nil,
        fullRow: Bool = true, scrolling: Bool = false, reapply: Bool = false, reduceMotion: Bool = false
    ) -> TileActionSetTransition {
        TileActionSetTransition.decide(old: old ?? off, new: new ?? playing, isFullRow: fullRow, isScrolling: scrolling,
                                       isReapply: reapply, reduceMotion: reduceMotion)
    }

    // MARK: Decision matrix

    @Test func aFullRowTileAnimatesAChangeOfShape() {
        #expect(decide() == .animate)
        #expect(decide(playing, off) == .animate, "and back")
    }

    @Test func anUnchangedShapeNeverMoves() {
        for fullRow in [false, true] {
            for scrolling in [false, true] {
                for reapply in [false, true] {
                    for reduce in [false, true] {
                        #expect(decide(off, off, fullRow: fullRow, scrolling: scrolling, reapply: reapply, reduceMotion: reduce) == .none)
                    }
                }
            }
        }
    }

    @Test func aTileThatDoesNotSpanItsRowAppliesInstantly() {
        #expect(decide(fullRow: false) == .none)
        #expect(decide(fullRow: false, scrolling: true) == .none, "nothing to defer: nothing animates")
        #expect(decide(fullRow: false, reduceMotion: true) == .none)
    }

    @Test func aChangeWhileScrollingWaits() {
        #expect(decide(scrolling: true) == .deferred)
        #expect(decide(scrolling: true, reduceMotion: true) == .deferred, "Reduce Motion waits too")
    }

    @Test func aReapplyNeverAnimatesWhateverElseIsTrue() {
        #expect(decide(reapply: true) == .none)
        #expect(decide(scrolling: true, reapply: true) == .none, "a reconnect during a scroll is not held back to animate later")
        #expect(decide(reapply: true, reduceMotion: true) == .none)
    }

    @Test func reduceMotionCrossFadesInsteadOfAnimatingHeight() {
        #expect(decide(reduceMotion: true) == .crossFade)
    }

    @Test func theShapeIgnoresEverythingButIdsAndTheAccessory() {
        let a = [TileActionItem(id: "play_pause", verb: "Pause", symbol: "pause.fill", feedback: .optimistic, isEmphasized: true)]
        let b = [TileActionItem(id: "play_pause", verb: "Play", symbol: "play.fill", phase: .unavailable, feedback: .optimistic)]
        #expect(TileActionShape(a) == TileActionShape(b), "a symbol, verb or phase change is a value change")
        #expect(TileActionShape(a) != TileActionShape(a, hasAccessory: true), "the volume slider appearing is a change of shape")
    }

    // MARK: Reapply window

    @Test func aChangeSoonAfterAReapplyIsPartOfIt() {
        #expect(!TileActionSetTransition.isReapply(elapsedSinceReapply: nil))
        #expect(TileActionSetTransition.isReapply(elapsedSinceReapply: .milliseconds(10)))
        #expect(TileActionSetTransition.isReapply(elapsedSinceReapply: .seconds(1.9)))
        #expect(!TileActionSetTransition.isReapply(elapsedSinceReapply: TileActionSetTransition.reapplyWindow))
    }

    // MARK: Tokens

    @Test func theMotionUsesOnlyTheStandardAndQuickTokens() {
        #expect(MotionTokens.standardDuration == 0.3 && MotionTokens.quickDuration == 0.2)
    }
}

/// The volume slider: step math, the spoken value, and an interaction that sends nothing until a drag ends.
struct TileVolumeSliderTests {
    @Test func voiceOverStepsFivePercentAndClamps() {
        #expect(TileVolumeSlider.step == 5)
        #expect(TileVolumeSlider.stepped(32, by: 5) == 37)
        #expect(TileVolumeSlider.stepped(32, by: -5) == 27)
        #expect(TileVolumeSlider.stepped(98, by: 5) == 100)
        #expect(TileVolumeSlider.stepped(3, by: -5) == 0)
    }

    @Test func aTouchMapsToAPercentAcrossTheTrack() {
        #expect(TileVolumeSlider.percent(atX: 0, width: 200) == 0)
        #expect(TileVolumeSlider.percent(atX: 100, width: 200) == 50)
        #expect(TileVolumeSlider.percent(atX: -20, width: 200) == 0)
        #expect(TileVolumeSlider.percent(atX: 400, width: 200) == 100)
        #expect(TileVolumeSlider.percent(atX: 10, width: 0) == 0)
    }

    @Test func theValueIsSpokenInPercent() {
        #expect(TileVolumeSlider.spokenValue(percent: 32) == "32 percent")
    }

    @Test func aDragSendsNothingUntilItEndsAndThenOnce() {
        var interaction = TileVolumeInteraction()
        for x in stride(from: 20.0, through: 160.0, by: 20.0) {
            interaction.dragChanged(translation: CGSize(width: x - 20, height: 0), x: x, width: 200)
        }
        #expect(interaction.dragPercent == 80 && interaction.shown(live: 32) == 80, "the level follows the finger, locally")
        #expect(interaction.pendingPercent == nil, "nothing is committed mid-drag")
        #expect(interaction.dragEnded(x: 160, width: 200, live: 32) == 80, "one level, on release")
        #expect(interaction.shown(live: 32) == 80, "and it stays until the live level answers")
        #expect(interaction.dragPercent == nil)
    }

    @Test func aVerticalDragIsLeftToTheScrollView() {
        var interaction = TileVolumeInteraction()
        interaction.dragChanged(translation: CGSize(width: 2, height: 30), x: 100, width: 200)
        #expect(interaction.dragPercent == nil)
        #expect(interaction.dragEnded(x: 100, width: 200, live: 32) == nil)
    }

    @Test func aCancelledDragCommitsNothing() {
        var interaction = TileVolumeInteraction()
        interaction.dragChanged(translation: CGSize(width: 30, height: 0), x: 150, width: 200)
        interaction.dragCancelled()
        #expect(interaction.dragPercent == nil && interaction.pendingPercent == nil)
        #expect(interaction.shown(live: 32) == 32)
    }

    @Test func releasingWhereItStartedSendsNothing() {
        var interaction = TileVolumeInteraction()
        interaction.dragChanged(translation: CGSize(width: 5, height: 0), x: 64, width: 200)
        #expect(interaction.dragEnded(x: 64, width: 200, live: 32) == nil, "32% to 32%")
    }

    @Test func eachVoiceOverStepWritesOnce() {
        var interaction = TileVolumeInteraction()
        #expect(interaction.adjust(by: 5, live: 32) == 37)
        #expect(interaction.adjust(by: 5, live: 32) == 42, "steps build on the level just sent, not the stale live one")
        #expect(interaction.adjust(by: -5, live: 32) == 37)
        var top = TileVolumeInteraction()
        #expect(top.adjust(by: 5, live: 100) == nil, "already at the end")
    }

    @Test func aLiveReportReplacesTheLevelShownMeanwhile() {
        var interaction = TileVolumeInteraction()
        _ = interaction.adjust(by: 5, live: 32)
        interaction.pendingPercent = nil
        #expect(interaction.shown(live: 37) == 37)
    }

    @Test func theHapticTicksEveryTenPercent() {
        #expect(TileVolumeSlider.hapticStep(nil) == nil)
        #expect(TileVolumeSlider.hapticStep(34) == 3)
        #expect(TileVolumeSlider.hapticStep(100) == 10)
    }
}

/// Whether a tile spans its row, from the grid's geometry and the tile's declared minimum (the grid's own span rule). It gates animation only.
struct TileGridGeometryTests {
    /// An iPhone page (370 pt of grid, 150 pt cells, 12 pt gutters): two 179 pt tracks.
    private let phone = TileGridGeometry(width: 370, minCellWidth: 150, maxColumns: 4, spacing: 12)

    /// Tiles no longer widen to their content (owner, 2026-10-30): one track whatever the declared minimum.
    @Test func onAnIPhoneNoMinimumMakesATileFullRow() {
        #expect(phone.metrics.columns == 2)
        #expect(!phone.isFullRow(minimum: 234), "a remote's 234 pt still takes one track")
        #expect(!phone.isFullRow(minimum: 172), "a lock-sized tile fits one track")
        #expect(!phone.isFullRow(minimum: 0), "no declared minimum: one track")
    }

    @Test func aTileWiderThanTheRowStillTakesOneTrack() {
        #expect(!phone.isFullRow(minimum: 900))
    }

    @Test func aOneColumnGridIsAllFullRow() {
        let narrow = TileGridGeometry(width: 200, minCellWidth: 150, maxColumns: 4, spacing: 12)
        #expect(narrow.metrics.columns == 1)
        #expect(narrow.isFullRow(minimum: 100) && narrow.isFullRow(minimum: 0))
    }

    @Test func acrossAHingeBandNoMinimumMakesATileFullRow() {
        let duo = TileGridGeometry(width: 900, minCellWidth: 150, maxColumns: 4, spacing: 12, evenColumns: true, band: 440...460)
        #expect(duo.metrics.sideColumns == 2 && duo.metrics.spanCap == 2)
        #expect(!duo.isFullRow(minimum: 150))
        #expect(!duo.isFullRow(minimum: 300), "one track, not the whole side")
        #expect(!duo.isFullRow(minimum: 900), "never across the band")
    }

    @Test func geometryEqualityLetsTheEnvironmentSkipUnchangedWidths() {
        #expect(phone == TileGridGeometry(width: 370, minCellWidth: 150, maxColumns: 4, spacing: 12))
        #expect(phone != TileGridGeometry(width: 402, minCellWidth: 150, maxColumns: 4, spacing: 12))
    }
}
