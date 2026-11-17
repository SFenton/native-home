import Foundation

// MARK: - Compiling a chart and a linear gauge

/// The compile steps of `chart` (`sh.chart@1`) and `linear-gauge` (`sh.linear-gauge@1`), following the Studio's `compiler.ts` (`chart`,
/// `chartSource`, `linearGauge`) and `chart-source.ts`: the combinations the closed shape cannot hold, the number operands, and what a `source`
/// series reads.
extension ServerUICompositionCompiler {
    // MARK: Operands

    /// A number operand slot: parsed like any operand, and refused (`binding_type`) when it can only give text, a yes or no, or a structure.
    mutating func numberOperand(_ c: Cursor) throws -> ServerUIOperand {
        let value = try operand(c)
        if let kind = value.staticKind, kind != .number { add(.bindingType, c.pointer) }
        return value
    }

    // MARK: Chart

    /// A `chart`: one series as bars, a line or an area.
    ///
    /// A `bar` block is for bars and a `line` block for the other two; a `ceiling` domain runs `min` to `max` in steps; a `fixed` one has a range; a
    /// `two-step` one reads its smallest step from an operand and its factors rise in (0, 10]. An axis label pattern holds `{value}` once and no
    /// other brace. A `source` series is judged by ``chartSeries(_:)``.
    mutating func chartComponent(_ c: Cursor, node: D.Node, props: Cursor) throws -> D.Component {
        require("chart")
        let mark: ServerUIChart.Mark = try props.e("mark")
        if props.value["bar"] != nil, mark != .bar { add(.invalidCombination, props.path("bar")) }
        if props.value["line"] != nil, mark == .bar { add(.invalidCombination, props.path("line")) }

        let domainCursor = try props.field("domain")
        let domain: ServerUIChart.Domain
        switch try domainCursor.s("type") {
        case "ceiling":
            let (step, lowest, highest) = try (domainCursor.n("step"), domainCursor.n("min"), domainCursor.n("max"))
            if lowest > highest { add(.invalidValue, domainCursor.path("max")) }
            domain = .ceiling(step: step, min: lowest, max: highest)
        case "fixed":
            let (lowest, highest) = try (domainCursor.n("min"), domainCursor.n("max"))
            if lowest >= highest { add(.invalidValue, domainCursor.path("max")) }
            domain = .fixed(min: lowest, max: highest)
        default:
            let step = try numberOperand(domainCursor.field("minimumStep"))
            if case .literal(.number(let literal)) = step, literal <= 0 { add(.invalidValue, domainCursor.path("minimumStep")) }
            var factors: [Double]?
            if domainCursor.value["factors"] != nil {
                let list = try domainCursor.field("factors").array().map { item -> Double in
                    guard case .number(let factor) = item.value else { throw Issue(.invalidValue, item.pointer) }
                    return factor
                }
                if list.indices.contains(where: { $0 > 0 && list[$0] <= list[$0 - 1] }) { add(.invalidValue, domainCursor.path("factors")) }
                factors = list
            }
            let digits = try domainCursor.value["maximumFractionDigits"] == nil ? 3 : domainCursor.i("maximumFractionDigits")
            domain = .twoStep(minimumStep: step, maximumFractionDigits: digits, factors: factors)
        }

        var axis: ServerUIChart.Axis?
        if props.value["axis"] != nil {
            let item = try props.field("axis")
            var value = try ServerUIChart.Axis(levels: item.i("levels"))
            if item.value["label"] != nil {
                let label = try item.field("label")
                let pattern = try label.s("pattern")
                // `{value}` exactly once and no other brace.
                if let hole = pattern.range(of: "{value}") {
                    let rest = pattern.replacingCharacters(in: hole, with: "")
                    if rest.contains("{") || rest.contains("}") { add(.invalidValue, label.path("pattern")) }
                } else { add(.invalidValue, label.path("pattern")) }
                value.pattern = pattern
                value.digits = try label.value["digits"] == nil ? nil : label.i("digits")
            }
            value.gridInk = try item.value["gridInk"] == nil ? nil : ink(item.field("gridInk"))
            value.labelInk = try item.value["labelInk"] == nil ? nil : ink(item.field("labelInk"))
            axis = value
        }
        var bar: ServerUIChart.Bar?
        if props.value["bar"] != nil {
            let item = try props.field("bar")
            bar = try .init(gap: item.value["gap"] == nil ? nil : item.n("gap"), radius: item.value["radius"] == nil ? nil : item.n("radius"),
                            minimum: item.value["minimum"] == nil ? nil : item.n("minimum"),
                            unknownInk: item.value["unknownInk"] == nil ? nil : ink(item.field("unknownInk")))
        }
        var line: ServerUIChart.Line?
        if props.value["line"] != nil {
            let item = try props.field("line")
            line = try .init(width: item.value["width"] == nil ? nil : item.n("width"), dots: item.value["dots"] == nil ? nil : item.b("dots"))
        }
        let a11y = try c.field("a11y")
        return try .chart(ServerUIChart(
            node: node, mark: mark, series: chartSeries(props.field("series")), domain: domain, tint: ink(props.field("tint")), axis: axis, bar: bar,
            line: line, height: props.value["height"] == nil ? ServerUIChart.defaultHeight : props.n("height"),
            labels: props.value["labels"] == nil ? .fit : props.e("labels"), emptyText: props.s("emptyText"),
            label: stringValue(a11y.field("label")), readsSeries: a11y.value["value"] != nil))
    }

