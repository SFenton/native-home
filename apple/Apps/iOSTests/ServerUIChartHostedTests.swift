import Accessibility
import HassCore
import HassDesign
import UIKit
import XCTest
@testable import HassUI

// MARK: - Tests

/// Hosted UX and accessibility checks for the chart and the linear gauge (`sh.chart@1`, `sh.linear-gauge@1`) at the widths of the iPhone, the folded
/// iPhone Duo and the iPad.
///
/// Every document is a case of the shared corpus, so what the Studio previews is what these draw. A simulator narrower than a width draws it at the
/// simulator's own, so each check reads the width the view really has. Charts and gauges take no touch, so nothing here taps: what changes is the
/// data (a flow's records, an entity's state), and each change is one write to one view.
@MainActor
final class ServerUIChartHostedTests: XCTestCase {
    private static let widths: [CGFloat] = [390, 744, 1024]
    private typealias F = ServerUIChartFixture

    override func tearDown() async throws {
        UKMotion.reduceMotionOverride = nil
        HostedPage.hideTracked()
        HostedPage.resetGlobals()
        try await super.tearDown()
    }

    // MARK: Bars

    /// The bars span the plot, stand on its floor and the labels under it thin to the width; `labels: all` shows every one.
    func testBarsFillThePlotAndTheLabelsThinToTheWidth() throws {
        for width in Self.widths {
            let shown = try F.show("chart-source-records-flow", width: width, records: F.records(60)) { F.setting(["series", "limit"], to: .number(60), in: $0) }
            defer { shown.window.isHidden = true }
            let view = try shown.chart()
            let bars = F.counts(of: view.barPath)
            XCTAssertEqual(bars.moves, 60, "one bar for each record (width \(width))")
            XCTAssertEqual(bars.boundary.minX, 0, accuracy: 0.5)
            XCTAssertEqual(bars.boundary.maxX, view.plotFrame.width, accuracy: 0.5, "the bars reach the end of the plot")
            XCTAssertEqual(bars.boundary.maxY, view.plotFrame.height, accuracy: 0.5, "the bars stand on the floor")
            XCTAssertEqual(view.plotFrame.height, 76, "the default height")
            let shownLabels = view.shownPointLabels
            XCTAssertEqual(shownLabels.first, "H0")
            XCTAssertGreaterThan(shownLabels.count, 1)
            XCTAssertLessThan(shownLabels.count, 60, "60 labels do not fit side by side")
            let all = try F.show("chart-source-records-flow", width: width, records: F.records(60)) {
                F.setting(["labels"], to: .string("all"), in: F.setting(["series", "limit"], to: .number(60), in: $0))
            }
            defer { all.window.isHidden = true }
            XCTAssertEqual(try all.chart().shownPointLabels.count, 60, "labels: all shows every label")
            let none = try F.show("chart-bar", width: width) { F.setting(["labels"], to: .string("none"), in: $0) }
            defer { none.window.isHidden = true }
            XCTAssertEqual(try none.chart().shownPointLabels, [], "labels: none shows none")
        }
    }

    /// An unknown value is a stub of the least height, never a bar of zero; a known one is as tall as its share of the axis.
    func testAnUnknownBarIsAStubAndAKnownOneIsItsShareOfTheAxis() throws {
        for width in Self.widths {
            let shown = try F.show("chart-null-values", width: width)
            defer { shown.window.isHidden = true }
            let view = try shown.chart()
            let stubs = F.counts(of: view.stubPath)
            XCTAssertEqual(stubs.moves, 2, "two unknown values (width \(width))")
            XCTAssertEqual(stubs.boundary.height, 2, accuracy: 0.01, "a stub is the least height")
            let known = F.counts(of: view.barPath)
            XCTAssertEqual(known.moves, 1)
            // The axis tops at 10 (the peak 5 rounded up to the step, at least 10): 5 is half of 76.
            XCTAssertEqual(known.boundary.height, 38, accuracy: 0.5)
        }
    }

