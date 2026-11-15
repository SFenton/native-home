import Foundation

// MARK: - Operand, predicate and call-service parsing

/// Validates authored operands, predicates and service calls and builds their typed forms in one pass, reporting every problem with
/// a JSON pointer. The shape validator uses it for diagnostics and the compiler for the plan, so there is one grammar.
///
/// Limits: expression depth 8, 64 operands or predicates per expression (128 per call), texts 2,000 characters.
struct ServerUIExpressionParser {
    typealias Issue = ServerUICompositionError
    static let maximumDepth = 8
    static let maximumNodes = 64
    static let maximumCallNodes = 128

    /// A place an expression names a source, for the compiler's reference checks.
    struct Reference: Equatable {
        let sourceId: String
        let path: [String]
        /// The pointer to blame for an unknown source or a bad path.
        let pointer: String
        /// The kind a `read` operand asked for; `nil` for a predicate, which compares text or numbers itself.
        let kind: ServerUICompositionDocument.ScalarKind?
    }

    private(set) var issues: [Issue] = []
    private(set) var references: [Reference] = []
    /// Sources named by an optimistic value (pointer, source id).
    private(set) var optimisticReferences: [(sourceId: String, pointer: String)] = []
    private(set) var usesControl = false
    /// Whether any operand (not only a predicate) was parsed, which needs `sh.operands@1`.
    private(set) var usedOperands = false
    private var budget = 0
    private let allowControl: Bool

    init(allowControl: Bool = false) { self.allowControl = allowControl }

    // MARK: Entry points

    /// Parses one operand.
    mutating func operand(_ json: JSONValue, at pointer: String) -> ServerUIOperand? {
        budget = Self.maximumNodes
        return operand(json, pointer, depth: 1)
    }

    /// Parses one predicate.
    mutating func predicate(_ json: JSONValue, at pointer: String) -> ServerUIPredicate? {
        budget = Self.maximumNodes
        return predicate(json, pointer, depth: 1)
    }

    /// Parses a `call-service` action (the whole object, `type` included).
    mutating func callService(_ json: JSONValue, at pointer: String) -> ServerUICallService? {
        budget = Self.maximumCallNodes
        guard let object = fields(json, pointer, ["type", "domain", "service"],
                                  ["target", "data", "optimistic", "confirmation", "feedback"]) else { return nil }
        if object["type"] != .string("call-service") { add(.unknownVariant, pointer + "/type") }
        if let feedback = object["feedback"], feedback != .string("policy") { add(.unknownVariant, pointer + "/feedback") }
        let domain = identifier(object["domain"], pointer + "/domain")
        let service = identifier(object["service"], pointer + "/service")
        var data: [String: ServerUIOperand] = [:]
        if let raw = object["data"] {
            if raw["type"] != .string("object") { add(.invalidValue, pointer + "/data") }
            else if case .object(let fields)? = operand(raw, pointer + "/data", depth: 1) { data = fields }
        }
        var target: [String: ServerUIOperand] = [:]
        if let raw = object["target"] {
            if case .object(let items) = raw {
                if items.isEmpty { add(.invalidValue, pointer + "/target") }
                for (key, item) in items.sorted(by: { $0.key < $1.key }) {
                    let at = ServerUICompositionJSON.pointer(pointer + "/target", key)
                    guard ServerUICallService.targetKeys.contains(key) else { add(.unknownField, at); continue }
                    guard let value = operand(item, at, depth: 1) else { continue }
                    if case .literal(let literal) = value, !Self.isIdentifier(literal) { add(.invalidValue, at + "/value") }
                    if data[key] != nil { add(.invalidCombination, at) }
                    target[key] = value
                }
            } else { add(.invalidValue, pointer + "/target") }
        }
        var optimistic: [ServerUICallService.Optimistic] = []
        if let raw = object["optimistic"] {
            if case .array(let items) = raw {
                if items.count > 16 { add(.limitExceeded, pointer + "/optimistic") }
                for (index, item) in items.enumerated() {
                    if let entry = optimisticEntry(item, pointer + "/optimistic/\(index)") { optimistic.append(entry) }
                }
            } else { add(.invalidValue, pointer + "/optimistic") }
        }
        var confirmation = ServerUICompositionDocument.Confirmation.policy
        var exempt: [String] = []
        if let raw = object["confirmation"] { (confirmation, exempt) = confirmationValue(raw, pointer + "/confirmation") }
        guard let domain, let service else { return nil }
        return ServerUICallService(domain: domain, service: service, target: target, data: data, optimistic: optimistic,
                                   confirmation: confirmation, exemptUserIds: exempt)
    }

