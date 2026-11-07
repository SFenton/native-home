import Foundation

/// Writes the "Today" briefing from the hourly and daily forecasts.
///
/// A faithful port of `generateWeatherDayBriefing`: same thresholds, same sentence order and the same copy.
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/weatherDayBriefing.ts`.
public enum WeatherDayBriefingGenerator {
    /// Bump when the briefing shape or wording rules change, so a stored briefing is discarded.
    public static let version = 3

    // MARK: - Samples

    private struct HourSample {
        var apparent: Double?
        var condition: String?
        var gust: Double?
        var hour: Int
        var precipitation: Double?
        var probability: Double?
        var temperature: Double?
        var timestamp: Date
        var uv: Double?
        var windBearing: Double?
        var windSpeed: Double?
    }

    private struct WetWindow {
        var end: Date
        var start: Date
    }

    // MARK: - Condition ranking

    /// Ranked from calm to disruptive so a mixed segment reports the notable half.
    private static let conditionWeights: [String: Int] = [
        "clear-night": 0, "sunny": 0, "partlycloudy": 1, "cloudy": 2, "windy": 3, "windy-variant": 3, "fog": 4,
        "rainy": 5, "snowy-rainy": 6, "pouring": 7, "snowy": 7, "hail": 8, "lightning": 9, "lightning-rainy": 9,
        "exceptional": 10,
    ]

    private static func weight(_ condition: String?) -> Int {
        guard let condition else { return -1 }
        return conditionWeights[condition] ?? 2
    }

    private static func phraseKey(_ condition: String?) -> String {
        guard let condition else { return "briefing.phrase.exceptional" }
        let key = "briefing.phrase.\(condition)"
        return WeatherCopy.has(key) ? key : "briefing.phrase.cloudy"
    }

    private static func dominantCondition(_ samples: [HourSample]) -> String? {
        var counts: [(condition: String, count: Int)] = []
        for sample in samples {
            guard let condition = sample.condition else { continue }
            if let index = counts.firstIndex(where: { $0.condition == condition }) { counts[index].count += 1 }
            else { counts.append((condition, 1)) }
        }
        guard !counts.isEmpty else { return nil }
        var best: String?
        var bestCount = -1
        for (condition, count) in counts where count > bestCount || (count == bestCount && weight(condition) > weight(best)) {
            best = condition
            bestCount = count
        }
        // A short but disruptive stretch outranks a marginally longer benign one.
        let threshold = max(2.0, Double(samples.count) * 0.25)
        var severe: (condition: String, count: Int)?
        for entry in counts where weight(entry.condition) >= 7 && Double(entry.count) >= threshold {
            if severe == nil || weight(entry.condition) > weight(severe?.condition) { severe = entry }
        }
        return severe?.condition ?? best
    }

    private static func isWet(_ condition: String?) -> Bool {
        guard let condition else { return false }
        return ["rainy", "pouring", "lightning-rainy", "snowy", "snowy-rainy", "hail"].contains(condition)
    }

    private static func isFrozen(_ condition: String?) -> Bool { condition == "snowy" || condition == "snowy-rainy" }

    // MARK: - Units

    private static func isCelsius(_ unit: String?) -> Bool { unit?.uppercased().contains("C") ?? false }
    private static func isMetricDepth(_ unit: String?) -> Bool { unit?.lowercased().contains("mm") ?? false }
    private static func toFahrenheit(_ value: Double, _ unit: String?) -> Double { isCelsius(unit) ? value * 9 / 5 + 32 : value }
    private static func toInches(_ value: Double, _ unit: String?) -> Double { isMetricDepth(unit) ? value / 25.4 : value }

    private static func toMph(_ value: Double, _ unit: String) -> Double {
        let normalized = unit.lowercased()
        if normalized.contains("km") { return value * 0.621371 }
        if normalized.contains("m/s") { return value * 2.23694 }
        if normalized.contains("kn") { return value * 1.15078 }
        return value
    }

    private static func fromMph(_ value: Double, _ unit: String) -> Double {
        let normalized = unit.lowercased()
        if normalized.contains("km") { return value / 0.621371 }
        if normalized.contains("m/s") { return value / 2.23694 }
        if normalized.contains("kn") { return value / 1.15078 }
        return value
    }

    private static func resolvedUnit(_ unit: String?) -> String? {
        guard let trimmed = unit?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func measure(_ amount: String, _ unit: String?) -> String {
        [amount, unit].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func temperatureLabel(_ value: Double?) -> String? { value.map { "\(WeatherFormat.integer($0))°" } }
    private static func percentLabel(_ value: Double?) -> String? { value.map { "\(WeatherFormat.integer($0))%" } }

    private static func speedLabel(_ value: Double?, unit: String) -> String? {
        value.map { measure(WeatherFormat.integer($0), resolvedUnit(unit) ?? WeatherUnits.defaultWindSpeedUnit) }
    }

    private static func depthLabel(_ value: Double?, unit: String?) -> String? {
        guard let value else { return nil }
        let digits = isMetricDepth(unit) ? (value < 10 ? 1 : 0) : (value < 1 ? 2 : 1)
        return measure(String(format: "%.\(digits)f", value), resolvedUnit(unit))
    }

    // MARK: - Statistics

    private static func maxOf(_ values: [Double?]) -> Double? { values.compactMap { $0 }.max() }
    private static func minOf(_ values: [Double?]) -> Double? { values.compactMap { $0 }.min() }
    private static func sumOf(_ values: [Double?]) -> Double? {
        let defined = values.compactMap { $0 }
        return defined.isEmpty ? nil : defined.reduce(0, +)
    }

    private static let windWords = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]

    private static func bearingWord(_ bearing: Double?) -> String? {
        guard let bearing else { return nil }
        let normalized = WeatherPresentation.normalizeBearingDegrees(bearing)
        return windWords[Int(WeatherFormat.round(normalized / 45)) % 8]
    }

    /// The briefing only reads the eight principal points (`bearingValue`).
    private static func bearingDegrees(_ value: WeatherWindBearing?) -> Double? {
        WeatherPresentation.bearingDegrees(value, principalOnly: true)?.degrees
    }

    private static func averageBearing(_ samples: [HourSample]) -> Double? {
        let bearings = samples.compactMap(\.windBearing)
        guard !bearings.isEmpty else { return nil }
        let x = bearings.reduce(0) { $0 + cos($1 * .pi / 180) }
        let y = bearings.reduce(0) { $0 + sin($1 * .pi / 180) }
        if abs(x) < 1e-9, abs(y) < 1e-9 { return nil }
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func segment(_ hour: Int) -> String {
        if hour < 5 { return "overnight" }
        if hour < 12 { return "morning" }
        if hour < 17 { return "afternoon" }
        if hour < 22 { return "evening" }
        return "overnight"
    }

    // MARK: - Generation

    /// Generates the briefing for the day containing `input.generatedAt`.
    public static func generate(_ input: WeatherDayBriefingInput) -> WeatherDayBriefing {
        let zone = input.timeZone
        let dateKey = WeatherDates.dateKey(input.generatedAt, in: zone)
        let temperatureUnit = input.temperatureUnit
        let windUnit = resolvedUnit(input.windSpeedUnit) ?? "mph"
        let precipitationUnit = resolvedUnit(input.precipitationUnit) ?? "in"

        let samples: [HourSample] = input.hourly.compactMap { forecast -> HourSample? in
            guard let timestamp = forecast.start else { return nil }
            return HourSample(
                apparent: forecast.apparentTemperature, condition: forecast.condition, gust: forecast.windGustSpeed,
                hour: WeatherDates.parts(timestamp, in: zone).hour, precipitation: forecast.precipitation,
                probability: forecast.precipitationProbability, temperature: forecast.temperature, timestamp: timestamp,
                uv: forecast.uvIndex, windBearing: bearingDegrees(forecast.windBearing), windSpeed: forecast.windSpeed
            )
        }
        .filter { WeatherDates.dateKey($0.timestamp, in: zone) == dateKey }
        .sorted { $0.timestamp < $1.timestamp }

        let today = input.daily.first { forecast in
            forecast.start.map { WeatherDates.dateKey($0, in: zone) == dateKey } ?? false
        } ?? input.daily.first

        if samples.isEmpty, today == nil {
            return WeatherDayBriefing(
                condition: nil, dateKey: dateKey, generatedAt: input.generatedAt, hazard: nil, headline: nil,
                headlineText: nil, icon: "mdi:cloud-question", sentences: [WeatherBriefingRef("briefing.unavailable")],
                severity: .calm, version: version
            )
        }

        let daytime = samples.filter { $0.hour >= 6 && $0.hour <= 20 }
        let pool = daytime.count >= 4 ? daytime : samples
        let dayCondition = dominantCondition(pool) ?? today?.condition

        let high = maxOf(samples.map(\.temperature) + [today?.temperature])
        let low = minOf(samples.map(\.temperature) + [today?.templow])
        let apparentHigh = maxOf(samples.map(\.apparent))
        let apparentLow = minOf(samples.map(\.apparent))
        let maxProbability = maxOf(samples.map(\.probability) + [today?.precipitationProbability])
        let totalPrecipitation = samples.isEmpty ? today?.precipitation : (sumOf(samples.map(\.precipitation)) ?? today?.precipitation)
        let maxWind = maxOf(samples.map(\.windSpeed) + [today?.windSpeed])
        let maxGust = maxOf(samples.map(\.gust) + [today?.windGustSpeed])
        let maxUv = maxOf(samples.map(\.uv) + [today?.uvIndex])
        let bearing = averageBearing(samples) ?? bearingDegrees(today?.windBearing)

        let highF = high.map { toFahrenheit($0, temperatureUnit) }
        let lowF = low.map { toFahrenheit($0, temperatureUnit) }
        let apparentHighF = apparentHigh.map { toFahrenheit($0, temperatureUnit) }
        let apparentLowF = apparentLow.map { toFahrenheit($0, temperatureUnit) }
        let gustMph = maxGust.map { toMph($0, windUnit) }
        let windMph = maxWind.map { toMph($0, windUnit) }
        let precipitationIn = totalPrecipitation.map { toInches($0, precipitationUnit) }

        let conditions = samples.map(\.condition)
        let frozenHours = conditions.filter(isFrozen).count
        let stormHours = conditions.filter { $0 == "lightning" || $0 == "lightning-rainy" }.count
        let hailHours = conditions.filter { $0 == "hail" }.count
        let fogHours = conditions.filter { $0 == "fog" }.count
        let mixHours = conditions.filter { $0 == "snowy-rainy" }.count
        let nearFreezing = samples.contains { sample in
            guard let temperature = sample.temperature.map({ toFahrenheit($0, temperatureUnit) }) else { return false }
            return temperature >= 26 && temperature <= 36
        }

        var hazards = Set<WeatherHazard>()
        if stormHours >= 1 { hazards.insert(.severeStorms) }
        if hailHours >= 1 { hazards.insert(.hail) }
        if mixHours >= 1, nearFreezing { hazards.insert(.ice) }
        if frozenHours >= 1 { hazards.insert(frozenHours >= 4 && (precipitationIn ?? 0) >= 0.4 ? .heavySnow : .snow) }
        if let gustMph, gustMph >= 46 { hazards.insert(.damagingWind) }
        else if let gustMph, gustMph >= 30 { hazards.insert(.wind) }
        if frozenHours == 0, (precipitationIn ?? 0) >= 1 || conditions.filter({ $0 == "pouring" }).count >= 2 {
            hazards.insert(.heavyRain)
        }
        let feelsHigh = apparentHighF ?? highF
        let feelsLow = apparentLowF ?? lowF
        if let feelsHigh, feelsHigh >= 100 { hazards.insert(.extremeHeat) }
        else if let feelsHigh, feelsHigh >= 90 { hazards.insert(.heat) }
        if let feelsLow, feelsLow <= 10 { hazards.insert(.extremeCold) }
        else if let feelsLow, feelsLow <= 28 { hazards.insert(.freeze) }
        if fogHours >= 2 { hazards.insert(.denseFog) }
        if let aqi = input.aqi, aqi >= 101 { hazards.insert(.poorAir) }
        if let maxUv, maxUv >= 8 { hazards.insert(.highUv) }

        func severity(of hazard: WeatherHazard) -> WeatherBriefingSeverity {
            if hazard == .severeStorms, (gustMph ?? 0) < 40, stormHours < 2 { return .caution }
            if hazard == .poorAir { return (input.aqi ?? 0) >= 201 ? .alert : .caution }
            return hazard.baseSeverity
        }

        let ranked = hazards.sorted { left, right in
            let bySeverity = severity(of: right).rank - severity(of: left).rank
            if bySeverity != 0 { return bySeverity < 0 }
            return (WeatherHazard.priority.firstIndex(of: left) ?? 0) < (WeatherHazard.priority.firstIndex(of: right) ?? 0)
        }
        let lead = ranked.first
        let briefingSeverity = lead.map(severity(of:)) ?? .calm
        let headlineOverride = lead != nil && (briefingSeverity == .alert || briefingSeverity == .caution)

        let info = WeatherConditionInfo(dayCondition)
        var headline: WeatherBriefingRef?
        var headlineText: String?
        if headlineOverride, let lead {
            headline = WeatherBriefingRef(lead.headlineKey)
        } else if dayCondition == nil || WeatherConditionInfo.isKnown(dayCondition) {
            headline = WeatherBriefingRef(dayCondition.map { "condition.\($0)" } ?? "condition.unavailable")
        } else {
            headlineText = info.label
        }
        let icon = headlineOverride ? (lead?.icon ?? info.icon) : info.icon

        var sentences = [overview(samples, dayCondition)]
        if let sentence = temperatureSentence(samples, high, low, apparentHigh, apparentLow, temperatureUnit) { sentences.append(sentence) }
        if let sentence = precipitationSentence(
            maxProbability: maxProbability, precipitationUnit: precipitationUnit, samples: samples,
            temperatureUnit: temperatureUnit, timeZone: zone, totalPrecipitation: totalPrecipitation
        ) { sentences.append(sentence) }
        if let sentence = windSentence(windMph, gustMph, bearing, windUnit) { sentences.append(sentence) }
        if let sentence = sunSentence(input.sunrise, input.sunset, dateKey, zone) { sentences.append(sentence) }

        return WeatherDayBriefing(
            condition: dayCondition, dateKey: dateKey, generatedAt: input.generatedAt, hazard: lead,
            headline: headline, headlineText: headlineText, icon: icon, sentences: sentences,
            severity: briefingSeverity, version: version
        )
    }

    // MARK: - Sentences

    private static func overview(_ samples: [HourSample], _ dayCondition: String?) -> WeatherBriefingRef {
        let morning = dominantCondition(samples.filter { $0.hour >= 5 && $0.hour < 12 })
        let afternoon = dominantCondition(samples.filter { $0.hour >= 12 && $0.hour < 17 })
        let evening = dominantCondition(samples.filter { $0.hour >= 17 && $0.hour < 22 })
        let parts = [morning, afternoon, evening].compactMap { $0 }
        var distinct: [String] = []
        for part in parts where !distinct.contains(part) { distinct.append(part) }

        if parts.isEmpty, dayCondition == nil { return WeatherBriefingRef("briefing.overview.unknown") }
        if parts.count < 2 || distinct.count == 1 {
            return WeatherBriefingRef("briefing.overview.steady", ["condition": .ref(WeatherBriefingRef(phraseKey(dayCondition ?? parts.first)))])
        }
        if parts.count == 3, distinct.count == 3 {
            return WeatherBriefingRef("briefing.overview.threePart", [
                "afternoon": .ref(WeatherBriefingRef(phraseKey(parts[1]))),
                "evening": .ref(WeatherBriefingRef(phraseKey(parts[2]))),
                "morning": .ref(WeatherBriefingRef(phraseKey(parts[0]))),
            ])
        }
        let first = parts[0]
        let last = parts.reversed().first { $0 != first } ?? parts[parts.count - 1]
        let clearing = weight(last) < weight(first)
        return WeatherBriefingRef(clearing ? "briefing.overview.improving" : "briefing.overview.twoPart", [
            "later": .ref(WeatherBriefingRef(phraseKey(last))),
            "start": .ref(WeatherBriefingRef(phraseKey(first))),
        ])
    }

    private static func temperatureSentence(
        _ samples: [HourSample], _ high: Double?, _ low: Double?, _ apparentHigh: Double?, _ apparentLow: Double?, _ unit: String?
    ) -> WeatherBriefingRef? {
        if high == nil, low == nil { return nil }
        let highLabel = temperatureLabel(high)
        let lowLabel = temperatureLabel(low)
        guard let highLabel, let lowLabel else {
            guard let only = highLabel ?? lowLabel else { return nil }
            return WeatherBriefingRef("briefing.temperature.single", ["temperature": .text(only)])
        }
        let spreadF: Double = {
            guard let high, let low else { return 0 }
            return abs(toFahrenheit(high, unit) - toFahrenheit(low, unit))
        }()
        let feelsGapHigh: Double = {
            guard let apparentHigh, let high else { return 0 }
            return toFahrenheit(apparentHigh, unit) - toFahrenheit(high, unit)
        }()
        let feelsGapLow: Double = {
            guard let apparentLow, let low else { return 0 }
            return toFahrenheit(apparentLow, unit) - toFahrenheit(low, unit)
        }()
        var peak: HourSample?
        for sample in samples {
            guard let temperature = sample.temperature else { continue }
            if peak == nil || (peak?.temperature ?? -.infinity) < temperature { peak = sample }
        }

        if abs(feelsGapHigh) >= 6 {
            return WeatherBriefingRef(feelsGapHigh > 0 ? "briefing.temperature.feelsWarmer" : "briefing.temperature.feelsCooler", [
                "feelsLike": .text(temperatureLabel(apparentHigh) ?? highLabel), "high": .text(highLabel), "low": .text(lowLabel),
            ])
        }
        if feelsGapLow <= -6 {
            return WeatherBriefingRef("briefing.temperature.windChill", [
                "feelsLike": .text(temperatureLabel(apparentLow) ?? lowLabel), "high": .text(highLabel), "low": .text(lowLabel),
            ])
        }
        if let peak, peak.hour < 11, spreadF >= 6 {
            return WeatherBriefingRef("briefing.temperature.falling", ["high": .text(highLabel), "low": .text(lowLabel)])
        }
        if spreadF <= 6 {
            return WeatherBriefingRef("briefing.temperature.flat", ["high": .text(highLabel), "low": .text(lowLabel)])
        }
        return WeatherBriefingRef("briefing.temperature.range", ["high": .text(highLabel), "low": .text(lowLabel)])
    }

    private static func precipitationTypeKey(_ samples: [HourSample], _ unit: String?) -> String {
        let conditions = samples.map(\.condition)
        if conditions.contains(where: { $0 == "lightning" || $0 == "lightning-rainy" }) { return "briefing.precipitationType.thunderstorms" }
        let snow = conditions.filter { $0 == "snowy" }.count
        let mix = conditions.filter { $0 == "snowy-rainy" }.count
        let rain = conditions.filter { $0 == "rainy" || $0 == "pouring" }.count
        if mix > 0 { return "briefing.precipitationType.wintryMix" }
        if snow > rain { return "briefing.precipitationType.snow" }
        if rain > 0 { return "briefing.precipitationType.rain" }
        // Without a wet hour to read, temperature still tells us what would fall.
        guard let coldest = minOf(samples.map { $0.temperature.map { toFahrenheit($0, unit) } }) else {
            return "briefing.precipitationType.precipitation"
        }
        if coldest <= 30 { return "briefing.precipitationType.snow" }
        if coldest <= 36 { return "briefing.precipitationType.wintryMix" }
        return "briefing.precipitationType.rain"
    }

    private static func wetWindows(_ samples: [HourSample]) -> [WetWindow] {
        var windows: [WetWindow] = []
        var current: WetWindow?
        for sample in samples {
            let wet = (sample.probability ?? 0) >= 35 || (sample.precipitation ?? 0) > 0.005 || isWet(sample.condition)
            if wet {
                if current != nil { current?.end = sample.timestamp }
                else { current = WetWindow(end: sample.timestamp, start: sample.timestamp) }
            } else if let finished = current {
                windows.append(finished)
                current = nil
            }
        }
        if let current { windows.append(current) }
        return windows
    }

    private static func windowValue(_ window: WetWindow, _ samples: [HourSample], _ zone: TimeZone) -> WeatherBriefingRef? {
        let spanHours = window.end.timeIntervalSince(window.start) / 3600
        let covered = samples.isEmpty ? 0 : (spanHours + 1) / Double(samples.count)
        if covered >= 0.7 { return nil }
        let startHour = WeatherDates.parts(window.start, in: zone).hour
        let endHour = WeatherDates.parts(window.end, in: zone).hour
        if spanHours < 1.5 { return WeatherBriefingRef("briefing.window.around", ["time": .text(WeatherDates.hour(window.start, in: zone))]) }
        if segment(startHour) == segment(endHour) { return WeatherBriefingRef("briefing.window.\(segment(startHour))") }
        // A stretch that runs from midnight or up to bedtime reads better open-ended.
        if startHour <= 1 { return WeatherBriefingRef("briefing.window.before", ["end": .text(WeatherDates.hour(window.end, in: zone))]) }
        if endHour >= 22 { return WeatherBriefingRef("briefing.window.after", ["start": .text(WeatherDates.hour(window.start, in: zone))]) }
        return WeatherBriefingRef("briefing.window.between", [
            "end": .text(WeatherDates.hour(window.end, in: zone)), "start": .text(WeatherDates.hour(window.start, in: zone)),
        ])
    }

    private static func precipitationSentence(
        maxProbability: Double?, precipitationUnit: String, samples: [HourSample], temperatureUnit: String?,
        timeZone: TimeZone, totalPrecipitation: Double?
    ) -> WeatherBriefingRef? {
        let type = WeatherBriefingValue.ref(WeatherBriefingRef(precipitationTypeKey(samples, temperatureUnit)))
        let chance = percentLabel(maxProbability)
        let amount: String? = {
            guard let totalPrecipitation, totalPrecipitation >= (isMetricDepth(precipitationUnit) ? 0.3 : 0.01) else { return nil }
            return depthLabel(totalPrecipitation, unit: precipitationUnit)
        }()
        if maxProbability == nil, amount == nil { return nil }
        if (maxProbability ?? 0) < 15, amount == nil { return WeatherBriefingRef("briefing.precipitation.none", ["type": type]) }
        if (maxProbability ?? 0) < 35, amount == nil {
            return WeatherBriefingRef("briefing.precipitation.slight", ["chance": .text(chance ?? ""), "type": type])
        }

        var longest: WetWindow?
        for window in wetWindows(samples) {
            if let best = longest {
                if window.end.timeIntervalSince(window.start) > best.end.timeIntervalSince(best.start) { longest = window }
            } else {
                longest = window
            }
        }
        let window = longest.flatMap { windowValue($0, samples, timeZone) }
        guard let window else {
            if let amount {
                return WeatherBriefingRef("briefing.precipitation.allDayAmount", ["amount": .text(amount), "chance": .text(chance ?? ""), "type": type])
            }
            return WeatherBriefingRef("briefing.precipitation.allDay", ["chance": .text(chance ?? ""), "type": type])
        }
        var values: [String: WeatherBriefingValue] = ["chance": .text(chance ?? ""), "type": type, "window": .ref(window)]
        if let amount {
            values["amount"] = .text(amount)
            return WeatherBriefingRef("briefing.precipitation.windowAmount", values)
        }
        return WeatherBriefingRef("briefing.precipitation.window", values)
    }

    private static func windSentence(_ windMph: Double?, _ gustMph: Double?, _ bearing: Double?, _ unit: String) -> WeatherBriefingRef? {
        if windMph == nil, gustMph == nil { return nil }
        let speed = speedLabel(windMph.map { fromMph($0, unit) }, unit: unit)
        let gust = speedLabel(gustMph.map { fromMph($0, unit) }, unit: unit)
        let direction = bearingWord(bearing)

        if (windMph ?? 0) < 6, (gustMph ?? 0) < 14 { return WeatherBriefingRef("briefing.wind.calm") }
        if let gustMph, let windMph, gustMph - windMph >= 8, let gust, let speed {
            if let direction {
                return WeatherBriefingRef("briefing.wind.gustyDirected", [
                    "direction": .ref(WeatherBriefingRef("briefing.direction.\(direction)")), "gust": .text(gust), "speed": .text(speed),
                ])
            }
            return WeatherBriefingRef("briefing.wind.gusty", ["gust": .text(gust), "speed": .text(speed)])
        }
        guard let speed else { return gust.map { WeatherBriefingRef("briefing.wind.gustsOnly", ["gust": .text($0)]) } }
        if let direction {
            return WeatherBriefingRef("briefing.wind.steadyDirected", [
                "direction": .ref(WeatherBriefingRef("briefing.direction.\(direction)")), "speed": .text(speed),
            ])
        }
        return WeatherBriefingRef("briefing.wind.steady", ["speed": .text(speed)])
    }

    /// Home Assistant's sun entity reports the *next* rise and set, which drift onto the following day once
    /// today's event has passed. Pull each back onto the briefing's day.
    private static func alignToDay(_ date: Date?, _ dateKey: String, _ zone: TimeZone) -> Date? {
        guard let date else { return nil }
        for shifted in [date, date.addingTimeInterval(-86_400), date.addingTimeInterval(86_400)]
        where WeatherDates.dateKey(shifted, in: zone) == dateKey {
            return shifted
        }
        return nil
    }

    private static func sunSentence(_ sunrise: String?, _ sunset: String?, _ dateKey: String, _ zone: TimeZone) -> WeatherBriefingRef? {
        guard let rise = alignToDay(sunrise.flatMap(HassDates.iso8601), dateKey, zone),
              let set = alignToDay(sunset.flatMap(HassDates.iso8601), dateKey, zone), set > rise else { return nil }
        let totalMinutes = Int(WeatherFormat.round(set.timeIntervalSince(rise) / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        var values: [String: WeatherBriefingValue] = [
            "count": .number(Double(hours)), "sunrise": .text(WeatherDates.clock(rise, in: zone)), "sunset": .text(WeatherDates.clock(set, in: zone)),
        ]
        if minutes <= 1 { return WeatherBriefingRef("briefing.sun.daylightWhole", values) }
        values["minutes"] = .number(Double(minutes))
        return WeatherBriefingRef("briefing.sun.daylight", values)
    }
}