    // MARK: Lines and areas

    /// A line breaks where a value is unknown, an area fills under each run, and dots mark the known values.
    func testALineBreaksAtAnUnknownValueAndAnAreaFillsUnderEachRun() throws {
        let points: JSONValue = .array([("P1", 10.0), ("P2", nil), ("P3", 30.0), ("P4", 40.0), ("P5", nil)].map { label, value in
            .object(["label": .string(label), "value": value.map(JSONValue.number) ?? .null])
        })
        for width in Self.widths {
            let line = try F.show("chart-line-look", width: width) { F.setting(["series", "points"], to: points, in: $0) }
            defer { line.window.isHidden = true }
            let lineView = try line.chart()
            // Two runs of known values; the first is one point, which is a dot and no line (a lone move-to is dropped from the path).
            XCTAssertEqual(F.counts(of: lineView.linePath).moves, 1, "one run of two or more values (width \(width))")
            XCTAssertNil(lineView.areaPath, "a line has no area")
            XCTAssertEqual(F.counts(of: lineView.dotPath).moves, 3, "a dot for each known value (dots: true)")
            XCTAssertNil(lineView.barPath, "a line has no bars")

            let area = try F.show("chart-area-look", width: width) { F.setting(["series", "points"], to: points, in: $0) }
            defer { area.window.isHidden = true }
            let areaView = try area.chart()
            XCTAssertEqual(F.counts(of: areaView.areaPath).closes, 2, "an area under each run")
            XCTAssertEqual(F.counts(of: areaView.dotPath).moves, 0, "no dots unless asked")
        }
    }

    // MARK: Updating in place

    /// One record that changes is one redraw of the same layers and labels; a record added adds one label; the same records draw nothing; and a page that
    /// only lays out again writes nothing.
    func testANewPointUpdatesThePathsInPlaceAndNothingIsWrittenWhileScrolling() throws {
        for width in Self.widths {
            let shown = try F.show("chart-source-records-flow", width: width, records: F.records(6)) { F.setting(["series", "limit"], to: .number(12), in: $0) }
            defer { shown.window.isHidden = true }
            let view = try shown.chart()
            let layers = view.layerIdentity
            let (draws, builds) = (view.drawCount, view.labelBuildCount)
            let before = try XCTUnwrap(view.barPath)

            try shown.collection.apply(records: F.records(6) { $0 == 2 ? 60 : 10 + Double($0 * 10) }, phase: .ready)
            HostedPage.until { view.drawCount > draws }
            XCTAssertEqual(view.drawCount, draws + 1, "one changed record is one redraw (width \(width))")
            XCTAssertEqual(view.labelBuildCount, builds, "no label is built again")
            XCTAssertEqual(view.layerIdentity, layers, "the layers stay")
            XCTAssertTrue(shown.page.nodes["c"]?.view === view, "the view stays")
            XCTAssertNotEqual(try XCTUnwrap(view.barPath), before, "the bar's path changed")

            let afterEdit = view.drawCount
            try shown.collection.apply(records: F.records(6) { $0 == 2 ? 60 : 10 + Double($0 * 10) }, phase: .ready)
            shown.settle()
            XCTAssertEqual(view.drawCount, afterEdit, "the same records draw nothing")

            try shown.collection.apply(records: F.records(7), phase: .ready)
            HostedPage.until { view.drawCount > afterEdit }
            XCTAssertEqual(F.counts(of: view.barPath).moves, 7, "the new point is drawn")
            XCTAssertEqual(view.labelBuildCount, builds + 1, "one label is added")
            XCTAssertEqual(view.layerIdentity, layers)

            let still = view.drawCount, path = view.barPath
            for _ in 0..<20 {
                shown.page.view.setNeedsLayout()
                shown.page.view.layoutIfNeeded()
                HostedPage.layoutTracked()
            }
            XCTAssertEqual(view.drawCount, still, "laying out writes no value")
            XCTAssertEqual(view.barPath, path)
        }
    }

