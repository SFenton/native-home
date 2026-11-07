import Foundation

/// The weather copy deck, ported key for key from the web's English strings so the native text matches.
///
/// Values use `{{name}}` placeholders; a `count` value picks `<key>_one` or `<key>_other` like i18next.
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/i18n/locales/en/modals/weather.json`.
public enum WeatherCopy {
    /// Resolves `key` and fills placeholders. An unknown key returns itself so a gap is visible, not blank.
    public static func text(_ key: String, _ values: [String: String] = [:]) -> String {
        var resolvedKey = key
        if let count = values["count"], let number = Double(count) {
            let plural = number == 1 ? "\(key)_one" : "\(key)_other"
            if strings[plural] != nil { resolvedKey = plural }
        }
        guard var template = strings[resolvedKey] else { return key }
        for (name, value) in values { template = template.replacingOccurrences(of: "{{\(name)}}", with: value) }
        return template
    }

    /// `forecast.dailyError` / `forecast.hourlyError`.
    public static func forecastFailure(_ kind: WeatherForecastKind) -> String {
        text(kind == .daily ? "forecast.dailyError" : "forecast.hourlyError")
    }

    /// Whether the deck has this key.
    public static func has(_ key: String) -> Bool {
        strings[key] != nil || strings["\(key)_one"] != nil
    }

    static let strings: [String: String] = [
        "aqi.ariaLabel": "Outdoor air quality {{value}}, {{category}}",
        "aqi.categories.good": "Good",
        "aqi.categories.hazardous": "Hazardous",
        "aqi.categories.moderate": "Moderate",
        "aqi.categories.sensitive": "Unhealthy for Sensitive Groups",
        "aqi.categories.unhealthy": "Unhealthy",
        "aqi.categories.veryUnhealthy": "Very Unhealthy",
        "aqi.guidance.good": "Air pollution poses little or no risk.",
        "aqi.guidance.hazardous": "Emergency health effects are possible for everyone.",
        "aqi.guidance.moderate": "Air quality is acceptable for most people.",
        "aqi.guidance.sensitive": "Sensitive groups may experience health effects.",
        "aqi.guidance.unhealthy": "Health effects are possible for everyone.",
        "aqi.guidance.veryUnhealthy": "Health risk is increased for everyone.",
        "aqi.title": "Air Quality",
        "aqi.unavailableAriaLabel": "Outdoor air quality unavailable",

        "briefing.direction.north": "north",
        "briefing.direction.northeast": "northeast",
        "briefing.direction.east": "east",
        "briefing.direction.southeast": "southeast",
        "briefing.direction.south": "south",
        "briefing.direction.southwest": "southwest",
        "briefing.direction.west": "west",
        "briefing.direction.northwest": "northwest",

        "briefing.hazard.damagingWind": "Damaging Wind",
        "briefing.hazard.denseFog": "Dense Fog",
        "briefing.hazard.extremeCold": "Extreme Cold",
        "briefing.hazard.extremeHeat": "Extreme Heat",
        "briefing.hazard.freeze": "Freezing",
        "briefing.hazard.hail": "Hail",
        "briefing.hazard.heat": "Hot",
        "briefing.hazard.heavyRain": "Heavy Rain",
        "briefing.hazard.heavySnow": "Heavy Snow",
        "briefing.hazard.highUv": "High UV",
        "briefing.hazard.ice": "Ice Risk",
        "briefing.hazard.poorAir": "Poor Air Quality",
        "briefing.hazard.severeStorms": "Severe Storms",
        "briefing.hazard.snow": "Snow",
        "briefing.hazard.wind": "Windy",

        "briefing.overview.improving": "The day opens with {{start}}, then eases into {{later}}.",
        "briefing.overview.steady": "Expect {{condition}} for most of the day.",
        "briefing.overview.threePart": "The day opens with {{morning}}, shifts to {{afternoon}}, and settles into {{evening}}.",
        "briefing.overview.twoPart": "The day opens with {{start}}, then turns to {{later}}.",
        "briefing.overview.unknown": "Conditions look mixed, with limited hourly detail from Pirate Weather.",

        "briefing.phrase.clear-night": "clear skies",
        "briefing.phrase.cloudy": "overcast skies",
        "briefing.phrase.exceptional": "unsettled conditions",
        "briefing.phrase.fog": "fog",
        "briefing.phrase.hail": "hail",
        "briefing.phrase.lightning": "thunder",
        "briefing.phrase.lightning-rainy": "thunderstorms",
        "briefing.phrase.partlycloudy": "a mix of sun and clouds",
        "briefing.phrase.pouring": "heavy rain",
        "briefing.phrase.rainy": "steady rain",
        "briefing.phrase.snowy": "snow",
        "briefing.phrase.snowy-rainy": "a wintry mix",
        "briefing.phrase.sunny": "full sun",
        "briefing.phrase.windy": "gusty wind",
        "briefing.phrase.windy-variant": "gusty wind under thick cloud",

        "briefing.precipitation.allDay": "Expect {{type}} on and off through the day, with chances near {{chance}}.",
        "briefing.precipitation.allDayAmount": "Expect {{type}} on and off through the day, with chances near {{chance}} and about {{amount}} adding up.",
        "briefing.precipitation.none": "No meaningful {{type}} is expected.",
        "briefing.precipitation.slight": "Only a slight chance of {{type}}, peaking near {{chance}}.",
        "briefing.precipitation.window": "Look for {{type}} {{window}}, with chances near {{chance}}.",
        "briefing.precipitation.windowAmount": "Look for {{type}} {{window}}, with chances near {{chance}} and about {{amount}} adding up.",

        "briefing.precipitationType.precipitation": "precipitation",
        "briefing.precipitationType.rain": "rain",
        "briefing.precipitationType.snow": "snow",
        "briefing.precipitationType.thunderstorms": "thunderstorms",
        "briefing.precipitationType.wintryMix": "a wintry mix",

        "briefing.sun.daylight_one": "Sunrise is at {{sunrise}} and sunset at {{sunset}}, giving {{count}} hour and {{minutes}} minutes of daylight.",
        "briefing.sun.daylight_other": "Sunrise is at {{sunrise}} and sunset at {{sunset}}, giving {{count}} hours and {{minutes}} minutes of daylight.",
        "briefing.sun.daylightWhole_one": "Sunrise is at {{sunrise}} and sunset at {{sunset}}, giving {{count}} hour of daylight.",
        "briefing.sun.daylightWhole_other": "Sunrise is at {{sunrise}} and sunset at {{sunset}}, giving {{count}} hours of daylight.",

        "briefing.temperature.falling": "Temperatures peak near {{high}} early, then slide toward {{low}} as the day goes on.",
        "briefing.temperature.feelsCooler": "Highs reach {{high}}, though it feels more like {{feelsLike}}, with lows near {{low}}.",
        "briefing.temperature.feelsWarmer": "Highs reach {{high}} but feel closer to {{feelsLike}}, with lows near {{low}}.",
        "briefing.temperature.flat": "Temperatures hold steady between {{low}} and {{high}} all day.",
        "briefing.temperature.range": "Highs reach {{high}} before falling back to {{low}} overnight.",
        "briefing.temperature.single": "Temperatures stay near {{temperature}}.",
        "briefing.temperature.windChill": "Highs reach {{high}}, and lows near {{low}} feel closer to {{feelsLike}} in the wind.",

        "briefing.unavailable": "Today's outlook appears once Pirate Weather returns forecast data.",

        "briefing.window.after": "from {{start}} onward",
        "briefing.window.afternoon": "through the afternoon",
        "briefing.window.around": "around {{time}}",
        "briefing.window.before": "before {{end}}",
        "briefing.window.between": "between {{start}} and {{end}}",
        "briefing.window.evening": "in the evening",
        "briefing.window.morning": "through the morning",
        "briefing.window.overnight": "overnight",

        "briefing.wind.calm": "Winds stay light all day.",
        "briefing.wind.gusty": "Winds near {{speed}} gust to {{gust}}.",
        "briefing.wind.gustyDirected": "Winds out of the {{direction}} near {{speed}} gust to {{gust}}.",
        "briefing.wind.gustsOnly": "Gusts reach {{gust}}.",
        "briefing.wind.steady": "Winds run near {{speed}}.",
        "briefing.wind.steadyDirected": "Winds run out of the {{direction}} near {{speed}}.",

        "condition.clear-night": "Clear Night",
        "condition.cloudy": "Cloudy",
        "condition.exceptional": "Exceptional",
        "condition.fog": "Fog",
        "condition.hail": "Hail",
        "condition.lightning": "Lightning",
        "condition.lightning-rainy": "Storms",
        "condition.partlycloudy": "Partly Cloudy",
        "condition.pouring": "Heavy Rain",
        "condition.rainy": "Rain",
        "condition.snowy": "Snow",
        "condition.snowy-rainy": "Wintry Mix",
        "condition.sunny": "Sunny",
        "condition.unavailable": "Weather Unavailable",
        "condition.windy": "Windy",
        "condition.windy-variant": "Windy Clouds",

        "carousel.conditions": "24-hour conditions",
        "carousel.forecast": "24-hour weather forecast",
        "carousel.section": "24-hour weather conditions",

        "details.ariaLabel": "{{title}} {{value}}",
        "details.sun.sunrise": "Sunrise",
        "details.sun.sunset": "Sunset",
        "details.uv.categories.extreme": "Extreme",
        "details.uv.categories.high": "High",
        "details.uv.categories.low": "Low",
        "details.uv.categories.moderate": "Moderate",
        "details.uv.categories.veryHigh": "Very High",
        "details.wind.ariaLabel": "Wind {{speed}}; {{gustLabel}} {{gust}}; {{directionLabel}} {{direction}}",
        "details.wind.bearingDegrees": "{{direction}}, {{degrees}} degrees",
        "details.wind.calm": "Calm",
        "details.wind.direction": "Direction",
        "details.wind.from": "From",
        "details.wind.gusts": "Gusts",
        "details.wind.speed": "Wind",
        "details.wind.todaysGust": "Today's gust",

        "headline.aqi": "Outdoor air quality is {{category}} ({{value}})",
        "headline.label": "Today",
        "headline.weather": "{{condition}}",

        "forecast.dailyError": "Unable to load Pirate Weather forecast.",
        "forecast.hourlyError": "Unable to load Pirate Weather hourly forecast.",
        "forecast.dailyEmpty": "No forecast data returned by Pirate Weather.",
        "forecast.hourlyEmpty": "No hourly forecast data returned by Pirate Weather.",

        "hero.high": "High: {{high}}",
        "hero.highLow": "High: {{high}}  Low: {{low}}",
        "hero.low": "Low: {{low}}",

        "hourlyMetrics.ariaLabel": "Hourly {{title}} over {{hours}} hours, ranging from {{minimum}} to {{maximum}}",
        "hourlyMetrics.cloudCover": "Cloud Cover",
        "hourlyMetrics.humidity": "Humidity",
        "hourlyMetrics.table.time": "Time",
        "hourlyMetrics.tableCaption": "{{hours}}-hour humidity and cloud cover details",

        "precipitation.chanceChartAriaLabel": "Hourly precipitation chance over {{hours}} hours, peaking at {{chance}}",
        "precipitation.cumulativeChartAriaLabel": "Cumulative precipitation through {{hours}} hours, totaling {{total}}",
        "precipitation.cumulativeHeading": "Accumulation",
        "precipitation.now": "Now",
        "precipitation.table.amount": "Amount",
        "precipitation.table.chance": "Chance",
        "precipitation.table.cumulative": "Cumulative",
        "precipitation.table.time": "Time",
        "precipitation.tableCaption": "{{hours}}-hour precipitation details",
        "precipitation.title": "Precipitation",

        "subtitle": "{{temperature}} · {{condition}}",
        "unavailable": "Unavailable",
    ]
}
