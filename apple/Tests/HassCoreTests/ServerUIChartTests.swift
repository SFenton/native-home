import Foundation
import Testing
@testable import HassCore

// MARK: - Chart and linear gauge (`sh.chart@1`, `sh.linear-gauge@1`)

/// What the chart and the linear gauge decode to, case by case over the Studio's corpus, and the arithmetic that places their marks.
///
/// The evaluation cases (`ContractCorpus/evaluation/chart-*.json`, `gauge-*.json`) run in ``ServerUIExpressionCorpusTests``; here the publications
/// (`accept/chart-*`, `reject/chart-*`, `linear-gauge-*`) are decoded one by one, and the edges the corpus does not name are pinned.
@Suite(.timeLimit(.minutes(2)))
@MainActor
struct ServerUIChartTests {
    nonisolated static let family: [ServerUIContractCorpusTests.Case] = ServerUIContractCorpusTests.cases.filter {
        let name = $0.file.split(separator: "/").last.map(String.init) ?? ""
        return name.hasPrefix("chart-") || name.hasPrefix("linear-gauge-")
    }

    private static func decode(_ file: String) throws -> ServerUICompositionPublication {
        try ServerUICompositionPublication.decode(Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent(file)))
    }

    /// Every chart and gauge in a document, wherever a container holds it.
    private static func parts(of publication: ServerUICompositionPublication) -> (charts: [ServerUIChart], gauges: [ServerUILinearGauge]) {
        var charts: [ServerUIChart] = [], gauges: [ServerUILinearGauge] = []
        func visit(_ components: [ServerUICompositionDocument.Component]) {
            for component in components {
                _ = component.mapped { found in
                    if case .chart(let chart) = found { charts.append(chart) }
                    if case .linearGauge(let gauge) = found { gauges.append(gauge) }
                    return found
                }
            }
        }
        for page in publication.document.pages { visit(page.surface.components) }
        for modal in publication.document.modals { visit(modal.surface.components) }
        return (charts, gauges)
    }

    // MARK: The corpus, case by case

    @Test func theCorpusHoldsTheWholeFamilyAndNothingIsPending() {
        #expect(Self.family.filter { $0.outcome == "accept" }.count == 47)
        #expect(Self.family.filter { $0.outcome == "reject" }.count == 117)
        #expect(Self.family.allSatisfy { $0.pending != true }, "both ids are shipped, so no case is pending")
    }

    @Test(arguments: family.filter { $0.outcome == "accept" })
    func anAcceptedCaseDecodesAndDrawsAPart(_ item: ServerUIContractCorpusTests.Case) throws {
        let found = Self.parts(of: try Self.decode(item.file))
        #expect(found.charts.count + found.gauges.count >= 1, "\(item.file) holds a chart or a gauge")
        if item.file.contains("/chart-") { #expect(!found.charts.isEmpty, "\(item.file)") }
        if item.file.contains("/linear-gauge-") { #expect(!found.gauges.isEmpty, "\(item.file)") }
    }

    @Test(arguments: family.filter { $0.outcome == "reject" })
    func aRefusedCaseGivesTheStudiosFirstIssue(_ item: ServerUIContractCorpusTests.Case) throws {
        let issue = try #require(item.issue)
        do {
            _ = try Self.decode(item.file)
            Issue.record("\(item.file) must be refused")
        } catch let thrown as ServerUICompositionError {
            #expect(thrown.code.rawValue == issue.code, "\(item.file): \(thrown)")
            #expect(thrown.pointer == issue.pointer, "\(item.file): \(thrown)")
        }
    }

    // MARK: What a document decodes to

    @Test func aBarChartKeepsItsPointsAxisAndLook() throws {
        let chart = try #require(Self.parts(of: try Self.decode("accept/chart-bar-look.json")).charts.first)
        #expect(chart.mark == .bar)
        #expect(chart.bar != nil && chart.line == nil)
        guard case .literal(let points) = chart.series else { Issue.record("a literal series"); return }
        #expect(!points.isEmpty)
        #expect(chart.height == ServerUIChart.defaultHeight, "an absent height is 76")
        #expect(chart.labels == .fit, "an absent labels is fit")
    }

    @Test func theModelRecordsWhetherTheDocumentWritesTheSeriesValue() throws {
        let spoken = try #require(Self.parts(of: try Self.decode("accept/chart-a11y-series.json")).charts.first)
        let silent = try #require(Self.parts(of: try Self.decode("accept/chart-bar.json")).charts.first)
        #expect(spoken.readsSeries)
        #expect(!silent.readsSeries)
    }

    @Test func nullValuesStayUnknownAndNeverBecomeZero() throws {
        let chart = try #require(Self.parts(of: try Self.decode("accept/chart-null-values.json")).charts.first)
        guard case .literal(let points) = chart.series else { Issue.record("a literal series"); return }
        #expect(points.contains { $0.value == nil })
        #expect(points.contains { $0.value != nil })
    }

    @Test func aTwoStepDomainReadsItsSmallestStepFromAnOperand() throws {
        let chart = try #require(Self.parts(of: try Self.decode("accept/chart-domain-two-step-factors.json")).charts.first)
        guard case .twoStep(_, _, let factors) = chart.domain else { Issue.record("a two-step domain"); return }
        #expect((factors?.count ?? 0) >= 2)
    }

    @Test func aChartOverARepeatListNamesNoFlowOfItsOwn() throws {
        let chart = try #require(Self.parts(of: try Self.decode("accept/chart-source-in-a-repeat.json")).charts.first)
        guard case .source(let providerId, let limit, _, _) = chart.series else { Issue.record("a source series"); return }
        #expect(providerId == nil)
        #expect(limit == 6)
    }

    @Test func aChartOverAFlowNamesIt() throws {
        let chart = try #require(Self.parts(of: try Self.decode("accept/chart-source-records-flow.json")).charts.first)
        guard case .source(let providerId, _, _, _) = chart.series else { Issue.record("a source series"); return }
        #expect(providerId == "records-flow")
    }

    @Test func aSpanGaugeKeepsItsStopsSpanAndMarker() throws {
        let gauge = try #require(Self.parts(of: try Self.decode("accept/linear-gauge-span.json")).gauges.first)
        #expect(gauge.fill == .span)
        #expect(gauge.span != nil)
        #expect(gauge.marker != nil && gauge.value != nil)
        #expect(gauge.stops.count >= 2)
        #expect(gauge.stops.map(\.at) == gauge.stops.map(\.at).sorted())
    }

    @Test func aScaleGaugeWithNoMarkerHasNoValue() throws {
        let gauge = try #require(Self.parts(of: try Self.decode("accept/linear-gauge-track-only.json")).gauges.first)
        #expect(gauge.value == nil && gauge.marker == nil && gauge.span == nil)
        #expect(gauge.animates)
        #expect(gauge.height == ServerUILinearGauge.defaultHeight)
    }

    @Test func aGaugeReadsTheEntitiesItsValueNames() throws {
        let gauge = try #require(Self.parts(of: try Self.decode("accept/linear-gauge-value-from-entity.json")).gauges.first)
        #expect(gauge.sourceIds == ["temp"])
        #expect(try #require(Self.parts(of: try Self.decode("accept/chart-height.json")).charts.first).height != ServerUIChart.defaultHeight)
    }

    @Test func aGaugeCanTurnItsGlideOffAndNameItself() throws {
        #expect(try #require(Self.parts(of: try Self.decode("accept/linear-gauge-no-animation.json")).gauges.first).animates == false)
        let named = try #require(Self.parts(of: try Self.decode("accept/linear-gauge-a11y-value.json")).gauges.first)
        guard case .value(_, let spoken) = named.accessibility else { Issue.record("a spoken gauge"); return }
        #expect(spoken != nil)
    }

    // MARK: Gating

    @Test func aDocumentThatDeclaresNeitherIdIsUnchanged() throws {
        let older = try Self.decode("accept/fixture-composition-first-slice.json")
        let found = Self.parts(of: older)
        #expect(found.charts.isEmpty && found.gauges.isEmpty)
        #expect(!older.capabilities.contains("sh.chart@1") && !older.capabilities.contains("sh.linear-gauge@1"))
    }

    @Test(arguments: [("accept/chart-bar.json", "sh.chart@1"), ("accept/linear-gauge-span.json", "sh.linear-gauge@1")])
    func aNodeWithoutItsDeclaredIdIsRefused(_ file: String, _ id: String) throws {
        let bytes = try Data(contentsOf: ServerUIContractCorpusTests.directory.appendingPathComponent(file))
        guard case .object(var envelope)? = try? JSONDecoder().decode(JSONValue.self, from: bytes),
              case .array(let declared)? = envelope["capabilities"] else { Issue.record("an envelope"); return }
        envelope["capabilities"] = .array(declared.filter { $0 != .string(id) })
        let stripped = try JSONEncoder().encode(JSONValue.object(envelope))
        do {
            _ = try ServerUICompositionPublication.decode(stripped)
            Issue.record("a node without its declared id must be refused")
        } catch let error as ServerUICompositionError {
            #expect(error.code.rawValue == "capability_manifest_mismatch")
            #expect(error.pointer == "/capabilities")
        }
    }

    @Test func bothIdsAreShippedAndListedOnce() {
        let supported = ServerUICompositionPublication.supportedCapabilities
        #expect(supported.filter { $0 == "sh.chart@1" }.count == 1)
        #expect(supported.filter { $0 == "sh.linear-gauge@1" }.count == 1)
        #expect(ServerUIIngestedCapabilities.dataParts == ["sh.chart@1", "sh.linear-gauge@1"])
    }

    // MARK: Axis arithmetic

    @Test func aCeilingRoundsThePeakUpToTheStepAndStaysInsideItsBounds() {
        #expect(ServerUIChartMath.ceilingDomain(peak: 37, step: 10, min: 10, max: 100) == 40)
        #expect(ServerUIChartMath.ceilingDomain(peak: 3, step: 10, min: 10, max: 100) == 10)
        #expect(ServerUIChartMath.ceilingDomain(peak: 340, step: 10, min: 10, max: 100) == 100)
        #expect(ServerUIChartMath.ceilingDomain(peak: nil, step: 10, min: 10, max: 100) == 10)
        #expect(ServerUIChartMath.ceilingDomain(peak: .infinity, step: 10, min: 10, max: 100) == 10)
    }

    @Test func aTwoStepAxisNeverTakesAStepThatCannotBePositive() {
        // A step an operand read as zero or less must not trap: the axis has no height and every bar is its stub.
        #expect(ServerUIChartMath.twoStepDomain(total: 0, minimumStep: 0, maximumFractionDigits: 2).domain == 0)
        #expect(ServerUIChartMath.twoStepDomain(total: nil, minimumStep: -3, maximumFractionDigits: 2).domain == 0)
        #expect(ServerUIChartMath.twoStepDomain(total: .nan, minimumStep: .nan, maximumFractionDigits: 2).step == 0)
        let axis = ServerUIChartMath.twoStepDomain(total: 7.3, minimumStep: 1, maximumFractionDigits: 0, factors: [1, 2, 5, 10])
        #expect(axis == .init(domain: 10, step: 5, digits: 0))
    }

    @Test func aShareIsHeldInsideTheAxisAndAnEmptyAxisIsZero() {
        #expect(ServerUIChartMath.scaledPercent(150, top: 100) == 100)
        #expect(ServerUIChartMath.scaledPercent(-5, top: 100) == 0)
        #expect(ServerUIChartMath.scaledPercent(10, top: -20, base: -20) == 0)
        #expect(ServerUIChartMath.scaledPercent(nil, top: 100) == 0)
        #expect(ServerUIChartMath.scaledPercent(10, top: 40, base: -20) == 50)
    }

    @Test func labelsThinToTheWidthAndANarrowPlotShowsOne() {
        let cadence = ServerUIChartMath.labelCadence(count: 24, plotWidth: 153, widestLabelWidth: 32)
        #expect(cadence == 6)
        #expect(ServerUIChartMath.labelIndices(count: 24, cadence: cadence) == [0, 6, 12, 18])
        #expect(ServerUIChartMath.labelCadence(count: 24, plotWidth: 10, widestLabelWidth: 40) == 24)
        #expect(ServerUIChartMath.labelCadence(count: 8, plotWidth: 0, widestLabelWidth: 0) == 2, "no width to go by shows a quarter")
        #expect(ServerUIChartMath.labelCadence(count: 0, plotWidth: 100, widestLabelWidth: 10) == 1)
        #expect(ServerUIChartMath.labelIndices(count: 5, cadence: 0) == [0, 1, 2, 3, 4])
    }

    @Test func barsKeepTheirColumnsAndAnUnknownOneIsAStub() {
        let bars = ServerUIChartMath.barMarks([100, nil, 0, 1], top: 100, width: 80, height: 76, gap: 2, minimum: 2)
        #expect(bars.map(\.unknown) == [false, true, false, false])
        #expect(bars[0].height == 76)
        #expect(bars[1].height == 2)
        #expect(bars[2].height == 0, "a known zero is no bar")
        #expect(bars[3].height == 2, "a small known value is never thinner than the minimum")
        #expect(bars[1].x == bars[0].x + bars[0].width + 2)
    }

    @Test func aLineBreaksWhereAValueIsUnknown() {
        let points = ServerUIChartMath.pointMarks([0, nil, 100], top: 100, width: 90, height: 76)
        #expect(points.map(\.y) == [76, nil, 0])
        #expect(points.map(\.x) == [15, 45, 75])
    }

    @Test func theSpokenSeriesNamesEachValueAndTheUnknownOnes() {
        let points = [ServerUIChart.Point(label: "Now", value: 94), .init(label: "7 PM", value: nil), .init(label: "8 PM", value: 1234.5)]
        #expect(ServerUIChartMath.seriesText(points, pattern: "{value}%", digits: 0, unknownText: "n/a") == "Now 94%, 7 PM n/a, 8 PM 1,235%")
    }

    // MARK: Gauge arithmetic

    @Test func aMarkerStaysWhollyInsideTheTrackAndAMirroredOneFlips() {
        let high = ServerUIGaugeMath.layout(.init(value: 1, fill: .scale, width: 200, markerSize: 12))
        #expect(high.marker == .init(percent: 100, left: 188))
        let low = ServerUIGaugeMath.layout(.init(value: 0, fill: .scale, width: 200, markerSize: 12))
        #expect(low.marker?.left == 0)
        let mirrored = ServerUIGaugeMath.layout(.init(value: 0, fill: .scale, width: 200, markerSize: 12, rtl: true))
        #expect(mirrored.marker?.left == 188)
        #expect(ServerUIGaugeMath.layout(.init(fill: .scale, width: 200, markerSize: 12)).marker == nil, "no value, no marker")
    }

    @Test func aSpanIsHeldInsideTheTrackAndAnEmptyOneIsNotDrawn() {
        let held = ServerUIGaugeMath.layout(.init(spanStart: 0.8, spanSize: 0.5, fill: .span, width: 100, markerSize: 12))
        #expect(held.span?.startPercent == 80 && held.span?.sizePercent == 20 && held.span?.width == 20)
        #expect(ServerUIGaugeMath.layout(.init(spanStart: 0.5, spanSize: 0, fill: .span, width: 100, markerSize: 12)).span == nil)
        #expect(ServerUIGaugeMath.layout(.init(spanStart: 0.5, spanSize: 9, fill: .scale, width: 100, markerSize: 12)).span?.width == 100)
        let flipped = ServerUIGaugeMath.layout(.init(spanStart: 0.2, spanSize: 0.3, fill: .span, width: 100, markerSize: 12, rtl: true))
        #expect(flipped.span?.left == 50)
    }

    @Test func aPercentGaugeReadsZeroToOneHundred() {
        #expect(ServerUIGaugeMath.percent(72, scale: .percent) == 72)
        #expect(ServerUIGaugeMath.percent(0.72, scale: .unit) == 72)
        #expect(ServerUIGaugeMath.percent(400, scale: .percent) == 100)
        #expect(ServerUIGaugeMath.percent(.nan) == 0)
        #expect(ServerUIGaugeMath.percent(nil) == 0)
    }
}
