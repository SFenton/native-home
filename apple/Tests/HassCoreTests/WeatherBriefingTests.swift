import Foundation
@testable import HassCore
import Testing

/// Ported from `weatherDayBriefing.test.ts` and a seeded slice of `weatherDayBriefing.simulation.test.ts`
/// (`ha-sfenton-react-dash@f5a7bf9`).
struct WeatherBriefingTests {
    static let zone = TimeZone(identifier: "America/Los_Angeles")!

    private func day(_ date: String, _ hours: [(hour: Int, forecast: WeatherForecast)]) -> [WeatherForecast] {
        hours.map { hour, forecast in
            var entry = forecast
            entry.datetime = String(format: "%@T%02d:00:00-08:00", date, hour)
            return entry
        }
    }

    private func steadyDay(_ condition: String, temperature: Double = 50, windSpeed: Double = 4, _ tweak: (inout WeatherForecast) -> Void = { _ in }) -> [WeatherForecast] {
        day("2026-01-15", (0..<24).map { hour in
            var forecast = WeatherForecast(condition: condition, temperature: temperature, precipitation: 0, precipitationProbability: 0, windSpeed: windSpeed)
            tweak(&forecast)
            return (hour, forecast)
        })
    }

    private func generate(
        hourly: [WeatherForecast] = [], daily: [WeatherForecast] = [], generatedAt: String = "2026-01-15T00:01:00-08:00",
        precipitationUnit: String? = "in", temperatureUnit: String? = "°F", windSpeedUnit: String? = "mph",
        sunrise: String? = nil, sunset: String? = nil, aqi: Double? = nil
    ) -> WeatherDayBriefing {
        WeatherDayBriefingGenerator.generate(WeatherDayBriefingInput(
            aqi: aqi, daily: daily, generatedAt: HassDates.iso8601(generatedAt)!, hourly: hourly,
            precipitationUnit: precipitationUnit, sunrise: sunrise, sunset: sunset, temperatureUnit: temperatureUnit,
            timeZone: Self.zone, windSpeedUnit: windSpeedUnit
        ))
    }

    private func text(_ briefing: WeatherDayBriefing) -> String { WeatherBriefingRenderer.text(briefing) }

    @Test func describesACalmSunnyDay() {
        let briefing = generate(
            hourly: steadyDay("sunny", temperature: 62, windSpeed: 7),
            sunrise: "2026-01-15T07:12:00-08:00", sunset: "2026-01-15T17:04:00-08:00"
        )
        let sentence = text(briefing)
        #expect(briefing.severity == .calm)
        #expect(briefing.hazard == nil)
        #expect(WeatherBriefingRenderer.headline(briefing) == "Sunny")
        #expect(briefing.icon == "mdi:weather-sunny")
        #expect(sentence.contains("Expect full sun for most of the day."))
        #expect(sentence.contains("62°"))
        #expect(sentence.contains("Sunrise is at 7:12 AM and sunset at 5:04 PM"))
        #expect(!sentence.contains("undefined"))
        #expect(!sentence.contains("NaN"))
    }

    @Test func neverRepeatsTheOldBulletFormat() {
        #expect(!text(generate(hourly: steadyDay("cloudy"))).contains(" · "))
    }

    @Test func narratesMorningRainThatClears() {
        let hours = day("2026-01-15", (0..<24).map { hour in
            (hour, WeatherForecast(
                condition: hour < 12 ? "rainy" : hour < 17 ? "cloudy" : "partlycloudy",
                temperature: 48 + Double(hour) * 0.4, precipitation: hour < 12 ? 0.08 : 0,
                precipitationProbability: hour < 12 ? 80 : 10, windSpeed: 8
            ))
        })
        let sentence = text(generate(hourly: hours))
        #expect(sentence.contains("The day opens with steady rain"))
        #expect(sentence.range(of: #"Look for rain (through the morning|before|between)"#, options: .regularExpression) != nil)
        #expect(sentence.contains("80%"))
    }