    // MARK: Operands

    private mutating func operand(_ json: JSONValue, _ pointer: String, depth: Int) -> ServerUIOperand? {
        guard depth <= Self.maximumDepth, budget > 0 else { add(.limitExceeded, pointer); return nil }
        budget -= 1
        usedOperands = true
        guard case .object(let object) = json else { add(.invalidValue, pointer); return nil }
        guard let tag = object["type"] else { add(.missingRequired, pointer + "/type"); return nil }
        guard case .string(let type) = tag else { add(.invalidValue, pointer + "/type"); return nil }
        switch type {
        case "literal":
            guard let object = fields(json, pointer, ["type", "value"]), let value = object["value"] else { return nil }
            return literal(value, pointer + "/value", depth: 1) ? .literal(value) : nil
        case "read":
            guard let object = fields(json, pointer, ["type", "from", "as", "missing"]) else { return nil }
            if object["missing"] != .string("unavailable") { add(.unknownVariant, pointer + "/missing") }
            guard let from = fields(object["from"] ?? .null, pointer + "/from", ["type", "sourceId", "path"]) else { return nil }
            if from["type"] != .string("source") { add(.unknownVariant, pointer + "/from/type") }
            guard case .string(let raw)? = object["as"], let kind = ServerUICompositionDocument.ScalarKind(rawValue: raw) else {
                add(object["as"] == nil ? .missingRequired : .unknownVariant, pointer + "/as")
                return nil
            }
            guard let (sourceId, path) = source(from, pointer + "/from") else { return nil }
            references.append(.init(sourceId: sourceId, path: path, pointer: pointer, kind: kind))
            return .read(sourceId: sourceId, path: path, as: kind)
        case "control":
            guard fields(json, pointer, ["type"]) != nil else { return nil }
            if !allowControl { add(.invalidCombination, pointer) }
            usesControl = true
            return .control
        case "viewer":
            guard let object = fields(json, pointer, ["type", "field"]) else { return nil }
            guard case .string(let raw)? = object["field"], let field = ServerUIOperand.ViewerField(rawValue: raw) else {
                add(object["field"] == nil ? .missingRequired : .unknownVariant, pointer + "/field")
                return nil
            }
            return .viewer(field)
        case "format": return format(json, pointer, depth: depth)
        case "map": return map(json, pointer, depth: depth)
        case "math":
            guard let object = fields(json, pointer, ["type", "op", "args"]) else { return nil }
            guard case .string(let raw)? = object["op"], let op = ServerUIOperand.MathOp(rawValue: raw) else {
                add(object["op"] == nil ? .missingRequired : .unknownVariant, pointer + "/op")
                return nil
            }
            guard case .array(let items)? = object["args"] else { add(.invalidValue, pointer + "/args"); return nil }
            if !op.arity.contains(items.count) { add(.invalidCombination, pointer + "/args") }
            let args = items.enumerated().compactMap { operand($0.element, pointer + "/args/\($0.offset)", depth: depth + 1) }
            return args.count == items.count && op.arity.contains(args.count) ? .math(op, args) : nil
        case "object":
            guard let object = fields(json, pointer, ["type", "fields"]), case .object(let items)? = object["fields"] else {
                if case .object(let object) = json, object["fields"] != nil { add(.invalidValue, pointer + "/fields") }
                return nil
            }
            if items.count > 64 { add(.limitExceeded, pointer + "/fields") }
            var result: [String: ServerUIOperand] = [:]
            for (key, item) in items.sorted(by: { $0.key < $1.key }) {
                let at = ServerUICompositionJSON.pointer(pointer + "/fields", key)
                if !ServerUICompositionShape.matches(key, "^[A-Za-z_][A-Za-z0-9_]{0,63}$") { add(.invalidValue, at) }
                if let value = operand(item, at, depth: depth + 1) { result[key] = value }
            }
            return result.count == items.count ? .object(result) : nil
        case "list":
            guard let object = fields(json, pointer, ["type", "items"]) else { return nil }
            guard case .array(let items)? = object["items"] else { add(.invalidValue, pointer + "/items"); return nil }
            if items.count > 64 { add(.limitExceeded, pointer + "/items") }
            let values = items.enumerated().compactMap { operand($0.element, pointer + "/items/\($0.offset)", depth: depth + 1) }
            return values.count == items.count ? .list(values) : nil
        default:
            add(.unknownVariant, pointer + "/type")
            return nil
        }
    }

