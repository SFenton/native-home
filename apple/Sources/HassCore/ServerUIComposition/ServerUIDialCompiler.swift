import Foundation

// MARK: - Compiling a dial and an arc track

/// The compile steps of `dial` (`sh.dial@1`) and `arc-track` (`sh.arc-track@1`), following the Studio's `compiler.ts` (`dial`, `arcTrack`): the
/// combinations the closed shape cannot hold and the number operands.
extension ServerUICompositionCompiler {
    // MARK: Parts

    private mutating func spoken(_ c: Cursor) throws -> (label: D.StringValue, value: D.StringValue?)? {
        let a11y = try c.field("a11y")
        guard try a11y.s("element") == "value" else { return nil }
        return try (stringValue(a11y.field("label")), a11y.value["value"] == nil ? nil : stringValue(a11y.field("value")))
    }

    private mutating func arcPoint(_ c: Cursor, inside box: ServerUIArcLayout.Box) throws -> ServerUIArcLayout.Point {
        let numbers = try c.array().map { item -> Double in
            guard case .number(let value) = item.value else { throw Issue(.invalidValue, item.pointer) }
            return value
        }
        let point = ServerUIArcLayout.Point(numbers[0], numbers[1])
        if point.x > box.width || point.y > box.height { add(.invalidValue, c.pointer) }
        return point
    }

    // MARK: Dial

    /// A `dial`: `degrees` reads a full turn, so the sweep must be 360; a ring's outer end lies beyond its inner end; a skipped tick is one the
    /// ring has; a letter that needs a value needs a pointer; the middle's lines follow the rules of a `text`.
    mutating func dialComponent(_ c: Cursor, node: D.Node, props: Cursor) throws -> D.Component {
        require("dial")
        let sweepCursor = try props.field("sweep")
        let sweep = try ServerUIDialLayout.Sweep(start: sweepCursor.n("start"), length: sweepCursor.n("length"))
        let scale: ServerUIDialLayout.Scale = try props.value["scale"] == nil ? .unit : props.e("scale")
        if scale == .degrees, sweep.length != 360 { add(.invalidCombination, props.path("scale")) }

        var size: ServerUIDial.Size?
        if props.value["size"] != nil {
            let item = try props.field("size")
            let cap = try item.value["maxPoints"] == nil ? nil : item.n("maxPoints")
            let points = try item.n("points")
            if let cap, cap < points { add(.invalidValue, item.path("maxPoints")) }
            size = try .init(points: points, relativeTo: item.value["relativeTo"] == nil ? nil : item.e("relativeTo"), maxPoints: cap)
        }

        var ticks: ServerUIDial.Ticks?
        if props.value["ticks"] != nil {
            let item = try props.field("ticks")
            let (count, inner, outer) = try (item.i("count"), item.n("inner"), item.n("outer"))
            if outer <= inner { add(.invalidValue, item.path("outer")) }
            var alternate: Double?
            if item.value["alternate"] != nil {
                let inside = try item.field("alternate")
                alternate = try inside.n("inner")
                if let alternate, alternate >= outer { add(.invalidValue, inside.path("inner")) }
            }
            var skip: [Int] = []
            if item.value["skip"] != nil {
                for (at, entry) in try item.field("skip").array().enumerated() {
                    guard case .number(let number) = entry.value, let index = Int(exactly: number) else { throw Issue(.invalidValue, entry.pointer) }
                    if index >= count { add(.invalidValue, item.path("skip") + "/\(at)") }
                    skip.append(index)
                }
            }
            ticks = try .init(ring: .init(count: count, inner: inner, outer: outer, alternateInner: alternate, skip: skip), width: item.n("width"),
                              ink: ink(item.field("ink")))
        }

        var pointer: ServerUIDial.Pointer?
        if props.value["pointer"] != nil {
            let item = try props.field("pointer")
            let value = try numberOperand(item.field("value"))
            if try item.s("kind") == "tick" {
                let (inner, outer) = try (item.n("inner"), item.n("outer"))
                if outer <= inner { add(.invalidValue, item.path("outer")) }
                pointer = try .tick(value: value, inner: inner, outer: outer, width: item.n("width"), ink: ink(item.field("ink")))
            } else {
                pointer = try .needle(value: value, ink: ink(item.field("ink")), tailInk: ink(item.field("tailInk")), dotInk: ink(item.field("dotInk")),
                                      animates: item.value["animates"] == nil ? true : item.b("animates"))
            }
        }

        var labels: ServerUIDial.Labels?
        if props.value["labels"] != nil {
            let item = try props.field("labels")
            var items: [ServerUIDialLayout.Label] = []
            for entry in try item.field("items").array() {
                let needsValue = try entry.value["needsValue"] == nil ? false : entry.b("needsValue")
                if needsValue, pointer == nil { add(.invalidCombination, entry.path("needsValue")) }
                items.append(try .init(at: entry.n("at"), text: entry.s("text"), needsValue: needsValue))
            }
            labels = try .init(ink: ink(item.field("ink")), items: items)
        }

        var flag: ServerUIDial.Flag?
        if props.value["flag"] != nil {
            let item = try props.field("flag")
            flag = try .init(at: item.n("at"), ink: ink(item.field("ink")))
        }

        var center: [ServerUIDial.Line] = []
        if props.value["center"] != nil {
            for line in try props.field("center").array() { center.append(try centerLine(line)) }
        }

        let words = try spoken(c)
        return try .dial(ServerUIDial(
            node: node, sweep: sweep, scale: scale, aspect: props.value["aspect"] == nil ? 1 : props.n("aspect"),
            centerY: props.value["centerY"] == nil ? 0.5 : props.n("centerY"), size: size,
            maxWidth: props.value["maxWidth"] == nil ? nil : props.n("maxWidth"), ticks: ticks, pointer: pointer, labels: labels, flag: flag,
            center: center, mirrors: props.value["mirrors"] == nil ? false : props.b("mirrors"),
            accessibility: words.map { .value(label: $0.label, value: $0.value) } ?? .hidden))
    }

