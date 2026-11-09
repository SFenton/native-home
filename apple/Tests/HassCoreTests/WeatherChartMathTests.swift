import Foundation
@testable import HassCore
import Testing

/// Ported from `precipitationTimeline.test.ts` (`ha-sfenton-react-dash@f5a7bf9`) plus the hourly metric series.
struct WeatherChartMathTests {
    @Test func keepsProbabilityAndAmountIndependentWhileAccumulatingAmounts() throws {
        let points = WeatherPrecipitationTimeline.points([
            WeatherForecast(datetime: "2026-08-27T12:00:00-07:00", precipitation: 0, precipitationProbability: 94),
            WeatherForecast(datetime: "2026-08-27T13:00:00-07:00", precipitation: 0.07, precipitationProbability: 40),
            WeatherForecast(datetime: "2026-08-27T14:00:00-07:00", precipitation: 0.02, precipitationProbability: 20),
        ])
        #expect(points.map(\.probability) == [94, 40, 20])
        #expect(points.map(\.amount) == [0, 0.07, 0.02])
        #expect(try abs(#require(WeatherPrecipitationTimeline.total(points)) - 0.09) < 1e-9)
        #expect(points[0].endTime == HassDates.iso8601("2026-08-27T20:00:00Z"))
        #expect(WeatherPrecipitationTimeline.peakChance(points) == 94)
    }

    @Test func clampsInvalidProviderValuesWithoutInventingBars() {
        let points = WeatherPrecipitationTimeline.points([
            WeatherForecast(precipitation: -1, precipitationProbability: -20),
            WeatherForecast(precipitation: nil, precipitationProbability: 140),
        ])
        #expect(points[0].amount == 0 && points[0].cumulative == 0 && points[0].probability == 0)
        #expect(points[1].amount == nil && points[1].cumulative == nil && points[1].probability == 100)
    }

    @Test func aMissingBucketPoisonsLaterCumulativeValues() {
        let points = WeatherPrecipitationTimeline.points([
            WeatherForecast(precipitation: 0.2, precipitationProbability: 0),
            WeatherForecast(precipitation: nil, precipitationProbability: 65),
            WeatherForecast(precipitation: 0.3),
        ])
        #expect(points.map(\.amount) == [0.2, nil, 0.3])
        #expect(points.map(\.cumulative) == [0.2, nil, nil])
        #expect(points.map(\.probability) == [0, 65, nil])
        #expect(WeatherPrecipitationTimeline.total(points) == nil)
        #expect(WeatherPrecipitationTimeline.total([]) == nil)
    }

    @Test func distinguishesTrueZeroFromUnknown() {
        let zero = WeatherPrecipitationTimeline.points([WeatherForecast(precipitation: 0), WeatherForecast(precipitation: 0, precipitationProbability: 0)])
        #expect(zero.map(\.cumulative) == [0, 0])
        #expect(zero.map(\.probability) == [nil, 0])
        #expect(WeatherPrecipitationTimeline.total(zero) == 0)
        let missing = WeatherPrecipitationTimeline.points([WeatherForecast(), WeatherForecast(precipitation: .nan, precipitationProbability: .infinity)])
        #expect(missing.map(\.cumulative) == [nil, nil])
        #expect(WeatherPrecipitationTimeline.total(missing) == nil)
        #expect(WeatherPrecipitationTimeline.peakChance(missing) == nil)
    }

    @Test func limitsThePointCount() {
        let many = (0..<30).map { _ in WeatherForecast(precipitation: 0.01) }
        #expect(WeatherPrecipitationTimeline.points(many).count == 24)
        #expect(WeatherPrecipitationTimeline.points(many, limit: 6).count == 6)
    }

