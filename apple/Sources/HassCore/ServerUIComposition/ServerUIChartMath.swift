import Foundation

// MARK: - Chart arithmetic

/// The arithmetic of a `chart` (`sh.chart@1`): the axis a series gets, where its marks stand, which labels fit and what a screen reader says.
///
/// It is the Studio's `chart-math.ts` (the one the preview draws with), which in turn is the precipitation and hourly charts of the weather
/// panel made generic (``WeatherPrecipitationTimeline``). The shared evaluation corpus (`ContractCorpus/evaluation/chart-*.json`) pins every
/// function here with the Studio's numbers, so a published chart draws what the Studio showed. It holds values only: no view, no state.
public enum ServerUIChartMath {
    /// The factors a two-step axis tries at each power of ten, in order.
    public static let axisFactors: [Double] = [1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6, 7.5, 10]
    private static let epsilon = 1e-9

    // MARK: Rounding

    /// A value rounded to `digits` places the way the axis math does: a tie goes away from zero, after nudging by one ulp.
    public static func roundedAxisValue(_ value: Double, digits: Int = 6) -> Double {
        let factor = pow(10, Double(digits))
        return ((value + Double.ulpOfOne) * factor).rounded() / factor
    }

    /// Places after the point once trailing zeros are dropped, at most `maximumFractionDigits` looked at.
    private static func decimalPlaces(_ value: Double, maximumFractionDigits: Int) -> Int {
        var fixed = String(format: "%.\(maximumFractionDigits)f", roundedAxisValue(value, digits: maximumFractionDigits))
        while fixed.hasSuffix("0") { fixed.removeLast() }
        guard let dot = fixed.firstIndex(of: ".") else { return 0 }
        return fixed.distance(from: dot, to: fixed.endIndex) - 1
    }

    // MARK: Axis

    /// The highest known value of a series, or `nil` when none is known.
    public static func peak(of values: [Double?]) -> Double? {
        values.compactMap { $0 }.filter(\.isFinite).max()
    }

    /// The axis top of a `ceiling` domain: the peak rounded up to the next `step`, at least `min` and at most `max`; `min` when no value is known.
    public static func ceilingDomain(peak: Double?, step: Double, min lowest: Double, max highest: Double) -> Double {
        guard let peak, peak.isFinite, step > 0 else { return lowest }
        let bounded = min(highest, max(0, peak))
        return min(highest, max(lowest, (bounded / step).rounded(.up) * step))
    }

    /// What a two-step axis chose: its top, the step (the middle label) and the most fraction digits a label needs.
    public struct TwoStepAxis: Equatable, Sendable {
        /// The top of the axis.
        public let domain: Double
        /// The size of each of the two steps.
        public let step: Double
        /// The most places after the point a label needs.
        public let digits: Int
    }

    /// A "nice" axis of two equal steps up to a top at least `total`: the smallest `factor * 10^n` step that is at least `total / 2` and `minimumStep`
    /// and prints in at most `maximumFractionDigits` places. A total that is unknown, negative or not finite counts as 0; a step that cannot be
    /// positive gives an axis of no height (`domain` 0), which draws every bar as its stub.
    public static func twoStepDomain(total: Double?, minimumStep: Double, maximumFractionDigits: Int,
                                     factors: [Double] = axisFactors) -> TwoStepAxis {
        let bounded = total.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 0
        let target = max(minimumStep, bounded / 2)
        guard target.isFinite, target > 0 else { return TwoStepAxis(domain: 0, step: 0, digits: 0) }
        let start = Int(log10(target).rounded(.down))
        for exponent in (start - 1)...(start + 12) {
            let magnitude = pow(10, Double(exponent))
            for factor in factors {
                let step = roundedAxisValue(factor * magnitude)
                if step + epsilon < target || step + epsilon < minimumStep { continue }
                let domain = roundedAxisValue(step * 2)
                let digits = max(decimalPlaces(step, maximumFractionDigits: maximumFractionDigits + 2),
                                 decimalPlaces(domain, maximumFractionDigits: maximumFractionDigits + 2))
                if digits > maximumFractionDigits { continue }
                return TwoStepAxis(domain: domain, step: step, digits: digits)
            }
        }
        let step = roundedAxisValue(target, digits: maximumFractionDigits)
        return TwoStepAxis(domain: roundedAxisValue(step * 2, digits: maximumFractionDigits), step: step, digits: maximumFractionDigits)
    }

    /// A value as a 0 to 100 share of the axis from `base` to `top`: unknown, or an axis with no height, is 0. Outside the axis it is held at the nearest end.
    public static func scaledPercent(_ value: Double?, top: Double, base: Double = 0) -> Double {
        guard let value, value.isFinite, top.isFinite, base.isFinite, top - base > 0 else { return 0 }
        return roundedAxisValue(min(100, max(0, (value - base) / (top - base) * 100)))
    }

