import Foundation

// MARK: - Template-owned sources (`sh.component-ref@1`)

extension ServerUIComponentExpansion {
    /// The most data sources a document holds once every use has added its own copies.
    static let maximumSources = 1_000

    /// A data source the expansion adds to the document's own `dataSources`, after them.
    struct AppendedSource {
        /// The source as the compiler decodes it.
        let source: JSONValue
        /// The reference whose use added the copy; nil for the copy that stands in for an entry's own source while its body is checked
        /// (it is compiled so the body's reads resolve, then dropped from the published document).
        let reference: String?
        /// The bound fields of the copy, under the source (`/entityId/value`), each to the parameter that filled it.
        let bound: [String: String]
        /// For the stand-in of an entry's own Data Flow: where the flow is written in the library (`/document/componentLibrary/<i>/flows/<j>`),
        /// which the issues found in the stand-in move back to.
        var libraryPointer: String?
    }

    /// Which appended source an issue pointer is under, with the rest of the pointer; nil when it is not under one.
    func appendedSource(at pointer: String) -> (index: Int, relative: String)? {
        let prefix = "/document/dataSources/"
        guard pointer.hasPrefix(prefix) else { return nil }
        let rest = pointer.dropFirst(prefix.count)
        let digits = rest.prefix { $0.isNumber }
        guard let position = Int(digits), position >= ownSourceCount, position - ownSourceCount < appendedSources.count else { return nil }
        return (position - ownSourceCount, String(rest.dropFirst(digits.count)))
    }

    /// `sources`, as the compiler decoded them, without the copies that only stand in for an entry's own while its body is checked.
    func published<T>(_ sources: [T]) -> [T] {
        let checks = appendedSources.prefix { $0.reference == nil }.count
        guard checks > 0, sources.count >= ownSourceCount + checks else { return sources }
        return Array(sources[..<ownSourceCount] + sources[(ownSourceCount + checks)...])
    }
}

// MARK: - Naming and rewriting

extension ServerUIComponentExpansion.Builder {
    /// Whether `key` names a data source or provider by id. A `copySourceId` names an entity, so it is not one.
    static func isSourceKey(_ key: String) -> Bool {
        key != "copySourceId" && key.range(of: "(source|provider)Id$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Whether `key` lists data source or provider ids.
    static func isSourceListKey(_ key: String) -> Bool {
        key.range(of: "(source|provider)Ids$", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// A new id for one appended source: an identifier the expression parser reads, equal to no data source the document names.
    mutating func freshSourceId() -> String {
        var name: String
        repeat {
            sourceCounter += 1
            name = "tpl-\(sourceCounter)"
        } while takenSourceIds.contains(name)
        return name
    }

    /// A new id for each of an entry's own sources, in order.
    mutating func freshSourceIds(for sources: [JSONValue]) -> [String] { sources.map { _ in freshSourceId() } }

    /// The ids of `sources` mapped to `names`; a repeated id keeps its first name, as a lookup by id finds the first.
    static func privateNames(_ sources: [JSONValue], _ names: [String]) -> [String: String] {
        var map: [String: String] = [:]
        for (source, name) in zip(sources, names) {
            if let id = source["id"]?.string, map[id] == nil { map[id] = name }
        }
        return map
    }

    /// `value` with every source key that names an id in `names` rewritten to the mapped name. Only those keys change: text, ids of
    /// nodes and a `copySourceId` are left as written.
    static func renamingSources(_ value: JSONValue, _ names: [String: String]) -> JSONValue {
        guard !names.isEmpty else { return value }
        switch value {
        case .array(let items):
            return .array(items.map { renamingSources($0, names) })
        case .object(let object):
            var next = object
            for (key, inner) in object {
                if case .string(let id) = inner, isSourceKey(key) {
                    next[key] = .string(names[id] ?? id)
                } else if case .array(let items) = inner, isSourceListKey(key) {
                    next[key] = .array(items.map { item in item.string.map { .string(names[$0] ?? $0) } ?? item })
                } else {
                    next[key] = renamingSources(inner, names)
                }
            }
            return .object(next)
        default:
            return value
        }
    }

    // MARK: - Checks

    /// An entry's own sources: each id once, and an entity of the form `domain.object`.
    mutating func checkSources(_ entry: ServerUIComponentExpansion.Entry, at pointer: String) {
        var ids = Set<String>()
        func written(_ index: Int) -> String {
            index < entry.entityCount ? "\(pointer)/sources/\(index)" : "\(pointer)/flows/\(index - entry.entityCount)"
        }
        for (index, source) in entry.sources.enumerated() {
            let at = written(index)
            // The first of two is where the document check reports a repeated id.
            if let id = source["id"]?.string, !ids.insert(id).inserted {
                let first = entry.sources.firstIndex { $0["id"]?.string == id } ?? index
                issues.append(ServerUICompositionError(.duplicateID, written(first) + "/id"))
            }
            if let entity = source["entityId"]?["value"]?.string,
               !ServerUICompositionShape.matches(entity, "^[a-z][a-z0-9_]*\\.[a-z0-9_]+$") {
                issues.append(ServerUICompositionError(.invalidValue, at + "/entityId/value"))
            }
        }
    }

    /// The copies of an entry's sources that stand in for them while its body is checked, each under its name in `names`.
    mutating func appendCheckCopies(of entry: ServerUIComponentExpansion.Entry, names: [String], at pointer: String) {
        for (index, (source, name)) in zip(entry.sources, names).enumerated() {
            guard case .object(var object) = source else { continue }
            object["id"] = .string(name)
            appended.append(.init(source: .object(object), reference: nil, bound: [:],
                                  libraryPointer: index < entry.entityCount ? nil : "\(pointer)/flows/\(index - entry.entityCount)"))
        }
    }

    /// One copy of each of the entry's sources for the use at `pointer`, each under its name in `names` and each bound field taking its
    /// argument. Appended to the document in the order the uses appear.
    mutating func appendUseCopies(of entry: ServerUIComponentExpansion.Entry, names: [String], pointer: String, arguments: [String: String]) {
        for (source, name) in zip(entry.sources, names) {
            guard case .object(var object) = source, let id = source["id"]?.string else { continue }
            object["id"] = .string(name)
            var next = JSONValue.object(object)
            var bound: [String: String] = [:]
            for binding in entry.bindings where binding.sourceId == id {
                guard let value = arguments[binding.parameter], let changed = Self.write(.string(value), to: next, field: binding.field) else { continue }
                next = changed
                bound[Self.fieldPointer(binding.field, under: "")] = binding.parameter
            }
            appended.append(.init(source: next, reference: pointer, bound: bound))
        }
    }
}
