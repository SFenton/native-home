import CoreGraphics
import Foundation
@testable import HassDesign
import SwiftUI
import Testing

struct ThermostatTargetsTests {
    @Test func singleAndRangeExposeTheirHandles() {
        #expect(ThermostatTargets.single(72).handles == [.target])
        #expect(ThermostatTargets.range(low: 68, high: 75).handles == [.low, .high])
        #expect(ThermostatTargets.single(72).value(of: .target) == 72)
        #expect(ThermostatTargets.single(72).value(of: .low) == nil)
        #expect(ThermostatTargets.range(low: 68, high: 75).value(of: .low) == 68)
        #expect(ThermostatTargets.range(low: 68, high: 75).value(of: .high) == 75)
    }

    @Test func heatToNeverPassesCoolTo() {
        let range = ThermostatTargets.range(low: 68, high: 75)
        #expect(range.setting(.low, to: 70) == .range(low: 70, high: 75))
        #expect(range.setting(.low, to: 80) == .range(low: 75, high: 75))
        #expect(range.setting(.high, to: 60) == .range(low: 68, high: 68))
        #expect(range.setting(.target, to: 60) == range)
        #expect(ThermostatTargets.single(72).setting(.target, to: 73) == .single(73))
        #expect(ThermostatTargets.single(72).setting(.low, to: 73) == .single(72))
    }

    @Test func ringTapsPickTheNearestHandle() {
        let range = ThermostatTargets.range(low: 68, high: 76)
        #expect(range.nearestHandle(to: 60) == .low)
        #expect(range.nearestHandle(to: 80) == .high)
        #expect(range.nearestHandle(to: 71) == .low)
        #expect(range.nearestHandle(to: 72) == .low)
        #expect(range.nearestHandle(to: 73) == .high)
        #expect(ThermostatTargets.single(72).nearestHandle(to: 50) == .target)
    }

    @Test func serviceDataMatchesSetTemperature() {
        #expect(ThermostatTargets.single(72).serviceData == ["temperature": 72])
        #expect(ThermostatTargets.range(low: 68, high: 75).serviceData == ["target_temp_low": 68, "target_temp_high": 75])
    }

    @Test func thermalStatusFollowsTheAction() {
        #expect(ThermostatThermalStatus(action: "heating") == .heat)
        #expect(ThermostatThermalStatus(action: "heat") == .heat)
        #expect(ThermostatThermalStatus(action: "cooling") == .cool)
        #expect(ThermostatThermalStatus(action: "cool") == .cool)
        #expect(ThermostatThermalStatus(action: "fan") == .idle)
    }
}

struct ThermostatDialConfigurationTests {
    func make(_ targets: ThermostatTargets? = .single(72), action: String = "heating", current: Double? = 68.5,
              unavailable: Bool = false, off: Bool = false) -> ThermostatDialConfiguration {
        ThermostatDialConfiguration(title: "Office", current: current, targets: targets, action: action, isUnavailable: unavailable, isOff: off)
    }

    @Test func inactiveMatchesTheWeb() {
        #expect(!make().isInactive)
        #expect(make(unavailable: true).isInactive)
        #expect(make(action: "off", off: true).isInactive)
        #expect(!make(action: "heating", off: true).isInactive)
        #expect(!make(.range(low: 68, high: 75), action: "off", off: true).isInactive)
        var forced = make()
        forced.inactiveOverride = true
        #expect(forced.isInactive)
    }

    @Test func inputNeedsAnInteractiveAvailableTarget() {
        #expect(make().acceptsInput)
        #expect(!make(nil).acceptsInput)
        #expect(!make(unavailable: true).acceptsInput)
        var readOnly = make()
        readOnly.isInteractive = false
        #expect(!readOnly.acceptsInput)
    }

    @Test func readoutTextMatchesTheWeb() {
        #expect(make().actionText == "Heating")
        #expect(make(action: "heat_cool").actionText == "Heat Cool")
        #expect(make(unavailable: true).actionText == "Unavailable")
        #expect(make().primaryText == "68.5")
        #expect(make(current: 70).primaryText == "70")
        #expect(make(current: nil).primaryText == "--")
        #expect(make(unavailable: true).primaryText == "--")
        #expect(make().primaryUnit == "°F")
        #expect(make().caption(for: .single(72)) == "72.0°F")
        #expect(make().caption(for: .range(low: 68, high: 75)) == "68.0 · 75.0")
        #expect(make().caption(for: nil) == nil)
    }

