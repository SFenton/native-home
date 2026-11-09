import Foundation

/// The colours the web paints a status chip's icon and card with when Home Assistant supplies one, so the native chips
/// can follow them (`.agents/patterns/status-rail.md`, "Chip colours").
///
/// Sources (`ha-sfenton-react-dash@9ac2a46`): `src/components/hass/StatusRail.tsx:45-54` (`colorEntityId` text helpers
/// tint a chip's icon), `src/components/cards/climateColor.ts:8-15,49-59` (`colorFromRgba`, then the temperature
/// gradient, for every climate card) and `src/components/cards/ClimateCard.tsx:71` (helper first, then gradient).
public enum ChipWebColor {
    // MARK: - Climate

    /// The colour helper that goes with a climate range helper: `input_text.demo_room_climate_range` →
    /// `input_text.demo_room_climate_color`; `nil` for any other entity.
    public static func climateColorEntityId(forRange rangeEntityId: String) -> String? {
        guard rangeEntityId.hasPrefix("input_text."), rangeEntityId.hasSuffix("_climate_range") else { return nil }
        return String(rangeEntityId.dropLast("_range".count)) + "_color"
    }

    /// A climate chip's colour: the helper's `rgba()` when it parses, else the web's temperature gradient at the mean of
    /// the range text ("70.1°F - 78.6°F"); `nil` when neither is available.
    /// - Parameters:
    ///   - colorText: The colour helper's state.
    ///   - rangeText: The range helper's state.
    public static func climate(colorText: String?, rangeText: String?) -> RoomColor? {
        if let color = RoomOverview.colorFromRgba(colorText) { return color }
        return RoomOverview.colorFromTemperature(meanTemperature(rangeText))
    }

    /// The mean of the numbers in a range text, in °F ("70.1°F - 78.6°F" → 74.35; Celsius ranges are converted); `nil` when
    /// it holds no number.
    public static func meanTemperature(_ text: String?) -> Double? {
        guard let text, !EntityState.isUnavailable(text) else { return nil }
        let numbers = text.matches(of: /\d+(?:\.\d+)?/).compactMap { Double($0.output) }
        guard !numbers.isEmpty else { return nil }
        let mean = numbers.reduce(0, +) / Double(numbers.count)
        return text.contains("°C") ? mean * 9 / 5 + 32 : mean
    }

    // MARK: - Air quality

    /// The web's default air teal (`rgb(0, 150, 136)`), used while the AQI helper has no colour.
    public static let airTeal = RoomColor(0, 150, 136)

    /// An AQI chip's colour: the helper's `rgb()`, `rgba()` or `#rrggbb`, else the web teal.
    public static func airQuality(colorText: String?) -> RoomColor {
        RoomOverview.colorFromCss(colorText) ?? airTeal
    }

    /// The AQI colour helper of the room a purifier's PM2.5 sensor belongs to (`input_text.demo_room_aqi_color`), or `nil`
    /// for a sensor no room lists.
    public static func airColorEntityId(forPM25 pm25EntityId: String) -> String? {
        RoomOverview.airQualityRooms.first { $0.pm25EntityId == pm25EntityId }?.colorEntityId
    }
}

public extension RoomColor {
    /// The colour as `0xRRGGBB`.
    var rgb: UInt32 {
        func channel(_ value: Double) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return channel(red) << 16 | channel(green) << 8 | channel(blue)
    }
}
