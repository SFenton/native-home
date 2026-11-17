import Foundation
@testable import HassCore

// MARK: - The chart and gauge subjects of the evaluation corpus

/// The answers the app's chart and gauge arithmetic give for the `chart` and `gauge` subjects of the shared evaluation corpus
/// (`ContractCorpus/evaluation/chart-*.json`, `gauge-*.json`), in the shape the case files record. The cases are hand-written from the weather
/// panel's native tests; the Studio's own module and this one must both give them byte for byte.
enum ServerUIChartCorpusAnswers {
    enum Failure: Error { case unknownOp(String), badSubject(String) }

    private static func number(_ value: JSONValue?) -> Double? { value?.number }
    private static func list(_ value: JSONValue?) -> [Double?] {
        (value?.array ?? []).map { $0.number }
    }
    private static func json(_ value: Double?) -> JSONValue { value.map(JSONValue.number) ?? .null }

    /// The answer for the `chart` subject `subject`, with `reader` as the environment a `source-points` case reads.
    static func chart(_ subject: JSONValue, reader: some ServerUIReading) throws -> JSONValue {
        let op = subject["op"]?.string ?? ""
        let body: [String: JSONValue]
        switch op {
        case "domain":
            let domain = subject["domain"]
            let top = ServerUIChartMath.ceilingDomain(peak: number(subject["peak"]), step: number(domain?["step"]) ?? 1,
                                                      min: number(domain?["min"]) ?? 0, max: number(domain?["max"]) ?? 0)
            body = ["domain": .number(top)]
        case "two-step":
            let axis = ServerUIChartMath.twoStepDomain(
                total: number(subject["total"]), minimumStep: number(subject["minimumStep"]) ?? 0,
                maximumFractionDigits: Int(number(subject["maximumFractionDigits"]) ?? 0),
                factors: subject["factors"]?.array?.compactMap(\.number) ?? ServerUIChartMath.axisFactors)
            body = ["domain": .number(axis.domain), "step": .number(axis.step), "digits": .number(Double(axis.digits))]
        case "share":
            body = ["percent": .number(ServerUIChartMath.scaledPercent(number(subject["value"]), top: number(subject["top"]) ?? 0,
                                                                         base: number(subject["base"]) ?? 0))]
        case "labels":
            let count = Int(number(subject["count"]) ?? 0)
            let cadence = ServerUIChartMath.labelCadence(count: count, plotWidth: number(subject["plotWidth"]) ?? 0,
                                                         widestLabelWidth: number(subject["widestLabelWidth"]) ?? 0)
            body = ["cadence": .number(Double(cadence)),
                    "indices": .array(ServerUIChartMath.labelIndices(count: count, cadence: cadence).map { .number(Double($0)) })]
        case "indices":
            body = ["indices": .array(ServerUIChartMath.labelIndices(count: Int(number(subject["count"]) ?? 0),
                                                                     cadence: Int(number(subject["cadence"]) ?? 1)).map { .number(Double($0)) })]
        case "levels":
            let values = ServerUIChartMath.axisLevels(Int(number(subject["levels"]) ?? 0), top: number(subject["top"]) ?? 0,
                                                      base: number(subject["base"]) ?? 0)
            let pattern = subject["pattern"]?.string ?? "{value}", digits = Int(number(subject["digits"]) ?? 0)
            body = ["values": .array(values.map(JSONValue.number)),
                    "labels": .array(values.map { .string(ServerUIChartMath.axisText(pattern: pattern, value: $0, digits: digits)) })]
        case "bars":
            let bars = ServerUIChartMath.barMarks(list(subject["values"]), top: number(subject["top"]) ?? 0, base: number(subject["base"]) ?? 0,
                                                  width: number(subject["width"]) ?? 0, height: number(subject["height"]) ?? 0,
                                                  gap: number(subject["gap"]) ?? 0, minimum: number(subject["minimum"]) ?? 0)
            body = ["bars": .array(bars.map {
                .object(["x": .number($0.x), "width": .number($0.width), "height": .number($0.height), "unknown": .bool($0.unknown)])
            })]
        case "points":
            let points = ServerUIChartMath.pointMarks(list(subject["values"]), top: number(subject["top"]) ?? 0, base: number(subject["base"]) ?? 0,
                                                      width: number(subject["width"]) ?? 0, height: number(subject["height"]) ?? 0)
            body = ["points": .array(points.map { .object(["x": .number($0.x), "y": json($0.y)]) })]
        case "spoken":
            let points = (subject["points"]?.array ?? []).map { ServerUIChart.Point(label: $0["label"]?.string ?? "", value: number($0["value"])) }
            body = ["spoken": .string(ServerUIChartMath.seriesText(points, pattern: subject["pattern"]?.string ?? "{value}",
                                                                   digits: Int(number(subject["digits"]) ?? 0),
                                                                   unknownText: subject["unknownText"]?.string ?? ""))]
        case "source-points":
            let series = subject["series"]
            let points = ServerUIChart.sourcePoints(
                limit: Int(number(series?["limit"]) ?? 0), label: try operand(series?["x"]?["label"]), value: try operand(series?["y"]),
                records: subject["records"]?.array ?? [], in: reader)
            body = ["sourcePoints": .array(points.map { .object(["label": .string($0.label), "value": json($0.value)]) })]
        default:
            throw Failure.unknownOp(op)
        }
        return .object(["chart": .object(body)])
    }

    /// The answer for the `gauge` subject `subject`.
    static func gauge(_ subject: JSONValue) -> JSONValue {
        let input = ServerUIGaugeMath.Input(
            scale: ServerUILinearGauge.Scale(rawValue: subject["scale"]?.string ?? "") ?? .unit, value: number(subject["value"]),
            spanStart: number(subject["span"]?["start"]), spanSize: number(subject["span"]?["size"]),
            fill: ServerUILinearGauge.Fill(rawValue: subject["fill"]?.string ?? "") ?? .scale, width: number(subject["width"]) ?? 0,
            markerSize: number(subject["markerSize"]) ?? 0, rtl: subject["rtl"]?.bool ?? false)
        let layout = ServerUIGaugeMath.layout(input)
        let span: JSONValue = layout.span.map {
            .object(["startPercent": .number($0.startPercent), "sizePercent": .number($0.sizePercent), "left": .number($0.left), "width": .number($0.width)])
        } ?? .null
        let marker: JSONValue = layout.marker.map { .object(["percent": .number($0.percent), "left": .number($0.left)]) } ?? .null
        return .object(["gauge": .object(["span": span, "marker": marker])])
    }

    private static func operand(_ json: JSONValue?) throws -> ServerUIOperand {
        var parser = ServerUIExpressionParser(allowControl: true, evaluationOnly: true)
        let value = parser.operand(json ?? .null, at: "")
        guard parser.issues.isEmpty, let value else { throw Failure.badSubject("operand issues: \(parser.issues)") }
        return value
    }
}