    /// The series of a chart. A literal one is the points as written. A `source` one reads the records of a flow (or of the repeat the chart sits in);
    /// its `label` and `y` operands are parsed with one record's shape in scope, so an `item` path the flow does not give is `invalid_reference`
    /// and one of the wrong kind `binding_type`.
    private mutating func chartSeries(_ c: Cursor) throws -> ServerUIChart.Series {
        if try c.s("type") == "literal" {
            return try .literal(c.field("points").array().map { item in
                let value: Double?
                if case .number(let number) = item.value["value"] { value = number } else { value = nil }
                return ServerUIChart.Point(label: try item.s("label"), value: value)
            })
        }
        let providerId = try c.optionalString("providerId")
        var shape: ServerUIFlowShape?
        if let providerId {
            if let source = rawSources[providerId] {
                if source["kind"] == .string("model"), source["model"] == .string("pipeline@1") {
                    if let flow = repeatFlow(providerId, source) {
                        let provided = ServerUIFlowCompiler.checkRepeatProvider(flow, at: c.pointer)
                        issues += provided.issues
                        shape = provided.item
                    }
                } else { add(.bindingType, c.path("providerId")) }
            } else { add(.invalidReference, c.path("providerId")) }
        } else if case .cell(let held, let placeholder)? = repeatScope, !placeholder {
            shape = held
        } else { add(.invalidCombination, c.pointer) }

        let limit = try c.i("limit")
        let outer = repeatScope
        defer { repeatScope = outer }
        // With no usable flow the paths cannot be checked, but `item` and `index` still stand: any shape fits.
        repeatScope = .cell(shape ?? .any, placeholder: false)
        let x = try c.field("x"), labelCursor = try x.field("label")
        let label = try operand(labelCursor)
        let value = try numberOperand(c.field("y"))
        if let kind = label.staticKind, kind != .string { add(.bindingType, labelCursor.pointer) }
        if let shape {
            Self.checkLeaf(label, in: shape, want: .string, at: labelCursor.pointer, issues: &issues)
            Self.checkLeaf(value, in: shape, want: .number, at: c.path("y"), issues: &issues)
        }
        return .source(providerId: providerId, limit: limit, label: label, value: value)
    }

    /// An `item` operand whose path exists but whose kinds cannot be the wanted one is `binding_type` (the Studio's `checkChartOperandKind`).
    private static func checkLeaf(_ operand: ServerUIOperand, in shape: ServerUIFlowShape, want: ServerUIFlowShape.Kind, at pointer: String,
                                  issues: inout [Issue]) {
        guard case .item(let path) = operand, let leaf = shape.shape(at: path) else { return }
        let have = leaf.withoutNull.kinds
        if !have.isEmpty, !have.contains(want) { issues.append(Issue(.bindingType, pointer)) }
    }

    // MARK: Linear gauge

    /// A `linear-gauge`: a `span` gauge needs its span and a `scale` gauge has none; the marker and the value come together; the gradient has two to
    /// eight stops that never fall back; the value and the span are number operands.
    mutating func linearGaugeComponent(_ c: Cursor, node: D.Node, props: Cursor) throws -> D.Component {
        require("linear-gauge")
        let fill: ServerUILinearGauge.Fill = try props.e("fill")
        let hasSpan = props.value["span"] != nil, hasMarker = props.value["marker"] != nil, hasValue = props.value["value"] != nil
        if fill == .span, !hasSpan { add(.missingRequired, props.path("span")) }
        if fill == .scale, hasSpan { add(.invalidCombination, props.path("span")) }
        if hasMarker, !hasValue { add(.missingRequired, props.path("value")) }
        if hasValue, !hasMarker { add(.invalidCombination, props.path("value")) }
        let value = try hasValue ? numberOperand(props.field("value")) : nil
        var span: ServerUILinearGauge.Span?
        if hasSpan {
            let item = try props.field("span")
            span = try .init(start: numberOperand(item.field("start")), size: numberOperand(item.field("size")))
        }
        let stopCursors = try props.field("stops").array()
        if stopCursors.count < 2 { add(.invalidValue, props.path("stops")) }
        var stops: [ServerUILinearGauge.Stop] = []
        for (index, item) in stopCursors.enumerated() {
            let stop = try ServerUILinearGauge.Stop(at: item.n("at"), ink: ink(item.field("ink")))
            if index > 0, stop.at < stops[index - 1].at { add(.invalidValue, item.path("at")) }
            stops.append(stop)
        }
        var marker: ServerUILinearGauge.Marker?
        if hasMarker {
            let item = try props.field("marker")
            var border: ServerUILinearGauge.Marker.Border?
            if item.value["border"] != nil {
                let edge = try item.field("border")
                border = try .init(ink: ink(edge.field("ink")), width: edge.n("width"))
            }
            marker = try .init(size: item.n("size"), ink: ink(item.field("ink")), border: border)
        }
        let a11y = try c.field("a11y")
        let spoken: ServerUILinearGauge.Accessibility
        if try a11y.s("element") == "value" {
            spoken = try .value(label: stringValue(a11y.field("label")),
                                value: a11y.value["value"] == nil ? nil : stringValue(a11y.field("value")))
        } else { spoken = .hidden }
        return try .linearGauge(ServerUILinearGauge(
            node: node, value: value, scale: props.value["scale"] == nil ? .unit : props.e("scale"), span: span, fill: fill, stops: stops,
            track: ink(props.field("track")), marker: marker, height: props.value["height"] == nil ? ServerUILinearGauge.defaultHeight : props.n("height"),
            animates: props.value["animates"] == nil ? true : props.b("animates"), accessibility: spoken))
    }
}
