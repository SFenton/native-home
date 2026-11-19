#if os(iOS)
import Foundation
import HassCore
import UIKit

// MARK: - Data parts (`sh.chart@1`, `sh.linear-gauge@1`, `sh.dial@1`, `sh.arc-track@1`)

/// Binds the `chart`, `linear-gauge`, `dial` and `arc-track` nodes to their views: what each reads from state, and the values it hands the view.
///
/// The views (``UKChartView``, ``UKLinearGaugeView``, ``UKDialView``, ``UKArcTrackView``) hold values only; every read of an entity or a flow happens here, in one observation that
/// touches exactly what the node's operands and series name, so one entity change is one update of the view that reads it, and a records flow
/// that gives a new record is one update of the chart over it. A value that is still loading keeps what the view showed.
@MainActor
enum UKServerUIDataParts {
    typealias D = ServerUICompositionDocument

    /// The text of a slot, or `fallback` while it has none.
    private static func words(_ slot: D.StringValue?, name: String, memories: UKServerUITextMemories, in renderer: UKServerUIRenderer,
                              fallback: String?) -> String? {
        guard let slot else { return fallback }
        if case .ready(let text) = memories.string(slot, slot: name, bindings: renderer.bindings), !text.trimmingCharacters(in: .whitespaces).isEmpty { return text }
        return fallback
    }

