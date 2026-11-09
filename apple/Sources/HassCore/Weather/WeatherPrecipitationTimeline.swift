import Foundation

/// Chart math for the Precipitation highlight tiles.
/// Source: `ha-sfenton-react-dash@f5a7bf9:src/components/hass/precipitationTimeline.ts`.
public enum WeatherPrecipitationTimeline {
    private static let chanceDomainMinimum = 10.0
    private static let chanceDomainStep = 10.0
    private static let chanceDomainMaximum = 100.0
    private static let axisFactors: [Double] = [1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 7.5, 10]
    private static let axisEpsilon = 1e-9

    /// Builds hourly points for the first `limit` forecasts. Negative values clamp to 0 and chance caps at 100.
    public static func points(_ forecasts: [WeatherForecast], limit: Int = 24) -> [PrecipitationPoint] {
        var cumulative: Double? = 0
        return forecasts.prefix(limit).enumerated().map { index, forecast in
            let start = forecast.start
            let probability = forecast.precipitationProbability.flatMap(finite).map { max(0, $0) }
            let amount = forecast.precipitation.flatMap(finite).map { max(0, $0) }
            if let running = cumulative, let amount { cumulative = running + amount } else { cumulative = nil }
            return PrecipitationPoint(
                amount: amount, cumulative: cumulative, endTime: start?.addingTimeInterval(3600), index: index,
                probability: probability.map { min(100, $0) }, startTime: start
            )
        }
    }

    private static func finite(_ value: Double) -> Double? { value.isFinite ? value : nil }

    /// The highest chance in the window, or `nil` when none is known.
    public static func peakChance(_ points: [PrecipitationPoint]) -> Double? {
        points.compactMap(\.probability).max()
    }

    /// The final running total, or `nil` when any hour was unknown.
    public static func total(_ points: [PrecipitationPoint]) -> Double? {
        points.last?.cumulative
    }

    /// The chance axis top: the peak rounded up to the next 10, at least 10 and at most 100.
    public static func chanceDomain(peak: Double?) -> Double {
        guard let peak, peak.isFinite else { return chanceDomainMinimum }
        let bounded = min(chanceDomainMaximum, max(0, peak))
        return min(chanceDomainMaximum, max(chanceDomainMinimum, (bounded / chanceDomainStep).rounded(.up) * chanceDomainStep))
    }

    /// A value as a 0...100 share of the domain.
    public static func scaledPercent(_ value: Double?, domain: Double) -> Double {
        guard let value, value.isFinite, domain.isFinite, domain > 0 else { return 0 }
        return roundedAxisValue(min(100, max(0, value / domain * 100)))
    }

    private static func roundedAxisValue(_ value: Double, digits: Int = 6) -> Double {
        let factor = pow(10, Double(digits))
        return ((value + Double.ulpOfOne) * factor).rounded() / factor
    }

    private static func decimalPlaces(_ value: Double, maximumFractionDigits: Int) -> Int {
        var fixed = String(format: "%.\(maximumFractionDigits)f", roundedAxisValue(value, digits: maximumFractionDigits))
        while fixed.hasSuffix("0") { fixed.removeLast() }
        guard let dot = fixed.firstIndex(of: ".") else { return 0 }
        return fixed.distance(from: dot, to: fixed.endIndex) - 1
    }

    /// A "nice" accumulation axis: two equal steps up to a domain at least the total.
    public static func amountAxis(total: Double?, unit: String) -> PrecipitationAmountAxis {
        let metric = unit.trimmingCharacters(in: .whitespaces).lowercased().contains("mm")
        let minimumStep = metric ? 0.25 : 0.01
        let maximumFractionDigits = metric ? 2 : 3
        let bounded = total.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 0
        let targetStep = max(minimumStep, bounded / 2)
        let startingExponent = Int(log10(targetStep).rounded(.down))

        for exponent in (startingExponent - 1)...(startingExponent + 12) {
            let magnitude = pow(10, Double(exponent))
            for factor in axisFactors {
                let step = roundedAxisValue(factor * magnitude)
                if step + axisEpsilon < targetStep || step + axisEpsilon < minimumStep { continue }
                let domain = roundedAxisValue(step * 2)
                let digits = max(
                    decimalPlaces(step, maximumFractionDigits: maximumFractionDigits + 2),
                    decimalPlaces(domain, maximumFractionDigits: maximumFractionDigits + 2)
                )
                if digits > maximumFractionDigits { continue }
                return PrecipitationAmountAxis(domain: domain, maximumFractionDigits: digits, step: step)
            }
        }
        let step = roundedAxisValue(targetStep, digits: maximumFractionDigits)
        return PrecipitationAmountAxis(
            domain: roundedAxisValue(step * 2, digits: maximumFractionDigits), maximumFractionDigits: maximumFractionDigits, step: step
        )
    }

    /// Every `cadence`-th label index so labels fit the available width.
    public static func labelIndices(count: Int, cadence: Int) -> [Int] {
        guard count > 0 else { return [] }
        let step = max(1, cadence)
        return (0..<count).filter { $0 % step == 0 }
    }

    /// How many hours apart axis labels sit (`precipitationLabelCadence`).
    public static func labelCadence(count: Int, plotWidth: Double, widestLabelWidth: Double, gap: Double = 6) -> Int {
        if count <= 0 { return 1 }
        if plotWidth <= 0 || widestLabelWidth <= 0 { return max(1, Int((Double(count) / 4).rounded(.up))) }
        let capacity = max(1, Int((plotWidth / (widestLabelWidth + gap)).rounded(.down)))
        return max(1, Int((Double(count) / Double(capacity)).rounded(.up)))
    }
}
