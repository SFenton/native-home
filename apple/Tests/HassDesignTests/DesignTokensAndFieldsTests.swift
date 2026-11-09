import SwiftUI
@testable import HassDesign
import Testing

/// Small shared design rules the UIKit port reads: dial colours, tile action ink, tile kinds, status tones, schedule fields.
struct DesignTokensAndFieldsTests {
    @Test func theDialColoursFollowTheThermalStatusAndRangeHandlesKeepHeatAndCool() {
        for status in [ThermostatThermalStatus.heat, .cool, .idle] {
            #expect(ThermostatDialPalette.color(for: status) == ThermostatDialPalette.color(for: .target, status: status))
            #expect(ThermostatDialPalette.colorToken(for: status) == ThermostatDialPalette.colorToken(for: .target, status: status))
        }
        #expect(ThermostatDialPalette.colorToken(for: .low, status: .cool) == ThermostatDialPalette.colorToken(for: .heat))
        #expect(ThermostatDialPalette.colorToken(for: .high, status: .heat) == ThermostatDialPalette.colorToken(for: .cool))
        #expect(ThermostatDialPalette.color(for: .low, status: .idle) == ThermostatDialPalette.color(for: .heat))
        #expect(ThermostatDialPalette.color(for: .high, status: .idle) == ThermostatDialPalette.color(for: .cool))
        #expect(ThermostatDialPalette.colorToken(for: .heat) != ThermostatDialPalette.colorToken(for: .cool))
    }

    @Test func aDialConfigurationsColourKeyChangesWithItsThermalStatus() {
        let idle = ThermostatDialConfiguration(title: "Hall", min: 45, max: 95, step: 0.5, current: 70, targets: .single(68), action: "idle")
        let heating = ThermostatDialConfiguration(title: "Hall", min: 45, max: 95, step: 0.5, current: 70, targets: .single(68), action: "heating")
        #expect(idle.colorKey != heating.colorKey)
        #expect(idle.colorKey == idle.colorKey)
    }

    @Test func aLitTileHasWhiteGlyphsAndAnOnDiscIsWhite() {
        let lit = TileActionInk.resolveTokens(face: .lit, isOn: false, family: nil)
        #expect(lit.glyph == .white)
        let litOn = TileActionInk.resolveTokens(face: .lit, isOn: true, family: .water)
        #expect(litOn.glyph == .white, "a lit tile's glyph stays white however it is on")
        let on = TileActionInk.resolveTokens(face: .dark, isOn: true, family: .water)
        #expect(on.disc == .white)
        #expect(on.glyph == ColorFamily.water.fillToken)
        #expect(TileActionInk.resolveTokens(face: .dark, isOn: true, family: nil).disc == .white)
    }

    @Test func anOffDiscIsDimmedByFaceAndTheGlyphFollowsTheFamilyOnlyWhenItReadsAsText() {
        let filled = TileActionInk.resolveTokens(face: .filled, isOn: false, family: .water)
        #expect(filled.disc == HassRGB.black.opacity(TileActionInk.filledDiscOpacity))
        #expect(filled.glyph == .white)
        let noFamily = TileActionInk.resolveTokens(face: .dark, isOn: false, family: nil)
        #expect(noFamily.disc == HassRGB.white.opacity(TileActionInk.darkDiscOpacity))
        #expect(noFamily.glyph == .white)
        for family in ColorFamily.allCases {
            let dark = TileActionInk.resolveTokens(face: .dark, isOn: false, family: family)
            #expect(dark.glyph == (TileActionInk.offGlyphPasses(family) ? family.offGlyphToken : .white))
            _ = TileActionInk.resolve(face: .dark, isOn: false, family: family)
            _ = TileActionInk.resolve(face: .dark, isOn: true, family: family)
        }
        _ = TileActionInk.resolve(face: .lit, isOn: false, family: nil)
        _ = TileActionInk.resolve(face: .filled, isOn: false, family: nil)
    }

    @Test func onlyCommandsTogglesAndSelectionsPlayTheTapHaptic() {
        #expect(GlassTileKind.toggle.playsTapFeedback)
        #expect(GlassTileKind.command.playsTapFeedback)
        #expect(GlassTileKind.selection(isSelected: false).playsTapFeedback)
        #expect(!GlassTileKind.navigate.playsTapFeedback)
        #expect(!GlassTileKind.state.playsTapFeedback)
        #expect(GlassTileKind.navigate.behavior == .navigate)
        #expect(GlassTileKind.state.behavior == .inert)
        #expect(GlassTileKind.toggle.behavior == .perform(""))
        #expect(GlassTileKind.selection(isSelected: true).behavior == .perform(""))
    }

    @Test func statusPillTonesHaveAColourAndATokenAndReadValueThenDetail() {
        let tones: [StatusPill.Tone] = [.neutral, .ok, .active, .warning, .danger, .unavailable]
        for tone in tones {
            _ = StatusPill.color(tone)
        }
        #expect(Set(tones.map { "\(StatusPill.colorToken($0))" }).count == tones.count, "every tone is its own colour")
        #expect(StatusPill.accessibilityValue(value: "Open", detail: nil) == "Open")
        let spoken = StatusPill.accessibilityValue(value: "Open", detail: "Front door")
        #expect(spoken.hasPrefix("Open") && spoken.hasSuffix("Front door"), "value first, then detail")
        #expect(StatusPill.pendingValue == "Loading")
    }

    @Test func tileSurfacesPickTheirSecondaryInk() {
        #expect(TileSurface.sheet.secondaryInkToken == HassTokens.RGB.Surface.secondaryInSheet)
        #expect(TileSurface.page.secondaryInkToken == HassTokens.RGB.Surface.secondaryOnModule)
        _ = TileSurface.sheet.secondaryInk
        #expect(EnvironmentValues().tileSurface == .page)
    }

    @Test func aScheduleFieldBoundsNeverInvertAndLimitedCopiesTheField() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let field = ScheduleDateField(label: "Starts", part: .dateAndTime, value: now, identifier: "start") { _ in }
        #expect(field.bounds == nil)
        #expect(field.id == "start")
        let later = now.addingTimeInterval(3_600)
        let limited = field.limited(from: now, to: later)
        #expect(limited.bounds == now...later)
        #expect(field.limited(from: now).bounds?.lowerBound == now)
        #expect(field.limited(to: later).bounds?.upperBound == later)
        let inverted = field.limited(from: later, to: now)
        #expect(inverted.bounds == later...later, "a saved value past the other bound stays reachable")
        #expect(ScheduleDateField.Part.date.components == .date)
        #expect(ScheduleDateField.Part.time.components == .hourAndMinute)
        #expect(ScheduleDateField.Part.dateAndTime.components == [.date, .hourAndMinute])
    }

    @Test func sheetSubtitlesAreAnIOS26ThingAndNotShownOnTheMacHost() {
        #expect(!SheetSubtitle.isShown)
    }

    @MainActor @Test func aTransientFailureShowsItsMessageThenClears() async throws {
        let failure = TransientFailure(duration: .milliseconds(30))
        #expect(failure.message == nil)
        failure.show("Couldn't reach the lock.")
        #expect(failure.message == "Couldn't reach the lock.")
        #expect(failure.count == 1)
        failure.show("Again")
        #expect(failure.count == 2)
        // Polls until the timer fires; the deadline only bounds a real failure (a loaded hosted runner starved the main actor for 2 s+).
        let deadline = ContinuousClock.now + .seconds(30)
        while failure.message != nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(failure.message == nil)
        #expect(TransientFailure.duration == .seconds(4))
    }
}