    private mutating func format(_ json: JSONValue, _ pointer: String, depth: Int) -> ServerUIOperand? {
        guard let object = fields(json, pointer, ["type", "pattern", "args"], ["formats"]) else { return nil }
        guard let pattern = text(object["pattern"], pointer + "/pattern", maximum: 2_000, blank: false) else { return nil }
        guard case .object(let rawArgs)? = object["args"] else { add(.invalidValue, pointer + "/args"); return nil }
        if rawArgs.count > 16 { add(.limitExceeded, pointer + "/args") }
        var args: [String: ServerUIOperand] = [:]
        for (key, item) in rawArgs.sorted(by: { $0.key < $1.key }) {
            let at = ServerUICompositionJSON.pointer(pointer + "/args", key)
            if !ServerUICompositionShape.matches(key, "^[A-Za-z_][A-Za-z0-9_]{0,31}$") { add(.invalidValue, at) }
            if let value = operand(item, at, depth: depth + 1) { args[key] = value }
        }
        // Every `{name}` hole must have an argument, and a hole cannot be left open.
        var rest = Substring(pattern)
        while let open = rest.firstIndex(of: "{") {
            guard let close = rest[open...].firstIndex(of: "}") else { add(.invalidValue, pointer + "/pattern"); break }
            let name = String(rest[rest.index(after: open)..<close])
            if rawArgs[name] == nil { add(.invalidReference, pointer + "/pattern") }
            rest = rest[rest.index(after: close)...]
        }
        var formats: [String: ServerUINumberFormat] = [:]
        if let raw = object["formats"] {
            guard case .object(let items) = raw else { add(.invalidValue, pointer + "/formats"); return nil }
            for (key, item) in items.sorted(by: { $0.key < $1.key }) {
                let at = ServerUICompositionJSON.pointer(pointer + "/formats", key)
                if rawArgs[key] == nil { add(.invalidReference, at) }
                guard let wrapper = fields(item, at, ["number"]), let number = fields(wrapper["number"] ?? .null, at + "/number",
                                                                                       ["maximumFractionDigits"]),
                      case .number(let digits)? = number["maximumFractionDigits"], digits.rounded() == digits, (0...6).contains(digits)
                else {
                    if issues.last?.pointer.hasPrefix(at) != true { add(.invalidValue, at + "/number/maximumFractionDigits") }
                    continue
                }
                formats[key] = ServerUINumberFormat(maximumFractionDigits: Int(digits))
            }
        }
        return args.count == rawArgs.count ? .format(pattern: pattern, args: args, formats: formats) : nil
    }