    /// With no records the chart draws its word, and when they arrive the same view draws the bars.
    func testAChartWithNoRecordsDrawsItsWordUntilTheyArrive() throws {
        for width in Self.widths {
            let shown = try F.show("chart-source-records-flow", width: width, records: nil, phase: .loading)
            defer { shown.window.isHidden = true }
            let view = try shown.chart()
            XCTAssertEqual(view.shownEmptyText, "Unavailable", "width \(width)")
            XCTAssertTrue(view.plotFrame.isEmpty || view.barPath == nil || F.counts(of: view.barPath).moves == 0)
            XCTAssertGreaterThan(view.gridHeight(forWidth: view.bounds.width), 24, "the word has room")
            try shown.collection.apply(records: F.records(4), phase: .ready)
            HostedPage.until { view.shownEmptyText == nil }
            XCTAssertNil(view.shownEmptyText)
            XCTAssertEqual(F.counts(of: view.barPath).moves, 4)
            XCTAssertTrue(shown.page.nodes["c"]?.view === view, "the view stays")
        }
    }

    /// A chart in the cell of a repeat with no flow of its own reads the whole list of that repeat: every cell draws it, and a record that changes
    /// redraws every cell once.
    func testAChartOverARepeatListReadsTheWholeList() throws {
        for width in Self.widths {
            let shown = try F.show("chart-source-in-a-repeat", width: width, records: F.records(3)) { $0 }
            defer { shown.window.isHidden = true }
            let charts = F.all(UKChartView.self, in: shown.page.view)
            XCTAssertEqual(charts.count, 3, "one chart in each cell (width \(width))")
            XCTAssertTrue(charts.allSatisfy { F.counts(of: $0.barPath).moves == 3 }, "each chart draws the three records")
            let draws = charts.map(\.drawCount)
            try shown.collection.apply(records: F.records(3) { $0 == 0 ? 80 : 10 + Double($0 * 10) }, phase: .ready)
            HostedPage.until { zip(charts, draws).allSatisfy { $0.drawCount > $1 } }
            XCTAssertEqual(charts.map(\.drawCount), draws.map { $0 + 1 }, "one redraw for each cell")
        }
    }

    // MARK: Gauge

    /// The span and the marker stand where the shared arithmetic puts them in the width the view has, and the marker stays inside the track.
    func testTheGaugePlacesItsSpanAndMarkerByTheSharedArithmetic() throws {
        for width in Self.widths {
            let shown = try F.show("linear-gauge-span", width: width)
            defer { shown.window.isHidden = true }
            let view = try shown.gauge()
            let w = Double(view.bounds.width)
            let expected = ServerUIGaugeMath.layout(.init(value: 0.5, spanStart: 0.25, spanSize: 0.5, fill: .span, width: w, markerSize: 12))
            XCTAssertEqual(view.spanFrame.minX, CGFloat(try XCTUnwrap(expected.span).left), accuracy: 0.5, "width \(width)")
            XCTAssertEqual(view.spanFrame.width, CGFloat(try XCTUnwrap(expected.span).width), accuracy: 0.5)
            XCTAssertEqual(view.spanFrame.height, 12)
            XCTAssertEqual(view.markerFrame.minX, CGFloat(try XCTUnwrap(expected.marker).left), accuracy: 0.5)
            XCTAssertEqual(view.markerFrame.size, CGSize(width: 12, height: 12))
            XCTAssertGreaterThanOrEqual(view.markerFrame.minX, 0)
            XCTAssertLessThanOrEqual(view.markerFrame.maxX, view.bounds.width)
            XCTAssertEqual(view.gradientLocations, [0, 1])
        }
    }

