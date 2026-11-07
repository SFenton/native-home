@testable import HassDesign
import SwiftUI
import Testing

/// What VoiceOver is told and what non-VoiceOver alternatives exist (mockup atlas, bucket "VoiceOver & accessibility"): these
/// check the strings and the logic directly, so coverage does not depend on a hosted accessibility tree (which needs an
/// unlocked screen).
@MainActor
struct VoiceOverSemanticsTests {
    private func render(_ view: some View, size: DynamicTypeSize = .large) -> CGImage? {
        ImageRenderer(content: view.frame(width: 360, height: 120).dynamicTypeSize(size)).cgImage
    }

    // MARK: Announcer

    @Test func announcementsGoThroughTheSinkAndEmptyTextIsDropped() {
        var heard: [String] = []
        Announcer.sink = { heard.append($0) }
        defer { Announcer.sink = nil }
        Announcer.announce("Saving")
        Announcer.announce("")
        Announcer.screenChanged()
        Announcer.screenChanged(announcing: "Home")
        #expect(heard == ["Saving", "screenChanged", "screenChanged: Home"])
    }

    // MARK: Brightness tile

    @Test func aBrightnessTileAlwaysCarriesAPowerDiscExceptAnUnavailableOneThatOpensDetails() {
        #expect(BrightnessTile.items(percent: 40, isUnavailable: false, opensDetails: false).map(\.id) == ["power"], "an action tile")
        #expect(BrightnessTile.items(percent: 40, isUnavailable: false, opensDetails: true).map(\.id) == ["power"], "a navigation tile")
        #expect(BrightnessTile.items(percent: 40, isUnavailable: true, opensDetails: false).first?.phase == .unavailable, "dimmed in place")
        #expect(BrightnessTile.items(percent: 40, isUnavailable: true, opensDetails: true).isEmpty, "no disc, as today")
        #expect(BrightnessTile.powerLabel(title: "Bollard", percent: 40) == "Turn Off Bollard")
        #expect(BrightnessTile.powerLabel(title: "Bollard", percent: 0) == "Turn On Bollard")
    }

    // MARK: Switch row

    // MARK: Dial actions

    @Test func theDialOffersNamedStepActions() {
        #expect(ThermostatDialConfiguration.raiseActionName == "Raise")
        #expect(ThermostatDialConfiguration.lowerActionName == "Lower")
    }

    // MARK: Increase Contrast

    @Test func increaseContrastMovesTextTowardTheExtreme() {
        let dark = HassTokens.Ink.increasedContrast((0.25, 0.61, 1.0), isDark: true)
        #expect(dark.0 > 0.25 && dark.1 > 0.61 && dark.2 == 1.0, "light text on dark moves toward white")
        let light = HassTokens.Ink.increasedContrast((0.0, 0.40, 0.80), isDark: false)
        #expect(light.0 == 0 && light.1 < 0.40 && light.2 < 0.80, "dark text on light moves toward black")
        let step = HassTokens.Ink.increasedContrastStep
        #expect(abs(light.2 - 0.80 * (1 - step)) < 1e-9)
    }
}
