import Foundation

// MARK: - Library and reference walk

extension ServerUIComponentExpansion {
    /// One saved component as the walk uses it.
    struct Entry {
        let index: Int
        let id: String
        /// The body, each nested reference replaced by a placeholder.
        let node: JSONValue
        let parameters: [(name: String, kind: String)]
        let bindings: [(parameter: String, nodeId: String, field: String)]
    }

    /// Reads the library, checks it, and expands every reference of the pages and sheets.
    struct Builder {
        var issues: [Issue] = []
        var bodies: [Body] = []
        var argumentReferences: [ArgumentReference] = []
        var regions: [Region] = []
        var refusedArguments: Set<String> = []
        private var entries: [String: Entry] = [:]
        private var sawReference = false

        // MARK: - Walk

        /// Replaces the references of `document` in place; true when it has a library or a reference.
        mutating func run(_ document: inout [String: JSONValue]) -> Bool {
            readLibrary(document["componentLibrary"]?.array ?? [])
            for kind in ["pages", "modals"] {
                guard let surfaces = document[kind]?.array else { continue }
                document[kind] = .array(surfaces.enumerated().map { index, surface in
                    guard case .object(var object) = surface, let nodes = object["components"]?.array else { return surface }
                    let pointer = "/document/\(kind)/\(index)/components"
                    object["components"] = .array(nodes.enumerated().map { expand($1, at: "\(pointer)/\($0)") })
                    return .object(object)
                })
            }
            let uses = document["componentLibrary"] != nil || sawReference
            document["componentLibrary"] = nil
            return uses
        }

        private mutating func expand(_ node: JSONValue, at pointer: String) -> JSONValue {
            if node["type"]?.string == "component-ref" { return expandReference(node, at: pointer) }
            return ServerUIComponentExpansion.mapChildren(node, at: pointer) { child, at in expand(child, at: at) }
        }

        // MARK: - Library

