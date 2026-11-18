import Foundation

// MARK: - Chart (`sh.chart@1`)

/// A chart of one series: bars, a line, or a line over a filled area, in one tint, on an axis with thinned labels (`sh.chart@1`).
///
/// It is the Studio's `chart` node, the one the preview draws. The arithmetic is ``ServerUIChartMath``; the drawing is `UKChartView`, which
/// takes values only. The chart is one accessibility element named by ``label``; its value is the series read out and VoiceOver's
/// audio graph has the data, whether or not ``readsSeries`` is set.
public struct ServerUIChart: Equatable, Sendable {
    /// What is drawn for each point.
    public enum Mark: String, CaseIterable, Sendable { case bar, line, area }

    /// Which labels under the plot show: `fit` thins them to the width, `all` shows every one, `none` shows none.
    public enum Labels: String, CaseIterable, Sendable { case fit, all, none }

    /// One point of a series: the label under it and its value, `nil` where it is not known.
    public struct Point: Equatable, Sendable {
        /// The label under the point.
        public var label: String
        /// The value, or `nil` where it is not known (a stub in a bar chart, a break in a line).
        public var value: Double?

        /// Creates a point.
        public init(label: String, value: Double?) {
            self.label = label
            self.value = value
        }
    }

    /// The one series a chart draws.
    public enum Series: Equatable, Sendable {
        /// The points written in the document.
        case literal([Point])
        /// The records of a records flow (`providerId`), or with none the list of the `repeat` the chart sits in; the first `limit` of them, each with the
        /// label and the number read from the record by `item` operands.
        case source(providerId: String?, limit: Int, label: ServerUIOperand, value: ServerUIOperand)
    }

    /// The scale of the value axis.
    public enum Domain: Equatable, Sendable {
        /// From 0 to the highest value rounded up to the next `step`, at least `min` and at most `max`.
        case ceiling(step: Double, min: Double, max: Double)
        /// From `min` to `max`.
        case fixed(min: Double, max: Double)
        /// Two equal "nice" steps (a factor times a power of ten) up to a top at least the highest value; no step below `minimumStep`, no label with more
        /// than `maximumFractionDigits` places.
        case twoStep(minimumStep: ServerUIOperand, maximumFractionDigits: Int, factors: [Double]?)
    }

    /// The labels beside the plot and the lines across it.
    public struct Axis: Equatable, Sendable {
        /// How many levels the axis has, from its top to its base.
        public var levels: Int
        /// The pattern of a label, holding `{value}` once; `nil` draws lines and no labels.
        public var pattern: String?
        /// The most places after the point of a label; the axis's own when `nil`.
        public var digits: Int?
        /// The colour of the lines across the plot, or `nil` for the default.
        public var gridInk: ServerUIInk?
        /// The colour of the labels, or `nil` for the default.
        public var labelInk: ServerUIInk?

        /// Creates an axis.
        public init(levels: Int, pattern: String? = nil, digits: Int? = nil, gridInk: ServerUIInk? = nil, labelInk: ServerUIInk? = nil) {
            self.levels = levels
            self.pattern = pattern
            self.digits = digits
            self.gridInk = gridInk
            self.labelInk = labelInk
        }
    }

    /// What a bar looks like.
    public struct Bar: Equatable, Sendable {
        /// The space between bars, in points.
        public var gap: Double?
        /// The corner radius.
        public var radius: Double?
        /// The least height of a bar above zero and of an unknown one.
        public var minimum: Double?
        /// The colour of an unknown bar's stub.
        public var unknownInk: ServerUIInk?

        /// Creates a bar look.
        public init(gap: Double? = nil, radius: Double? = nil, minimum: Double? = nil, unknownInk: ServerUIInk? = nil) {
            self.gap = gap
            self.radius = radius
            self.minimum = minimum
            self.unknownInk = unknownInk
        }
    }

    /// What a line, or the edge of an area, looks like.
    public struct Line: Equatable, Sendable {
        /// The width in points.
        public var width: Double?
        /// Whether each known value gets a dot.
        public var dots: Bool?

        /// Creates a line look.
        public init(width: Double? = nil, dots: Bool? = nil) {
            self.width = width
            self.dots = dots
        }
    }

    /// The plot's height when the document gives none.
    public static let defaultHeight = 76.0