    // MARK: Labels

    /// Every `cadence`-th label index, so the labels fit. A cadence below 1 shows every label.
    public static func labelIndices(count: Int, cadence: Int) -> [Int] {
        guard count > 0 else { return [] }
        let step = max(1, cadence)
        return (0..<count).filter { $0 % step == 0 }
    }

    /// How many marks apart labels sit: the count over how many labels fit in the plot, each with a gap of 6 points. With no width or no label width
    /// to go by it shows a quarter of them.
    public static func labelCadence(count: Int, plotWidth: Double, widestLabelWidth: Double, gap: Double = 6) -> Int {
        guard count > 0 else { return 1 }
        if plotWidth <= 0 || widestLabelWidth <= 0 { return max(1, Int((Double(count) / 4).rounded(.up))) }
        let capacity = max(1, Int((plotWidth / (widestLabelWidth + gap)).rounded(.down)))
        return max(1, Int((Double(count) / Double(capacity)).rounded(.up)))
    }

    /// A number with up to `digits` fraction digits and `en-US` grouping, a tie going away from zero.
    public static func axisNumber(_ value: Double, digits: Int) -> String {
        WeatherFormat.number(value, digits: digits) ?? ""
    }

    /// An axis label or a spoken value: `pattern` with `{value}` replaced by the number.
    public static func axisText(pattern: String, value: Double, digits: Int) -> String {
        pattern.replacingOccurrences(of: "{value}", with: axisNumber(value, digits: digits))
    }

    /// The value of each axis level from the top down: `levels` of them, evenly from the top of the axis to its base.
    public static func axisLevels(_ levels: Int, top: Double, base: Double = 0) -> [Double] {
        guard levels > 1 else { return levels == 1 ? [roundedAxisValue(top)] : [] }
        return (0..<levels).map { roundedAxisValue(top - (top - base) * Double($0) / Double(levels - 1)) }
    }

    // MARK: Marks

    /// One bar as drawn: its column, and its height in points. An unknown value is a short stub, never a bar of zero.
    public struct BarMark: Equatable, Sendable {
        /// The position of the bar in the series.
        public let index: Int
        /// The left edge, in points from the plot's leading edge.
        public let x: Double
        /// The width of the column.
        public let width: Double
        /// The height, from the base.
        public let height: Double
        /// Whether the value is unknown.
        public let unknown: Bool
    }

    /// The bars of a series in a plot `width` by `height` points: equal columns with `gap` between, each as tall as its share of the axis, never shorter
    /// than `minimum` once it is above zero, and an unknown one `minimum` tall.
    public static func barMarks(_ values: [Double?], top: Double, base: Double = 0, width: Double, height: Double, gap: Double,
                                minimum: Double) -> [BarMark] {
        let count = Double(max(values.count, 1))
        let column = max(0, (width - gap * (count - 1)) / count)
        return values.enumerated().map { index, value in
            let unknown = value.map { !$0.isFinite } ?? true
            let percent = scaledPercent(value, top: top, base: base)
            return BarMark(index: index, x: Double(index) * (column + gap), width: column,
                           height: unknown ? minimum : max(percent > 0 ? minimum : 0, height * percent / 100), unknown: unknown)
        }
    }

    /// One point of a line or an area: the middle of its slot and its distance from the top of the plot, or `nil` where the value is unknown.
    public struct PointMark: Equatable, Sendable {
        /// The position of the point in the series.
        public let index: Int
        /// The middle of the slot.
        public let x: Double
        /// Points from the top of the plot, or `nil` where the line breaks.
        public let y: Double?
    }

    /// The points of a series for a line: the middle of each of the equal slots across `width`, `y` measured from the top of a plot `height` points tall.
    public static func pointMarks(_ values: [Double?], top: Double, base: Double = 0, width: Double, height: Double) -> [PointMark] {
        let count = Double(max(values.count, 1))
        return values.enumerated().map { index, value in
            let known = value.flatMap { $0.isFinite ? $0 : nil }
            return PointMark(index: index, x: (Double(index) + 0.5) * width / count,
                             y: known.map { height - height * scaledPercent($0, top: top, base: base) / 100 })
        }
    }

    // MARK: Spoken

    /// What a screen reader says for a series: each label and its value, in order (`Now 94%, 7 PM 40%`); an unknown value says `unknownText`.
    public static func seriesText(_ points: [ServerUIChart.Point], pattern: String, digits: Int, unknownText: String) -> String {
        points.map { point in
            let value = point.value.flatMap { $0.isFinite ? $0 : nil }.map { axisText(pattern: pattern, value: $0, digits: digits) } ?? unknownText
            return "\(point.label) \(value)"
        }.joined(separator: ", ")
    }
}
