import Foundation
@testable import HassCore
import Testing

struct WeatherFormatTests {
    private let utc = TimeZone(identifier: "UTC")!

    @Test func roundsHalvesUpLikeJavaScript() {
        #expect(WeatherFormat.integer(2.5) == "3")
        #expect(WeatherFormat.integer(-2.5) == "-2")
        #expect(WeatherFormat.integer(-0.4) == "0")
        #expect(WeatherFormat.integer(71.49) == "71")
    }

    @Test func formatsTemperatures() {
        #expect(WeatherFormat.temperature(71.6, unit: "°F") == "72°F")
        #expect(WeatherFormat.temperature(20, unit: "°C") == "20°C")
        #expect(WeatherFormat.temperature(20, unit: nil) == "20°F")
        #expect(WeatherFormat.temperature(20, unit: "  ") == "20°F")
        #expect(WeatherFormat.temperature(nil, unit: "°F") == "--")
        #expect(WeatherFormat.degree(70.4) == "70°")
        #expect(WeatherFormat.degree(nil) == "--")
    }

    @Test func formatsNumbersAndMeasures() {
        #expect(WeatherFormat.number(1234.5) == "1,235")
        #expect(WeatherFormat.number(1234.5, digits: 1) == "1,234.5")
        #expect(WeatherFormat.number(0.1 + 0.2, digits: 2) == "0.3")
        #expect(WeatherFormat.number(nil) == nil)
        #expect(WeatherFormat.number(.infinity) == nil)
        #expect(WeatherFormat.percent(44.6) == "45%")
        #expect(WeatherFormat.measure(29.923, unit: "inHg", digits: 2) == "29.92 inHg")
        #expect(WeatherFormat.measure(5, unit: nil) == "5")
        #expect(WeatherFormat.measure(nil, unit: "in") == nil)
    }

    @Test func formatsWindSpeedsAndRanges() {
        #expect(WeatherFormat.windMeasure(0.4, unit: "mph")?.value == "<1 mph")
        #expect(WeatherFormat.windMeasure(0, unit: "mph")?.value == "0 mph")
        #expect(WeatherFormat.windMeasure(12.4, unit: nil)?.value == "12 mph")
        #expect(WeatherFormat.windMeasure(-1, unit: "mph") == nil)
        #expect(WeatherFormat.windRange(speed: 8, gust: 15, unit: "mph") == "8-15 mph")
        #expect(WeatherFormat.windRange(speed: 8, gust: 8.2, unit: "mph") == "8 mph")
        #expect(WeatherFormat.windRange(speed: nil, gust: 15, unit: "mph") == "15 mph")
        #expect(WeatherFormat.windRange(speed: 8, gust: nil, unit: "mph") == "8 mph")
        #expect(WeatherFormat.windRange(speed: nil, gust: nil, unit: "mph") == "--")
    }

    @Test func labelsDaysAndHours() {
        #expect(WeatherFormat.dayLabel("2026-09-05T00:00:00Z", index: 0, timeZone: utc) == "Today")
        #expect(WeatherFormat.dayLabel("2026-09-06T00:00:00Z", index: 1, timeZone: utc) == "Sun")
        #expect(WeatherFormat.dayLabel(nil, index: 0) == "Today")
        #expect(WeatherFormat.dayLabel(nil, index: 2) == "Day 3")
        #expect(WeatherFormat.dayLabel("garbage", index: 3) == "Day 4")
        #expect(WeatherFormat.hourLabel("2026-09-05T19:00:00Z", index: 0, timeZone: utc) == "Now")
        #expect(WeatherFormat.hourLabel("2026-09-05T19:00:00Z", index: 1, timeZone: utc) == "7 PM")
        #expect(WeatherFormat.hourLabel("2026-09-05T00:00:00Z", index: 5, timeZone: utc) == "12 AM")
        #expect(WeatherFormat.hourLabel(nil, index: 4) == "4h")
        #expect(WeatherFormat.hourLabel("junk", index: 4) == "4h")
    }

