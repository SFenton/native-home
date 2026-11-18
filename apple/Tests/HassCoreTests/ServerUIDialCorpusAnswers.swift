import Foundation
@testable import HassCore

// MARK: - The dial and arc subjects of the evaluation corpus

/// The answers the app's dial and arc arithmetic give for the `dial` and `arc` subjects of the shared evaluation corpus
/// (`ContractCorpus/evaluation/dial-*.json`, `arc-track-*.json`), in the shape the case files record. The cases are hand-written from the weather
/// panel's native tests; the Studio's own modules and ``ServerUIDialLayout`` and ``ServerUIArcLayout`` must both give them byte for byte.
enum ServerUIDialCorpusAnswers {
    enum Failure: Error { case unknownOp(String), badSubject(String) }

    private static func json(_ value: Double?) -> JSONValue { value.map(JSONValue.number) ?? .null }

    private static func sweep(_ value: JSONValue?) -> ServerUIDialLayout.Sweep {
        .init(start: value?["start"]?.number ?? 0, length: value?["length"]?.number ?? 0)
    }

    private static func scale(_ value: JSONValue?) -> ServerUIDialLayout.Scale { ServerUIDialLayout.Scale(rawValue: value?.string ?? "") ?? .unit }

    /// The input of a `layout` case.
    static func dialInput(_ input: JSONValue?) -> ServerUIDialLayout.Input {
        var ring: ServerUIDialLayout.Ring?
        if let ticks = input?["ticks"] {
            ring = .init(count: Int(ticks["count"]?.number ?? 0), inner: ticks["inner"]?.number ?? 0, outer: ticks["outer"]?.number ?? 0,
                         alternateInner: ticks["alternate"]?["inner"]?.number, skip: (ticks["skip"]?.array ?? []).compactMap { $0.number.map { Int($0) } })
        }
        var pointer: ServerUIDialLayout.Pointer?
        if let held = input?["pointer"] {
            pointer = .init(kind: held["kind"]?.string == "needle" ? .needle : .tick, value: held["value"]?.number, inner: held["inner"]?.number ?? 0,
                            outer: held["outer"]?.number ?? 0)
        }
        let labels = (input?["labels"]?.array ?? []).map {
            ServerUIDialLayout.Label(at: $0["at"]?.number ?? 0, text: $0["text"]?.string ?? "", needsValue: $0["needsValue"]?.bool ?? false)
        }
        return .init(width: input?["width"]?.number ?? 0, aspect: input?["aspect"]?.number ?? 1, centerY: input?["centerY"]?.number ?? 0.5,
                     sweep: sweep(input?["sweep"]), scale: scale(input?["scale"]), ring: ring, pointer: pointer, labels: labels,
                     flag: input?["flag"]?["at"]?.number, mirrors: input?["mirrors"]?.bool ?? false, rtl: input?["rtl"]?.bool ?? false)
    }

    private static func segment(_ value: ServerUIDialLayout.Segment?) -> JSONValue {
        value.map { .object(["x1": .number($0.x1), "y1": .number($0.y1), "x2": .number($0.x2), "y2": .number($0.y2)]) } ?? .null
    }

    /// The parts of a layout a case names, in the case's own keys.
    static func dialParts(_ layout: ServerUIDialLayout.Layout) -> [String: JSONValue] {
        [
            "width": .number(layout.width), "height": .number(layout.height), "cx": .number(layout.cx), "cy": .number(layout.cy),
            "radius": .number(layout.radius), "ticks": .array(layout.ticks.map { segment($0) }), "lit": segment(layout.lit),
            "needle": layout.needle.map { .object(["rotation": .number($0.rotation), "angle": .number($0.angle)]) } ?? .null,
            "labels": .array(layout.labels.map {
                .object(["text": .string($0.text), "x": .number($0.x), "y": .number($0.y), "fontSize": .number($0.fontSize)])
            }),
            "flag": layout.flag.map { .array($0.map { .object(["x": .number($0.x), "y": .number($0.y)]) }) } ?? .null,
            "share": json(layout.share)
        ]
    }

