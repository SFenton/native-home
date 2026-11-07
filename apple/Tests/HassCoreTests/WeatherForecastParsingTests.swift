import Foundation
@testable import HassCore
import HassTestSupport
import Testing

@Suite(.demoHouse)
struct WeatherForecastParsingTests {
    private let entityId = "weather.demo_weather_1"

    private func response(_ forecast: [JSONValue]) -> JSONValue {
        .object([entityId: .object(["forecast": .array(forecast)])])
    }

    @Test func readsEveryFieldOfAForecastObject() {
        let forecast = WeatherForecast(json: [
            "apparent_temperature": .number(70.5), "cloud_coverage": .number(40), "condition": .string("partlycloudy"),
            "datetime": .string("2026-09-05T12:00:00+00:00"), "dew_point": .number(50), "humidity": .number(55),
            "precipitation": .number(0.02), "precipitation_probability": .number(30), "pressure": .number(1012),
            "temperature": .number(72), "templow": .number(58), "uv_index": .number(6), "wind_bearing": .number(250),
            "wind_gust_speed": .number(20), "wind_speed": .number(9),
        ])
        #expect(forecast == WeatherForecast(
            datetime: "2026-09-05T12:00:00+00:00", condition: "partlycloudy", temperature: 72, templow: 58, apparentTemperature: 70.5,
            cloudCoverage: 40, dewPoint: 50, humidity: 55, precipitation: 0.02, precipitationProbability: 30, pressure: 1012,
            uvIndex: 6, windBearing: .degrees(250), windGustSpeed: 20, windSpeed: 9
        ))
        #expect(forecast.start == HassDates.iso8601("2026-09-05T12:00:00Z"))
    }

    @Test func acceptsNumericStringsAndIgnoresJunk() {
        let forecast = WeatherForecast(json: [
            "temperature": .string(" 72.5 "), "humidity": .string("n/a"), "templow": .bool(true), "wind_bearing": .string("NW"),
            "condition": .number(3), "datetime": .null,
        ])
        #expect(forecast.temperature == 72.5)
        #expect(forecast.humidity == nil)
        #expect(forecast.templow == nil)
        #expect(forecast.windBearing == .cardinal("NW"))
        #expect(forecast.condition == nil)
        #expect(forecast.datetime == nil)
        #expect(forecast.start == nil)
    }

    @Test func roundTripsThroughCodable() throws {
        let original = WeatherForecast(
            datetime: "2026-09-05T12:00:00+00:00", condition: "rainy", temperature: 61.5, templow: 50, apparentTemperature: 59,
            cloudCoverage: 90, dewPoint: 48, humidity: 80, precipitation: 0.1, precipitationProbability: 70, pressure: 1005,
            uvIndex: 2, windBearing: .cardinal("SSW"), windGustSpeed: 18, windSpeed: 11
        )
        let data = try JSONEncoder().encode([original, WeatherForecast(windBearing: .degrees(90))])
        let decoded = try JSONDecoder().decode([WeatherForecast].self, from: data)
        #expect(decoded == [original, WeatherForecast(windBearing: .degrees(90))])
    }

    @Test func bearingsReadFromAttributes() {
        #expect(WeatherWindBearing(json: .number(10)) == .degrees(10))
        #expect(WeatherWindBearing(json: .string("N")) == .cardinal("N"))
        #expect(WeatherWindBearing(json: .string("  ")) == nil)
        #expect(WeatherWindBearing(json: .number(.nan)) == nil)
        #expect(WeatherWindBearing(json: .bool(true)) == nil)
        #expect(WeatherWindBearing(json: nil) == nil)
    }

    @Test func extractsAndLimitsForecasts() throws {
        let many = (0..<40).map { JSONValue.object(["temperature": .number(Double($0))]) }
        let daily = try WeatherForecast.extract(from: response(many), entityId: entityId, kind: .daily)
        let hourly = try WeatherForecast.extract(from: response(many), entityId: entityId, kind: .hourly)
        #expect(daily.count == 7)
        #expect(hourly.count == 24)
        #expect(daily.last?.temperature == 6)
        #expect(WeatherForecastKind.daily.limit == 7 && WeatherForecastKind.hourly.limit == 24)
    }

    @Test func dropsNonObjectEntriesBeforeLimiting() throws {
        let mixed: [JSONValue] = [.null, .string("x"), .object(["temperature": .number(1)]), .number(4), .object(["temperature": .number(2)])]
        let result = try WeatherForecast.extract(from: response(mixed), entityId: entityId, kind: .hourly)
        #expect(result.map(\.temperature) == [1, 2])
    }

    @Test func unwrapsServiceResponse() throws {
        let wrapped = JSONValue.object(["service_response": response([.object(["temperature": .number(75)])])])
        #expect(try WeatherForecast.extract(from: wrapped, entityId: entityId, kind: .daily).first?.temperature == 75)
        // A null wrapper falls through to the object itself, like `??`.
        let nullWrapped = JSONValue.object(["service_response": .null, entityId: .object(["forecast": .array([.object(["temperature": .number(3)])])])])
        #expect(try WeatherForecast.extract(from: nullWrapped, entityId: entityId, kind: .daily).first?.temperature == 3)
    }

    @Test(arguments: [JSONValue.null, .array([]), .string("x"), .object([:]), .object(["weather.demo_other": .object([:])]),
                      .object(["weather.demo_weather_1": .object(["forecast": .string("none")])])])
    func rejectsMalformedEnvelopes(value: JSONValue) {
        #expect(throws: WeatherForecastError.self) { try WeatherForecast.extract(from: value, entityId: entityId, kind: .daily) }
        do {
            _ = try WeatherForecast.extract(from: value, entityId: entityId, kind: .hourly)
        } catch {
            #expect((error as? WeatherForecastError)?.message == "Unable to load Pirate Weather hourly forecast.")
            #expect((error as? LocalizedError)?.errorDescription == "Unable to load Pirate Weather hourly forecast.")
        }
    }

    @Test func currentConditionsReadTheEntity() {
        let entity = EntityState(entityId: "weather.demo_weather_1", state: "partlycloudy", attributes: [
            "temperature": .number(71.6), "apparent_temperature": .number(73), "temperature_unit": .string("°F"), "humidity": .number(40),
            "wind_speed": .number(9), "wind_gust_speed": .number(14), "wind_speed_unit": .string("mph"), "wind_bearing": .number(200),
            "pressure": .number(29.9), "pressure_unit": .string("inHg"), "visibility": .number(10), "visibility_unit": .string("mi"),
            "precipitation_unit": .string("in"),
        ])
        let current = WeatherCurrent(entity: entity)
        #expect(current.condition == "partlycloudy")
        #expect(current.temperatureText == "72°F")
        #expect(current.degreeText == "72°")
        #expect(current.conditionLabel == "Partly Cloudy")
        #expect(current.windBearing == .degrees(200))
        #expect(current.drawnCondition == "partlycloudy")

        let missing = WeatherCurrent(entity: nil)
        #expect(missing.temperatureText == "--")
        #expect(missing.conditionLabel == "Weather Unavailable")
        let unavailable = WeatherCurrent(entity: EntityState(entityId: "weather.demo_weather_1", state: "unavailable"))
        #expect(unavailable.conditionLabel == "Weather Unavailable")
        #expect(unavailable.drawnCondition == nil)
        #expect(WeatherCurrent(entity: EntityState(entityId: "weather.demo_x", state: "")).condition == nil)
    }

    @Test func sunInputReadsTheSunEntity() {
        #expect(WeatherSunInput(entity: nil) == nil)
        let sun = WeatherSunInput(entity: EntityState(entityId: "sun.sun", state: "below_horizon", attributes: [
            "next_rising": .string("2026-09-06T13:00:00+00:00"), "next_setting": .string("2026-09-06T02:00:00+00:00"),
        ]))
        #expect(sun?.isNight == true)
        #expect(sun?.nextRising == "2026-09-06T13:00:00+00:00")
        #expect(WeatherSunInput(state: "above_horizon", nextRising: nil, nextSetting: nil).isNight == false)
    }

    @Test func briefingContextCollectsUnitsAndSun() {
        let current = WeatherCurrent(temperatureUnit: "°C", windSpeedUnit: "km/h", precipitationUnit: "mm")
        let sun = WeatherSunInput(state: "above_horizon", nextRising: "r", nextSetting: "s")
        let context = WeatherBriefingContext(current: current, aqiState: " 42 ", sun: sun)
        #expect(context == WeatherBriefingContext(aqi: 42, precipitationUnit: "mm", sunrise: "r", sunset: "s", temperatureUnit: "°C", windSpeedUnit: "km/h"))
        #expect(WeatherBriefingContext(current: current, aqiState: "unavailable", sun: nil).aqi == nil)
    }
}
