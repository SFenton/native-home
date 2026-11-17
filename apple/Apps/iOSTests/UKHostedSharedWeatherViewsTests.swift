import HassCore
import UIKit
import XCTest
@testable import HassUI

/// The weather card's small drawn parts: the gauge rail that glides to a new range, the wind compass that turns the short way round,
/// and the measuring of the chart, gauge, arc and tile the sheet lays out.
@MainActor
final class UKHostedSharedWeatherViewsTests: XCTestCase {
    private func hosted(_ view: UIView, size: CGSize = CGSize(width: 300, height: 200)) -> UIWindow {
        let host = UIViewController()
        host.view.addSubview(view)
        view.frame = CGRect(origin: .zero, size: size)
        let window = HostedPage.show(host, size: size)
        host.view.layoutIfNeeded()
        return window
    }

    func testTheRailMovesItsMarkerWhenTheRangeChangesAndSnapsWhenMotionIsReduced() {
        let rail = UKWeatherRailView(tone: .temperature, range: WeatherRailRange(markerPercent: 10, rangeSizePercent: 20, rangeStartPercent: 30))
        let window = hosted(rail, size: CGSize(width: 200, height: 12))
        defer { window.isHidden = true }
        let marker = rail.subviews.last!
        let before = marker.frame.midX
        rail.update(WeatherRailRange(markerPercent: 90, rangeSizePercent: 20, rangeStartPercent: 30))
        HostedPage.wait(0.5)
        XCTAssertGreaterThan(marker.frame.midX, before + 50, "the marker glides to 90 percent")
        let detached = UKWeatherRailView(tone: .uv, range: WeatherRailRange(markerPercent: 90, rangeSizePercent: 20, rangeStartPercent: 30))
        detached.frame = CGRect(x: 0, y: 0, width: 200, height: 12)
        detached.layoutIfNeeded()
        let detachedMarker = detached.subviews.last!
        detached.update(WeatherRailRange(markerPercent: 5, rangeSizePercent: 0, rangeStartPercent: 0))
        XCTAssertLessThan(detachedMarker.frame.midX, 40, "a rail that is not on screen is placed at once")
        XCTAssertEqual(rail.intrinsicContentSize, CGSize(width: 48, height: 12))
    }

    func testTheCompassHidesItsNeedleWithoutADirectionAndTurnsTheShortWayRound() throws {
        let compass = UKWeatherCompassView(sourceDegrees: 350)
        let window = hosted(compass, size: CGSize(width: 140, height: 140))
        defer { window.isHidden = true }
        let dial = compass.face
        XCTAssertTrue(dial.isNeedleShown)
        XCTAssertEqual(dial.shownLetters, ["N", "E", "S", "W"])
        compass.update(sourceDegrees: 10)
        HostedPage.wait(0.4)
        XCTAssertEqual(dial.needleDegrees, 10, accuracy: 1.5, "350 to 10 turns 20 degrees, ending at 10")
        XCTAssertEqual(try XCTUnwrap(dial.turned), 370, accuracy: 0.01, "unwrapped: 20 on, not 340 back")
        let off = UKWeatherCompassView(sourceDegrees: 20)
        off.frame = CGRect(x: 0, y: 0, width: 140, height: 140)
        off.layoutIfNeeded()
        off.update(sourceDegrees: 200)
        XCTAssertEqual(abs(off.face.needleDegrees), 160, accuracy: 1.5, "off screen the needle is placed at once, the short way")
        XCTAssertEqual(off.face.animatedTurns, 0)
        compass.update(sourceDegrees: nil)
        XCTAssertFalse(dial.isNeedleShown, "no direction hides the needle")
        XCTAssertEqual(dial.shownLetters, ["N", "S"], "and drops E and W")
        compass.update(sourceDegrees: nil)
        XCTAssertFalse(dial.isNeedleShown)
    }