    private mutating func map(_ json: JSONValue, _ pointer: String, depth: Int) -> ServerUIOperand? {
        guard let object = fields(json, pointer, ["type", "of", "cases", "otherwise"]) else { return nil }
        let subject = operand(object["of"] ?? .null, pointer + "/of", depth: depth + 1)
        let otherwise = operand(object["otherwise"] ?? .null, pointer + "/otherwise", depth: depth + 1)
        guard case .array(let items)? = object["cases"] else { add(.invalidValue, pointer + "/cases"); return nil }
        if items.isEmpty || items.count > 32 { add(.limitExceeded, pointer + "/cases") }
        var cases: [ServerUIOperand.MapCase] = []
        for (index, item) in items.enumerated() {
            let at = pointer + "/cases/\(index)"
            guard let entry = fields(item, at, ["equals", "then"]), let equals = entry["equals"] else { continue }
            switch equals {
            case .string, .number, .bool: break
            default: add(.invalidValue, at + "/equals")
            }
            if let then = operand(entry["then"] ?? .null, at + "/then", depth: depth + 1) {
                cases.append(.init(equals: equals, then: then))
            }
        }
        guard let subject, let otherwise, cases.count == items.count, !cases.isEmpty else { return nil }
        return .map(of: subject, cases: cases, otherwise: otherwise)
    }

    /// A literal JSON value: bounded text, finite numbers, shallow nesting.
    private mutating func literal(_ value: JSONValue, _ pointer: String, depth: Int) -> Bool {
        switch value {
        case .string(let text):
            if text.utf16.count > 2_000 { add(.limitExceeded, pointer); return false }
        case .number(let number):
            if !number.isFinite { add(.invalidValue, pointer); return false }
        case .bool: break
        case .null: add(.invalidValue, pointer); return false
        case .array(let items):
            guard depth <= 4, items.count <= 64 else { add(.limitExceeded, pointer); return false }
            var ok = true
            for (index, item) in items.enumerated() where !literal(item, pointer + "/\(index)", depth: depth + 1) { ok = false }
            return ok
        case .object(let items):
            guard depth <= 4, items.count <= 64 else { add(.limitExceeded, pointer); return false }
            var ok = true
            for (key, item) in items.sorted(by: { $0.key < $1.key })
            where !literal(item, ServerUICompositionJSON.pointer(pointer, key), depth: depth + 1) { ok = false }
            return ok
        }
        return true
    }

    // MARK: Predicates

    private mutating func predicate(_ json: JSONValue, _ pointer: String, depth: Int) -> ServerUIPredicate? {
        guard depth <= Self.maximumDepth, budget > 0 else { add(.limitExceeded, pointer); return nil }
        budget -= 1
        guard case .object(let object) = json else { add(.invalidValue, pointer); return nil }
        guard let tag = object["type"] else { add(.missingRequired, pointer + "/type"); return nil }
        guard case .string(let type) = tag else { add(.invalidValue, pointer + "/type"); return nil }
        switch type {
        case "state":
            guard let object = fields(json, pointer, ["type", "sourceId", "path", "in"]),
                  let (sourceId, path) = source(object, pointer) else { return nil }
            guard let values = textList(object["in"], pointer + "/in", maximum: 32) else { return nil }
            references.append(.init(sourceId: sourceId, path: path, pointer: pointer, kind: nil))
            return .state(sourceId: sourceId, path: path, values: values)
        case "numeric":
            guard let object = fields(json, pointer, ["type", "sourceId", "path"], ["above", "below"]),
                  let (sourceId, path) = source(object, pointer) else { return nil }
            if object["above"] == nil, object["below"] == nil { add(.invalidCombination, pointer); return nil }
            references.append(.init(sourceId: sourceId, path: path, pointer: pointer, kind: nil))
            let above = object["above"].flatMap { operand($0, pointer + "/above", depth: depth + 1) }
            let below = object["below"].flatMap { operand($0, pointer + "/below", depth: depth + 1) }
            if (object["above"] != nil && above == nil) || (object["below"] != nil && below == nil) { return nil }
            return .numeric(sourceId: sourceId, path: path, above: above, below: below)
        case "viewer":
            guard let object = fields(json, pointer, ["type"], ["isAdmin", "userIds"]) else { return nil }
            if object["isAdmin"] == nil, object["userIds"] == nil { add(.invalidCombination, pointer); return nil }
            var isAdmin: Bool?
            if let raw = object["isAdmin"] {
                guard case .bool(let flag) = raw else { add(.invalidValue, pointer + "/isAdmin"); return nil }
                isAdmin = flag
            }
            var userIds: [String]?
            if let raw = object["userIds"] {
                guard let ids = textList(raw, pointer + "/userIds", maximum: 32) else { return nil }
                userIds = ids
            }
            return .viewer(isAdmin: isAdmin, userIds: userIds)
        case "viewer-person":
            guard let object = fields(json, pointer, ["type", "in"]),
                  let values = textList(object["in"], pointer + "/in", maximum: 32) else { return nil }
            return .viewerPerson(values: values)
        case "all", "any":
            guard let object = fields(json, pointer, ["type", "of"]) else { return nil }
            guard case .array(let items)? = object["of"] else { add(.invalidValue, pointer + "/of"); return nil }
            if items.isEmpty || items.count > 16 { add(.limitExceeded, pointer + "/of") }
            let parts = items.enumerated().compactMap { predicate($0.element, pointer + "/of/\($0.offset)", depth: depth + 1) }
            guard parts.count == items.count, !parts.isEmpty, items.count <= 16 else { return nil }
            return type == "all" ? .all(parts) : .any(parts)
        case "not":
            guard let object = fields(json, pointer, ["type", "of"]),
                  let part = predicate(object["of"] ?? .null, pointer + "/of", depth: depth + 1) else { return nil }
            return .not(part)
        default:
            add(.unknownVariant, pointer + "/type")
            return nil
        }
    }

