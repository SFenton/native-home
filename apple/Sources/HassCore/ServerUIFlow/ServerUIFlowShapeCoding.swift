import Foundation

// MARK: - Shape JSON

extension ServerUIFlowShape {
    /// The shape in the Studio's JSON form: `{ kind, ... }`, with `optional`, `integer`, `format` and `enum` present only when set.
    public var json: JSONValue {
        func object(_ fields: [String: JSONValue]) -> JSONValue { JSONValue.object(fields) }
        switch self {
        case .never: return object(["kind": .string("never")])
        case .any: return object(["kind": .string("any")])
        case .null: return object(["kind": .string("null")])
        case .boolean: return object(["kind": .string("boolean")])
        case .number(let integer): return object(integer ? ["kind": .string("number"), "integer": .bool(true)] : ["kind": .string("number")])
        case .string(let format, let values):
            var fields: [String: JSONValue] = ["kind": .string("string")]
            if let format { fields["format"] = .string(format.rawValue) }
            if let values { fields["enum"] = .array(values.map { .string($0) }) }
            return object(fields)
        case .array(let of): return object(["kind": .string("array"), "of": of.json])
        case .object(let fields):
            return object(["kind": .string("object"), "fields": object(fields.mapValues { field in
                field.isOptional ? object(["shape": field.shape.json, "optional": .bool(true)]) : object(["shape": field.shape.json])
            })])
        case .union(let list): return object(["kind": .string("union"), "of": .array(list.map(\.json))])
        }
    }

    /// Reads a shape from its JSON form; `nil` when the JSON is not one (``issues(in:at:)`` says why).
    public init?(json: JSONValue) {
        guard case .object(let object) = json, case .string(let kind)? = object["kind"] else { return nil }
        switch kind {
        case "never": self = .never
        case "any": self = .any
        case "null": self = .null
        case "boolean": self = .boolean
        case "number": self = .number(integer: object["integer"] == .bool(true))
        case "string":
            let format = object["format"]?.string.flatMap(Format.init(rawValue:))
            let values = object["enum"]?.array?.compactMap(\.string)
            self = .string(format: format, values: values)
        case "array":
            guard let inner = object["of"].flatMap(Self.init(json:)) else { return nil }
            self = .array(inner)
        case "object":
            guard case .object(let raw)? = object["fields"] else { return nil }
            var fields: [String: Field] = [:]
            for (name, entry) in raw {
                guard let shape = entry["shape"].flatMap(Self.init(json:)) else { return nil }
                fields[name] = Field(shape, optional: entry["optional"] == .bool(true))
            }
            self = .object(fields)
        case "union":
            guard let items = object["of"]?.array else { return nil }
            let list = items.compactMap(Self.init(json:))
            guard list.count == items.count else { return nil }
            self = .union(list)
        default: return nil
        }
    }

    /// Every structural problem of `value` as a shape: unknown and missing fields, wrong kinds, unknown variants, list sizes.
    static func issues(in value: JSONValue, at pointer: String) -> [ServerUICompositionError] {
        var found: [ServerUICompositionError] = []
        func issue(_ code: ServerUICompositionError.Code, _ at: String) { found.append(ServerUICompositionError(code, at)) }
        func keys(_ object: [String: JSONValue], _ allowed: Set<String>, _ at: String) {
            for key in object.keys where !allowed.contains(key) { issue(.unknownField, ServerUICompositionJSON.pointer(at, key)) }
        }
        func walk(_ value: JSONValue, _ at: String) {
            guard case .object(let object) = value else { issue(.invalidValue, at); return }
            guard let tag = object["kind"] else { issue(.missingRequired, at + "/kind"); return }
            guard case .string(let kind) = tag else { issue(.invalidValue, at + "/kind"); return }
            switch kind {
            case "never", "any", "null", "boolean": keys(object, ["kind"], at)
            case "number":
                keys(object, ["kind", "integer"], at)
                if let integer = object["integer"], integer != .bool(true) { issue(.invalidValue, at + "/integer") }
            case "string":
                keys(object, ["kind", "format", "enum"], at)
                if let format = object["format"] {
                    guard case .string(let name) = format else { issue(.invalidValue, at + "/format"); break }
                    if Format(rawValue: name) == nil { issue(.unknownVariant, at + "/format") }
                }
                if let values = object["enum"] {
                    guard case .array(let items) = values else { issue(.invalidValue, at + "/enum"); break }
                    if items.isEmpty || items.count > Limits.enumValues { issue(.limitExceeded, at + "/enum") }
                    for (index, item) in items.enumerated() {
                        guard case .string(let text) = item else { issue(.invalidValue, at + "/enum/\(index)"); continue }
                        if text.utf16.count > Limits.enumLength { issue(.limitExceeded, at + "/enum/\(index)") }
                    }
                }
            case "array":
                keys(object, ["kind", "of"], at)
                if let inner = object["of"] { walk(inner, at + "/of") } else { issue(.missingRequired, at + "/of") }
            case "object":
                keys(object, ["kind", "fields"], at)
                guard let fields = object["fields"] else { issue(.missingRequired, at + "/fields"); break }
                guard case .object(let entries) = fields else { issue(.invalidValue, at + "/fields"); break }
                for (name, entry) in entries.sorted(by: { $0.key < $1.key }) {
                    let own = ServerUICompositionJSON.pointer(at + "/fields", name)
                    if name.isEmpty || name.utf16.count > Limits.fieldName
                        || !ServerUICompositionShape.matches(name, "^[A-Za-z0-9_.-]+$") || ServerUICompositionJSON.reserved.contains(name) {
                        issue(.invalidValue, own)
                    }
                    guard case .object(let field) = entry else { issue(.invalidValue, own); continue }
                    keys(field, ["shape", "optional"], own)
                    if let inner = field["shape"] { walk(inner, own + "/shape") } else { issue(.missingRequired, own + "/shape") }
                    if let optional = field["optional"], optional != .bool(true) { issue(.invalidValue, own + "/optional") }
                }
            case "union":
                keys(object, ["kind", "of"], at)
                guard let members = object["of"] else { issue(.missingRequired, at + "/of"); break }
                guard case .array(let items) = members else { issue(.invalidValue, at + "/of"); break }
                if items.count < 2 || items.count > Limits.unionMembers { issue(.limitExceeded, at + "/of") }
                for (index, item) in items.enumerated() { walk(item, at + "/of/\(index)") }
            default: issue(.unknownVariant, at + "/kind")
            }
        }
        walk(value, pointer)
        return found
    }
}

extension ServerUIFlowShape.Limits {
    /// The longest name of an object field.
    public static let fieldName = 160
}