    /// A right-to-left layout mirrors the span and the marker, and an unknown value hides the marker.
    func testAMirroredGaugeFlipsAndAnUnknownValueHidesTheMarker() throws {
        for width in Self.widths {
            let shown = try F.show("linear-gauge-span", width: width)
            defer { shown.window.isHidden = true }
            let view = try shown.gauge()
            let (span, marker) = (view.spanFrame, view.markerFrame)
            view.semanticContentAttribute = .forceRightToLeft
            view.setNeedsLayout()
            view.layoutIfNeeded()
            XCTAssertEqual(view.spanFrame.minX, view.bounds.width - span.maxX, accuracy: 0.5, "the span flips (width \(width))")
            XCTAssertEqual(view.markerFrame.minX, view.bounds.width - marker.maxX, accuracy: 0.5, "the marker flips")

            let unknown = try F.show("linear-gauge-value-from-entity", width: width)
            defer { unknown.window.isHidden = true }
            XCTAssertFalse(try unknown.gauge().isMarkerShown, "no entity, no marker")
        }
    }

    /// The marker follows the entity in place: one write is one redraw of the same parts; it glides unless Reduce Motion is on or the gauge says it
    /// does not animate.
    func testTheMarkerFollowsItsEntityInPlaceAndGlidesOnlyWhenMotionIsAllowed() throws {
        func entity(_ state: String) -> EntityState { EntityState(entityId: "sensor.demo_bath_temperature", state: state, attributes: [:]) }
        for width in Self.widths {
            // Motion allowed.
            let moving = try F.show("linear-gauge-value-from-entity", width: width, entities: [entity("20")], reduceMotion: false)
            defer { moving.window.isHidden = true }
            let view = try moving.gauge()
            let (parts, draws, moves) = (view.partIdentity, view.drawCount, view.animatedMoves)
            let start = view.markerFrame.minX
            moving.store.apply([entity("80")])
            HostedPage.until { view.drawCount > draws }
            XCTAssertEqual(view.drawCount, draws + 1, "one entity change is one redraw (width \(width))")
            XCTAssertEqual(view.partIdentity, parts, "the parts stay")
            XCTAssertEqual(view.animatedMoves, moves + 1, "the marker glides")
            XCTAssertGreaterThan(view.markerFrame.minX, start, "and ends further along")

            // Reduce Motion.
            let still = try F.show("linear-gauge-value-from-entity", width: width, entities: [entity("20")], reduceMotion: true)
            defer { still.window.isHidden = true }
            let stillView = try still.gauge()
            let stillDraws = stillView.drawCount
            still.store.apply([entity("80")])
            HostedPage.until { stillView.drawCount > stillDraws }
            XCTAssertEqual(stillView.animatedMoves, 0, "under Reduce Motion the marker jumps")
            let expected = ServerUIGaugeMath.layout(.init(scale: .percent, value: 80, fill: .scale, width: Double(stillView.bounds.width), markerSize: 12))
            XCTAssertEqual(stillView.markerFrame.minX, CGFloat(try XCTUnwrap(expected.marker).left), accuracy: 0.5, "and is already where it ends")

            // The document says it does not animate.
            let fixed = try F.show("linear-gauge-value-from-entity", width: width, entities: [entity("20")], reduceMotion: false) {
                F.setting(["animates"], to: .bool(false), in: $0)
            }
            defer { fixed.window.isHidden = true }
            let fixedView = try fixed.gauge()
            let fixedDraws = fixedView.drawCount
            fixed.store.apply([entity("80")])
            HostedPage.until { fixedView.drawCount > fixedDraws }
            XCTAssertEqual(fixedView.animatedMoves, 0, "animates: false never glides")
        }
    }