    /// One line of the middle: the props of a `text`, with a text's rules and the ids it needs.
    private mutating func centerLine(_ line: Cursor) throws -> ServerUIDial.Line {
        require("text")
        let style: D.TextStyle = try line.e("style")
        if [.subheadline, .footnote].contains(style) { require("supporting-text-styles") }
        if style == .sectionTitle { require("section-title") }
        return try .init(value: stringValue(line.field("value")), style: style, unavailableText: line.s("unavailableText"),
                         look: textLook(line, style: style))
    }

    // MARK: Arc track

    /// An `arc-track`: the curve's three points and the horizon's two lie in the box; the marker and the progress come together; the progress is a
    /// number operand.
    mutating func arcTrackComponent(_ c: Cursor, node: D.Node, props: Cursor) throws -> D.Component {
        require("arc-track")
        let boxNumbers = try props.field("box").array().map { item -> Double in
            guard case .number(let value) = item.value else { throw Issue(.invalidValue, item.pointer) }
            return value
        }
        let box = ServerUIArcLayout.Box(width: boxNumbers[0], height: boxNumbers[1])
        let curveCursor = try props.field("curve")
        let curve = try ServerUIArcLayout.Curve(from: arcPoint(curveCursor.field("from"), inside: box),
                                                control: arcPoint(curveCursor.field("control"), inside: box),
                                                to: arcPoint(curveCursor.field("to"), inside: box))
        var horizon: ServerUIArcTrack.Horizon?
        if props.value["horizon"] != nil {
            let item = try props.field("horizon")
            horizon = try .init(line: .init(from: arcPoint(item.field("from"), inside: box), to: arcPoint(item.field("to"), inside: box)),
                                ink: ink(item.field("ink")), width: item.n("width"))
        }
        var dash: ServerUIArcTrack.Dash?
        if props.value["dash"] != nil {
            let numbers = try props.field("dash").array().map { item -> Double in
                guard case .number(let value) = item.value else { throw Issue(.invalidValue, item.pointer) }
                return value
            }
            dash = .init(stroke: numbers[0], gap: numbers[1])
        }
        let hasMarker = props.value["marker"] != nil, hasProgress = props.value["progress"] != nil
        if hasMarker, !hasProgress { add(.missingRequired, props.path("progress")) }
        if hasProgress, !hasMarker { add(.invalidCombination, props.path("progress")) }
        let progress = try hasProgress ? numberOperand(props.field("progress")) : nil
        var marker: ServerUIArcTrack.Marker?
        if hasMarker {
            let item = try props.field("marker")
            marker = try .init(size: item.n("size"), ink: ink(item.field("ink")))
        }
        let words = try spoken(c)
        return try .arcTrack(ServerUIArcTrack(
            node: node, curve: curve, box: box, maxWidth: props.value["maxWidth"] == nil ? nil : props.n("maxWidth"), ink: ink(props.field("ink")),
            width: props.n("width"), dash: dash, horizon: horizon, progress: progress,
            scale: props.value["scale"] == nil ? .unit : props.e("scale"), marker: marker,
            mirrors: props.value["mirrors"] == nil ? true : props.b("mirrors"),
            accessibility: words.map { .value(label: $0.label, value: $0.value) } ?? .hidden))
    }
}