    /// The node's id, title and layout.
    public let node: ServerUICompositionDocument.Node
    /// Bars, a line or an area.
    public var mark: Mark
    /// The points drawn.
    public var series: Series
    /// The scale of the value axis.
    public var domain: Domain
    /// The colour of the marks.
    public var tint: ServerUIInk
    /// The axis, or `nil` for none.
    public var axis: Axis?
    /// The look of a bar (a bar chart only).
    public var bar: Bar?
    /// The look of a line (a line or an area).
    public var line: Line?
    /// The plot's height in points.
    public var height: Double
    /// Which labels under the plot show.
    public var labels: Labels
    /// What is drawn, and spoken for an unknown value, where there is no series or no value is known.
    public var emptyText: String
    /// The name VoiceOver gives the chart.
    public var label: ServerUICompositionDocument.StringValue
    /// Whether the document writes `a11y.value: "series"`. The native view speaks the series either way (HIG, Charting data, Best practices).
    public var readsSeries: Bool

    /// Creates a chart.
    public init(node: ServerUICompositionDocument.Node, mark: Mark, series: Series, domain: Domain, tint: ServerUIInk, axis: Axis? = nil, bar: Bar? = nil,
                line: Line? = nil, height: Double = defaultHeight, labels: Labels = .fit, emptyText: String,
                label: ServerUICompositionDocument.StringValue, readsSeries: Bool = false) {
        self.node = node
        self.mark = mark
        self.series = series
        self.domain = domain
        self.tint = tint
        self.axis = axis
        self.bar = bar
        self.line = line
        self.height = height
        self.labels = labels
        self.emptyText = emptyText
        self.label = label
        self.readsSeries = readsSeries
    }

    // MARK: Source points

    /// The points a `source` series draws from the records of its flow: at most `limit` of them from the first, each read with `item` set to the
    /// record and `index` to its position. A label is the text of the label operand (a number is written as it is; anything else is empty), and a
    /// value the number the value operand gives: a number, or text that is one, else `nil`, so an unknown value is a stub in a bar chart and a break
    /// in a line, as for a literal series.
    public static func sourcePoints(limit: Int, label: ServerUIOperand, value: ServerUIOperand, records: [JSONValue],
                                    in reader: some ServerUIReading) -> [Point] {
        records.prefix(max(0, limit)).enumerated().map { index, record in
            let at = RecordReading(base: reader, item: record, index: index)
            return Point(label: Self.text(label.evaluate(at)), value: Self.number(value.evaluate(at)))
        }
    }

    private static func text(_ result: ServerUIReadResult) -> String {
        switch result.json {
        case .string(let text)?: text
        case .number(let number)?: ServerUIOperand.scalarText(.number(number)) ?? ""
        default: ""
        }
    }

    private static func number(_ result: ServerUIReadResult) -> Double? {
        switch result.json {
        case .number(let number)?:
            return number.isFinite ? number : nil
        case .string(let text)?:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : Double(trimmed).flatMap { $0.isFinite ? $0 : nil }
        default:
            return nil
        }
    }

    /// A reading that is `base` with one record as `item` and its position as `index`.
    private struct RecordReading<Base: ServerUIReading>: ServerUIReading {
        let base: Base
        let item: JSONValue?
        let index: Int?
        func read(sourceId: String, path: [String]) -> ServerUIReadResult { base.read(sourceId: sourceId, path: path) }
        var viewer: ServerUIViewer? { base.viewer }
        func readRaw(sourceId: String) -> ServerUIReadResult { base.readRaw(sourceId: sourceId) }
        func readChanged(sourceId: String) -> ServerUIReadResult { base.readChanged(sourceId: sourceId) }
        func viewerPersonState() -> ServerUIReadResult { base.viewerPersonState() }
        var controlValue: JSONValue? { base.controlValue }
        var clock: ServerUIClock? { base.clock }
        var secondClock: ServerUIClock? { base.secondClock }
        func parameter(_ name: String) -> JSONValue? { base.parameter(name) }
        var isFlow: Bool { base.isFlow }
        var locale: Locale? { base.locale }
        func drawsSymbol(_ name: String) -> Bool { base.drawsSymbol(name) }
        func spend() { base.spend() }
    }

    // MARK: Reading

    /// The source ids the chart reads: the number the two-step axis takes its smallest step from, and the operands of a `source` series.
    public var sourceIds: Set<String> {
        var ids = Set<String>()
        if case .twoStep(let step, _, _) = domain { ids.formUnion(step.sourceIds) }
        if case .source(_, _, let label, let value) = series { ids.formUnion(label.sourceIds); ids.formUnion(value.sourceIds) }
        ids.formUnion(ServerUIStringResolver.sourceIds(self.label))
        return ids
    }
}