    /// A marker that goes away and returns appears where it belongs: it never glides in from the place it last stood.
    func testAMarkerThatReturnsAppearsInPlaceAndDoesNotGlide() throws {
        func entity(_ state: String) -> EntityState { EntityState(entityId: "sensor.demo_bath_temperature", state: state, attributes: [:]) }
        for width in Self.widths {
            let shown = try F.show("linear-gauge-value-from-entity", width: width, entities: [entity("20")], reduceMotion: false)
            defer { shown.window.isHidden = true }
            let view = try shown.gauge()
            var draws = view.drawCount
            shown.store.apply([entity("unavailable")])
            HostedPage.until { view.drawCount > draws }
            XCTAssertFalse(view.isMarkerShown, "an unknown value hides the marker (width \(width))")
            let (moves, hiddenDraws) = (view.animatedMoves, view.drawCount)
            draws = hiddenDraws
            shown.store.apply([entity("80")])
            HostedPage.until { view.drawCount > draws }
            XCTAssertTrue(view.isMarkerShown)
            XCTAssertEqual(view.animatedMoves, moves, "the returning marker does not glide")
            let expected = ServerUIGaugeMath.layout(.init(scale: .percent, value: 80, fill: .scale, width: Double(view.bounds.width), markerSize: 12))
            XCTAssertEqual(view.markerFrame.minX, CGFloat(try XCTUnwrap(expected.marker).left), accuracy: 0.5, "and is already where it belongs")
        }
    }

    /// A gauge in the cell of a repeat reads its own record: the three records put the marker at the start, the middle and the end.
    func testAGaugeInARepeatReadsItsOwnCellsRecord() throws {
        for width in Self.widths {
            let shown = try F.show("linear-gauge-in-a-repeat", width: width, records: F.records(3) { [50, 70, 90][$0] })
            defer { shown.window.isHidden = true }
            let gauges = F.all(UKLinearGaugeView.self, in: shown.page.view)
            XCTAssertEqual(gauges.count, 3, "width \(width)")
            let sorted = gauges.sorted { $0.convert($0.bounds, to: shown.page.view).minY < $1.convert($1.bounds, to: shown.page.view).minY }
            XCTAssertEqual(sorted[0].markerFrame.minX, 0, accuracy: 0.5)
            XCTAssertEqual(sorted[1].markerFrame.midX, sorted[1].bounds.width / 2, accuracy: 0.5)
            XCTAssertEqual(sorted[2].markerFrame.maxX, sorted[2].bounds.width, accuracy: 0.5)
        }
    }

    // MARK: VoiceOver

    /// A chart that reads its series is one element named by the document whose value is the series, with an audio graph of the data; one that does not
    /// has a name and nothing more. The axis and the labels are never read separately.
    func testTheChartIsOneNamedElementThatReadsItsSeriesAndPlaysAnAudioGraph() throws {
        for width in Self.widths {
            let shown = try F.show("chart-a11y-series", width: width)
            defer { shown.window.isHidden = true }
            let view = try shown.chart()
            XCTAssertTrue(view.isAccessibilityElement, "width \(width)")
            XCTAssertEqual(view.accessibilityLabel, "Chance of rain")
            XCTAssertEqual(view.accessibilityValue, "P1 10, P2 40, P3 20")
            XCTAssertTrue(view.accessibilityTraits.contains(.image))
            XCTAssertTrue(F.all(UILabel.self, in: view).allSatisfy { !$0.isAccessibilityElement }, "the axis and the labels are not read apart")
            let descriptor = try XCTUnwrap(view.accessibilityChartDescriptor, "the audio graph")
            XCTAssertEqual(descriptor.title, "Chance of rain")
            let series = try XCTUnwrap(descriptor.series.first)
            XCTAssertEqual(descriptor.series.count, 1)
            XCTAssertEqual(series.dataPoints.map { $0.yValue?.__number }, [10, 40, 20])
            XCTAssertEqual(series.dataPoints.map { $0.xValue.__category }, ["P1", "P2", "P3"])
            XCTAssertFalse(series.isContinuous, "bars are categories")
            XCTAssertEqual(try XCTUnwrap(descriptor.yAxis).range, 0...40, "the axis tops at the peak rounded up to the step")

            let quiet = try F.show("chart-bar", width: width)
            defer { quiet.window.isHidden = true }
            let quietView = try quiet.chart()
            XCTAssertTrue(quietView.isAccessibilityElement)
            XCTAssertEqual(quietView.accessibilityLabel, "Series")
            XCTAssertNotNil(quietView.accessibilityValue, "the series is read even when the document writes no a11y.value")
            XCTAssertNotNil(quietView.accessibilityChartDescriptor)
        }
    }

