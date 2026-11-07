import Foundation
@testable import HassCore
import Testing

/// Ported from `weatherPresentation.test.ts` (`ha-sfenton-react-dash@f5a7bf9`).
struct WeatherPresentationTests {
    @Test(arguments: [
        (0.0, WeatherPresentation.AqiLevel.good), (50, .good), (51, .moderate), (100, .moderate), (101, .sensitive),
        (150, .sensitive), (151, .unhealthy), (200, .unhealthy), (201, .veryUnhealthy), (300, .veryUnhealthy),
        (301, .hazardous), (500, .hazardous), (501, .hazardous),
    ])
    func classifiesUsAqi(value: Double, level: WeatherPresentation.AqiLevel) {
        #expect(WeatherPresentation.classifyUsAqi(value)?.level == level)
    }

    @Test func aqiMarkerUsesEqualWidthBands() throws {
        #expect(try abs(#require(WeatherPresentation.classifyUsAqi(50)).markerPercent - 100.0 / 6) < 1e-9)
        #expect(try abs(#require(WeatherPresentation.classifyUsAqi(151)).markerPercent - 50) < 1e-9)
        #expect(WeatherPresentation.classifyUsAqi(500)?.markerPercent == 100)
        #expect(WeatherPresentation.classifyUsAqi(900)?.markerPercent == 100)
        #expect(WeatherPresentation.classifyUsAqi(state: "unavailable") == nil)
        #expect(WeatherPresentation.classifyUsAqi(state: nil) == nil)
        #expect(WeatherPresentation.classifyUsAqi(-3) == nil)
        #expect(WeatherPresentation.classifyUsAqi(state: " 42 ")?.value == 42)
    }

    @Test func aqiRoundsBeforeCategorizing() {
        #expect(WeatherPresentation.classifyUsAqi(50.4) == .init(elevated: false, level: .good, markerPercent: WeatherPresentation.classifyUsAqi(50)!.markerPercent, value: 50))
        #expect(WeatherPresentation.classifyUsAqi(100.4)?.level == .moderate)
        #expect(WeatherPresentation.classifyUsAqi(100.4)?.elevated == false)
        #expect(WeatherPresentation.classifyUsAqi(100.6)?.level == .sensitive)
        #expect(WeatherPresentation.classifyUsAqi(100.6)?.elevated == true)
        #expect(WeatherPresentation.classifyUsAqi(100.6)?.value == 101)
    }

    @Test func uvCategoriesUseTheUnroundedValue() {
        #expect(WeatherPresentation.uv(2.9)?.level == .low)
        #expect(WeatherPresentation.uv(3)?.level == .moderate)
        #expect(WeatherPresentation.uv(5.9)?.level == .moderate)
        #expect(WeatherPresentation.uv(6)?.level == .high)
        #expect(WeatherPresentation.uv(6.7).map { abs($0.markerPercent - 6.7 / 11 * 100) < 1e-9 } == true)
        #expect(WeatherPresentation.uv(8)?.level == .veryHigh)
        #expect(WeatherPresentation.uv(11)?.level == .extreme)
        #expect(WeatherPresentation.uv(11)?.markerPercent == 100)
        #expect(WeatherPresentation.uv(15)?.markerPercent == 100)
        #expect(WeatherPresentation.uv(nil) == nil)
        #expect(WeatherPresentation.uv(-1) == nil)
    }

    @Test func feelsLikeIsADeltaFromTheActualTemperature() {
        let warmer = WeatherPresentation.feelsLike(actual: 57, apparent: 63, unit: "°F")
        #expect(warmer?.markerPercent == 75)
        #expect(warmer?.relation == .warmer)
        #expect(WeatherPresentation.feelsLike(actual: 20, apparent: 20.8, unit: "°C")?.relation == .similar)
        #expect(WeatherPresentation.feelsLike(actual: 50, apparent: 42, unit: "°F")?.relation == .cooler)
        #expect(WeatherPresentation.feelsLike(actual: 50, apparent: nil, unit: "°F") == nil)
        // Celsius uses a narrower neutral band and range.
        #expect(WeatherPresentation.feelsLike(actual: 20, apparent: 22, unit: "°C")?.relation == .warmer)
        #expect(WeatherPresentation.feelsLike(actual: 50, apparent: 100, unit: nil)?.markerPercent == 100)
    }

