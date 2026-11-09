import Foundation
@testable import HassCore
import Testing
import HassTestSupport

@Suite(.demoHouse)
struct WeatherHighlightsTests {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!

    private var current: WeatherCurrent {
        WeatherCurrent(
            condition: "sunny", temperature: 70, apparentTemperature: 75, temperatureUnit: "°F", windSpeed: 9, windGustSpeed: 14,
            windSpeedUnit: "mph", windBearing: .degrees(250), pressure: 29.92, pressureUnit: "inHg", visibility: 10, visibilityUnit: "mi"
        )
    }

    private func tile(_ kind: WeatherHighlight.Kind, _ tiles: [WeatherHighlight]) throws -> WeatherHighlight {
        try #require(tiles.first { $0.kind == kind })
    }

    @Test func buildsTheTilesInWebOrder() {
        let sun = WeatherSunInput(state: "above_horizon", nextRising: "2026-09-06T13:00:00Z", nextSetting: "2026-09-06T02:30:00Z")
        let tiles = WeatherHighlights.tiles(current: current, today: WeatherForecast(uvIndex: 7), sun: sun, now: Date(timeIntervalSince1970: 1_788_611_400), timeZone: zone)
        #expect(tiles.map(\.kind) == [.feels, .uv, .wind, .sun, .visibility, .pressure])
        #expect(Set(tiles.map(\.id)).count == tiles.count)
    }

    @Test func omitsTheSunTileWithoutASunEntity() {
        let tiles = WeatherHighlights.tiles(current: current, today: nil, sun: nil)
        #expect(!tiles.contains { $0.kind == .sun })
    }

    @Test func feelsLikeAndUvCarryValuesStatusAndLabels() throws {
        let tiles = WeatherHighlights.tiles(current: current, today: WeatherForecast(uvIndex: 7.04), sun: nil)
        let feels = try tile(.feels, tiles)
        #expect(feels.value == "75°F")
        #expect(feels.available)
        #expect(feels.accessibilityLabel == "Feels Like 75°F")
        #expect(feels.tone == "warmer")
        let uv = try tile(.uv, tiles)
        #expect(uv.value == "7")
        #expect(uv.status == "High")
        #expect(uv.accessibilityLabel == "UV Index 7 High")
    }

    @Test func missingDataReadsUnavailable() throws {
        let tiles = WeatherHighlights.tiles(current: WeatherCurrent(), today: nil, sun: nil)
        for kind in [WeatherHighlight.Kind.feels, .uv, .visibility, .pressure] {
            let tile = try tile(kind, tiles)
            #expect(!tile.available)
            #expect(tile.value == "--")
            #expect(tile.accessibilityLabel.hasSuffix("Unavailable"))
        }
        let wind = try tile(.wind, tiles)
        #expect(!wind.available)
        #expect(wind.wind?.speedValue == "Unavailable")
    }

    @Test func windTileSpeaksSpeedGustAndDirection() throws {
        let wind = try tile(.wind, WeatherHighlights.tiles(current: current, today: nil, sun: nil))
        #expect(wind.value == "9 mph")
        #expect(wind.accessibilityLabel == "Wind 9 mph; Gusts 14 mph; From west-southwest, 250 degrees")
        #expect(wind.wind?.directionValue == "WSW · 250°")
        #expect(wind.wind?.showVector == true)
        #expect(wind.wind?.bearingDegrees == 250)
        #expect(wind.wind?.destinationDegrees == 70)
        #expect(wind.wind?.gustIsForecast == false)
    }

    @Test func windTileFallsBackToTodaysGustAndHandlesCalm() throws {
        var noGust = current
        noGust.windGustSpeed = nil
        let forecastGust = try tile(.wind, WeatherHighlights.tiles(current: noGust, today: WeatherForecast(windGustSpeed: 22), sun: nil))
        #expect(forecastGust.wind?.gustIsForecast == true)
        #expect(forecastGust.wind?.gustLabel == "Today's gust")
        #expect(forecastGust.wind?.gustValue == "22 mph")

        var calm = current
        calm.windSpeed = 0
        calm.windGustSpeed = nil
        let calmTile = try tile(.wind, WeatherHighlights.tiles(current: calm, today: nil, sun: nil))
        #expect(calmTile.wind?.directionLabel == "Direction")
        #expect(calmTile.wind?.directionValue == "Calm")
        #expect(calmTile.wind?.showVector == false)
        #expect(calmTile.wind?.bearingDegrees == nil)
        #expect(calmTile.accessibilityLabel == "Wind 0 mph; Gusts Unavailable; Direction Calm")

        var cardinal = current
        cardinal.windBearing = .cardinal("WNW")
        let named = try tile(.wind, WeatherHighlights.tiles(current: cardinal, today: nil, sun: nil))
        #expect(named.wind?.directionValue == "WNW")
        #expect(named.accessibilityLabel.hasSuffix("From west-northwest"))

        var noBearing = current
        noBearing.windBearing = nil
        let undirected = try tile(.wind, WeatherHighlights.tiles(current: noBearing, today: nil, sun: nil))
        #expect(undirected.wind?.directionLabel == "Direction")
        #expect(undirected.wind?.directionValue == "Unavailable")
    }