    // MARK: Pieces

    private mutating func optimisticEntry(_ json: JSONValue, _ pointer: String) -> ServerUICallService.Optimistic? {
        guard let object = fields(json, pointer, ["sourceId", "value", "revertAfterSeconds", "failsOnTimeout"]) else { return nil }
        let sourceId = sourceIdentifier(object["sourceId"], pointer + "/sourceId")
        let value = text(object["value"], pointer + "/value", maximum: 160, blank: false)
        var seconds: Double?
        if case .number(let number)? = object["revertAfterSeconds"], number.isFinite, number >= 0.1, number <= 60 { seconds = number }
        else { add(object["revertAfterSeconds"] == nil ? .missingRequired : .limitExceeded, pointer + "/revertAfterSeconds") }
        var fails: Bool?
        if case .bool(let flag)? = object["failsOnTimeout"] { fails = flag } else { add(.invalidValue, pointer + "/failsOnTimeout") }
        guard let sourceId, let value, let seconds, let fails else { return nil }
        optimisticReferences.append((sourceId, pointer + "/sourceId"))
        return .init(sourceId: sourceId, value: value, revertAfterSeconds: seconds, failsOnTimeout: fails)
    }

    private mutating func confirmationValue(_ json: JSONValue, _ pointer: String)
        -> (ServerUICompositionDocument.Confirmation, [String]) {
        guard case .object(let object) = json, case .string(let type)? = object["type"] else {
            add(.invalidValue, pointer)
            return (.policy, [])
        }
        switch type {
        case "policy":
            _ = fields(json, pointer, ["type"])
            return (.policy, [])
        case "additional":
            guard let object = fields(json, pointer, ["type", "style", "title", "confirmLabel", "cancelLabel", "destructive"],
                                      ["message", "exemptUserIds"]) else { return (.policy, []) }
            guard case .string(let rawStyle)? = object["style"],
                  let style = ServerUICompositionDocument.ConfirmationStyle(rawValue: rawStyle) else {
                add(.unknownVariant, pointer + "/style")
                return (.policy, [])
            }
            let title = text(object["title"], pointer + "/title", maximum: 240, blank: false)
            let message = object["message"].flatMap { text($0, pointer + "/message", maximum: 2_000, blank: true) }
            let confirm = text(object["confirmLabel"], pointer + "/confirmLabel", maximum: 240, blank: false)
            if object["cancelLabel"] != .string("Cancel") { add(.unknownVariant, pointer + "/cancelLabel") }
            var destructive = false
            if case .bool(let flag)? = object["destructive"] { destructive = flag } else { add(.invalidValue, pointer + "/destructive") }
            let exempt = object["exemptUserIds"].flatMap { textList($0, pointer + "/exemptUserIds", maximum: 32) } ?? []
            guard let title, let confirm else { return (.policy, []) }
            return (.additional(style: style, title: title, message: message, confirmLabel: confirm,
                                cancelLabel: "Cancel", destructive: destructive), exempt)
        default:
            add(.unknownVariant, pointer + "/type")
            return (.policy, [])
        }
    }