    @Test func leadsWithAHazardHeadlineAndIcon() {
        let hours = day("2026-01-15", (0..<24).map { hour in
            let storm = hour >= 14 && hour <= 18
            return (hour, WeatherForecast(
                condition: storm ? "lightning-rainy" : "cloudy", temperature: 74, precipitation: storm ? 0.2 : 0,
                precipitationProbability: storm ? 90 : 20, windGustSpeed: 38, windSpeed: 14
            ))
        })
        let briefing = generate(hourly: hours)
        #expect(briefing.hazard == .severeStorms)
        #expect(briefing.severity == .alert)
        #expect(briefing.icon == "mdi:weather-lightning")
        #expect(WeatherBriefingRenderer.headline(briefing) == "Severe Storms")
        #expect(briefing.sentences.count == 4)
        #expect(text(briefing).hasSuffix("Winds near 14 mph gust to 38 mph."))
    }

    @Test func prefersTheMostSevereHazard() {
        let hours = day("2026-01-15", (0..<24).map { hour in
            (hour, WeatherForecast(
                condition: hour < 10 ? "snowy" : "cloudy", temperature: 24, apparentTemperature: 14, precipitation: hour < 10 ? 0.12 : 0,
                precipitationProbability: hour < 10 ? 95 : 10, uvIndex: 9, windGustSpeed: 33, windSpeed: 18
            ))
        })
        let briefing = generate(hourly: hours)
        #expect(briefing.hazard == .heavySnow)
        #expect(WeatherBriefingRenderer.headline(briefing) == "Heavy Snow")
        #expect(briefing.icon == "mdi:weather-snowy-heavy")
    }

    @Test func reportsDamagingWindInNativeUnits() {
        let briefing = generate(hourly: steadyDay("windy", temperature: 58, windSpeed: 26) { $0.windGustSpeed = 52 })
        let sentence = text(briefing)
        #expect(briefing.hazard == .damagingWind)
        #expect(sentence.contains("52 mph"))
        #expect(sentence.contains("gust to 52 mph"))
    }

    @Test func convertsMetricInputsWhenClassifyingHazards() {
        let briefing = generate(
            hourly: steadyDay("sunny", temperature: 39, windSpeed: 6) { $0.apparentTemperature = 41 },
            precipitationUnit: "mm", temperatureUnit: "°C", windSpeedUnit: "km/h"
        )
        #expect(briefing.hazard == .extremeHeat)
        #expect(WeatherBriefingRenderer.headline(briefing) == "Extreme Heat")
    }

    @Test func saysNothingIsComingOnADryDay() {
        #expect(text(generate(hourly: steadyDay("partlycloudy"))).contains("No meaningful rain is expected."))
    }

    @Test func fallsBackToTheDailyForecastWithoutHourlyData() {
        let briefing = generate(daily: [
            WeatherForecast(datetime: "2026-01-15T00:00:00-08:00", condition: "rainy", temperature: 55, templow: 44, precipitation: 0.5, precipitationProbability: 70, windSpeed: 9),
        ])
        #expect(briefing.condition == "rainy")
        #expect(text(briefing).contains("55°"))
    }

    @Test func reportsThePendingStateWhenNothingCameBack() {
        let briefing = generate(hourly: [], daily: [])
        #expect(briefing.sentences.count == 1)
        #expect(text(briefing).contains("Pirate Weather"))
        #expect(briefing.icon == "mdi:cloud-question")
        #expect(briefing.severity == .calm)
        #expect(briefing.headline == nil)
    }