    /// The parts a case's `pick` names, each by a path: a part (`lit`), an item of a list (`ticks.24`), a field of it (`labels.0.fontSize`) or a
    /// list's length (`ticks.length`); all the parts when it names none.
    private static func pick(_ names: JSONValue?, from parts: [String: JSONValue]) -> [String: JSONValue] {
        let picked = (names?.array ?? []).compactMap(\.string)
        guard !picked.isEmpty else { return parts }
        var chosen: [String: JSONValue] = [:]
        for name in picked {
            var path = name.split(separator: ".").map(String.init)
            guard let head = path.first, var part = parts[head] else { continue }
            path.removeFirst()
            for step in path {
                if step == "length", let items = part.array { part = .number(Double(items.count)) }
                else if let index = Int(step), let items = part.array, items.indices.contains(index) { part = items[index] }
                else if let next = part[step] { part = next }
            }
            chosen[name] = part
        }
        return chosen
    }

    /// The answer for the `dial` subject `subject`.
    static func dial(_ subject: JSONValue) throws -> JSONValue {
        let op = subject["op"]?.string ?? ""
        let body: [String: JSONValue]
        switch op {
        case "layout":
            let parts = dialParts(ServerUIDialLayout.layoutDial(dialInput(subject["input"])))
            body = pick(subject["pick"], from: parts)
        case "share":
            body = ["share": json(ServerUIDialLayout.dialShare(subject["value"]?.number, scale: scale(subject["scale"]), sweep: sweep(subject["sweep"])))]
        case "normalize": body = ["degrees": .number(ServerUIDialLayout.normalizeDegrees(subject["value"]?.number ?? 0))]
        case "delta":
            body = ["delta": .number(ServerUIDialLayout.shortestTurn(from: subject["from"]?.number ?? 0, to: subject["to"]?.number ?? 0))]
        case "next":
            body = ["angle": .number(ServerUIDialLayout.nextTurn(previous: subject["previous"]?.number, target: subject["target"]?.number ?? 0))]
        default: throw Failure.unknownOp(op)
        }
        return .object(["dial": .object(body)])
    }

    private static func arcPoint(_ value: JSONValue?) -> ServerUIArcLayout.Point {
        let numbers = (value?.array ?? []).compactMap(\.number)
        return .init(numbers.first ?? 0, numbers.dropFirst().first ?? 0)
    }

    private static func pair(_ point: ServerUIArcLayout.Point) -> JSONValue { .array([.number(point.x), .number(point.y)]) }

    private static func line(_ value: JSONValue?) -> ServerUIArcLayout.Line? {
        value.map { .init(from: arcPoint($0["from"]), to: arcPoint($0["to"])) }
    }

    private static func curve(_ value: JSONValue?) -> ServerUIArcLayout.Curve {
        .init(from: arcPoint(value?["from"]), control: arcPoint(value?["control"]), to: arcPoint(value?["to"]))
    }

    /// The answer for the `arc` subject `subject`.
    static func arc(_ subject: JSONValue) throws -> JSONValue {
        let op = subject["op"]?.string ?? ""
        let body: [String: JSONValue]
        switch op {
        case "layout":
            let input = subject["input"]
            let box = (input?["box"]?.array ?? []).compactMap(\.number)
            let layout = ServerUIArcLayout.layoutArc(.init(
                curve: curve(input?["curve"]), box: .init(width: box.first ?? 1, height: box.dropFirst().first ?? 1), maxWidth: input?["maxWidth"]?.number,
                horizon: line(input?["horizon"]), width: input?["width"]?.number ?? 0, progress: input?["progress"]?.number,
                scale: ServerUIArcLayout.Scale(rawValue: input?["scale"]?.string ?? "") ?? .unit, mirrors: input?["mirrors"]?.bool ?? true,
                rtl: input?["rtl"]?.bool ?? false))
            let parts: [String: JSONValue] = [
                "width": .number(layout.width), "height": .number(layout.height),
                "curve": .object(["from": pair(layout.curve.from), "control": pair(layout.curve.control), "to": pair(layout.curve.to)]),
                "horizon": layout.horizon.map { .object(["from": pair($0.from), "to": pair($0.to)]) } ?? .null,
                "marker": layout.marker.map { .object(["x": .number($0.x), "y": .number($0.y), "t": .number($0.t)]) } ?? .null
            ]
            body = pick(subject["pick"], from: parts)
        case "progress":
            body = ["t": json(ServerUIArcLayout.progress(subject["value"]?.number, scale: ServerUIArcLayout.Scale(rawValue: subject["scale"]?.string ?? "") ?? .unit))]
        case "point":
            let point = ServerUIArcLayout.curvePoint(curve(subject["curve"]), t: subject["t"]?.number ?? 0)
            body = ["x": .number(point.x), "y": .number(point.y)]
        default: throw Failure.unknownOp(op)
        }
        return .object(["arc": .object(body)])
    }
}
