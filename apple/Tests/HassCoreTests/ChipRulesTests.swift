import Foundation
@testable import HassCore
import HassTestSupport
import Testing

/// The status chips' colour rules: the contact states, and the web colours the Climate and Air Quality chips follow
/// (`ha-sfenton-react-dash@9ac2a46:src/components/cards/climateColor.ts`, `StatusRail.tsx`).
@Suite(.demoHouse)
struct ChipRulesTests {
    // MARK: Contact chip

    @Test(arguments: ["armed_home", "armed_away", "armed_night", "armed_vacation", "armed_custom_bypass", "triggered"])
    func everyArmedModeCountsAsArmed(_ mode: String) {
        #expect(ContactChipState.isArmed(mode))
    }

    @Test(arguments: [nil, "disarmed", "arming", "pending", "unknown", "unavailable"] as [String?])
    func otherPanelStatesAreNotArmed(_ mode: String?) {
        #expect(!ContactChipState.isArmed(mode))
    }

    @Test func allClosedIgnoresTheHouseAndTheAlarm() {
        for alarm in ["armed_away", "disarmed", nil] as [String?] {
            for away in [true, false] {
                #expect(ContactChipState.resolve(isOpen: false, alarmState: alarm, isAway: away) == .allClosed)
            }
        }
    }

    @Test func openDoorsReadTheHouseWithTheAlarmFirst() {
        #expect(ContactChipState.resolve(isOpen: true, alarmState: "disarmed", isAway: false) == .openHome)
        #expect(ContactChipState.resolve(isOpen: true, alarmState: nil, isAway: false) == .openHome)
        #expect(ContactChipState.resolve(isOpen: true, alarmState: "disarmed", isAway: true) == .openAway)
        #expect(ContactChipState.resolve(isOpen: true, alarmState: "arming", isAway: true) == .openAway, "Arming is not armed yet")
        for mode in ["armed_home", "armed_away", "armed_night", "triggered"] {
            // Armed beats away and home alike.
            #expect(ContactChipState.resolve(isOpen: true, alarmState: mode, isAway: true) == .openArmed, "\(mode)")
            #expect(ContactChipState.resolve(isOpen: true, alarmState: mode, isAway: false) == .openArmed, "\(mode)")
        }
    }

    @Test func noReadingIsUnavailable() {
        #expect(ContactChipState.resolve(isOpen: nil, alarmState: "armed_home", isAway: false) == .unavailable)
        #expect(!ContactChipState.unavailable.isOpen && !ContactChipState.allClosed.isOpen)
        #expect(ContactChipState.openHome.isOpen && ContactChipState.openAway.isOpen && ContactChipState.openArmed.isOpen)
    }

    @Test func currentReadsTheAlarmAndTheEffectiveAwayMode() {
        func state(_ alarm: String?, awayMode: String?) -> ContactChipState {
            let read: EntityLookup = { id in
                switch id {
                case SecurityConfig.alarmEntityId: alarm.map { EntityState(entityId: id, state: $0) }
                case ClimateConfig.homeAwayEntityId: awayMode.map { EntityState(entityId: id, state: $0) }
                default: nil
                }
            }
            return ContactChipState.current(isOpen: true, read: read)
        }
        #expect(state("disarmed", awayMode: "Home") == .openHome)
        #expect(state("disarmed", awayMode: "Away") == .openAway)
        #expect(state("armed_home", awayMode: "Home") == .openArmed)
        #expect(state(nil, awayMode: nil) == .openHome, "Nothing known: the quiet state")
    }

    // MARK: Climate colour

    @Test func climateColourHelperIsNamedFromTheRangeHelper() {
        #expect(ChipWebColor.climateColorEntityId(forRange: "input_text.demo_all_climate_range") == "input_text.demo_all_climate_color")
        #expect(ChipWebColor.climateColorEntityId(forRange: "input_text.demo_room_climate_range") == "input_text.demo_room_climate_color")
        #expect(ChipWebColor.climateColorEntityId(forRange: "climate.demo_climate_1") == nil)
        #expect(ChipWebColor.climateColorEntityId(forRange: "input_text.demo_some_other_range") == nil)
    }