    @Test(arguments: [(0.0, "N"), (11.24, "N"), (11.25, "NNE"), (33.75, "NE"), (59, "ENE"), (300, "WNW"), (348.75, "N")])
    func mapsDegreesToACompassPoint(degrees: Double, cardinal: String) {
        #expect(WeatherPresentation.windBearing(.degrees(degrees))?.cardinal == cardinal)
    }

    @Test func normalizesNumericAndCardinalBearingsWithoutInventingPrecision() {
        let negative = WeatherPresentation.windBearing(.degrees(-10))
        #expect(negative == .init(cardinal: "N", destinationDegrees: 170, displayDegrees: 350, sourceDegrees: 350, spoken: "north"))
        let cardinal = WeatherPresentation.windBearing(.cardinal("WNW"))
        #expect(cardinal?.destinationDegrees == 112.5)
        #expect(cardinal?.displayDegrees == nil)
        #expect(cardinal?.sourceDegrees == 292.5)
        #expect(cardinal?.spoken == "west-northwest")
        let numeric = WeatherPresentation.windBearing(.cardinal("276"))
        #expect(numeric?.cardinal == "W")
        #expect(numeric?.destinationDegrees == 96)
        #expect(numeric?.displayDegrees == 276)
        #expect(WeatherPresentation.windBearing(.degrees(190))?.destinationDegrees == 10)
        #expect(WeatherPresentation.windBearing(.cardinal("gusty")) == nil)
        #expect(WeatherPresentation.windBearing(nil) == nil)
        #expect(WeatherPresentation.windBearing(.cardinal(" nne "))?.cardinal == "NNE")
    }

    @Test func unwrapsBearingsOverTheShortestArc() {
        #expect(WeatherPresentation.normalizeBearingDegrees(-10) == 350)
        #expect(WeatherPresentation.shortestBearingDelta(from: 359, to: 1) == 2)
        #expect(WeatherPresentation.shortestBearingDelta(from: 1, to: 359) == -2)
        #expect(WeatherPresentation.shortestBearingDelta(from: 350, to: 10) == 20)
        #expect(WeatherPresentation.shortestBearingDelta(from: 10, to: 350) == -20)
        #expect(WeatherPresentation.shortestBearingDelta(from: 0, to: 180) == 180)
        #expect(WeatherPresentation.shortestBearingDelta(from: 0, to: -180) == 180)
        #expect(WeatherPresentation.shortestBearingDelta(from: 720, to: 10) == 10)
    }

    @Test func compassTurnTimeScalesWithTheArc() {
        #expect(WeatherPresentation.compassRotationDurationMs(from: 0, to: 0) == 260)
        #expect(WeatherPresentation.compassRotationDurationMs(from: 0, to: 90) == 390)
        #expect(WeatherPresentation.compassRotationDurationMs(from: 0, to: 180) == 520)
        #expect(WeatherPresentation.compassRotationDurationMs(from: 350, to: 370) == 289)
        #expect(WeatherPresentation.dataTransitionMs == WeatherPresentation.compassRotationDurationMs(from: 0, to: 90))
    }

    @Test func normalizesPressureUnitsBeforeBanding() {
        #expect(WeatherPresentation.pressure(29.92, unit: "inHg")?.band == .typical)
        #expect(WeatherPresentation.pressure(1000, unit: "hPa")?.band == .below)
        #expect(WeatherPresentation.pressure(1030, unit: "hPa")?.band == .above)
        #expect(WeatherPresentation.pressure(101_300, unit: "Pa")?.hpa == 1013)
        #expect(WeatherPresentation.pressure(101.3, unit: "kPa")?.hpa == 1013)
        #expect(WeatherPresentation.pressure(1013, unit: "mbar")?.hpa == 1013)
        #expect(WeatherPresentation.pressure(1013, unit: "mb")?.hpa == 1013)
        #expect(WeatherPresentation.pressure(1013, unit: "furlongs") == nil)
        #expect(WeatherPresentation.pressure(1013, unit: nil) == nil)
        #expect(WeatherPresentation.pressure(nil, unit: "hPa") == nil)
        #expect(WeatherPresentation.pressure(970, unit: "hPa")?.markerPercent == 0)
        #expect(WeatherPresentation.pressure(1100, unit: "hPa")?.markerPercent == 100)
    }