    @Test func keysTheBriefingToTheLocalDayAcrossSpringForward() {
        let hours = day("2026-03-08", [(1, WeatherForecast(condition: "sunny", temperature: 44)), (13, WeatherForecast(condition: "sunny", temperature: 61))])
        let briefing = generate(
            hourly: hours, generatedAt: "2026-03-08T00:01:00-08:00",
            sunrise: "2026-03-08T07:16:00-07:00", sunset: "2026-03-08T19:04:00-07:00"
        )
        #expect(briefing.dateKey == "2026-03-08")
        #expect(text(briefing).contains("of daylight"))
    }

    @Test func pullsTomorrowsNextRisingBackOntoTheBriefingDay() {
        let briefing = generate(
            hourly: steadyDay("sunny"), generatedAt: "2026-01-15T14:00:00-08:00",
            sunrise: "2026-01-16T07:11:00-08:00", sunset: "2026-01-15T17:05:00-08:00"
        )
        #expect(text(briefing).contains("Sunrise is at 7:11 AM"))
    }

    @Test func isDeterministicAndRoundTripsThroughJSON() throws {
        let hours = steadyDay("rainy") { $0.precipitation = 0.05; $0.precipitationProbability = 60 }
        let first = generate(hourly: hours)
        #expect(first == generate(hourly: hours))
        let decoded = try JSONDecoder().decode(WeatherDayBriefing.self, from: JSONEncoder().encode(first))
        #expect(decoded == first)
        #expect(text(decoded) == text(first))
    }

    @Test func unknownProviderConditionsGetALiteralHeadline() {
        let briefing = generate(hourly: steadyDay("heavy-snow"))
        #expect(briefing.headline == nil)
        #expect(briefing.headlineText == "Heavy Snow")
        #expect(WeatherBriefingRenderer.headline(briefing) == "Heavy Snow")
        // Unknown conditions read as overcast in the narrative.
        #expect(text(briefing).contains("overcast skies"))
    }

    @Test func poorAirQualityBecomesTheHeadlineAndEscalatesAbove200() {
        let moderate = generate(hourly: steadyDay("sunny"), aqi: 150)
        #expect(moderate.hazard == .poorAir)
        #expect(moderate.severity == .caution)
        #expect(WeatherBriefingRenderer.headline(moderate) == "Poor Air Quality")
        #expect(generate(hourly: steadyDay("sunny"), aqi: 250).severity == .alert)
        #expect(generate(hourly: steadyDay("sunny"), aqi: 80).hazard == nil)
    }

    @Test func calmHazardsKeepTheConditionHeadline() {
        let hot = generate(hourly: steadyDay("sunny", temperature: 92))
        #expect(hot.hazard == .heat)
        #expect(hot.severity == .notable)
        #expect(WeatherBriefingRenderer.headline(hot) == "Sunny")
        #expect(hot.icon == "mdi:weather-sunny")
        let uv = generate(hourly: steadyDay("sunny", temperature: 70) { $0.uvIndex = 9 })
        #expect(uv.hazard == .highUv)
    }

    @Test func coversTheTemperatureSentenceVariants() {
        // Peaks early then slides.
        let falling = day("2026-01-15", (0..<24).map { hour in (hour, WeatherForecast(condition: "cloudy", temperature: hour < 9 ? 60 : 45)) })
        #expect(text(generate(hourly: falling)).contains("Temperatures peak near 60° early, then slide toward 45°"))
        // Wide range.
        let range = day("2026-01-15", (0..<24).map { hour in (hour, WeatherForecast(condition: "cloudy", temperature: hour == 15 ? 70 : 50)) })
        #expect(text(generate(hourly: range)).contains("Highs reach 70° before falling back to 50° overnight."))
        // Feels warmer / cooler / wind chill.
        let warmer = day("2026-01-15", (0..<24).map { hour in (hour, WeatherForecast(condition: "cloudy", temperature: 80, apparentTemperature: hour == 15 ? 90 : 80)) })
        #expect(text(generate(hourly: warmer)).contains("feel closer to 90°"))
        let cooler = day("2026-01-15", (0..<24).map { hour in (hour, WeatherForecast(condition: "cloudy", temperature: hour == 15 ? 50 : 40, apparentTemperature: hour == 15 ? 40 : 40)) })
        #expect(text(generate(hourly: cooler)).contains("feels more like 40°"))
        let chill = day("2026-01-15", (0..<24).map { hour in (hour, WeatherForecast(condition: "cloudy", temperature: 40, apparentTemperature: hour == 3 ? 30 : 40)) })
        #expect(text(generate(hourly: chill)).contains("feel closer to 30° in the wind"))
        // Only one end known.
        let single = generate(daily: [WeatherForecast(datetime: "2026-01-15T00:00:00-08:00", condition: "sunny", temperature: 66)])
        #expect(text(single).contains("Temperatures stay near 66°."))
    }

