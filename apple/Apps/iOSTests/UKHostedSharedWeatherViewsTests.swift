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

    func testTheCompassHidesItsNeedleWithoutADirectionAndTurnsTheShortWayRound() {
        let compass = UKWeatherCompassView(sourceDegrees: 350)
        let window = hosted(compass, size: CGSize(width: 140, height: 140))
        defer { window.isHidden = true }
        let needle = compass.subviews.compactMap { $0 as? UKWindNeedleView }.first
        XCTAssertNotNil(needle)
        XCTAssertEqual(needle?.isHidden, false)
        compass.update(sourceDegrees: 10)
        HostedPage.wait(0.4)
        let turned = atan2(needle!.transform.b, needle!.transform.a) * 180 / .pi
        XCTAssertEqual(turned, 370 - 360, accuracy: 1.5, "350 to 10 turns 20 degrees, ending at 10")
        let off = UKWeatherCompassView(sourceDegrees: 20)
        let offNeedle = off.subviews.compactMap { $0 as? UKWindNeedleView }.first
        off.update(sourceDegrees: 200)
        XCTAssertEqual(abs(atan2(offNeedle!.transform.b, offNeedle!.transform.a) * 180 / .pi), 160, accuracy: 1.5,
                       "off screen the needle is placed at once, the short way")
        compass.update(sourceDegrees: nil)
        XCTAssertEqual(needle?.isHidden, true, "no direction hides the needle")
        compass.update(sourceDegrees: nil)
        XCTAssertEqual(needle?.isHidden, true)
    }

    func testTheChartGaugeArcAndTileMeasureThemselvesForTheirGrid() {
        let chart = UKWeatherBarChartView(values: [10, nil, 40], domain: 50, axisLabels: ("50%", "25%", "0%"), hourLabels: ["1p", "2p", "3p"], tint: .systemBlue)
        let chartHeight = chart.gridHeight(forWidth: 280)
        XCTAssertGreaterThan(chartHeight, 76, "the plot plus its hour row")
        XCTAssertEqual(chart.sizeThatFits(CGSize(width: 280, height: 0)), CGSize(width: 280, height: chartHeight))

        let arc = UKWeatherSunArcView(percent: 0.4)
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
}
