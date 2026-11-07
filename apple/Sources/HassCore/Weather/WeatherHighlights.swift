import Foundation

/// Builds the highlight tiles from current conditions, today's forecast and the sun.
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/WeatherSummary.tsx:511` (`highlightTiles`) and
/// `WeatherAqiTile` (`:1006`).
public enum WeatherHighlights {
    /// Feels Like, UV Index, Wind, Sunrise/Sunset, Visibility and Pressure, in web order.
    public static func tiles(current: WeatherCurrent, today: WeatherForecast?, sun: WeatherSunInput?, now: Date = Date(), timeZone: TimeZone = .current) -> [WeatherHighlight] {
        let unavailable = WeatherCopy.text("unavailable")
        let wind = WeatherFormat.windMeasure(current.windSpeed, unit: current.windSpeedUnit)
        let currentGust = current.windGustSpeed
        let dailyGust = today?.windGustSpeed
        let gustIsForecast = currentGust == nil && dailyGust != nil
        let gust = WeatherFormat.windMeasure(currentGust ?? dailyGust, unit: current.windSpeedUnit)
        let bearing = WeatherPresentation.windBearing(current.windBearing)
        let calm = wind?.numeric == 0
        let gustLabel = WeatherCopy.text(gustIsForecast ? "details.wind.todaysGust" : "details.wind.gusts")
        let directionLabel = WeatherCopy.text(calm || bearing == nil ? "details.wind.direction" : "details.wind.from")
        let directionValue: String
        let directionSpoken: String
        if calm {
            directionValue = WeatherCopy.text("details.wind.calm")
            directionSpoken = directionValue
        } else if let bearing {
            directionValue = bearing.cardinal + (bearing.displayDegrees.map { " · \($0)°" } ?? "")
            directionSpoken = bearing.displayDegrees.map {
                WeatherCopy.text("details.wind.bearingDegrees", ["degrees": String($0), "direction": bearing.spoken])
            } ?? bearing.spoken
        } else {
            directionValue = unavailable
            directionSpoken = unavailable
        }
        let windAria = WeatherCopy.text("details.wind.ariaLabel", [
            "direction": directionSpoken, "directionLabel": directionLabel, "gust": gust?.value ?? unavailable,
            "gustLabel": gustLabel, "speed": wind?.value ?? unavailable,
        ])

        let pressure = WeatherPresentation.pressure(current.pressure, unit: current.pressureUnit)
        let uv = WeatherPresentation.uv(today?.uvIndex)
        let feels = WeatherPresentation.feelsLike(actual: current.temperature, apparent: current.apparentTemperature, unit: current.temperatureUnit)
        let visibility = WeatherPresentation.visibility(current.visibility, unit: current.visibilityUnit)
        let sunReading = sun.flatMap { WeatherPresentation.sun(state: $0.state, nextRising: $0.nextRising, nextSetting: $0.nextSetting, now: now) }
        let sunValue = sunReading.map { WeatherDates.clock($0.primaryTime, in: timeZone) }

        func accessible(_ title: String, _ value: String, available: Bool, status: String? = nil) -> String {
            let text = available ? [value, status].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ") : unavailable
            return WeatherCopy.text("details.ariaLabel", ["title": title, "value": text])
        }

        var tiles: [WeatherHighlight] = []
        tiles.append(WeatherHighlight(
            kind: .feels, accessibilityLabel: accessible("Feels Like", feels == nil ? "--" : WeatherFormat.temperature(current.apparentTemperature, unit: current.temperatureUnit), available: feels != nil),
            available: feels != nil, icon: "mdi:thermometer-lines", percent: feels?.markerPercent, rotation: nil, status: nil,
            title: "Feels Like", value: feels == nil ? "--" : WeatherFormat.temperature(current.apparentTemperature, unit: current.temperatureUnit),
            wind: nil, tone: feels?.relation.rawValue
        ))
        let uvStatus = uv.map { WeatherCopy.text($0.level.categoryKey) }
        let uvValue = uv.map { WeatherFormat.number($0.value, digits: 1) ?? unavailable } ?? "--"
        tiles.append(WeatherHighlight(
            kind: .uv, accessibilityLabel: accessible("UV Index", uvValue, available: uv != nil, status: uvStatus),
            available: uv != nil, icon: "mdi:weather-sunny-alert", percent: uv?.markerPercent, rotation: nil, status: uvStatus,
            title: "UV Index", value: uvValue, wind: nil, tone: uv?.level.rawValue
        ))
        tiles.append(WeatherHighlight(
            kind: .wind, accessibilityLabel: windAria, available: wind != nil || gust != nil || bearing != nil, icon: "mdi:weather-windy",
            percent: nil, rotation: nil, status: nil, title: "Wind", value: wind?.value ?? "--",
            wind: .init(
                bearingDegrees: calm ? nil : bearing?.sourceDegrees, destinationDegrees: calm ? nil : bearing?.destinationDegrees,
                directionLabel: directionLabel, directionValue: directionValue, gustIsForecast: gustIsForecast,
                gustLabel: gustLabel, gustValue: gust?.value ?? unavailable, showVector: bearing != nil && !calm,
                speedLabel: WeatherCopy.text("details.wind.speed"), speedValue: wind?.value ?? unavailable
            ),
            tone: nil
        ))
        if sun != nil {
            let title = sunReading.map { WeatherCopy.text($0.titleKey) } ?? WeatherCopy.text("details.sun.sunset")
            tiles.append(WeatherHighlight(
                kind: .sun, accessibilityLabel: accessible(title, sunValue ?? "--", available: sunReading != nil && sunValue != nil),
                available: sunReading != nil && sunValue != nil, icon: "mdi:weather-sunny", percent: sunReading?.markerPercent,
                rotation: nil, status: nil, title: title, value: sunValue ?? "--", wind: nil, tone: nil
            ))
        }
        let visibilityValue = visibility == nil ? "--" : WeatherFormat.measure(current.visibility, unit: current.visibilityUnit, digits: 1) ?? "--"
        tiles.append(WeatherHighlight(
            kind: .visibility, accessibilityLabel: accessible("Visibility", visibilityValue, available: visibility != nil),
            available: visibility != nil, icon: "mdi:eye", percent: visibility?.markerPercent, rotation: nil, status: nil,
            title: "Visibility", value: visibilityValue, wind: nil, tone: visibility?.band.rawValue
        ))
        let pressureValue = pressure == nil ? "--" : WeatherFormat.measure(current.pressure, unit: current.pressureUnit, digits: 2) ?? "--"
        tiles.append(WeatherHighlight(
            kind: .pressure, accessibilityLabel: accessible("Pressure", pressureValue, available: pressure != nil),
            available: pressure != nil, icon: "mdi:gauge", percent: pressure?.markerPercent,
            rotation: pressure.map { ($0.markerPercent - 50) * 1.35 }, status: nil, title: "Pressure", value: pressureValue,
            wind: nil, tone: pressure?.band.rawValue
        ))
        return tiles
    }

    /// The Air Quality tile from the air-quality sensor's state.
    public static func airQuality(state: String?) -> WeatherHighlight {
        let reading = WeatherPresentation.classifyUsAqi(state: state)
        let unavailable = WeatherCopy.text("unavailable")
        let category = reading.map { WeatherCopy.text($0.level.categoryKey) } ?? unavailable
        let value = reading.map { String($0.value) } ?? "--"
        let label = reading != nil
            ? WeatherCopy.text("aqi.ariaLabel", ["category": category, "value": value])
            : WeatherCopy.text("aqi.unavailableAriaLabel")
        return WeatherHighlight(
            kind: .aqi, accessibilityLabel: label, available: reading != nil, icon: "mdi:air-filter", percent: reading?.markerPercent,
            rotation: nil, status: category, title: WeatherCopy.text("aqi.title"), value: value, wind: nil, tone: reading?.level.rawValue ?? "unavailable"
        )
    }
}