    private mutating func source(_ object: [String: JSONValue], _ pointer: String) -> (String, [String])? {
        let sourceId = sourceIdentifier(object["sourceId"], pointer + "/sourceId")
        guard case .array(let raw)? = object["path"], (1...8).contains(raw.count) else {
            add(object["path"] == nil ? .missingRequired : .limitExceeded, pointer + "/path")
            return nil
        }
        var path: [String] = []
        for (index, item) in raw.enumerated() {
            guard case .string(let segment) = item else { add(.invalidValue, pointer + "/path/\(index)"); continue }
            // Prototype segments, interpreters and numeric array indexing are disallowed in each segment.
            if segment.utf8.count > 160 || ["__proto__", "prototype", "constructor"].contains(segment)
                || !ServerUICompositionShape.matches(segment, "^[A-Za-z0-9_-]+$") || segment.allSatisfy(\.isNumber) {
                add(.invalidReference, pointer + "/path/\(index)")
            }
            path.append(segment)
        }
        guard let sourceId, path.count == raw.count else { return nil }
        return (sourceId, path)
    }

    private mutating func sourceIdentifier(_ value: JSONValue?, _ pointer: String) -> String? {
        guard case .string(let text)? = value, ServerUICompositionShape.validID(text) else {
            add(value == nil ? .missingRequired : .invalidValue, pointer)
            return nil
        }
        return text
    }

    private mutating func identifier(_ value: JSONValue?, _ pointer: String) -> String? {
        guard case .string(let text)? = value, ServerUICompositionShape.matches(text, "^[a-z][a-z0-9_]{0,63}$") else {
            add(value == nil ? .missingRequired : .invalidValue, pointer)
            return nil
        }
        return text
    }

    private mutating func text(_ value: JSONValue?, _ pointer: String, maximum: Int, blank: Bool) -> String? {
        guard case .string(let text)? = value else { add(value == nil ? .missingRequired : .invalidValue, pointer); return nil }
        if text.utf16.count > maximum { add(.limitExceeded, pointer); return nil }
        if !blank, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { add(.invalidValue, pointer); return nil }
        return text
    }

    private mutating func textList(_ value: JSONValue?, _ pointer: String, maximum: Int) -> [String]? {
        guard case .array(let items)? = value else { add(value == nil ? .missingRequired : .invalidValue, pointer); return nil }
        if items.isEmpty || items.count > maximum { add(.limitExceeded, pointer); return nil }
        var result: [String] = []
        for (index, item) in items.enumerated() {
            if let entry = text(item, pointer + "/\(index)", maximum: 160, blank: false) { result.append(entry) }
        }
        return result.count == items.count ? result : nil
    }

    /// An object with exactly the allowed keys; reports unknown and missing ones.
    private mutating func fields(_ json: JSONValue, _ pointer: String, _ required: [String],
                                 _ optional: [String] = []) -> [String: JSONValue]? {
        guard case .object(let object) = json else { add(.invalidValue, pointer); return nil }
        var ok = true
        for key in object.keys.sorted() where !required.contains(key) && !optional.contains(key) {
            add(.unknownField, ServerUICompositionJSON.pointer(pointer, key))
            ok = false
        }
        for key in required where object[key] == nil { add(.missingRequired, pointer + "/" + key); ok = false }
        return ok ? object : nil
    }

    private mutating func add(_ code: Issue.Code, _ pointer: String) { issues.append(Issue(code, pointer)) }

    private static func isIdentifier(_ value: JSONValue) -> Bool {
        switch value {
        case .string(let text): !text.isEmpty
        case .array(let items): !items.isEmpty && items.allSatisfy { if case .string(let text) = $0 { !text.isEmpty } else { false } }
        default: false
        }
    }
}