    /// A chart whose document writes only `a11y.label` still speaks its series and plays the audio graph (HIG, Charting data, Best practices: make
    /// every chart accessible; HIG, Charts, Enhancing the accessibility of a chart). `chart-bar-axis` is such a case.
    func testALabelOnlyChartStillSpeaksItsSeriesAndPlaysTheAudioGraph() throws {
        for width in Self.widths {
            let shown = try F.show("chart-bar-axis", width: width)
            defer { shown.window.isHidden = true }
            let view = try shown.chart()
            let value = try XCTUnwrap(view.accessibilityValue, "the series is spoken (width \(width))")
            XCTAssertFalse(value.isEmpty)
            let points = try XCTUnwrap(view.accessibilityChartDescriptor?.series.first?.dataPoints, "the audio graph (width \(width))")
            XCTAssertFalse(points.isEmpty)
            XCTAssertEqual(try XCTUnwrap(view.accessibilityChartDescriptor).series.count, 1)
        }
    }

    /// An unknown value is spoken as the chart's word, and a line is a continuous graph.
    func testAnUnknownValueIsSpokenAsTheWordAndALineIsContinuous() throws {
        for width in Self.widths {
            let shown = try F.show("chart-null-values", width: width) { F.setting(["mark"], to: .string("line"), in: F.setting(["value"], to: .string("series"), in: $0, under: "a11y")) }
            defer { shown.window.isHidden = true }
            let view = try shown.chart()
            XCTAssertEqual(view.accessibilityValue, "P1 Unavailable, P2 5, P3 Unavailable", "width \(width)")
            XCTAssertEqual(try XCTUnwrap(view.accessibilityChartDescriptor?.series.first).isContinuous, true)
            XCTAssertEqual(try XCTUnwrap(view.accessibilityChartDescriptor?.series.first).dataPoints.map { $0.yValue?.__number }, [nil, 5, nil])
        }
    }

    /// A gauge is hidden, or one element named by the document with the text it gives, or the marker's percent when it gives none.
    func testTheGaugeIsHiddenOrOneNamedElementWithAValue() throws {
        for width in Self.widths {
            let hidden = try F.show("linear-gauge-span", width: width)
            defer { hidden.window.isHidden = true }
            XCTAssertFalse(try hidden.gauge().isAccessibilityElement, "width \(width)")

            let named = try F.show("linear-gauge-a11y-value", width: width)
            defer { named.window.isHidden = true }
            let view = try named.gauge()
            XCTAssertTrue(view.isAccessibilityElement)
            XCTAssertEqual(view.accessibilityLabel, "Air quality")
            XCTAssertEqual(view.accessibilityValue, "72, moderate")

            let percent = try F.show("linear-gauge-a11y-label-only", width: width)
            defer { percent.window.isHidden = true }
            XCTAssertEqual(try percent.gauge().accessibilityValue, "50%", "the marker's percent when the document gives no text")
        }
    }

    /// At the largest accessibility text size the labels grow, the plot keeps its height and its width, and no label leaves the chart.
    func testAtTheLargestTextSizeTheLabelsGrowAndNothingLeavesTheChart() throws {
        for width in Self.widths {
            let shown = try F.show("chart-bar-axis", width: width)
            defer { shown.window.isHidden = true }
            let view = try shown.chart()
            let normal = view.gridHeight(forWidth: view.bounds.width)
            shown.window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            shown.settle()
            XCTAssertGreaterThan(view.gridHeight(forWidth: view.bounds.width), normal, "the label row grows (width \(width))")
            XCTAssertEqual(view.plotFrame.height, 76)
            XCTAssertGreaterThan(view.plotFrame.width, 60, "the plot keeps room beside the axis")
            for label in F.all(UILabel.self, in: view) where !label.isHidden {
                XCTAssertTrue(view.bounds.insetBy(dx: -1, dy: -1).contains(label.frame), "\(label.text ?? "") stays inside the chart")
            }
            XCTAssertEqual(view.axisTexts, ["40%", "20%", "0%"].map { $0 }, "the axis levels from the top down")
        }
    }