    @Test func coversTheWindSentenceVariants() {
        #expect(text(generate(hourly: steadyDay("sunny", windSpeed: 3))).contains("Winds stay light all day."))
        let steady = steadyDay("sunny", windSpeed: 12) { $0.windBearing = .degrees(270) }
        #expect(text(generate(hourly: steady)).contains("Winds run out of the west near 12 mph."))
        let undirected = steadyDay("sunny", windSpeed: 12)
        #expect(text(generate(hourly: undirected)).contains("Winds run near 12 mph."))
        let gustyDirected = steadyDay("sunny", windSpeed: 10) { $0.windGustSpeed = 25; $0.windBearing = .cardinal("SW") }
        #expect(text(generate(hourly: gustyDirected)).contains("Winds out of the southwest near 10 mph gust to 25 mph."))
        let gustsOnly = generate(daily: [WeatherForecast(datetime: "2026-01-15T00:00:00-08:00", condition: "sunny", temperature: 60, windGustSpeed: 20)])
        #expect(text(gustsOnly).contains("Gusts reach 20 mph."))
        // Units convert back for display.
        let metric = steadyDay("sunny", windSpeed: 20) { $0.windGustSpeed = 40 }
        #expect(text(generate(hourly: metric, windSpeedUnit: "km/h")).contains("Winds near 20 km/h gust to 40 km/h."))
    }

    @Test func coversThePrecipitationSentenceVariants() {
        let slight = steadyDay("cloudy") { $0.precipitationProbability = 25 }
        #expect(text(generate(hourly: slight)).contains("Only a slight chance of rain, peaking near 25%."))
        let allDay = steadyDay("rainy") { $0.precipitationProbability = 60; $0.precipitation = 0.1 }
        #expect(text(generate(hourly: allDay)).contains("on and off through the day, with chances near 60% and about 2.4 in adding up."))
        let allDayDry = steadyDay("rainy") { $0.precipitationProbability = 60 }
        #expect(text(generate(hourly: allDayDry)).contains("Expect rain on and off through the day, with chances near 60%."))
        let snowy = steadyDay("cloudy", temperature: 25) { $0.precipitationProbability = 5 }
        #expect(text(generate(hourly: snowy)).contains("No meaningful snow is expected."))
        let mix = steadyDay("cloudy", temperature: 33) { $0.precipitationProbability = 5 }
        #expect(text(generate(hourly: mix)).contains("No meaningful a wintry mix is expected."))
        // Evening window and "around" a single hour.
        let evening = day("2026-01-15", (0..<24).map { hour in
            (hour, WeatherForecast(condition: hour >= 18 && hour <= 20 ? "rainy" : "cloudy", temperature: 50, precipitation: hour >= 18 && hour <= 20 ? 0.05 : 0, precipitationProbability: hour >= 18 && hour <= 20 ? 70 : 0))
        })
        #expect(text(generate(hourly: evening)).contains("Look for rain in the evening, with chances near 70%"))
        let single = day("2026-01-15", (0..<24).map { hour in
            (hour, WeatherForecast(condition: hour == 9 ? "rainy" : "cloudy", temperature: 50, precipitation: 0, precipitationProbability: hour == 9 ? 70 : 0))
        })
        #expect(text(generate(hourly: single)).contains("Look for rain around 9 AM"))
        // Metric amounts.
        let metric = steadyDay("rainy") { $0.precipitationProbability = 60; $0.precipitation = 0.5 }
        #expect(text(generate(hourly: metric, precipitationUnit: "mm", temperatureUnit: "°C")).contains("about 12 mm adding up."))
    }