    @Test func overridesReplaceTheReadout() {
        var config = make()
        config.actionTextOverride = "Away"
        config.primaryValueOverride = "ECO"
        config.primaryUnitOverride = .some(nil)
        config.targetCaption = .custom("Until 6 PM")
        #expect(config.actionText == "Away")
        #expect(config.primaryText == "ECO")
        #expect(config.primaryUnit == nil)
        #expect(config.caption(for: .single(72)) == "Until 6 PM")
        config.targetCaption = .hidden
        #expect(config.caption(for: .single(72)) == nil)
    }

    @Test func signedLevelReadoutFollowsTheDisplayedTarget() {
        var config = make(.single(3), current: 86.5)
        config.scale = .signedLevel
        config.primaryUnitOverride = .some(nil)
        #expect(config.primaryText(for: .single(3)) == "+3")
        // A drag's pending value, not the committed target.
        #expect(config.primaryText(for: .single(-4)) == "-4")
        #expect(config.primaryText(for: .single(0)) == "0")
        #expect(config.primaryText(for: .single(1.5)) == "+1.5")
        // A -0.0 target from Home Assistant reads 0, as the bed's VoiceOver label (`BedLevel.format`) does (#214).
        #expect(config.primaryText(for: .single(-0.0)) == "0")
        #expect(ThermostatDialConfiguration.signedLevel(-0.0) == "0")
        #expect(config.spokenValue(-0.0) == "0")
        #expect(config.primaryText(for: nil) == "--")
        config.primaryValueOverride = "OFF"
        #expect(config.primaryText(for: .single(-4)) == "OFF")
        // A temperature dial keeps the measured temperature as its large text.
        #expect(make().primaryText(for: .single(75)) == "68.5")
    }

    @Test func accessibilityTextNamesEachHandle() {
        let config = make()
        #expect(config.accessibilityLabel(for: .target) == "Office target temperature")
        #expect(config.accessibilityLabel(for: .low) == "Office heat to")
        #expect(config.accessibilityLabel(for: .high) == "Office cool to")
        #expect(ThermostatDialConfiguration.spokenTemperature(72.5) == "72.5 degrees")
        #expect(config.readoutAccessibilityLabel == "Office thermostat, Heating, currently 68.5°F")
        #expect(make(current: nil).readoutAccessibilityLabel == "Office thermostat, Heating, current temperature unknown")
    }

    @Test func formattingMatchesToFixed() {
        #expect(ThermostatDialConfiguration.oneDecimal(nil) == "--")
        #expect(ThermostatDialConfiguration.oneDecimal(71.26) == "71.3")
        #expect(ThermostatDialConfiguration.compact(72) == "72")
        #expect(ThermostatDialConfiguration.compact(nil) == "--")
    }

    @Test func paletteColorsFollowStatusAndHandle() {
        #expect(ThermostatDialPalette.color(for: .heat) == ThermostatDialPalette.heat)
        #expect(ThermostatDialPalette.color(for: .cool) == ThermostatDialPalette.cool)
        #expect(ThermostatDialPalette.color(for: .idle) == ThermostatDialPalette.neutral)
        #expect(ThermostatDialPalette.color(for: .low, status: .cool) == ThermostatDialPalette.heat)
        #expect(ThermostatDialPalette.color(for: .high, status: .heat) == ThermostatDialPalette.cool)
        #expect(ThermostatDialPalette.color(for: .target, status: .cool) == ThermostatDialPalette.cool)
    }
}

struct ThermostatDialEditorTests {
    let single = ThermostatDialConfiguration(title: "Office", current: 70, targets: .single(72), action: "heating")
    let range = ThermostatDialConfiguration(title: "Home", current: 70, targets: .range(low: 68, high: 75), action: "idle")
    let start = Date(timeIntervalSince1970: 0)

    private func point(_ value: Double, _ config: ThermostatDialConfiguration) -> CGPoint {
        config.geometry.point(for: value, side: 300)
    }

    @Test func draggingShowsThePendingValueAndCommitsOnRelease() {
        var editor = ThermostatDialEditor()
        editor.drag(.target, to: point(74, single), side: 300, in: single)
        #expect(editor.activeHandle == .target)
        #expect(editor.displayed(single) == .single(74))
        let commit = editor.endDrag(.target, at: point(74.5, single), side: 300, in: single, now: start)
        #expect(commit == .single(74.5))
        #expect(editor.activeHandle == nil)
        #expect(editor.displayed(single) == .single(74.5))
    }

