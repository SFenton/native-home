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
    /// Nodes in one rule's or flow's condition, and how deep it nests (a document predicate keeps the operand limits).
    static let maximumConditionNodes = 32
    static let maximumConditionDepth = 6
    static let maximumRuleCases = 16

    /// A place an expression names a source, for the compiler's reference checks.
    struct Reference: Equatable {
        let sourceId: String
        let path: [String]
        /// The pointer to blame for an unknown source or a bad path.
        let pointer: String
        /// The kind a `read` operand asked for; `nil` for a predicate, which compares text or numbers itself.
        let kind: ServerUICompositionDocument.ScalarKind?
        /// What the expression does with the source: read a value (the default), read its raw state or read a list attribute.
        var access: Access = .value

        /// The way an expression reads a source, which decides how the compiler checks it.
        enum Access: Equatable {
            /// A `read` operand or a condition leaf: the state or an attribute as a scalar.
            case value
            /// `raw-state`: the entity's state text, on an `ha-entity` only (`sh.raw-state@1`).
            case raw
            /// `last-changed`: the entity's time of last change, on an `ha-entity` only (`sh.entity-time@1`).
            case changed
            /// `list-count` and `list-includes`: one attribute, on an `ha-entity` only (`sh.list-read@1`).
            case list
        }
    }

    private(set) var issues: [Issue] = []
    private(set) var references: [Reference] = []
    /// Sources named by an optimistic value (pointer, source id).
    private(set) var optimisticReferences: [(sourceId: String, pointer: String)] = []
    private(set) var usesControl = false
    /// Whether any operand (not only a predicate) was parsed, which needs `sh.operands@1`.
    private(set) var usedOperands = false
    /// The capabilities (without `sh.` and `@1`) the walk found beyond the base grammar: `pipeline-operands`, `conditions`, `rules`.
    private(set) var needs: Set<String> = []
    private var budget = 0
    /// Nodes left for the condition being walked; `nil` for a document predicate, whose limits are the operand ones.
    private var conditionBudget: Int?
    private let allowControl: Bool
    /// True inside a Data Flow, where `item` and `param` may stand and `control` may not.
    private let flow: Bool

    /// Builds the typed form without the compiler's judgement on where an expression may stand and what kinds it combines: no
    /// `binding_type` or `invalid_combination` issue, and a `null` literal is allowed. Evaluation is total, so the evaluation corpus
    /// holds subjects the compiler would refuse (a `null`, an `item` outside a flow) to pin what they evaluate to.
    private let evaluationOnly: Bool

    /// Where `item` and `index` may stand outside a flow (`sh.repeat@1`): `nil` refuses both; ``Scope/lenient`` is the structure pass, which leaves the
    /// decision to the compiler's walk (it knows where a node sits); ``Scope/cell(_:placeholder:)`` is a repeat's template (a record of that shape)
    /// or its placeholder (no record, so `item` is refused there and `index` stays).
    enum Scope: Equatable {
        case lenient
        case cell(ServerUIFlowShape, placeholder: Bool)
    }
    private let scope: Scope?

    init(allowControl: Bool = false, flow: Bool = false, evaluationOnly: Bool = false, scope: Scope? = nil) {
        self.allowControl = allowControl
        self.flow = flow
        self.evaluationOnly = evaluationOnly
        self.scope = scope
    }

    // MARK: Entry points

    /// Parses one operand.
    mutating func operand(_ json: JSONValue, at pointer: String) -> ServerUIOperand? {
        budget = Self.maximumNodes
        conditionBudget = nil
        return operand(json, pointer, depth: 1)
    }

    /// Parses one predicate.
    mutating func predicate(_ json: JSONValue, at pointer: String) -> ServerUIPredicate? {
        budget = Self.maximumNodes
        conditionBudget = flow ? Self.maximumConditionNodes : nil
        return predicate(json, pointer, depth: 1, conditionDepth: 1)
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
        var confirmWhen: ServerUIPredicate?
        if let raw = object["confirmation"] { (confirmation, exempt, confirmWhen) = confirmationValue(raw, pointer + "/confirmation") }
        guard let domain, let service else { return nil }
        return ServerUICallService(domain: domain, service: service, target: target, data: data, optimistic: optimistic,
                                   confirmation: confirmation, exemptUserIds: exempt, confirmWhen: confirmWhen)
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
            if !allowControl || flow { add(.invalidCombination, pointer) }
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
        case "choose": return choose(json, pointer, depth: depth)
        case "item":
            needs.insert("pipeline-operands")
            guard let object = fields(json, pointer, ["type", "path"]) else { return nil }
            var itemShape: ServerUIFlowShape?
            if flow {
                // A flow's own scope.
            } else if let scope {
                needs.insert("repeat")
                if case .cell(let shape, let placeholder) = scope {
                    if placeholder { add(.invalidCombination, pointer) } else { itemShape = shape }
                }
            } else { add(.invalidCombination, pointer) }
            guard case .array(let items)? = object["path"] else { add(.invalidValue, pointer + "/path"); return nil }
            if items.count > 8 { add(.limitExceeded, pointer + "/path") }
            var path: [String] = []
            for (index, item) in items.enumerated() {
                guard case .string(let segment) = item else { add(.invalidValue, pointer + "/path/\(index)"); continue }
                // The structure pass leaves the segments to the compiler's walk, which also checks the path against the record's shape; the Studio's
                // first issue for a reserved segment is that one, at the path itself.
                if scope != .lenient, segment.utf8.count > 160 || ["__proto__", "prototype", "constructor"].contains(segment)
                    || !ServerUICompositionShape.matches(segment, "^[A-Za-z0-9_-]+$") || segment.allSatisfy(\.isNumber) {
                    add(.invalidReference, pointer + "/path/\(index)")
                }
                path.append(segment)
            }
            if path.count == items.count, items.count <= 8, let itemShape, itemShape.shape(at: path) == nil {
                add(.invalidReference, pointer + "/path")
            }
            return path.count == items.count && items.count <= 8 ? .item(path: path) : nil
        case "index":
            needs.insert("repeat")
            guard fields(json, pointer, ["type"]) != nil else { return nil }
            if !flow, scope == nil { add(.invalidCombination, pointer) }
            return .index
        case "param":
            needs.insert("pipeline-operands")
            guard let object = fields(json, pointer, ["type", "name"]) else { return nil }
            if !flow { add(.invalidCombination, pointer) }
            guard case .string(let name)? = object["name"], ServerUICompositionShape.matches(name, "^[A-Za-z_][A-Za-z0-9_]{0,31}$") else {
                add(object["name"] == nil ? .missingRequired : .invalidValue, pointer + "/name")
                return nil
            }
            return .param(name: name)
        case "clock":
            needs.insert("pipeline-operands")
            guard let object = fields(json, pointer, ["type", "part"]) else { return nil }
            guard case .string(let raw)? = object["part"], let part = ServerUIOperand.ClockPart(rawValue: raw) else {
                add(object["part"] == nil ? .missingRequired : .unknownVariant, pointer + "/part")
                return nil
            }
            if part == .nowSecond {
                // The second clock is the page's own 1 Hz tick; a flow runs once on the minute clock it is given.
                needs.insert("countdown")
                if flow { add(.invalidCombination, pointer) }
            }
            return .clock(part)
        case "date":
            needs.insert("pipeline-operands")
            guard let object = fields(json, pointer, ["type", "op", "from", "to"]) else { return nil }
            let progress = object["op"] == .string("progress"), seconds = object["op"] == .string("seconds-between")
            if object["op"] != .string("days-between"), !progress, !seconds { add(.unknownVariant, pointer + "/op") }
            if progress { needs.insert("flow-extras") }
            if seconds { needs.insert("countdown") }
            let from = operand(object["from"] ?? .null, pointer + "/from", depth: depth + 1)
            let to = operand(object["to"] ?? .null, pointer + "/to", depth: depth + 1)
            guard let from, let to, object["op"] == .string("days-between") || progress || seconds else { return nil }
            return progress ? .progress(from: from, to: to) : seconds ? .secondsBetween(from: from, to: to) : .date(from: from, to: to)
        case "raw-state":
            needs.insert("raw-state")
            guard let object = fields(json, pointer, ["type", "sourceId"]) else { return nil }
            if flow { add(.invalidCombination, pointer) }
            guard let sourceId = sourceIdentifier(object["sourceId"], pointer + "/sourceId") else { return nil }
            references.append(.init(sourceId: sourceId, path: ["state"], pointer: pointer, kind: nil, access: .raw))
            return .rawState(sourceId: sourceId)
        case "last-changed":
            needs.insert("entity-time")
            guard let object = fields(json, pointer, ["type", "sourceId"]) else { return nil }
            if flow { add(.invalidCombination, pointer) }
            guard let sourceId = sourceIdentifier(object["sourceId"], pointer + "/sourceId") else { return nil }
            references.append(.init(sourceId: sourceId, path: ["state"], pointer: pointer, kind: nil, access: .changed))
            return .lastChanged(sourceId: sourceId)
        case "list-count", "list-includes":
            return listRead(json, pointer, depth: depth, includes: type == "list-includes")
        case "count":
            return count(json, pointer, depth: depth)
        case "math":
            guard let object = fields(json, pointer, ["type", "op", "args"]) else { return nil }
            guard case .string(let raw)? = object["op"], let op = ServerUIOperand.MathOp(rawValue: raw) else {
                add(object["op"] == nil ? .missingRequired : .unknownVariant, pointer + "/op")
                return nil
            }
            guard case .array(let items)? = object["args"] else { add(.invalidValue, pointer + "/args"); return nil }
            if op == .truncate { needs.insert("math-truncate") }
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
        var formats: [String: ServerUIFormatSpec] = [:]
        if let raw = object["formats"] {
            guard case .object(let items) = raw else { add(.invalidValue, pointer + "/formats"); return nil }
            for (key, item) in items.sorted(by: { $0.key < $1.key }) {
                let at = ServerUICompositionJSON.pointer(pointer + "/formats", key)
                if rawArgs[key] == nil { add(.invalidReference, at) }
                guard case .object(let spec) = item else { add(.invalidValue, at); continue }
                if let parsed = formatSpec(spec, at, argument: args[key]) { formats[key] = parsed }
            }
        }
        return args.count == rawArgs.count ? .format(pattern: pattern, args: args, formats: formats) : nil
    }

    /// One `formats[name]`: exactly one of `number`, `date` and `text`, else `unknown_variant` at the spec.
    private mutating func formatSpec(_ spec: [String: JSONValue], _ at: String, argument: ServerUIOperand?) -> ServerUIFormatSpec? {
        guard spec.count == 1, let (tag, body) = spec.first, ["number", "date", "text", "duration"].contains(tag) else {
            add(.unknownVariant, at)
            return nil
        }
        let kind = argument.flatMap(Self.kind)
        switch tag {
        case "date":
            needs.insert("pipeline-operands")
            guard let wrapper = fields(body, at + "/date", ["style"]) else { return nil }
            guard case .string(let raw)? = wrapper["style"], let style = ServerUIDateStyle(rawValue: raw) else {
                add(.unknownVariant, at)
                return nil
            }
            if style.needsFlowExtras { needs.insert("flow-extras") }
            // A date style draws a date or a date and time: text. A kind that is known and is not text cannot be one.
            if let kind, kind != .string { add(.bindingType, at) }
            return .date(style)
        case "duration":
            needs.insert("duration-format")
            guard let wrapper = fields(body, at + "/duration", ["style"], ["unit"]) else { return nil }
            guard case .string(let rawStyle)? = wrapper["style"], let style = ServerUIDurationFormat.Style(rawValue: rawStyle) else {
                add(.unknownVariant, at)
                return nil
            }
            var unit: ServerUIDurationFormat.Unit?
            if let rawUnit = wrapper["unit"] {
                guard case .string(let name) = rawUnit, let parsed = ServerUIDurationFormat.Unit(rawValue: name) else {
                    add(.unknownVariant, at)
                    return nil
                }
                // Only a compact duration says its unit: the others are always seconds.
                if style != .compact { add(.invalidCombination, at + "/duration/unit") }
                unit = parsed
            }
            // A duration draws a number: a kind that is known and is not a number cannot be one.
            if let kind, kind != .number { add(.bindingType, at) }
            return .duration(ServerUIDurationFormat(style: style, unit: unit))
        case "text":
            guard let wrapper = fields(body, at + "/text", ["case"]) else { return nil }
            guard case .string(let raw)? = wrapper["case"], let letterCase = ServerUITextCase(rawValue: raw) else {
                add(.unknownVariant, at)
                return nil
            }
            needs.insert(letterCase.capability)
            if let kind, kind != .string { add(.bindingType, at) }
            return .text(letterCase)
        default:
            let pointer = at + "/number"
            guard let number = fields(body, pointer, ["maximumFractionDigits"], ["minimumFractionDigits"]),
                  let most = fractionDigits(number["maximumFractionDigits"], pointer + "/maximumFractionDigits") else { return nil }
            var least: Int?
            if let raw = number["minimumFractionDigits"] {
                // A fixed count of fraction digits needs `sh.pipeline-operands@1`, and it cannot exceed the most the number may have.
                needs.insert("pipeline-operands")
                guard let digits = fractionDigits(raw, pointer + "/minimumFractionDigits") else { return nil }
                if digits > most { add(.invalidCombination, pointer + "/minimumFractionDigits") }
                least = digits
            }
            return .number(ServerUINumberFormat(maximumFractionDigits: most, minimumFractionDigits: least))
        }
    }

    /// A count of fraction digits: a whole number, 0 to 6 (`limit_exceeded` outside it).
    private mutating func fractionDigits(_ value: JSONValue?, _ pointer: String) -> Int? {
        guard case .number(let digits)? = value, digits.rounded() == digits else { add(.invalidValue, pointer); return nil }
        guard (0...6).contains(digits) else { add(.limitExceeded, pointer); return nil }
        return Int(digits)
    }

    /// `list-count` and `list-includes`: a source and a path, and for `includes` the value to look for (`sh.list-read@1`).
    private mutating func listRead(_ json: JSONValue, _ pointer: String, depth: Int, includes: Bool) -> ServerUIOperand? {
        needs.insert("list-read")
        guard let object = fields(json, pointer, includes ? ["type", "from", "value"] : ["type", "from"]) else { return nil }
        if flow { add(.invalidCombination, pointer) }
        guard let from = fields(object["from"] ?? .null, pointer + "/from", ["type", "sourceId", "path"]) else { return nil }
        if from["type"] != .string("source") { add(.unknownVariant, pointer + "/from/type") }
        guard let (sourceId, path) = source(from, pointer + "/from") else { return nil }
        references.append(.init(sourceId: sourceId, path: path, pointer: pointer, kind: nil, access: .list))
        guard includes else { return .listCount(sourceId: sourceId, path: path) }
        guard let value = operand(object["value"] ?? .null, pointer + "/value", depth: depth + 1) else { return nil }
        if Self.kind(value) == .structure { add(.bindingType, pointer + "/value") }
        return .listIncludes(sourceId: sourceId, path: path, value: value)
    }

    /// `count`: one to ``ServerUICountEntry/maximumEntries`` entries, each a condition and an optional list of people (`sh.count@1`).
    ///
    /// Each test is a condition of a rule's case, so it has its own 32 nodes and 6 levels inside the expression's 64 nodes. Every entry is
    /// walked, so each problem is reported where it stands; the count is built only when every entry is.
    private mutating func count(_ json: JSONValue, _ pointer: String, depth: Int) -> ServerUIOperand? {
        needs.insert("count")
        guard let object = fields(json, pointer, ["type", "of"]) else { return nil }
        // The tests read the document's sources, which a flow does not have: its reads are its own.
        if flow { add(.invalidCombination, pointer) }
        guard case .array(let items)? = object["of"] else { add(.invalidValue, pointer + "/of"); return nil }
        let allowed = 1...ServerUICountEntry.maximumEntries
        if !allowed.contains(items.count) { add(.limitExceeded, pointer + "/of") }
        let outer = conditionBudget
        defer { conditionBudget = outer }
        var entries: [ServerUICountEntry] = []
        for (index, item) in items.enumerated() {
            let at = pointer + "/of/\(index)"
            let shaped = fields(item, at, ["test"], ["viewer"]) != nil
            guard case .object(let raw) = item else { continue }
            conditionBudget = Self.maximumConditionNodes
            let test = raw["test"].flatMap { predicate($0, at + "/test", depth: depth + 1, conditionDepth: 1) }
            let filter = raw["viewer"].map { personFilter($0, at + "/viewer") }
            if shaped, let test, filter != .some(nil) { entries.append(.init(test: test, personEntityIds: filter ?? nil)) }
        }
        guard entries.count == items.count, allowed.contains(items.count) else { return nil }
        return .count(entries)
    }

    /// A count entry's viewer filter: `personEntityIds`, one to 32 `person.<name>` ids.
    private mutating func personFilter(_ json: JSONValue, _ pointer: String) -> [String]? {
        guard let object = fields(json, pointer, ["personEntityIds"]) else { return nil }
        guard case .array(let items)? = object["personEntityIds"] else { add(.invalidValue, pointer + "/personEntityIds"); return nil }
        if items.isEmpty || items.count > ServerUICountEntry.maximumEntries { add(.limitExceeded, pointer + "/personEntityIds"); return nil }
        var ids: [String] = []
        for (slot, item) in items.enumerated() {
            guard case .string(let id) = item, ServerUICompositionShape.matches(id, "^person\\.[a-z0-9_]+$") else {
                add(.invalidValue, pointer + "/personEntityIds/\(slot)")
                continue
            }
            ids.append(id)
        }
        return ids.count == items.count ? ids : nil
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

    private mutating func choose(_ json: JSONValue, _ pointer: String, depth: Int) -> ServerUIOperand? {
        needs.insert("rules")
        guard let object = fields(json, pointer, ["type", "cases", "otherwise"]) else { return nil }
        guard case .array(let items)? = object["cases"] else { add(.invalidValue, pointer + "/cases"); return nil }
        if items.isEmpty || items.count > Self.maximumRuleCases { add(.limitExceeded, pointer + "/cases") }
        var cases: [ServerUIOperand.ChooseCase] = []
        for (index, item) in items.enumerated() {
            let at = pointer + "/cases/\(index)"
            guard let entry = fields(item, at, ["when", "then"]) else { continue }
            conditionBudget = Self.maximumConditionNodes
            let when = predicate(entry["when"] ?? .null, at + "/when", depth: depth + 1, conditionDepth: 1)
            let then = operand(entry["then"] ?? .null, at + "/then", depth: depth + 1)
            if let when, let then { cases.append(.init(when: when, then: then)) }
        }
        let otherwise = operand(object["otherwise"] ?? .null, pointer + "/otherwise", depth: depth + 1)
        // The branches of a rule give one kind: a mismatch is reported at the second branch that disagrees.
        // A flow is typed by ``ServerUIFlowCompiler``, which knows the shape of an `item` and a parameter, so it does not judge kinds here.
        let kinds = flow ? [] : cases.enumerated().map { (Self.kind($0.element.then), pointer + "/cases/\($0.offset)/then") }
            + [(otherwise.flatMap(Self.kind), pointer + "/otherwise")]
        if let first = kinds.first(where: { $0.0 != nil })?.0,
           let clash = kinds.first(where: { $0.0 != nil && $0.0 != first }) { add(.bindingType, clash.1) }
        guard let otherwise, cases.count == items.count, !cases.isEmpty, items.count <= Self.maximumRuleCases else { return nil }
        return .choose(cases: cases, otherwise: otherwise)
    }

    /// The kind an operand gives when it can be told without typing; `nil` when it cannot. Used for the rule and comparison checks.
    enum Kind { case string, number, boolean, structure }

    static func kind(_ operand: ServerUIOperand) -> Kind? {
        switch operand {
        case .literal(let value):
            switch value {
            case .string: .string
            case .number: .number
            case .bool: .boolean
            case .null: nil
            case .array, .object: .structure
            }
        case .read(_, _, let kind):
            switch kind {
            case .string, .entityID: .string
            case .number: .number
            case .boolean: .boolean
            }
        case .viewer(let field): field == .isAdmin ? .boolean : .string
        case .format, .clock, .rawState, .lastChanged: .string
        case .math, .date, .progress, .secondsBetween, .index, .listCount, .count: .number
        case .listIncludes: .boolean
        case .object, .list: .structure
        case .map(_, _, let otherwise), .choose(_, let otherwise): kind(otherwise)
        case .control, .item, .param: nil
        }
    }

    /// A literal JSON value: bounded text, finite numbers, shallow nesting.
    private mutating func literal(_ value: JSONValue, _ pointer: String, depth: Int) -> Bool {
        switch value {
        case .string(let text):
            if text.utf16.count > 2_000 { add(.limitExceeded, pointer); return false }
        case .number(let number):
            if !number.isFinite { add(.invalidValue, pointer); return false }
        case .bool: break
        case .null:
            if evaluationOnly { return true }
            add(.invalidValue, pointer)
            return false
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

    private mutating func predicate(_ json: JSONValue, _ pointer: String, depth: Int, conditionDepth: Int) -> ServerUIPredicate? {
        guard depth <= Self.maximumDepth, budget > 0 else { add(.limitExceeded, pointer); return nil }
        budget -= 1
        if let remaining = conditionBudget {
            guard conditionDepth <= Self.maximumConditionDepth, remaining > 0 else { add(.limitExceeded, pointer); return nil }
            conditionBudget = remaining - 1
        }
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
            let parts = items.enumerated().compactMap {
                predicate($0.element, pointer + "/of/\($0.offset)", depth: depth + 1, conditionDepth: conditionDepth + 1)
            }
            guard parts.count == items.count, !parts.isEmpty, items.count <= 16 else { return nil }
            return type == "all" ? .all(parts) : .any(parts)
        case "not":
            guard let object = fields(json, pointer, ["type", "of"]),
                  let part = predicate(object["of"] ?? .null, pointer + "/of", depth: depth + 1, conditionDepth: conditionDepth + 1)
            else { return nil }
            return .not(part)
        case "compare":
            needs.insert("conditions")
            guard let object = fields(json, pointer, ["type", "op", "left", "right"]) else { return nil }
            let op: ServerUIPredicate.CompareOp?
            if case .string(let raw)? = object["op"], let known = ServerUIPredicate.CompareOp(rawValue: raw) { op = known }
            else { add(.unknownVariant, pointer + "/op"); op = nil }
            let left = operand(object["left"] ?? .null, pointer + "/left", depth: depth + 1)
            let right = operand(object["right"] ?? .null, pointer + "/right", depth: depth + 1)
            guard let op, let left, let right else { return nil }
            // `above` and `below` take numbers; `before` and `after` take date text.
            let want: Kind? = op == .above || op == .below ? .number : op == .before || op == .after ? .string : nil
            let (a, b) = (Self.kind(left), Self.kind(right))
            if flow {
                // A flow is typed by ``ServerUIFlowCompiler``.
            } else if let want, (a != nil && a != want) || (b != nil && b != want) {
                add(.bindingType, pointer + (a != nil && a != want ? "/left" : "/right"))
            } else if want == nil, let a, let b, a != b, a != .structure, b != .structure {
                add(.bindingType, pointer + "/right")
            }
            return .compare(op, left: left, right: right)
        case "in":
            needs.insert("conditions")
            guard let object = fields(json, pointer, ["type", "value", "in"]) else { return nil }
            let value = operand(object["value"] ?? .null, pointer + "/value", depth: depth + 1)
            guard case .array(let items)? = object["in"] else { add(.invalidValue, pointer + "/in"); return nil }
            if items.isEmpty || items.count > 16 { add(.limitExceeded, pointer + "/in") }
            let options = items.enumerated().compactMap { operand($0.element, pointer + "/in/\($0.offset)", depth: depth + 1) }
            guard let value, options.count == items.count, !options.isEmpty, items.count <= 16 else { return nil }
            return .in(value: value, options: options)
        case "exists":
            needs.insert("conditions")
            guard let object = fields(json, pointer, ["type", "value"]),
                  let value = operand(object["value"] ?? .null, pointer + "/value", depth: depth + 1) else { return nil }
            return .exists(value)
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
        -> (ServerUICompositionDocument.Confirmation, [String], ServerUIPredicate?) {
        guard case .object(let object) = json, case .string(let type)? = object["type"] else {
            add(.invalidValue, pointer)
            return (.policy, [], nil)
        }
        switch type {
        case "policy":
            _ = fields(json, pointer, ["type"])
            return (.policy, [], nil)
        case "additional":
            guard let object = fields(json, pointer, ["type", "style", "title", "confirmLabel", "cancelLabel", "destructive"],
                                      ["message", "exemptUserIds", "when"]) else { return (.policy, [], nil) }
            guard case .string(let rawStyle)? = object["style"],
                  let style = ServerUICompositionDocument.ConfirmationStyle(rawValue: rawStyle) else {
                add(.unknownVariant, pointer + "/style")
                return (.policy, [], nil)
            }
            let title = text(object["title"], pointer + "/title", maximum: 240, blank: false)
            let message = object["message"].flatMap { text($0, pointer + "/message", maximum: 2_000, blank: true) }
            let confirm = text(object["confirmLabel"], pointer + "/confirmLabel", maximum: 240, blank: false)
            if object["cancelLabel"] != .string("Cancel") { add(.unknownVariant, pointer + "/cancelLabel") }
            var destructive = false
            if case .bool(let flag)? = object["destructive"] { destructive = flag } else { add(.invalidValue, pointer + "/destructive") }
            let exempt = object["exemptUserIds"].flatMap { textList($0, pointer + "/exemptUserIds", maximum: 32) } ?? []
            // Ask only while a condition holds (`sh.confirm-when@1`): a rule's condition, with a rule's limits, inside the call's own budget.
            var when: ServerUIPredicate?
            if let raw = object["when"] {
                needs.insert("confirm-when")
                let outer = conditionBudget
                conditionBudget = Self.maximumConditionNodes
                when = predicate(raw, pointer + "/when", depth: 1, conditionDepth: 1)
                conditionBudget = outer
            }
            guard let title, let confirm else { return (.policy, [], nil) }
            return (.additional(style: style, title: title, message: message, confirmLabel: confirm,
                                cancelLabel: "Cancel", destructive: destructive), exempt, when)
        default:
            add(.unknownVariant, pointer + "/type")
            return (.policy, [], nil)
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

    private mutating func add(_ code: Issue.Code, _ pointer: String) {
        if evaluationOnly, code == .bindingType || code == .invalidCombination { return }
        issues.append(Issue(code, pointer))
    }

    private static func isIdentifier(_ value: JSONValue) -> Bool {
        switch value {
        case .string(let text): !text.isEmpty
        case .array(let items): !items.isEmpty && items.allSatisfy { if case .string(let text) = $0 { !text.isEmpty } else { false } }
        default: false
        }
    }
}