    @Test func coversTheOverviewVariants() {
        let three = day("2026-01-15", (0..<24).map { hour in
            (hour, WeatherForecast(condition: hour < 12 ? "fog" : hour < 17 ? "sunny" : "cloudy", temperature: 50))
        })
        #expect(text(generate(hourly: three)).contains("The day opens with fog, shifts to full sun, and settles into overcast skies."))
        let worsening = day("2026-01-15", (0..<24).map { hour in
            (hour, WeatherForecast(condition: hour < 12 ? "sunny" : "cloudy", temperature: 50))
        })
        #expect(text(generate(hourly: worsening)).contains("The day opens with full sun, then turns to overcast skies."))
        let improving = day("2026-01-15", (0..<24).map { hour in
            (hour, WeatherForecast(condition: hour < 12 ? "cloudy" : "sunny", temperature: 50))
        })
        #expect(text(generate(hourly: improving)).contains("then eases into full sun"))
    }

    @Test func plannerWritesOncePerDayAtOrAfterOneMinutePastMidnight() {
        let hourly = steadyDay("sunny")
        let current = generate(hourly: hourly)
        let now = HassDates.iso8601("2026-01-15T09:00:00-08:00")!
        #expect(!WeatherBriefingPlanner.shouldGenerate(current: current, now: now, timeZone: Self.zone, hourly: hourly, daily: []))
        let nextDay = HassDates.iso8601("2026-01-16T09:00:00-08:00")!
        let tomorrow = day("2026-01-16", [(8, WeatherForecast(condition: "sunny"))])
        #expect(WeatherBriefingPlanner.shouldGenerate(current: current, now: nextDay, timeZone: Self.zone, hourly: tomorrow, daily: []))
        // Before 00:01 an existing briefing is kept; the first ever is written at once.
        let midnight = HassDates.iso8601("2026-01-16T00:00:30-08:00")!
        #expect(!WeatherBriefingPlanner.shouldGenerate(current: current, now: midnight, timeZone: Self.zone, hourly: tomorrow, daily: []))
        #expect(WeatherBriefingPlanner.shouldGenerate(current: nil, now: midnight, timeZone: Self.zone, hourly: tomorrow, daily: []))
        // Needs forecast data for today.
        #expect(!WeatherBriefingPlanner.shouldGenerate(current: nil, now: nextDay, timeZone: Self.zone, hourly: hourly, daily: []))
        #expect(WeatherBriefingPlanner.shouldGenerate(current: nil, now: nextDay, timeZone: Self.zone, hourly: [], daily: [WeatherForecast(datetime: "2026-01-16T00:00:00-08:00")]))
        #expect(!WeatherBriefingPlanner.shouldGenerate(current: nil, now: nextDay, timeZone: Self.zone, hourly: [WeatherForecast()], daily: []))
    }

    // MARK: - Seeded fuzz