    @Test func buildsHighLowLabels() {
        let both = WeatherForecast(temperature: 72.4, templow: 55)
        #expect(WeatherFormat.compactHighLow(both) == "H:72°  L:55°")
        #expect(WeatherFormat.compactHighLow(WeatherForecast(temperature: 72)) == "H:72°")
        #expect(WeatherFormat.compactHighLow(WeatherForecast(templow: 50)) == "L:50°")
        #expect(WeatherFormat.compactHighLow(WeatherForecast()) == "")
        #expect(WeatherFormat.compactHighLow(nil) == "")
        #expect(WeatherFormat.modalHighLow(both) == "High: 72°  Low: 55°")
        #expect(WeatherFormat.modalHighLow(WeatherForecast(temperature: 72)) == "High: 72°")
        #expect(WeatherFormat.modalHighLow(WeatherForecast(templow: 50)) == "Low: 50°")
        #expect(WeatherFormat.modalHighLow(WeatherForecast()) == "")
        #expect(WeatherFormat.modalHighLow(nil) == "")
    }

    @Test func parsesDatesWithAndWithoutFractions() {
        #expect(HassDates.iso8601("2026-09-05T12:00:00+00:00") == HassDates.iso8601("2026-09-05T12:00:00.000Z"))
        #expect(HassDates.iso8601("2026-09-05T05:00:00-07:00") == HassDates.iso8601("2026-09-05T12:00:00Z"))
        #expect(HassDates.iso8601("") == nil)
        #expect(HassDates.iso8601("tomorrow") == nil)
    }

    @Test func keysTheLocalDay() {
        let la = TimeZone(identifier: "America/Los_Angeles")!
        let instant = HassDates.iso8601("2026-01-15T00:30:00Z")!
        #expect(WeatherDates.dateKey(instant, in: utc) == "2026-01-15")
        #expect(WeatherDates.dateKey(instant, in: la) == "2026-01-14")
        #expect(WeatherDates.parts(instant, in: la) == .init(year: 2026, month: 1, day: 14, hour: 16, minute: 30))
        #expect(WeatherDates.clock(instant, in: la) == "4:30 PM")
        #expect(WeatherDates.hour(instant, in: la) == "4 PM")
    }

    @Test func conditionInfoLabelsKnownAndUnknownConditions() {
        #expect(WeatherConditionInfo("partlycloudy").label == "Partly Cloudy")
        #expect(WeatherConditionInfo("lightning-rainy").label == "Storms")
        #expect(WeatherConditionInfo("pouring").label == "Heavy Rain")
        #expect(WeatherConditionInfo("sunny").icon == "mdi:weather-sunny")
        #expect(WeatherConditionInfo(nil).label == "Weather Unavailable")
        #expect(WeatherConditionInfo("").icon == "mdi:alert-circle")
        #expect(WeatherConditionInfo("heavy-snow_showers").label == "Heavy Snow Showers")
        #expect(WeatherConditionInfo("heavy-snow").icon == "mdi:cloud")
        #expect(WeatherConditionInfo.isKnown("rainy"))
        #expect(!WeatherConditionInfo.isKnown("heavy-snow"))
        #expect(!WeatherConditionInfo.isKnown(nil))
    }

    @Test func everyKnownConditionHasALabel() {
        for condition in WeatherConditionInfo.icons.keys {
            #expect(WeatherCopy.has("condition.\(condition)"), "missing label for \(condition)")
            #expect(WeatherCopy.has("briefing.phrase.\(condition)"), "missing phrase for \(condition)")
        }
    }

    @Test func copyFillsPlaceholdersAndPlurals() {
        #expect(WeatherCopy.text("subtitle", ["temperature": "72°", "condition": "Sunny"]) == "72° · Sunny")
        #expect(WeatherCopy.text("briefing.sun.daylightWhole", ["count": "1", "sunrise": "7 AM", "sunset": "8 AM"]).contains("1 hour of daylight"))
        #expect(WeatherCopy.text("briefing.sun.daylightWhole", ["count": "10", "sunrise": "7 AM", "sunset": "8 AM"]).contains("10 hours of daylight"))
        #expect(WeatherCopy.text("not.a.key") == "not.a.key")
        #expect(WeatherCopy.forecastFailure(.daily) == "Unable to load Pirate Weather forecast.")
        #expect(WeatherCopy.forecastFailure(.hourly) == "Unable to load Pirate Weather hourly forecast.")
    }
}