    @Test func homeAssistantsNextValueReplacesThePendingEdit() {
        var editor = ThermostatDialEditor()
        _ = editor.endDrag(.target, at: point(74, single), side: 300, in: single, now: start)
        var echoed = single
        echoed.targets = .single(73)
        #expect(editor.displayed(echoed) == .single(73))
    }

    @Test func aRejectedCommitRollsBackAndCanBeSentAgain() {
        var editor = ThermostatDialEditor()
        #expect(editor.endDrag(.target, at: point(74, single), side: 300, in: single, now: start) == .single(74))
        editor.rollBack(rejected: .single(74))
        #expect(editor.pending == nil)
        #expect(editor.displayed(single) == .single(72), "Back to Home Assistant's setpoint")
        #expect(editor.endDrag(.target, at: point(74, single), side: 300, in: single, now: start.addingTimeInterval(0.1)) == .single(74),
                "The same value is not dropped as a duplicate after a rollback")
    }

    @Test func aLateRejectionNeverUndoesANewerEdit() {
        var editor = ThermostatDialEditor()
        _ = editor.adjust(.target, increment: true, in: single, now: start)
        _ = editor.adjust(.target, increment: true, in: single, now: start.addingTimeInterval(0.5))
        let newer = editor.displayed(single)
        editor.rollBack(rejected: .single(72.5))
        #expect(editor.displayed(single) == newer, "The older commit's failure leaves the newer edit")
        editor.drag(.target, to: point(75, single), side: 300, in: single)
        let dragging = editor.displayed(single)
        editor.rollBack(rejected: dragging!)
        #expect(editor.displayed(single) == dragging, "No rollback mid-drag")
        #expect(ThermostatRejection(targets: .single(72), count: 1) != ThermostatRejection(targets: .single(72), count: 2))
    }

    @Test func releasingWhereItStartedSendsNothing() {
        var editor = ThermostatDialEditor()
        #expect(editor.endDrag(.target, at: point(72, single), side: 300, in: single, now: start) == nil)
    }

    @Test func identicalCommitsWithin400msAreDropped() {
        var editor = ThermostatDialEditor()
        #expect(editor.endDrag(.target, at: point(74, single), side: 300, in: single, now: start) == .single(74))
        #expect(editor.endDrag(.target, at: point(74, single), side: 300, in: single, now: start.addingTimeInterval(0.2)) == nil)
        #expect(editor.endDrag(.target, at: point(74, single), side: 300, in: single, now: start.addingTimeInterval(0.5)) == .single(74))
    }

    @Test func rangeHandlesStayOrdered() {
        var editor = ThermostatDialEditor()
        let commit = editor.endDrag(.low, at: point(80, range), side: 300, in: range, now: start)
        #expect(commit == .range(low: 75, high: 75))
    }

    @Test func ringTapsMoveTheNearestHandle() {
        var editor = ThermostatDialEditor()
        #expect(editor.tap(at: point(78, range), side: 300, in: range, now: start) == .range(low: 68, high: 78))
        #expect(editor.tap(at: CGPoint(x: 150, y: 150), side: 300, in: range, now: start) == nil)
    }

    @Test func voiceOverAdjustsOneStep() {
        var editor = ThermostatDialEditor()
        #expect(editor.adjust(.target, increment: true, in: single, now: start) == .single(72.5))
        // Stepping back to Home Assistant's own value has nothing to send.
        #expect(editor.adjust(.target, increment: false, in: single, now: start.addingTimeInterval(1)) == nil)
        #expect(editor.displayed(single) == .single(72))
        #expect(editor.adjust(.high, increment: true, in: range, now: start) == .range(low: 68, high: 75.5))
        #expect(editor.adjust(.low, increment: true, in: single, now: start) == nil)
    }

    @Test func unavailableOrReadOnlyIgnoresInput() {
        var editor = ThermostatDialEditor()
        var readOnly = single
        readOnly.isInteractive = false
        editor.drag(.target, to: point(80, single), side: 300, in: readOnly)
        #expect(editor.activeHandle == nil)
        #expect(editor.tap(at: point(80, single), side: 300, in: readOnly, now: start) == nil)
        #expect(editor.adjust(.target, increment: true, in: readOnly, now: start) == nil)
    }
}

struct ThermostatDialSizeTests {
    @Test func sizesCapTheRingBox() {
        #expect(ThermostatDial.Size.page.maxSide == 316)
        #expect(ThermostatDial.Size.modal.maxSide == 300)
        #expect(ThermostatDial.Size.compact.maxSide == 250)
        #expect(ThermostatDial.gutter == 20)
    }
}