    private struct SeededRandom {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double((state >> 33) & 0xFFFFFF) / Double(0x1000000)
        }
        mutating func range(_ low: Double, _ high: Double) -> Double { low + next() * (high - low) }
        mutating func pick<T>(_ values: [T]) -> T { values[min(values.count - 1, Int(next() * Double(values.count)))] }
    }

    private static let conditions = [
        "clear-night", "cloudy", "exceptional", "fog", "hail", "lightning", "lightning-rainy", "partlycloudy", "pouring",
        "rainy", "snowy", "snowy-rainy", "sunny", "windy", "windy-variant", "meteor-shower",
    ]

    /// Every simulated day yields well-formed copy: no placeholders left, no "undefined", proper sentences.
    @Test func staysWellFormedAcrossSimulatedDays() {
        var rng = SeededRandom(state: 42)
        var severities = Set<WeatherBriefingSeverity>()
        var hazards = Set<WeatherHazard>()
        var narratives = Set<String>()
        for scenario in 0..<250 {
            let metric = rng.next() < 0.4
            let wind = rng.pick(["mph", "km/h", "m/s", "kn"])
            let sparse = rng.next() < 0.1
            let hourCount = sparse ? Int(rng.range(1, 5)) : 24
            let base = metric ? rng.range(-20, 38) : rng.range(-5, 100)
            let steady = rng.pick(Self.conditions)
            let chaotic = rng.next() < 0.5
            var hourly: [WeatherForecast] = []
            for index in 0..<hourCount {
                let hour = sparse ? Int(rng.range(0, 24)) : index
                let daylight = max(0, sin(Double(hour - 6) / 12 * .pi))
                let gust = rng.range(0, chaotic ? 90 : 25)
                var forecast = WeatherForecast(
                    datetime: String(format: "2026-01-15T%02d:00:00-08:00", hour), condition: chaotic ? rng.pick(Self.conditions) : steady,
                    temperature: base + (metric ? 6 : 12) * daylight, precipitation: chaotic ? rng.range(0, 0.5) : 0,
                    precipitationProbability: rng.range(0, chaotic ? 100 : 30), uvIndex: (daylight * rng.range(0, 12)).rounded(),
                    windBearing: rng.next() < 0.1 ? .cardinal(rng.pick(["N", "SW", "E"])) : .degrees(rng.range(0, 360)),
                    windGustSpeed: gust, windSpeed: gust * 0.5
                )
                if rng.next() < 0.7 { forecast.apparentTemperature = (forecast.temperature ?? 0) + rng.range(-14, 14) }
                hourly.append(forecast)
            }
            let briefing = generate(
                hourly: hourly, precipitationUnit: metric ? "mm" : "in", temperatureUnit: metric ? "°C" : "°F", windSpeedUnit: wind,
                sunrise: "2026-01-15T07:12:00-08:00", sunset: "2026-01-15T17:04:00-08:00", aqi: rng.next() < 0.3 ? rng.range(0, 400) : nil
            )
            let headline = WeatherBriefingRenderer.headline(briefing)
            let narrative = text(briefing)
            let context = "scenario \(scenario): \(headline) - \(narrative)"
            for bad in ["undefined", "NaN", "{{", "Infinity", "nan", "inf"] {
                #expect(!narrative.contains(bad), "\(context) contains \(bad)")
                #expect(!headline.contains(bad), "\(context) headline contains \(bad)")
            }
            #expect(!headline.isEmpty, "\(context)")
            #expect(narrative.first?.isUppercase == true, "\(context)")
            #expect(narrative.hasSuffix("."), "\(context)")
            #expect(!narrative.contains("  ") && !narrative.contains(" .") && !narrative.contains(",.") && !narrative.contains(".."), "\(context)")
            #expect(narrative.count < 700, "\(context)")
            #expect(briefing.icon.hasPrefix("mdi:"), "\(context)")
            #expect((1...6).contains(briefing.sentences.count), "\(context)")
            #expect(Set(briefing.sentences.map(\.key)).count == briefing.sentences.count, "\(context)")
            if briefing.severity == .alert || briefing.severity == .caution { #expect(briefing.hazard != nil, "\(context)") }
            if briefing.hazard == nil { #expect(briefing.severity == .calm, "\(context)") }
            severities.insert(briefing.severity)
            if let hazard = briefing.hazard { hazards.insert(hazard) }
            narratives.insert(narrative)
        }
        #expect(severities.count >= 3)
        #expect(hazards.count >= 6)
        #expect(narratives.count > 100)
    }
}