    func testTheCompassIsTheScaledSizeAndTheSameDialAnAuthorWouldWrite() {
        let compass = UKWeatherCompassView(sourceDegrees: 90)
        let window = hosted(compass, size: CGSize(width: 300, height: 200))
        defer { window.isHidden = true }
        XCTAssertEqual(compass.intrinsicContentSize, CGSize(width: 104, height: 104), "104 pt at the default text size")
        XCTAssertEqual(compass.face.dial, WeatherDialSpecs.compass())
        XCTAssertEqual(compass.face.dialFrame.width, 104, accuracy: 0.5)
        let needle = compass.face.placed?.needle
        XCTAssertEqual(needle?.rotation, 90)
        XCTAssertEqual(needle?.angle, 0)
        XCTAssertTrue(compass.sizeThatFits(CGSize(width: 300, height: 300)).width >= 104)
    }

    func testTheChartGaugeArcAndTileMeasureThemselvesForTheirGrid() {
        let chart = UKWeatherBarChartView(values: [10, nil, 40], domain: 50, axisLabels: ("50%", "25%", "0%"), hourLabels: ["1p", "2p", "3p"], tint: .systemBlue)
        let chartHeight = chart.gridHeight(forWidth: 280)
        XCTAssertGreaterThan(chartHeight, 76, "the plot plus its hour row")
        XCTAssertEqual(chart.sizeThatFits(CGSize(width: 280, height: 0)), CGSize(width: 280, height: chartHeight))

        let arc = UKWeatherSunArcView(percent: 40)
        XCTAssertEqual(arc.gridHeight(forWidth: 300), 96, "capped at 200 pt wide, 100:48")
        XCTAssertEqual(arc.sizeThatFits(CGSize(width: 300, height: 0)), CGSize(width: 200, height: 96))

        let gauge = UKWeatherPressureGaugeView(percent: 40, value: "1013", unit: "hPa")
        XCTAssertEqual(gauge.gridHeight(forWidth: 140), 100, accuracy: 0.001, "1.4 : 1")
        XCTAssertEqual(gauge.sizeThatFits(CGSize(width: 140, height: 0)).height, 100, accuracy: 0.001)

        gauge.heightAnchor.constraint(equalToConstant: 100).isActive = true
        let tile = UKWeatherTileView(title: "Pressure", symbol: "gauge", label: "Pressure", identifier: "t", value: "1013 hPa", content: gauge)
        XCTAssertEqual(tile.accessibilityLabel, "Pressure")
        XCTAssertEqual(tile.accessibilityValue, "1013 hPa")
        XCTAssertGreaterThan(tile.gridHeight(forWidth: 180), 100)
        XCTAssertEqual(tile.sizeThatFits(CGSize(width: 180, height: 0)).height, tile.gridHeight(forWidth: 180))
    }

    func testTheBarometerDrawsThroughTheDialWithItsValueAndUnitWhereTheHandBuiltViewPutThem() {
        let gauge = UKWeatherPressureGaugeView(percent: 40, value: "1013", unit: "hPa")
        let window = hosted(gauge, size: CGSize(width: 140, height: 100))
        defer { window.isHidden = true }
        let dial = gauge.face
        XCTAssertEqual(dial.dial, WeatherDialSpecs.barometer(hasUnit: true))
        XCTAssertEqual(dial.placed?.ticks.count, 49)
        XCTAssertNotNil(dial.placed?.lit)
        XCTAssertEqual(dial.centerLines.map(\.accessibilityLabel), ["1013", "hPa"])
        let block = dial.centerLines[0].frame.minY ... dial.centerLines[1].frame.maxY
        XCTAssertEqual((block.lowerBound + block.upperBound) / 2, 100 / 2 + 4, accuracy: 0.01, "half the height down and 4 pt: production's place, not the ring's 0.56")
        let bare = UKWeatherPressureGaugeView(percent: 40, value: "30.1", unit: nil)
        let bareWindow = hosted(bare, size: CGSize(width: 140, height: 100))
        defer { bareWindow.isHidden = true }
        XCTAssertEqual(bare.face.centerLines.count, 1, "no unit, no second line")
    }

