import Foundation

// MARK: - Compiling a repeat

/// The compile step of `repeat` (`sh.repeat@1`), following the Studio's `compiler.ts` (`repeat`) and `repeat.ts` (`checkRepeat`).
extension ServerUICompositionCompiler {
    /// A `repeat`: one copy of its first child for every record of a `records` flow.
    ///
    /// The flow must exist and give records (`binding_type` otherwise); a repeat does not hold a repeat (`invalid_combination` at the inner node)
    /// or a saved component (``ServerUIRepeatCheck``); the paging fits the repeat's axis and its counts; the second child is the placeholder and
    /// exists exactly when `placeholder` is set. The first child is decoded with the flow's record shape in scope, so an `item` path the flow does
    /// not give is `invalid_reference`; the placeholder has no record, so `item` is refused there.
    mutating func repeatComponent(_ c: Cursor, node: D.Node, props: Cursor, depth: Int) throws -> D.Component {
        require("repeat")
        if repeatScope != nil { add(.invalidCombination, c.path("type")) }
        let providerId = try props.s("providerId")
        let axis: ServerUIRepeat.Axis = try props.e("axis")
        var paging: ServerUIRepeat.Paging?
        if props.value["paging"] != nil {
            let field = try props.field("paging")
            let scale = try field.value["scaleByTextSize"] == nil ? nil : field.field("scaleByTextSize").array().map { item -> Double in
                guard case .number(let factor) = item.value else { throw Issue(.invalidValue, item.pointer) }
                return factor
            }
            let minimum = try field.value["minimum"] == nil ? nil : field.i("minimum")
            let value = try ServerUIRepeat.Paging(
                compact: field.i("compact"), regular: field.i("regular"), scaleByTextSize: scale, minimum: minimum,
                indicator: field.value["indicator"] == nil ? false : field.b("indicator"),
                buttons: field.value["buttons"] == nil ? .never : field.e("buttons"), label: field.optionalString("label"))
            if axis != .horizontal { add(.invalidCombination, field.pointer) }
            if let minimum, minimum > value.compact || minimum > value.regular { add(.invalidValue, field.path("minimum")) }
            if let scale, scale.indices.contains(where: { $0 > 0 && scale[$0] > scale[$0 - 1] }) { add(.invalidValue, field.path("scaleByTextSize")) }
            paging = value
        }
        let placeholderCount = try props.value["placeholder"] == nil ? nil : props.field("placeholder").i("count")
        let items = try c.field("children").array()
        if placeholderCount != nil, items.count < 2 { add(.missingRequired, c.path("children")) }
        else if placeholderCount == nil, items.count > 1 { add(.invalidCombination, c.path("children") + "/1") }

        // The flow: it must be a `pipeline@1` source that gives records, and its schema says what `item` may read.
        var shape: ServerUIFlowShape?
        if let source = rawSources[providerId] {
            if source["kind"] == .string("model"), source["model"] == .string("pipeline@1") {
                let flow = repeatFlow(providerId, source)
                if let flow {
                    let provided = ServerUIFlowCompiler.checkRepeatProvider(flow, at: props.pointer)
                    issues += provided.issues
                    shape = provided.item
                }
            } else { add(.bindingType, props.path("providerId")) }
        } else { add(.invalidReference, props.path("providerId")) }

        let outer = repeatScope
        defer { repeatScope = outer }
        var children: [D.Component] = []
        for (index, child) in items.enumerated() {
            // With no usable flow the paths cannot be checked, but `item` and `index` still stand: any shape fits.
            repeatScope = .cell(shape ?? .any, placeholder: index == 1)
            do { children.append(try component(child, depth: depth + 1, gridChild: false)) } catch let issue as Issue { issues.append(issue) }
        }
        return try .repeatNode(.init(
            node: node, providerId: providerId, axis: axis, spacing: space(props.field("spacing")),
            limit: props.value["limit"] == nil ? ServerUIRepeat.maximumCells : props.i("limit"), paging: paging, placeholderCount: placeholderCount,
            words: .init(loading: props.s("loadingText"), empty: props.s("emptyText"), unavailable: props.s("unavailableText"),
                         error: props.s("errorText"), stale: props.s("staleText")),
            children: children))
    }

    /// The flow a source holds, decoded once for the repeats that name it; `nil` when it does not decode (the source's own compile says why).
    private mutating func repeatFlow(_ id: String, _ source: JSONValue) -> ServerUIFlow? {
        if let known = repeatFlows[id] { return known }
        let flow = source["inputs"].flatMap { ServerUIFlowDecoder.decode($0, at: "").flow }
        repeatFlows[id] = .some(flow)
        return flow
    }
}

// MARK: - A repeat holds no saved component

/// The check that a `repeat` holds no `component-ref`: a saved component inside it could hold a repeat, so it is refused at the child's `type`.
///
/// It reads the document as written, not as expanded (the reference is gone by then), the way ``ServerUIStackTapCheck`` does.
enum ServerUIRepeatCheck {
    typealias Issue = ServerUICompositionError

    /// The issues of every repeat in the publication `json`, in walk order.
    static func issues(in json: JSONValue) -> [Issue] {
        guard let document = json["document"] else { return [] }
        var found: [Issue] = []
        func visit(_ node: JSONValue, at pointer: String) {
            let type = node["type"]?.string
            if type == "repeat" {
                for (index, child) in (node["children"]?.array ?? []).enumerated() where child["type"]?.string == "component-ref" {
                    found.append(Issue(.invalidCombination, "\(pointer)/children/\(index)/type"))
                }
            }
            if type == "local-tabs" {
                for key in ["tabs", "blocks"] {
                    for (group, entry) in (node[key]?.array ?? []).enumerated() {
                        for (index, child) in (entry["children"]?.array ?? []).enumerated() { visit(child, at: "\(pointer)/\(key)/\(group)/children/\(index)") }
                    }
                }
            } else {
                for (index, child) in (node["children"]?.array ?? []).enumerated() { visit(child, at: "\(pointer)/children/\(index)") }
            }
        }
        for key in ["pages", "modals"] {
            for (index, surface) in (document[key]?.array ?? []).enumerated() {
                for (position, node) in (surface["components"]?.array ?? []).enumerated() {
                    visit(node, at: "/document/\(key)/\(index)/components/\(position)")
                }
            }
        }
        for (index, entry) in (document["componentLibrary"]?.array ?? []).enumerated() {
            if let node = entry["node"] { visit(node, at: "/document/componentLibrary/\(index)/node") }
        }
        return found
    }
}