    @Test func labelCadenceFitsTheWidth() {
        #expect(WeatherPrecipitationTimeline.labelCadence(count: 24, plotWidth: 153, widestLabelWidth: 32) == 6)
        #expect(WeatherPrecipitationTimeline.labelIndices(count: 24, cadence: 6) == [0, 6, 12, 18])
        #expect(WeatherPrecipitationTimeline.labelCadence(count: 24, plotWidth: 326, widestLabelWidth: 32) == 3)
        #expect(WeatherPrecipitationTimeline.labelIndices(count: 24, cadence: 3) == [0, 3, 6, 9, 12, 15, 18, 21])
        #expect(WeatherPrecipitationTimeline.labelCadence(count: 0, plotWidth: 100, widestLabelWidth: 10) == 1)
        #expect(WeatherPrecipitationTimeline.labelCadence(count: 24, plotWidth: 0, widestLabelWidth: 10) == 6)
        #expect(WeatherPrecipitationTimeline.labelIndices(count: 0, cadence: 3).isEmpty)
        #expect(WeatherPrecipitationTimeline.labelIndices(count: 3, cadence: 0) == [0, 1, 2])
    }

    @Test(arguments: [
        (nil as Double?, 10.0), (0, 10), (1, 10), (5, 10), (9, 10), (10, 10), (11, 20), (20, 20), (21, 30), (26, 30), (41, 50),
        (50, 50), (51, 60), (60, 60), (75, 80), (94, 100), (100, 100),
    ])
    func chanceDomain(peak: Double?, expected: Double) {
        #expect(WeatherPrecipitationTimeline.chanceDomain(peak: peak) == expected)
    }

    @Test(arguments: [
        (0.0, "in", 0.02, 0.01, 2), (0.005, "in", 0.02, 0.01, 2), (0.01, "in", 0.02, 0.01, 2), (0.02, "in", 0.02, 0.01, 2),
        (0.04, "in", 0.04, 0.02, 2), (0.09, "in", 0.1, 0.05, 2), (0.12, "in", 0.12, 0.06, 2), (0.19, "in", 0.2, 0.1, 1),
        (1.01, "in", 1.2, 0.6, 1), (0, "mm", 0.5, 0.25, 2), (0.1, "mm", 0.5, 0.25, 2), (0.7, "mm", 0.8, 0.4, 1),
        (2.286, "mm", 2.5, 1.25, 2), (7.3, "mm", 8, 4, 0), (130, "mm", 150, 75, 0),
    ])
    func amountAxis(total: Double, unit: String, domain: Double, step: Double, digits: Int) {
        #expect(WeatherPrecipitationTimeline.amountAxis(total: total, unit: unit) == PrecipitationAmountAxis(domain: domain, maximumFractionDigits: digits, step: step))
    }

    @Test func amountAxisCopesWithUnknownTotals() {
        #expect(WeatherPrecipitationTimeline.amountAxis(total: nil, unit: "in").domain == 0.02)
        #expect(WeatherPrecipitationTimeline.amountAxis(total: -5, unit: "in").domain == 0.02)
        #expect(WeatherPrecipitationTimeline.amountAxis(total: .infinity, unit: "mm").domain == 0.5)
    }

    @Test func scalesValuesIntoTheirDomain() {
        #expect(WeatherPrecipitationTimeline.scaledPercent(5, domain: 10) == 50)
        #expect(WeatherPrecipitationTimeline.scaledPercent(9, domain: 10) == 90)
        #expect(WeatherPrecipitationTimeline.scaledPercent(41, domain: 50) == 82)
        #expect(WeatherPrecipitationTimeline.scaledPercent(0.09, domain: 0.1) == 90)
        #expect(WeatherPrecipitationTimeline.scaledPercent(100, domain: 100) == 100)
        #expect(WeatherPrecipitationTimeline.scaledPercent(120, domain: 100) == 100)
        #expect(WeatherPrecipitationTimeline.scaledPercent(nil, domain: 100) == 0)
        #expect(WeatherPrecipitationTimeline.scaledPercent(5, domain: 0) == 0)
    }

    @Test func hourlyMetricsTakeSixClampedHours() {
        let forecasts = (0..<10).map {
            WeatherForecast(datetime: "2026-09-05T\(String(format: "%02d", $0)):00:00Z", cloudCoverage: Double($0) * 20, humidity: $0 == 2 ? nil : 150)
        }
        let points = WeatherHourlyMetrics.points(forecasts)
        #expect(points.count == 6)
        #expect(points[2].humidity == nil)
        #expect(points[0].humidity == 100)
        #expect(points[5].cloudCover == 100)
        #expect(points[3].cloudCover == 60)
        #expect(points[1].time == HassDates.iso8601("2026-09-05T01:00:00Z"))
    }
}