    @Test func climateColourPrefersTheHelperThenTheGradient() {
        #expect(ChipWebColor.climate(colorText: "rgba(223, 213, 15, 1)", rangeText: "50°F") == RoomColor(223, 213, 15))
        #expect(ChipWebColor.climate(colorText: "rgb(10, 20, 30)", rangeText: nil) == RoomColor(10, 20, 30))
        // No usable helper: the web's gradient at the range's mean.
        #expect(ChipWebColor.climate(colorText: nil, rangeText: "70.0°F - 74.0°F") == RoomOverview.colorFromTemperature(72))
        #expect(ChipWebColor.climate(colorText: "unavailable", rangeText: "68°F") == RoomColor(0, 200, 120))
        #expect(ChipWebColor.climate(colorText: "", rangeText: "unavailable") == nil)
        #expect(ChipWebColor.climate(colorText: nil, rangeText: nil) == nil)
    }

    /// The web gradient's stops (`climateColor.ts:8-15`) and what lies beyond them.
    @Test(arguments: [
        (50.0, UInt32(0x006EFF)), (60, 0x8000FF), (68, 0x00C878), (74, 0xFFD700), (80, 0xFFA500), (85, 0xFF0000),
        (30, 0x006EFF), (100, 0xFF0000),
    ])
    func gradientHitsItsStopsAndClampsBeyondThem(_ degrees: Double, _ expected: UInt32) {
        let color = ChipWebColor.climate(colorText: nil, rangeText: "\(degrees)°F")
        #expect(color?.rgb == expected)
    }

    @Test func gradientBlendsBetweenStops() {
        // Halfway from green (0,200,120) at 68 to yellow (255,215,0) at 74 is 71.
        #expect(ChipWebColor.climate(colorText: nil, rangeText: "71.0°F")?.rgb == 0x80D03C)
        // 64 is halfway from purple (128,0,255) at 60 to green (0,200,120) at 68.
        #expect(ChipWebColor.climate(colorText: nil, rangeText: "64°F")?.rgb == 0x4064BC)
    }

    @Test func meanTemperatureReadsRangesAndConvertsCelsius() {
        #expect((ChipWebColor.meanTemperature("70.1°F - 78.6°F") ?? 0).isClose(to: 74.35))
        #expect(ChipWebColor.meanTemperature("71.2°F") == 71.2)
        #expect(ChipWebColor.meanTemperature("20°C") == 68)
        #expect(ChipWebColor.meanTemperature("unavailable") == nil)
        #expect(ChipWebColor.meanTemperature("--") == nil)
        #expect(ChipWebColor.meanTemperature(nil) == nil)
    }

    // MARK: Air quality colour

    @Test func airColourIsTheHelperElseTheWebTeal() {
        #expect(ChipWebColor.airQuality(colorText: "rgba(0, 150, 136, 1)") == ChipWebColor.airTeal)
        #expect(ChipWebColor.airQuality(colorText: "rgb(255, 190, 0)") == RoomColor(255, 190, 0))
        #expect(ChipWebColor.airQuality(colorText: "#E53935") == RoomColor(229, 57, 53))
        #expect(ChipWebColor.airQuality(colorText: "unavailable") == ChipWebColor.airTeal)
        #expect(ChipWebColor.airQuality(colorText: nil) == ChipWebColor.airTeal)
        #expect(ChipWebColor.airTeal.rgb == 0x009688)
    }

    @Test func roomAirChipsFindTheirColourHelper() {
        #expect(ChipWebColor.airColorEntityId(forPM25: "sensor.demo_office_1") == "input_text.demo_office_color_1")
        #expect(ChipWebColor.airColorEntityId(forPM25: "sensor.demo_sensor_17") == "input_text.demo_studio_color_1")
        #expect(ChipWebColor.airColorEntityId(forPM25: "sensor.demo_nobody_pm2_5") == nil)
    }

    @Test func homeClimateChipNamesItsColourHelper() {
        let chip = HomeConfig.statusChips.first { $0.sheet == .climate }
        #expect(chip?.colorEntityId == "input_text.demo_color_1")
        #expect(HomeConfig.statusChips.first { $0.sheet == .airQuality }?.colorEntityId == "input_text.demo_color_2")
    }

    @Test func roomColourPacksIntoRGB() {
        #expect(RoomColor(255, 128, 0).rgb == 0xFF8000)
        #expect(RoomColor(0, 0, 0).rgb == 0)
    }
}

private extension Double {
    /// Approximate equality for the mean test.
    func isClose(to other: Double) -> Bool { abs(self - other) < 0.001 }
}