    @Test func normalizesVisibilityAndKeepsDescriptiveBands() {
        let clear = WeatherPresentation.visibility(10, unit: "mi")
        #expect(clear?.band == .clear)
        #expect(clear?.markerPercent == 100)
        #expect(WeatherPresentation.visibility(5, unit: "mi")?.markerPercent == 50)
        #expect(WeatherPresentation.visibility(0, unit: "mi")?.markerPercent == 0)
        #expect(WeatherPresentation.visibility(nil, unit: "mi") == nil)
        #expect(WeatherPresentation.visibility(10, unit: "km")?.band == .good)
        #expect(WeatherPresentation.visibility(800, unit: "m")?.band == .veryPoor)
        #expect(WeatherPresentation.visibility(4, unit: "mi")?.band == .moderate)
        #expect(WeatherPresentation.visibility(2, unit: "mi")?.band == .poor)
    }

    @Test func selectsTheNextSolarEventAndDaylightProgress() {
        let now = HassDates.iso8601("2026-08-25T20:00:00.000Z")!
        let above = WeatherPresentation.sun(state: "above_horizon", nextRising: "2026-08-26T13:20:00.000Z", nextSetting: "2026-08-26T03:00:00.000Z", now: now)
        #expect(above?.primary == .sunset)
        #expect(above?.secondary == .sunrise)
        #expect((above?.markerPercent ?? 0) > 0)
        #expect(above?.titleKey == "details.sun.sunset")

        let below = WeatherPresentation.sun(state: "below_horizon", nextRising: "2026-08-26T13:20:00.000Z", nextSetting: "2026-08-27T03:00:00.000Z")
        #expect(below?.primary == .sunrise)
        #expect(below?.secondary == .sunset)
        #expect(below?.markerPercent == nil)
        #expect(WeatherPresentation.sun(state: "below_horizon", nextRising: nil, nextSetting: "2026-08-27T03:00:00.000Z") == nil)
        #expect(WeatherPresentation.sun(state: "above_horizon", nextRising: "junk", nextSetting: "junk") == nil)
    }

    @Test func keepsTheSolarMarkerOnTheArc() {
        #expect(WeatherPresentation.sunArcMarker(percent: 0) == (8, 40))
        #expect(WeatherPresentation.sunArcMarker(percent: 50) == (50, 22))
        #expect(WeatherPresentation.sunArcMarker(percent: 100) == (92, 40))
        #expect(WeatherPresentation.sunArcMarker(percent: 200) == (92, 40))
    }

    @Test(arguments: [
        ("sunny", false, WeatherScene.sunny), ("sunny", true, .night), ("clear-night", false, .night), ("partlycloudy", false, .clouds),
        ("cloudy", false, .clouds), ("fog", false, .fog), ("rainy", false, .rain), ("pouring", false, .rain), ("hail", false, .storm),
        ("lightning-rainy", false, .storm), ("snowy-rainy", false, .snow), ("windy-variant", false, .wind),
        ("exceptional", false, .exceptional), ("mystery", false, .neutral),
    ])
    func mapsConditionsToScenes(condition: String, isNight: Bool, scene: WeatherScene) {
        #expect(WeatherScene(condition: condition, isNight: isNight) == scene)
    }

    @Test func aMissingConditionIsTheNeutralScene() {
        #expect(WeatherScene(condition: nil) == .neutral)
    }

    /// One bearing parser for the tiles (16 points) and the briefing (eight principal points only).
    @Test func bearingDegreesReadsDegreesAndCompassPoints() {
        #expect(WeatherPresentation.bearingDegrees(.degrees(200))?.degrees == 200)
        #expect(WeatherPresentation.bearingDegrees(.degrees(200))?.reported == true)
        #expect(WeatherPresentation.bearingDegrees(.cardinal(" 90 "))?.degrees == 90)
        #expect(WeatherPresentation.bearingDegrees(.cardinal("nne"))?.degrees == 22.5)
        #expect(WeatherPresentation.bearingDegrees(.cardinal("NNE"))?.reported == false)
        #expect(WeatherPresentation.bearingDegrees(.cardinal("NNE"), principalOnly: true) == nil)
        #expect(WeatherPresentation.bearingDegrees(.cardinal("SW"), principalOnly: true)?.degrees == 225)
        #expect(WeatherPresentation.bearingDegrees(.cardinal("nowhere")) == nil)
        #expect(WeatherPresentation.bearingDegrees(nil) == nil)
    }
}
