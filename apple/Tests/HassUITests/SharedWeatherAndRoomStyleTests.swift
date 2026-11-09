import HassCore
import HassDesign
import Testing
@testable import HassUI

/// The symbols the weather sheet draws and the colour families the room cards take.
struct SharedWeatherAndRoomStyleTests {
    @Test func everyHomeAssistantConditionHasASymbolAndNightSwapsTheSkyOnes() {
        #expect(WeatherSymbols.condition("sunny") == "sun.max.fill")
        #expect(WeatherSymbols.condition("sunny", night: true) == "moon.stars.fill")
        #expect(WeatherSymbols.condition("clear-night") == "moon.stars.fill")
        #expect(WeatherSymbols.condition("partlycloudy") == "cloud.sun.fill")
        #expect(WeatherSymbols.condition("partlycloudy", night: true) == "cloud.moon.fill")
        #expect(WeatherSymbols.condition("rainy") == "cloud.rain.fill")
        #expect(WeatherSymbols.condition("rainy", night: true) == "cloud.moon.rain.fill")
        let fixed = ["cloudy": "cloud.fill", "pouring": "cloud.heavyrain.fill", "snowy": "cloud.snow.fill", "snowy-rainy": "cloud.sleet.fill",
                     "lightning": "cloud.bolt.fill", "lightning-rainy": "cloud.bolt.rain.fill", "fog": "cloud.fog.fill",
                     "hail": "cloud.hail.fill", "windy": "wind", "windy-variant": "smoke.fill", "exceptional": "exclamationmark.triangle.fill"]
        for (key, symbol) in fixed { #expect(WeatherSymbols.condition(key) == symbol) }
        #expect(WeatherSymbols.condition(nil) == "cloud.fill")
        #expect(WeatherSymbols.condition("unknown") == "cloud.fill")
    }

    @Test func everyHazardAndHighlightHasADistinctlyNamedSymbol() {
        for hazard in WeatherHazard.allCases { #expect(!WeatherSymbols.hazard(hazard).isEmpty) }
        #expect(WeatherSymbols.hazard(.extremeCold) == "thermometer.snowflake")
        #expect(WeatherSymbols.hazard(.poorAir) == "aqi.medium")
        #expect(WeatherSymbols.hazard(.severeStorms) == "cloud.bolt.fill")
        for kind in WeatherHighlight.Kind.allCases { #expect(!WeatherSymbols.highlight(kind).isEmpty) }
        #expect(WeatherSymbols.highlight(.sun, sun: .sunrise) == "sunrise.fill")
        #expect(WeatherSymbols.highlight(.sun, sun: .sunset) == "sunset.fill")
        #expect(WeatherSymbols.highlight(.sun) == "sunset.fill")
        #expect(WeatherSymbols.highlight(.visibility) == "eye.fill")
    }

    @Test func hourlyModesAndTheNameListsCoverEverySymbolDrawn() {
        #expect(WeatherSymbols.mode(.condition) == "cloud.fill")
        #expect(WeatherSymbols.mode(.precipitation) == "drop.fill")
        #expect(WeatherSymbols.mode(.wind) == "wind")
        #expect(WeatherSymbols.conditionNames.contains("cloud.moon.rain.fill"))
        #expect(WeatherSymbols.conditionNames == Array(Set(WeatherSymbols.conditionNames)).sorted())
        #expect(Set(WeatherSymbols.conditionNames).isSubset(of: WeatherSymbols.allNames))
        #expect(WeatherSymbols.allNames.contains("sunrise.fill"))
        #expect(WeatherSymbols.leadingInset(of: "cloud.sun.fill") == 0.05625)
        #expect(WeatherSymbols.leadingInset(of: "nothing") == 0)
    }

    @Test func eachRoomToneMapsToItsColourFamilyAndWarningAndNeutralHaveNone() {
        let tones: [(RoomTone, ColorFamily?)] = [
            (.light, .lights), (.air, .air), (.climate, .climate), (.presence, .occupancy), (.contact, .contact),
            (.vacuum, .cleaning), (.media, .media), (.power, .power), (.warning, nil), (.neutral, nil),
        ]
        for (tone, family) in tones {
            #expect(tone.family == family)
            _ = tone.color
        }
    }

    @Test func aRoomColourBecomesATokenWithItsOpacityAsAlpha() {
        let token = RoomColor(51, 102, 153, opacity: 0.4).token
        #expect(token == HassRGB(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.4))
    }

    @Test func roomCardKindsPickTheirFamilyAndAHeatWaveIconIsPower() {
        #expect(RoomTileFace.family(.light, icon: "mdi:lightbulb") == .lights)
        #expect(RoomTileFace.family(.light, icon: "mdi:heat-wave") == .power)
        #expect(RoomTileFace.family(.wakeLight, icon: "mdi:heat-wave") == .power)
        let expected: [RoomCardKind: ColorFamily] = [
            .air: .air, .fan: .air, .vent: .vents, .humidifier: .water, .climate: .neutral, .occupancy: .occupancy,
            .contact: .contact, .vacuum: .cleaning, .appliance: .cleaning, .laundry: .cleaning, .media: .media, .power: .power, .grill: .cooking,
        ]
        for (kind, family) in expected { #expect(RoomTileFace.family(kind, icon: "mdi:x") == family) }
    }
}
