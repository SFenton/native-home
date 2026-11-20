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
        /// The data sources the entry owns, as authored: its entities (`sources`), then its Data Flows (`flows`, `sh.repeat@1`).
        let sources: [JSONValue]
        /// How many of ``sources`` are entities; the rest are flows.
        let entityCount: Int
        /// The names the sources take in the copies that stand in for them while the body is checked.
        let checkNames: [String]
        /// A binding fills a field of one body node or of one owned source.
        let bindings: [(parameter: String, nodeId: String?, sourceId: String?, field: String)]
    }

    /// Reads the library, checks it, and expands every reference of the pages and sheets.
    struct Builder {
        var issues: [Issue] = []
        var bodies: [Body] = []
        var argumentReferences: [ArgumentReference] = []
        var regions: [Region] = []
        var refusedArguments: Set<String> = []
        /// The data sources added to the document, after its own.
        var appended: [AppendedSource] = []
        /// How many data sources the document itself holds.
        private(set) var ownSourceCount = 0
        /// How many data sources the uses walked so far have added (they count toward the document's limit).
        private var addedSources = 0
        /// The ids of the document's own data sources, which a fresh source id may not equal, and the fresh ids handed out so far.
        var takenSourceIds: Set<String> = []
        var sourceCounter = 0
        private var entries: [String: Entry] = [:]
        private var sawReference = false
        /// Whether any entry owns a Data Flow, so the document needs `sh.repeat@1`.
        private(set) var ownsFlows = false

        // MARK: - Walk

        /// Replaces the references of `document` in place; true when it has a library or a reference.
        mutating func run(_ document: inout [String: JSONValue]) -> Bool {
            let own = document["dataSources"]?.array ?? []
            ownSourceCount = own.count
            takenSourceIds = Set(own.compactMap { $0["id"]?.string })
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
            if !appended.isEmpty { document["dataSources"] = .array(own + appended.map(\.source)) }
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
                if let name = item["name"]?.string, Self.hasInvisible(name) { issues.append(Issue(.invalidValue, at + "/name")) }
                for (position, parameter) in (item["params"]?.array ?? []).enumerated() {
                    if let label = parameter["label"]?.string, Self.hasInvisible(label) {
                        issues.append(Issue(.invalidValue, "\(at)/params/\(position)/label"))
                    }
                }
                let body = sanitize(item["node"] ?? .null, at: at + "/node")
                let entities = item["sources"]?.array ?? [], flows = item["flows"]?.array ?? []
                if !flows.isEmpty { ownsFlows = true }
                let sources = entities + flows
                let entry = Entry(
                    index: index, id: id, node: body,
                    parameters: (item["params"]?.array ?? []).map { ($0["name"]?.string ?? "", $0["kind"]?.string ?? "") },
                    sources: sources, entityCount: entities.count, checkNames: freshSourceIds(for: sources),
                    bindings: (item["bindings"]?.array ?? []).map {
                        ($0["param"]?.string ?? "", $0["nodeId"]?.string, $0["sourceId"]?.string, $0["field"]?.string ?? "")
                    })
                checkSources(entry, at: at)
                checkParameters(entry, at: at)
                // The body is checked with its own sources standing as copies of them (see ``appendCheckCopies(of:names:)``).
                bodies.append(Body(pointer: at + "/node", value: Self.renamingSources(body, Self.privateNames(sources, entry.checkNames))))
                appendCheckCopies(of: entry, names: entry.checkNames, at: at)
                if entries[id] == nil { entries[id] = entry }
            }
        }

        /// Whether `text` holds a control or format character, which a name or a label may not.
        private static func hasInvisible(_ text: String) -> Bool {
            text.unicodeScalars.contains { $0.properties.generalCategory == .control || $0.properties.generalCategory == .format }
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
                if binding.nodeId == nil, binding.sourceId == nil { issues.append(Issue(.missingRequired, at + "/nodeId")); continue }
                if binding.nodeId != nil, binding.sourceId != nil { issues.append(Issue(.invalidCombination, at + "/sourceId")); continue }
                let target: JSONValue?
                if let nodeId = binding.nodeId { target = Self.find(nodeId, in: entry.node) }
                else { target = entry.sources.first { $0["id"]?.string == binding.sourceId } }
                guard let target else {
                    issues.append(Issue(.invalidReference, at + (binding.nodeId != nil ? "/nodeId" : "/sourceId")))
                    continue
                }
                guard Self.read(target, field: binding.field) != nil else {
                    issues.append(Issue(.invalidReference, at + "/field"))
                    continue
                }
                if let parameter, Self.kind(of: binding.field, in: target) != parameter.kind { issues.append(Issue(.bindingType, at + "/field")) }
                let key = "\(binding.nodeId != nil ? "node" : "source")\u{0}\(binding.nodeId ?? binding.sourceId ?? "")\u{0}\(binding.field)"
                if !bound.insert(key).inserted { issues.append(Issue(.invalidCombination, at + "/field")) }
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
            if !entry.sources.isEmpty {
                // The copies each use adds count toward the document's limit.
                if ownSourceCount + addedSources + entry.sources.count > ServerUIComponentExpansion.maximumSources {
                    issues.append(Issue(.limitExceeded, pointer + "/componentId"))
                }
                addedSources += entry.sources.count
            }
            checkArguments(arguments, of: entry, at: pointer + "/args")
            var written: [String: String] = [:]
            // A source key naming an owned source is rewritten first, so an argument that happens to equal one is not.
            let useNames = freshSourceIds(for: entry.sources)
            let body = rename(Self.renamingSources(entry.node, Self.privateNames(entry.sources, useNames)), entry: entry, arguments: arguments,
                              reference: reference, relative: "", written: &written)
            appendUseCopies(of: entry, names: useNames, pointer: pointer, arguments: arguments)
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
                case "entity-id":
                    // No catalog lookup: the field's own rule (a style's domain, a source's model) runs on the expansion.
                    if !ServerUICompositionShape.matches(value, "^[a-z][a-z0-9_]*\\.[a-z0-9_]+$") { refuse(at) }
                default:
                    guard ServerUICompositionShape.validID(value) else { refuse(at); continue }
                    let catalog = ["source-id": "source", "page-id": "page", "state-id": "local-state"][parameter.kind] ?? "modal"
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
            for binding in entry.bindings where binding.nodeId != nil && binding.nodeId == node["id"]?.string {
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
                // The place says where the component sits (`sh.fold-sides@1`); the body's own side is not read.
                layout["foldSide"] = reference["layout"]?["foldSide"]
                object["layout"] = .object(layout)
            }
            return .object(object)
        }
    }
}