    /// Production's arithmetic, `top = (height - total) / 2 + 4` with each line's height rounded up, at two widths and an accessibility text size.
    func testTheBarometerTextTopIsProductionsAtTwoWidthsAndAnAccessibilitySize() {
        for (width, category) in [(93.0, UIContentSizeCategory.large), (140, .large), (140, .accessibilityExtraExtraExtraLarge)] {
            let gauge = UKWeatherPressureGaugeView(percent: 40, value: "1013", unit: "hPa")
            gauge.traitOverrides.preferredContentSizeCategory = category
            let height = width / 1.4
            let window = hosted(gauge, size: CGSize(width: width, height: height))
            defer { window.isHidden = true }
            gauge.layoutIfNeeded()
            gauge.face.layoutIfNeeded()
            let lines = gauge.face.centerLines
            let heights = lines.map { ceil($0.gridHeight(forWidth: width)) }
            let total = heights.reduce(0, +)
            XCTAssertEqual(lines[0].frame.minY, (height - total) / 2 + 4, accuracy: 0.01, "width \(width), \(category.rawValue)")
            XCTAssertEqual(lines[1].frame.minY, lines[0].frame.minY + heights[0], accuracy: 0.01)
        }
    }

    /// The value and unit are drawn in the fonts, and take the heights, the hand-built labels had (`UILabel.uk`), at the default and an accessibility size.
    func testTheBarometerLinesAreProductionsFontsAndHeights() {
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraLarge] {
            let gauge = UKWeatherPressureGaugeView(percent: 40, value: "1013", unit: "hPa")
            gauge.traitOverrides.preferredContentSizeCategory = category
            let window = hosted(gauge, size: CGSize(width: 338, height: 229.3))
            defer { window.isHidden = true }
            let value = UILabel.uk(.title3, weight: .bold, monospacedDigit: true, ink: .white, lines: 1, alignment: .center)
            let unit = UILabel.uk(.caption1, ink: .white, lines: 1, alignment: .center)
            value.text = "1013"
            unit.text = "hPa"
            gauge.addSubview(value)
            gauge.addSubview(unit)
            gauge.layoutIfNeeded()
            let lines = gauge.face.centerLines
            XCTAssertEqual(lines[0].drawnFont.pointSize, value.font.pointSize, accuracy: 0.01, "value font at \(category.rawValue)")
            XCTAssertEqual(lines[1].drawnFont.pointSize, unit.font.pointSize, accuracy: 0.01, "unit font at \(category.rawValue)")
            XCTAssertEqual(ceil(lines[0].gridHeight(forWidth: 338)), ceil(value.sizeThatFits(CGSize(width: 338, height: 200)).height), "value height at \(category.rawValue)")
            XCTAssertEqual(ceil(lines[1].gridHeight(forWidth: 338)), ceil(unit.sizeThatFits(CGSize(width: 338, height: 200)).height), "unit height at \(category.rawValue)")
        }
    }

    func testTheBarometerRingFitsATileTallerThanItsShapeAsTheHandBuiltViewDid() {
        let gauge = UKWeatherPressureGaugeView(percent: 40, value: "1013", unit: "hPa")
        let window = hosted(gauge, size: CGSize(width: 402, height: 229.3))
        defer { window.isHidden = true }
        gauge.layoutIfNeeded()
        XCTAssertEqual(gauge.face.dialFrame.width, 1.4 * 229.3, accuracy: 0.5, "no wider than 1.4 times the tile's height")
        XCTAssertEqual(gauge.face.dialFrame.height, 229.3, accuracy: 0.5, "and so it does not clip at the bottom")
        XCTAssertEqual(gauge.face.dialFrame.minY + CGFloat(gauge.face.placed?.cy ?? 0), 0.56 * 229.3, accuracy: 0.3)
    }

    func testTheSunArcDrawsThroughTheArcTrackAndHidesItsMarkerWithoutProgress() {
        let arc = UKWeatherSunArcView(percent: 50)
        let window = hosted(arc, size: CGSize(width: 300, height: 96))
        defer { window.isHidden = true }
        arc.track.setNeedsDisplay()
        HostedPage.wait(0.2)
        XCTAssertEqual(arc.track.arc, WeatherDialSpecs.sunArc())
        XCTAssertEqual(arc.track.placed?.width, 200)
        XCTAssertEqual(arc.track.placed?.marker?.x, 100, "the middle of the day is the middle of the curve")
        let night = UKWeatherSunArcView(percent: nil)
        let nightWindow = hosted(night, size: CGSize(width: 300, height: 96))
        defer { nightWindow.isHidden = true }
        night.track.setNeedsDisplay()
        HostedPage.wait(0.2)
        XCTAssertNil(night.track.placed?.marker, "the sun is below the horizon: no marker")
    }
}
