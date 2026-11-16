import Foundation

// MARK: - Bound fields

extension ServerUIComponentExpansion.Builder {
    /// The steps of a bound field: `props/sourceId` is `["props", "sourceId"]`.
    static func steps(_ field: String) -> [String] { field.split(separator: "/").map(String.init) }

    /// The pointer of a bound field under the node at `parent`.
    static func fieldPointer(_ field: String, under parent: String) -> String {
        steps(field).reduce(parent) { ServerUICompositionJSON.pointer($0, $1) }
    }

    /// The node with `id` inside `node`, itself included, first in document order.
    static func find(_ id: String, in node: JSONValue) -> JSONValue? {
        if node["id"]?.string == id { return node }
        var found: JSONValue?
        _ = ServerUIComponentExpansion.mapChildren(node, at: "") { child, _ in
            if found == nil { found = find(id, in: child) }
            return child
        }
        return found
    }

    /// The value at `field` under `node`, or nil when a step is missing.
    static func read(_ node: JSONValue, field: String) -> JSONValue? {
        steps(field).reduce(Optional(node)) { value, step in
            switch value {
            case .object(let object)?: object[step]
            case .array(let array)?: Int(step).flatMap { array.indices.contains($0) ? array[$0] : nil }
            default: nil
            }
        }
    }

    /// `node` with `field` set to `value`; nil when a step is missing (the value must replace one that is there).
    static func write(_ value: JSONValue, to node: JSONValue, field: String) -> JSONValue? {
        func set(_ current: JSONValue, _ remaining: ArraySlice<String>) -> JSONValue? {
            guard let step = remaining.first else { return value }
            switch current {
            case .object(var object):
                guard let child = object[step], let changed = set(child, remaining.dropFirst()) else { return nil }
                object[step] = changed
                return .object(object)
            case .array(var array):
                guard let index = Int(step), array.indices.contains(index), let changed = set(array[index], remaining.dropFirst()) else { return nil }
                array[index] = changed
                return .array(array)
            default: return nil
            }
        }
        let steps = steps(field)
        return steps.isEmpty ? nil : set(node, steps[...])
    }

    /// What a field holds, as far as a binding cares, from where it sits: a page or sheet id, a source or provider id, an SF Symbol name,
    /// a literal's value or the node's own `title`. Nil for any field a parameter may not fill.
    static func kind(of field: String, in node: JSONValue) -> String? {
        let steps = steps(field)
        guard let last = steps.last, read(node, field: field)?.string != nil else { return nil }
        let parent = read(node, field: steps.dropLast().joined(separator: "/"))
        if last == "pageId" { return "page-id" }
        if last == "modalId" { return "modal-id" }
        if last.range(of: "(source|provider)Id$", options: [.regularExpression, .caseInsensitive]) != nil { return "source-id" }
        if last == "name", parent?["type"]?.string == "sf-symbol" { return "symbol" }
        if last == "value", parent?["type"]?.string == "literal" { return "text" }
        if steps.count == 1, last == "title" { return "text" }
        return nil
    }
}