    @Test func sunTileShowsTheNextEventAndDaylightProgress() throws {
        let sunset = "2026-09-05T19:30:00Z"
        let sun = WeatherSunInput(state: "above_horizon", nextRising: "2026-09-06T13:00:00Z", nextSetting: sunset)
        let now = HassDates.iso8601("2026-09-05T18:00:00Z")!
        let tile = try tile(.sun, WeatherHighlights.tiles(current: current, today: nil, sun: sun, now: now, timeZone: zone))
        #expect(tile.title == "Sunset")
        #expect(tile.value == "12:30 PM")
        #expect((tile.percent ?? 0) > 70)
        let night = try self.tile(.sun, WeatherHighlights.tiles(current: current, today: nil, sun: WeatherSunInput(state: "below_horizon", nextRising: "2026-09-06T13:00:00Z", nextSetting: sunset), now: now, timeZone: zone))
        #expect(night.title == "Sunrise")
        #expect(night.percent == nil)
        let broken = try self.tile(.sun, WeatherHighlights.tiles(current: current, today: nil, sun: WeatherSunInput(state: "above_horizon", nextRising: nil, nextSetting: nil)))
        #expect(!broken.available)
        #expect(broken.title == "Sunset")
        #expect(broken.value == "--")
    }

    @Test func visibilityAndPressureTilesFormatReadings() throws {
        let tiles = WeatherHighlights.tiles(current: current, today: nil, sun: nil)
        let visibility = try tile(.visibility, tiles)
        #expect(visibility.value == "10 mi")
        #expect(visibility.percent == 100)
        let pressure = try tile(.pressure, tiles)
        #expect(pressure.value == "29.92 inHg")
        #expect(pressure.rotation != nil)
        #expect(pressure.tone == "typical")
        #expect(pressure.accessibilityLabel == "Pressure 29.92 inHg")
    }

    @Test func airQualityTile() {
        let moderate = WeatherHighlights.airQuality(state: "72")
        #expect(moderate.value == "72")
        #expect(moderate.status == "Moderate")
        #expect(moderate.accessibilityLabel == "Outdoor air quality 72, Moderate")
        #expect(moderate.tone == "moderate")
        #expect(moderate.title == "Air Quality")
        let broken = WeatherHighlights.airQuality(state: "unavailable")
        #expect(!broken.available)
        #expect(broken.value == "--")
        #expect(broken.status == "Unavailable")
        #expect(broken.accessibilityLabel == "Outdoor air quality unavailable")
        #expect(broken.tone == "unavailable")
        #expect(WeatherHighlights.airQuality(state: nil).available == false)
    }

    @Test func weekRailsPositionDaysInsideTheWeeksSpan() throws {
        let week = [
            WeatherForecast(temperature: 80, templow: 60), WeatherForecast(temperature: 70, templow: 50),
            WeatherForecast(temperature: 90, templow: 70), WeatherForecast(temperature: 55, templow: 60),
        ]
        let today = try #require(WeatherRails.week(forecast: week[0], all: week, currentTemperature: 70, index: 0))
        #expect(today.rangeStartPercent == 25)
        #expect(today.rangeSizePercent == 50)
        #expect(today.markerPercent == 50)
        let tomorrow = try #require(WeatherRails.week(forecast: week[1], all: week, currentTemperature: 70, index: 1))
        #expect(tomorrow.rangeStartPercent == 0)
        #expect(tomorrow.markerPercent == nil)
        // High below low is not a usable range.
        #expect(WeatherRails.week(forecast: week[3], all: week, currentTemperature: 70, index: 3) == nil)
        #expect(WeatherRails.week(forecast: WeatherForecast(), all: week, currentTemperature: nil, index: 0) == nil)
        #expect(WeatherRails.week(forecast: week[0], all: [], currentTemperature: nil, index: 0) == nil)
    }

    @Test func weekRailsHandleAFlatWeek() {
        let flat = [WeatherForecast(temperature: 70, templow: 70)]
        #expect(WeatherRails.week(forecast: flat[0], all: flat, currentTemperature: 60, index: 0)?.markerPercent == 0)
        #expect(WeatherRails.week(forecast: flat[0], all: flat, currentTemperature: 80, index: 0)?.markerPercent == 100)
        #expect(WeatherRails.week(forecast: flat[0], all: flat, currentTemperature: 70, index: 0)?.markerPercent == 50)
        #expect(WeatherRails.week(forecast: flat[0], all: flat, currentTemperature: nil, index: 0)?.markerPercent == nil)
        #expect(WeatherRails.week(forecast: flat[0], all: flat, currentTemperature: 70, index: 0)?.rangeStartPercent == 50)
    }

    @Test func heroRailSpansTheTrackWithTheCurrentTemperature() throws {
        let rail = try #require(WeatherRails.hero(forecast: WeatherForecast(temperature: 80, templow: 60), currentTemperature: 75))
        #expect(rail == WeatherRailRange(markerPercent: 75, rangeSizePercent: 100, rangeStartPercent: 0))
        #expect(WeatherRails.hero(forecast: WeatherForecast(temperature: 80, templow: 60), currentTemperature: 100)?.markerPercent == 100)
        #expect(WeatherRails.hero(forecast: WeatherForecast(temperature: 60, templow: 80), currentTemperature: 70) == nil)
        #expect(WeatherRails.hero(forecast: WeatherForecast(temperature: 70, templow: 70), currentTemperature: 70)?.markerPercent == 50)
        #expect(WeatherRails.hero(forecast: WeatherForecast(temperature: 70, templow: 70), currentTemperature: 10)?.markerPercent == 0)
    }
}