    // MARK: Appearance

    /// In a sheet that is light the default inks follow it: the axis labels keep 4.5 to 1 against the sheet's ground, the grid is visible and a pair of
    /// inks takes its light side. On the page, which is always dark, the same labels keep their contrast too.
    func testAChartInALightSheetKeepsItsContrastAndTakesItsLightInks() throws {
        func plain(_ components: [JSONValue]) -> [JSONValue] {
            F.setting(["axis", "labelInk"], to: .null, in: F.setting(["axis", "gridInk"], to: .null, in: components))
        }
        for width in Self.widths {
            let sheet = try F.show("chart-bar-axis", width: width, inSheet: true, dropping: "sh.text-style@1", edit: plain)
            defer { sheet.window.isHidden = true }
            let view = try sheet.chart()
            let traits = view.traitCollection.modifyingTraits { $0.userInterfaceStyle = .light }
            let ground = UIColor.systemGroupedBackground
            let label = try XCTUnwrap(F.all(UILabel.self, in: view).first { !$0.isHidden && $0.text == "40%" })
            XCTAssertGreaterThanOrEqual(F.contrast(label.textColor, over: ground, in: traits), 4.5, "axis text on the light sheet (width \(width))")
            XCTAssertEqual(view.traitCollection.userInterfaceStyle, .light, "the sheet follows the system")

            let pair = try F.show("chart-ink-pair", width: width, inSheet: true)
            defer { pair.window.isHidden = true }
            let marks = UIColor(cgColor: try XCTUnwrap(try pair.chart().markColor))
            var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
            marks.getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertEqual(b, 200 / 255, accuracy: 0.01, "the light side of the pair (width \(width))")
            XCTAssertGreaterThanOrEqual(F.contrast(marks, over: ground, in: traits), 3, "marks on the light sheet")

            let page = try F.show("chart-bar-axis", width: width, dropping: "sh.text-style@1", edit: plain)
            defer { page.window.isHidden = true }
            let pageView = try page.chart()
            let darkTraits = pageView.traitCollection.modifyingTraits { $0.userInterfaceStyle = .dark }
            let pageLabel = try XCTUnwrap(F.all(UILabel.self, in: pageView).first { !$0.isHidden && $0.text == "40%" })
            XCTAssertEqual(pageView.traitCollection.userInterfaceStyle, .dark, "a page is always dark")
            XCTAssertGreaterThanOrEqual(F.contrast(pageLabel.textColor, over: UIColor(red: 17 / 255, green: 23 / 255, blue: 35 / 255, alpha: 1), in: darkTraits), 4.5,
                                        "axis text on the page")
        }
    }

    /// In a light sheet a gauge with a pair of inks draws its light side: the track, the gradient and the marker.
    func testAGaugeInALightSheetTakesItsLightInks() throws {
        for width in Self.widths {
            let sheet = try F.show("linear-gauge-ink-pairs", width: width, inSheet: true)
            defer { sheet.window.isHidden = true }
            let view = try sheet.gauge()
            XCTAssertEqual(view.traitCollection.userInterfaceStyle, .light, "width \(width)")
            var (r, g, b, a) = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0))
            let first = try XCTUnwrap(view.gradientColors.first)
            UIColor(cgColor: first).getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertEqual(g, 140 / 255, accuracy: 0.01, "the light side of the first stop")
            let track = try XCTUnwrap(view.subviews.first?.backgroundColor).resolvedColor(with: view.traitCollection)
            track.getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertEqual(a, 0.12, accuracy: 0.01, "the light track is black at 12%")
            XCTAssertEqual(r, 0, accuracy: 0.01)
        }
    }
}