        private mutating func readLibrary(_ library: [JSONValue]) {
            var firstId: [String: String] = [:]
            for (index, item) in library.enumerated() {
                let at = "/document/componentLibrary/\(index)"
                let id = item["id"]?.string ?? ""
                if let previous = firstId[id] { issues.append(Issue(.duplicateID, min(previous, at + "/id"))) } else { firstId[id] = at + "/id" }
                if let name = item["name"]?.string,
                   name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || $0.properties.generalCategory == .format }) {
                    issues.append(Issue(.invalidValue, at + "/name"))
                }
                let body = sanitize(item["node"] ?? .null, at: at + "/node")
                let entry = Entry(
                    index: index, id: id, node: body,
                    parameters: (item["params"]?.array ?? []).map { ($0["name"]?.string ?? "", $0["kind"]?.string ?? "") },
                    bindings: (item["bindings"]?.array ?? []).map {
                        ($0["param"]?.string ?? "", $0["nodeId"]?.string ?? "", $0["field"]?.string ?? "")
                    })
                checkParameters(entry, at: at)
                bodies.append(Body(pointer: at + "/node", value: body))
                if entries[id] == nil { entries[id] = entry }
            }
        }

        /// `node` with each reference replaced by a placeholder; a reference in a body is refused at its `type`.
        private mutating func sanitize(_ node: JSONValue, at pointer: String) -> JSONValue {
            if node["type"]?.string == "component-ref" {
                issues.append(Issue(.invalidCombination, pointer + "/type"))
                return ServerUIComponentExpansion.placeholder(for: node)
            }
            return ServerUIComponentExpansion.mapChildren(node, at: pointer) { child, at in sanitize(child, at: at) }
        }

        /// Parameter names are unique, and each binding names a parameter, a node of the body and a field that exists and fits the kind.
        private mutating func checkParameters(_ entry: Entry, at pointer: String) {
            var names = Set<String>()
            for (index, parameter) in entry.parameters.enumerated() {
                if !names.insert(parameter.name).inserted { issues.append(Issue(.duplicateID, "\(pointer)/params/\(index)/name")) }
            }
            var bound = Set<String>()
            for (index, binding) in entry.bindings.enumerated() {
                let at = "\(pointer)/bindings/\(index)"
                let parameter = entry.parameters.first { $0.name == binding.parameter }
                if parameter == nil { issues.append(Issue(.invalidReference, at + "/param")) }
                guard let target = Self.find(binding.nodeId, in: entry.node) else {
                    issues.append(Issue(.invalidReference, at + "/nodeId"))
                    continue
                }
                guard Self.read(target, field: binding.field) != nil else {
                    issues.append(Issue(.invalidReference, at + "/field"))
                    continue
                }
                if let parameter, Self.kind(of: binding.field, in: target) != parameter.kind { issues.append(Issue(.bindingType, at + "/field")) }
                if !bound.insert("\(binding.nodeId)\u{0}\(binding.field)").inserted { issues.append(Issue(.invalidCombination, at + "/field")) }
            }
        }

        // MARK: - Reference

        private mutating func expandReference(_ reference: JSONValue, at pointer: String) -> JSONValue {
            sawReference = true
            guard let entry = entries[reference["componentId"]?.string ?? ""] else {
                issues.append(Issue(.invalidReference, pointer + "/componentId"))
                return ServerUIComponentExpansion.placeholder(for: reference)
            }
            var arguments: [String: String] = [:]
            if case .object(let given)? = reference["args"] {
                for (name, value) in given { arguments[name] = value.string ?? "" }
            }
            checkArguments(arguments, of: entry, at: pointer + "/args")
            var written: [String: String] = [:]
            let body = rename(entry.node, entry: entry, arguments: arguments, reference: reference, relative: "", written: &written)
            regions.append(Region(pointer: pointer, entry: entry.index, bound: written))
            return body
        }

        /// One argument for each parameter, none for anything else, and a value that fits the parameter's kind.
        private mutating func checkArguments(_ arguments: [String: String], of entry: Entry, at pointer: String) {
            let names = Set(entry.parameters.map(\.name))
            for name in arguments.keys.sorted() where !names.contains(name) {
                issues.append(Issue(.unknownField, ServerUICompositionJSON.pointer(pointer, name)))
            }
            for parameter in entry.parameters {
                let at = ServerUICompositionJSON.pointer(pointer, parameter.name)
                guard let value = arguments[parameter.name] else { issues.append(Issue(.missingRequired, at)); continue }
                switch parameter.kind {
                case "text": continue
                case "symbol": if value.utf16.count > 80 { refuse(at) }
                default:
                    guard ServerUICompositionShape.validID(value) else { refuse(at); continue }
                    let catalog = parameter.kind == "source-id" ? "source" : parameter.kind == "page-id" ? "page" : "modal"
                    argumentReferences.append(ArgumentReference(catalog: catalog, id: value, pointer: at))
                }
            }
        }

        private mutating func refuse(_ pointer: String) {
            issues.append(Issue(.invalidValue, pointer))
            refusedArguments.insert(pointer)
        }

        /// The body as one use: arguments written into the bound fields, the root given the reference's id and width, every other id derived.
        private func rename(_ node: JSONValue, entry: Entry, arguments: [String: String], reference: JSONValue,
                            relative: String, written: inout [String: String]) -> JSONValue {
            let root = relative.isEmpty
            var next = node
            for binding in entry.bindings where binding.nodeId == node["id"]?.string {
                guard let value = arguments[binding.parameter], let changed = Self.write(.string(value), to: next, field: binding.field) else { continue }
                next = changed
                written[Self.fieldPointer(binding.field, under: relative)] = binding.parameter
            }
            // `written` is threaded through the closure by a local copy, since the walk is not mutating.
            var inner = written
            next = ServerUIComponentExpansion.mapChildren(next, at: relative) { child, at in
                rename(child, entry: entry, arguments: arguments, reference: reference, relative: at, written: &inner)
            }
            written = inner
            guard case .object(var object) = next else { return next }
            let referenceId = reference["id"]?.string ?? ""
            let innerId = object["id"]?.string ?? ""
            object["id"] = .string(root ? referenceId : "\(referenceId)~\(innerId)")
            if root, case .object(var layout)? = object["layout"] {
                layout["span"] = reference["layout"]?["span"] ?? .number(1)
                object["layout"] = .object(layout)
            }
            return .object(object)
        }
    }
}