    /// The number an operand gives, or `nil` when it is loading, unavailable or not a number (a `nil` hides a marker and breaks a line).
    private static func number(_ operand: ServerUIOperand?, in reader: UKServerUIReader) -> Double? {
        guard let operand else { return nil }
        switch operand.evaluate(reader).json {
        case .number(let value)?: return value.isFinite ? value : nil
        case .string(let text)?: return Double(text.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
        default: return nil
        }
    }

    // MARK: Chart

    /// The records a `source` series reads: the flow it names, or with none the list of the repeat the chart sits in.
    private static func records(of providerId: String?, in renderer: UKServerUIRenderer) -> [JSONValue] {
        let collection = providerId.flatMap { renderer.collections[$0] } ?? renderer.bindings.cell?.list
        return collection?.records ?? []
    }

    /// Binds a chart: its points (written, or read from the records), the axis they sit on, and what a screen reader says.
    ///
    /// The series is always spoken and always plays as an audio graph, whether or not the document writes `a11y.value` (HIG, Charting data, Best
    /// practices: make every chart accessible; HIG, Charts, Enhancing the accessibility of a chart: without an audio graph, give an overview).
    static func bind(_ chart: ServerUIChart, view: UKChartView, entry: UKServerUINode, renderer: UKServerUIRenderer) {
        let memories = entry.textMemories
        entry.bag.observe { [weak view, weak renderer] in
            guard let view, let renderer else { return }
            let reader = renderer.reader()
            let points: [ServerUIChart.Point]
            switch chart.series {
            case .literal(let written): points = written
            case .source(let providerId, let limit, let label, let value):
                points = ServerUIChart.sourcePoints(limit: limit, label: label, value: value, records: records(of: providerId, in: renderer), in: reader)
            }
            let content = content(chart, points: points, reader: reader)
            let pattern = chart.axis?.pattern ?? "{value}"
            let digits = chart.axis?.digits ?? content.digits
            let speech = UKChartSpeech(
                label: words(chart.label, name: "label", memories: memories, in: renderer, fallback: chart.node.title) ?? chart.node.title,
                series: ServerUIChartMath.seriesText(points, pattern: pattern, digits: digits, unknownText: chart.emptyText),
                describe: { ServerUIChartMath.axisText(pattern: pattern, value: $0, digits: digits) })
            view.apply(content.value, speech: speech)
        }
    }

    /// The value a chart draws: the axis its domain gives for these points, and the look the document states.
    static func content(_ chart: ServerUIChart, points: [ServerUIChart.Point], reader: UKServerUIReader) -> (value: UKChartContent, digits: Int) {
        let peak = ServerUIChartMath.peak(of: points.map(\.value))
        var top = 0.0, base = 0.0, computedDigits = 0
        switch chart.domain {
        case .ceiling(let step, let lowest, let highest): top = ServerUIChartMath.ceilingDomain(peak: peak, step: step, min: lowest, max: highest)
        case .fixed(let lowest, let highest): (base, top) = (lowest, highest)
        case .twoStep(let minimumStep, let maximumDigits, let factors):
            let axis = ServerUIChartMath.twoStepDomain(total: peak, minimumStep: number(minimumStep, in: reader) ?? 0.01, maximumFractionDigits: maximumDigits,
                                                       factors: factors ?? ServerUIChartMath.axisFactors)
            (top, computedDigits) = (axis.domain, axis.digits)
        }
        let digits = chart.axis?.digits ?? computedDigits
        var levelTexts: [String]?
        if let axis = chart.axis, let pattern = axis.pattern {
            levelTexts = ServerUIChartMath.axisLevels(axis.levels, top: top, base: base).map { ServerUIChartMath.axisText(pattern: pattern, value: $0, digits: digits) }
        }
        let value = UKChartContent(
            mark: chart.mark, points: points, top: top, base: base, levelTexts: levelTexts, gridLines: chart.axis?.levels ?? 0, height: CGFloat(chart.height),
            gap: CGFloat(chart.bar?.gap ?? 2), radius: CGFloat(chart.bar?.radius ?? 2), minimum: CGFloat(chart.bar?.minimum ?? 2),
            lineWidth: CGFloat(chart.line?.width ?? 2), dots: chart.line?.dots ?? false, labels: chart.labels,
            tint: UKStyledText.color(chart.tint), gridInk: chart.axis?.gridInk.map(UKStyledText.color), labelInk: chart.axis?.labelInk.map(UKStyledText.color),
            unknownInk: chart.bar?.unknownInk.map(UKStyledText.color), emptyText: chart.emptyText)
        return (value, digits)
    }

    // MARK: Linear gauge

    /// Binds a gauge: the numbers its operands give now, and the name and value it tells a screen reader.
    static func bind(_ gauge: ServerUILinearGauge, view: UKLinearGaugeView, entry: UKServerUINode, renderer: UKServerUIRenderer) {
        let memories = entry.textMemories
        entry.bag.observe { [weak view, weak renderer] in
            guard let view, let renderer else { return }
            let reader = renderer.reader()
            let reading = UKGaugeReading(value: number(gauge.value, in: reader), spanStart: number(gauge.span?.start, in: reader),
                                         spanSize: number(gauge.span?.size, in: reader))
            let speech: UKGaugeSpeech
            switch gauge.accessibility {
            case .hidden: speech = .hidden
            case .value(let label, let value):
                speech = .value(label: words(label, name: "label", memories: memories, in: renderer, fallback: gauge.node.title) ?? gauge.node.title, value: words(value, name: "value", memories: memories, in: renderer, fallback: nil))
            }
            view.apply(gauge, reading: reading, speech: speech)
        }
    }

    // MARK: Dial and arc track

    /// What a gauge part tells an assistive technology.
    private static func speech(_ spoken: (label: D.StringValue, value: D.StringValue?)?, title: String, memories: UKServerUITextMemories,
                               in renderer: UKServerUIRenderer) -> UKGaugeSpeech {
        guard let spoken else { return .hidden }
        return .value(label: words(spoken.label, name: "label", memories: memories, in: renderer, fallback: title) ?? title,
                      value: words(spoken.value, name: "value", memories: memories, in: renderer, fallback: nil))
    }

    /// Binds a dial: the pointer's number, the words of each line in the middle, and the name and value it tells a screen reader.
    static func bind(_ dial: ServerUIDial, view: UKDialView, entry: UKServerUINode, renderer: UKServerUIRenderer) {
        let memories = entry.textMemories
        entry.bag.observe { [weak view, weak renderer] in
            guard let view, let renderer else { return }
            let reader = renderer.reader()
            let lines = dial.center.enumerated().map { index, line -> UKDialLineValue in
                switch memories.string(line.value, slot: "center.\(index)", bindings: renderer.bindings) {
                case .ready(let text): .text(text)
                case .unavailable: .unavailable
                case .loading: .loading
                }
            }
            var spoken: (label: D.StringValue, value: D.StringValue?)?
            if case .value(let label, let value) = dial.accessibility { spoken = (label, value) }
            view.apply(dial, reading: UKDialReading(value: number(dial.pointer?.value, in: reader), lines: lines),
                       speech: speech(spoken, title: dial.node.title, memories: memories, in: renderer))
        }
    }

    /// Binds an arc: the progress its operand gives now, and the name and value it tells a screen reader.
    static func bind(_ arc: ServerUIArcTrack, view: UKArcTrackView, entry: UKServerUINode, renderer: UKServerUIRenderer) {
        let memories = entry.textMemories
        entry.bag.observe { [weak view, weak renderer] in
            guard let view, let renderer else { return }
            var spoken: (label: D.StringValue, value: D.StringValue?)?
            if case .value(let label, let value) = arc.accessibility { spoken = (label, value) }
            view.apply(arc, progress: number(arc.progress, in: renderer.reader()), speech: speech(spoken, title: arc.node.title, memories: memories, in: renderer))
        }
    }
}
#endif
