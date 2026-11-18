import Foundation

// MARK: - Typing a flow

/// The typing rules of a Data Flow: each operand, condition and step has a rule from the shapes it is given to the shape it gives,
/// computed without running anything. The compiler uses them to check a flow against its authored shapes.
///
/// `null` is tolerated everywhere: every operand is total, so a missing value is `null` and no rule refuses a shape for being nullable. A
/// rule refuses only a kind that can never fit (a list where a number is needed) or a name that does not exist. The corpus pins the
/// compiler's first issue for each mistake, so the pointers and codes here follow the Studio's rules one for one.
public struct ServerUIFlowTyping {
    typealias Issue = ServerUICompositionError
    typealias Shape = ServerUIFlowShape

    /// What walking the operands and steps of one flow found. Pointers are the ones the document uses.
    public struct Facts {
        public var issues: [ServerUICompositionError] = []
        /// Every `read` operand, for the compiler's source checks.
        var reads: [(sourceId: String, path: [String], kind: ServerUICompositionDocument.ScalarKind, pointer: String)] = []
        /// Every `param` operand, for the acyclic check and the reference check.
        var parameterReferences: [(name: String, pointer: String)] = []
        /// Whether an `item`, `param`, `clock` or `date` operand appears: the flow then needs `sh.pipeline-operands@1`.
        var needsOperands = false
        /// Whether a `choose` appears: the flow then needs `sh.rules@1`.
        var usesRules = false
        /// Whether a step, a date style or a `date` operation of `sh.flow-extras@1` appears: the flow then needs it.
        var flowExtras = false
        /// Whether an `index` operand appears: the flow then needs `sh.repeat@1`.
        var usesRepeat = false
        /// The edge-logic ids (without `sh.` and `@1`) a duration format, a truncation or a `seconds-between` needs: `duration-format`, `math-truncate`, `countdown`.
        var edge: Set<String> = []
        /// Creates empty facts.
        public init() {}
    }

    /// Where an operand stands: what it may read and what `item` means there.
    struct Scope {
        /// The shape of `item`; absent outside a step and a row.
        var item: Shape?
        /// The declared parameters and their kinds.
        var parameters: [String: ServerUICompositionDocument.ScalarKind]
        /// A `read` of another source: parameters only.
        var allowsRead: Bool
        /// A `viewer` operand: parameters and the request only.
        var allowsViewer: Bool
    }

    /// The nodes left in one operand tree.
    struct Budget { var nodes = ServerUIFlow.Limits.operandNodes }

    /// The shape a parameter of the given kind has.
    static func shape(of kind: ServerUICompositionDocument.ScalarKind) -> Shape {
        switch kind {
        case .string: .text
        case .number: .float
        case .boolean: .boolean
        case .entityID: .text(.entityId)
        }
    }

    private static let scalarKinds: [Shape.Kind] = [.boolean, .number, .string]
    /// The non-null kinds a shape can take; `any` is all of them.
    private static func kinds(_ shape: Shape) -> Set<Shape.Kind> { shape.withoutNull.kinds }

    private static func report(_ facts: inout Facts, _ code: Issue.Code, _ at: String) { facts.issues.append(Issue(code, at)) }

    /// Requires a shape to be able to take one of `allowed`; `never` (no value was ever seen) fits anything.
    private static func expect(_ facts: inout Facts, _ shape: Shape, _ allowed: [Shape.Kind], _ at: String, code: Issue.Code = .bindingType) {
        let have = kinds(shape)
        if !have.isEmpty, !allowed.contains(where: have.contains) { report(&facts, code, at) }
    }

    /// Two shapes can be compared when they can take a scalar kind in common.
    private static func comparable(_ a: Shape, _ b: Shape) -> Bool {
        let left = kinds(a), right = kinds(b)
        if left.isEmpty || right.isEmpty { return true }
        return scalarKinds.contains { left.contains($0) && right.contains($0) }
    }

    private static func join(_ base: String, _ parts: Any...) -> String {
        parts.reduce(base) { pointer, part in
            if let name = part as? String { ServerUICompositionJSON.pointer(pointer, name) } else { pointer + "/\(part)" }
        }
    }

    /// A path segment is `[A-Za-z0-9_-]`, never all digits, never a reserved name: a list cannot be indexed.
    static func checkSegments(_ path: [String], at: String, _ facts: inout Facts) {
        for (index, segment) in path.enumerated() {
            if segment.utf16.count > 64 || !ServerUICompositionShape.matches(segment, "^[A-Za-z0-9_-]{1,64}$") || segment.allSatisfy(\.isASCIINumber)
                || ServerUICompositionJSON.reserved.contains(segment) {
                report(&facts, .invalidReference, join(at, index))
            }
        }
    }

    // MARK: Operands

    /// Types one operand. Issues, reads and parameter references go to `facts`; the result is `any` where the operand is wrong.
    static func type(_ operand: ServerUIOperand, _ scope: Scope, at: String, _ facts: inout Facts, budget: inout Budget, depth: Int = 1) -> Shape {
        if depth > ServerUIExpressionParser.maximumDepth || budget.nodes <= 0 { report(&facts, .limitExceeded, at); return .any }
        budget.nodes -= 1
        func sub(_ child: ServerUIOperand, _ parts: Any..., facts: inout Facts, budget: inout Budget) -> Shape {
            type(child, scope, at: parts.reduce(at) { join($0, $1) }, &facts, budget: &budget, depth: depth + 1)
        }
        switch operand {
        case .literal(let value):
            if !literalFits(value, level: 1) { report(&facts, .limitExceeded, join(at, "value")) }
            return inferLiteral(value)
        case .read(let sourceId, let path, let kind):
            if !scope.allowsRead { report(&facts, .invalidCombination, at) }
            checkSegments(path, at: join(at, "from", "path"), &facts)
            facts.reads.append((sourceId, path, kind, at))
            return shape(of: kind).orNull
        case .viewer(let field):
            if !scope.allowsViewer { report(&facts, .invalidCombination, at) }
            return field == .isAdmin ? Shape.boolean.orNull : (field == .personEntityId ? Shape.text(.entityId) : Shape.text).orNull
        case .item(let path):
            facts.needsOperands = true
            guard let item = scope.item else { report(&facts, .invalidCombination, at); return .any }
            checkSegments(path, at: join(at, "path"), &facts)
            guard let found = item.shape(at: path) else { report(&facts, .invalidReference, join(at, "path")); return .any }
            return found
        case .param(let name):
            facts.needsOperands = true
            facts.parameterReferences.append((name, join(at, "name")))
            return scope.parameters[name].map { shape(of: $0).orNull } ?? .any
        case .clock(let part):
            facts.needsOperands = true
            // A flow runs once on the minute clock it is given: there is no second clock for it (`sh.countdown@1`).
            if part == .nowSecond { report(&facts, .invalidCombination, at) }
            return .text(part == .today ? .date : .dateTime)
        case .index:
            // The position of the item a step looks at (`sh.repeat@1`); a parameter or the request has no item.
            facts.usesRepeat = true
            if scope.item == nil { report(&facts, .invalidCombination, at) }
            return .integer
        case .progress(let from, let to):
            facts.needsOperands = true
            facts.flowExtras = true
            let start = sub(from, "from", facts: &facts, budget: &budget), end = sub(to, "to", facts: &facts, budget: &budget)
            expect(&facts, start, [.string], join(at, "from"))
            expect(&facts, end, [.string], join(at, "to"))
            // A fraction of the span, `null` when either moment or the clock is not a date.
            return Shape.float.orNull
        case .date(let from, let to):
            facts.needsOperands = true
            let start = sub(from, "from", facts: &facts, budget: &budget), end = sub(to, "to", facts: &facts, budget: &budget)
            expect(&facts, start, [.string], join(at, "from"))
            expect(&facts, end, [.string], join(at, "to"))
            let dated: (Shape) -> Bool = {
                guard !$0.isNullable, case .string(let format, _) = $0 else { return false }
                return format == .date || format == .dateTime
            }
            return dated(start) && dated(end) ? .integer : Shape.integer.orNull
        case .secondsBetween(let from, let to):
            // Whole seconds (`sh.countdown@1`): typed like the days between two dates.
            facts.needsOperands = true
            facts.edge.insert("countdown")
            let start = sub(from, "from", facts: &facts, budget: &budget), end = sub(to, "to", facts: &facts, budget: &budget)
            expect(&facts, start, [.string], join(at, "from"))
            expect(&facts, end, [.string], join(at, "to"))
            let dated: (Shape) -> Bool = {
                guard !$0.isNullable, case .string(let format, _) = $0 else { return false }
                return format == .date || format == .dateTime
            }
            return dated(start) && dated(end) ? .integer : Shape.integer.orNull
        case .format(let pattern, let args, let formats):
            if args.count > 16 { report(&facts, .limitExceeded, join(at, "args")) }
            var anyNull = false
            var shapes: [String: Shape] = [:]
            for name in args.keys.sorted() {
                if !ServerUICompositionShape.matches(name, "^[A-Za-z_][A-Za-z0-9_]{0,31}$") { report(&facts, .invalidValue, join(at, "args", name)) }
                let shape = sub(args[name]!, "args", name, facts: &facts, budget: &budget)
                expect(&facts, shape, scalarKinds, join(at, "args", name))
                anyNull = anyNull || shape.isNullable
                shapes[name] = shape
            }
            var rest = Substring(pattern)
            while let open = rest.firstIndex(of: "{") {
                guard let close = rest[open...].firstIndex(of: "}") else { report(&facts, .invalidValue, join(at, "pattern")); break }
                if args[String(rest[rest.index(after: open)..<close])] == nil { report(&facts, .invalidReference, join(at, "pattern")) }
                rest = rest[rest.index(after: close)...]
            }
            if pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { report(&facts, .invalidValue, join(at, "pattern")) }
            for name in formats.keys.sorted() {
                let where_ = join(at, "formats", name)
                guard let held = shapes[name] else { report(&facts, .invalidReference, where_); continue }
                switch formats[name]! {
                case .text:
                    facts.needsOperands = true
                    expect(&facts, held, [.string], where_)
                case .duration(let format):
                    facts.edge.insert("duration-format")
                    if format.unit != nil, format.style != .compact { report(&facts, .invalidCombination, join(where_, "duration", "unit")) }
                    expect(&facts, held, [.number], where_)
                case .date(let style):
                    // A date style draws a date or a date and time, which is text; `hour` and `weekday` are `sh.flow-extras@1`'s.
                    facts.needsOperands = true
                    if style.needsFlowExtras { facts.flowExtras = true }
                    expect(&facts, held, [.string], where_)
                case .number(let format):
                    if format.declaresMinimum {
                        facts.needsOperands = true
                        if format.minimumFractionDigits > format.maximumFractionDigits {
                            report(&facts, .invalidCombination, join(where_, "number", "minimumFractionDigits"))
                        }
                    }
                    expect(&facts, held, [.number], where_)
                }
            }
            return anyNull ? Shape.text.orNull : .text
        case .map(let of, let cases, let otherwise):
            let subject = sub(of, "of", facts: &facts, budget: &budget)
            var result = sub(otherwise, "otherwise", facts: &facts, budget: &budget)
            if cases.isEmpty || cases.count > 32 { report(&facts, .limitExceeded, join(at, "cases")) }
            for (index, entry) in cases.enumerated() {
                result = result.merged(with: sub(entry.then, "cases", index, "then", facts: &facts, budget: &budget))
            }
            return subject.isNullable ? result.orNull : result
        case .math(let op, let args):
            if !op.arity.contains(args.count) { report(&facts, .invalidCombination, join(at, "args")) }
            if op == .truncate { facts.edge.insert("math-truncate") }
            var anyNull = [ServerUIOperand.MathOp.divide, .scale, .clamp, .round, .truncate].contains(op)
            for (index, arg) in args.enumerated() {
                let shape = sub(arg, "args", index, facts: &facts, budget: &budget)
                expect(&facts, shape, [.number], join(at, "args", index))
                anyNull = anyNull || shape.isNullable
            }
            return anyNull ? Shape.float.orNull : .float
        case .object(let fields):
            if fields.count > ServerUIFlow.Limits.mapFields * 2 { report(&facts, .limitExceeded, join(at, "fields")) }
            var shapes: [String: Shape] = [:]
            for name in fields.keys.sorted() {
                if !ServerUICompositionShape.matches(name, "^[A-Za-z_][A-Za-z0-9_]{0,63}$") { report(&facts, .invalidValue, join(at, "fields", name)) }
                shapes[name] = sub(fields[name]!, "fields", name, facts: &facts, budget: &budget)
            }
            return .record(shapes)
        case .control, .rawState, .lastChanged, .listCount, .listIncludes, .count:
            report(&facts, .invalidCombination, at)
            return .any
        case .choose(let cases, let otherwise):
            facts.usesRules = true
            if cases.isEmpty || cases.count > ServerUIExpressionParser.maximumRuleCases { report(&facts, .limitExceeded, join(at, "cases")) }
            var result = sub(otherwise, "otherwise", facts: &facts, budget: &budget)
            var branches: [(Shape, String)] = []
            for (index, entry) in cases.enumerated() {
                var conditions = Counter()
                typeWhere(entry.when, scope, at: join(at, "cases", index, "when"), &facts, counter: &conditions)
                branches.append((sub(entry.then, "cases", index, "then", facts: &facts, budget: &budget), join(at, "cases", index, "then")))
            }
            // The branches give one kind: a branch with no kind in common with the first reports at itself.
            let first = branches.first?.0 ?? result
            for (shape, pointer) in branches where !comparable(first, shape) { report(&facts, .bindingType, pointer); break }
            if !comparable(first, result) { report(&facts, .bindingType, join(at, "otherwise")) }
            for (shape, _) in branches { result = result.merged(with: shape) }
            return result
        case .list(let items):
            if items.count > 64 { report(&facts, .limitExceeded, join(at, "items")) }
            var result = Shape.never
            for (index, item) in items.enumerated() { result = result.merged(with: sub(item, "items", index, facts: &facts, budget: &budget)) }
            return .array(result)
        }
    }

    private static func literalFits(_ value: JSONValue, level: Int) -> Bool {
        switch value {
        case .string(let text): text.utf16.count <= 2_000
        case .object(let fields): level <= 4 && fields.count <= 64 && fields.values.allSatisfy { literalFits($0, level: level + 1) }
        case .array(let items): level <= 4 && items.count <= 64 && items.allSatisfy { literalFits($0, level: level + 1) }
        default: true
        }
    }

    private static func inferLiteral(_ value: JSONValue) -> Shape {
        switch value {
        case .null: .null
        case .bool: .boolean
        case .number(let number): .number(integer: number.rounded() == number)
        case .string: .text
        case .array(let items): .array(items.reduce(.never) { $0.merged(with: inferLiteral($1)) })
        case .object(let fields): .record(fields.mapValues(inferLiteral))
        }
    }

    // MARK: Conditions

    /// The nodes left in one condition.
    struct Counter { var nodes = ServerUIFlow.Limits.whereNodes }

    /// Types a condition. Operands inside it are checked against `scope`.
    static func typeWhere(_ condition: ServerUIPredicate, _ scope: Scope, at: String, _ facts: inout Facts, counter: inout Counter, depth: Int = 1) {
        if counter.nodes <= 0 || depth > ServerUIExpressionParser.maximumConditionDepth { report(&facts, .limitExceeded, at); return }
        counter.nodes -= 1
        func operand(_ value: ServerUIOperand, _ parts: Any..., facts: inout Facts) -> Shape {
            var budget = Budget()
            return type(value, scope, at: parts.reduce(at) { join($0, $1) }, &facts, budget: &budget)
        }
        switch condition {
        case .all(let parts), .any(let parts):
            for (index, part) in parts.enumerated() { typeWhere(part, scope, at: join(at, "of", index), &facts, counter: &counter, depth: depth + 1) }
        case .not(let part): typeWhere(part, scope, at: join(at, "of"), &facts, counter: &counter, depth: depth + 1)
        // The document leaves read a source or the signed-in person by name; a flow reads through a parameter's `read` and `viewer` instead.
        case .state, .numeric, .viewer, .viewerPerson: report(&facts, .invalidCombination, at)
        case .exists(let value): _ = operand(value, "value", facts: &facts)
        case .in(let value, let options):
            let subject = operand(value, "value", facts: &facts)
            for (index, option) in options.enumerated() {
                var budget = Budget()
                let shape = type(option, scope, at: join(at, "in", index), &facts, budget: &budget)
                if !comparable(subject, shape) { report(&facts, .bindingType, join(at, "in", index)) }
            }
        case .compare(let op, let leftOperand, let rightOperand):
            let left = operand(leftOperand, "left", facts: &facts), right = operand(rightOperand, "right", facts: &facts)
            switch op {
            case .eq, .ne: if !comparable(left, right) { report(&facts, .bindingType, join(at, "right")) }
            case .above, .below:
                expect(&facts, left, [.number], join(at, "left"))
                expect(&facts, right, [.number], join(at, "right"))
            case .before, .after:
                expect(&facts, left, [.string], join(at, "left"))
                expect(&facts, right, [.string], join(at, "right"))
            }
        }
    }

    // MARK: Steps

    /// The shape a step gives when it receives `input`. A step that cannot apply to the shape reports `binding_type` at its `op`; a name that
    /// does not exist reports `invalid_reference` at the name; the result is then `any`, so one mistake reports once.
    static func type(_ step: ServerUIFlow.Step, input: Shape, parameters: [String: ServerUICompositionDocument.ScalarKind],
                     at: String, _ facts: inout Facts) -> Shape {
        func scope(_ item: Shape?) -> Scope { Scope(item: item, parameters: parameters, allowsRead: false, allowsViewer: false) }
        func list(_ facts: inout Facts) -> Shape? {
            let element = input.element
            if element == nil { report(&facts, .bindingType, join(at, "op")) }
            return element
        }
        func operand(_ value: ServerUIOperand, _ item: Shape?, _ parts: Any..., facts: inout Facts) -> Shape {
            var budget = Budget()
            return type(value, scope(item), at: parts.reduce(at) { join($0, $1) }, &facts, budget: &budget)
        }
        switch step.operation {
        case .get(let path):
            guard input.hasObject else { report(&facts, .bindingType, join(at, "op")); return .any }
            guard let found = input.shape(at: path) else { report(&facts, .invalidReference, join(at, "path")); return .any }
            checkSegments(path, at: join(at, "path"), &facts)
            return found
        case .selectKey(let keyOperand):
            let key = operand(keyOperand, nil, "key", facts: &facts)
            expect(&facts, key, [.string], join(at, "key"))
            let holder = input.withoutNull
            guard case .object(let fields) = holder else {
                if holder != .any { report(&facts, .bindingType, join(at, "op")) }
                return .any
            }
            if case .literal(.string(let name)) = keyOperand {
                guard let found = holder.field(name) else { report(&facts, .invalidReference, join(at, "key", "value")); return .any }
                return found
            }
            var all = Shape.never
            for field in fields.values { all = all.merged(with: field.isOptional ? field.shape.orNull : field.shape) }
            return all == .never ? .any : all.orNull
        case .filter(let condition):
            let element = list(&facts)
            var counter = Counter()
            typeWhere(condition, scope(element ?? .any), at: join(at, "where"), &facts, counter: &counter)
            return element == nil ? .any : input
        case .sort(let keys):
            let element = list(&facts)
            for (index, by) in keys.enumerated() {
                let shape = operand(by.value, element ?? .any, "by", index, "value", facts: &facts)
                expect(&facts, shape, by.kind == .number ? [.number] : [.string], join(at, "by", index, "value"))
            }
            return element == nil ? .any : input
        case .limit: return list(&facts) == nil ? .any : input
        case .map(let fields):
            if fields.isEmpty || fields.count > ServerUIFlow.Limits.mapFields { report(&facts, .limitExceeded, join(at, "fields")) }
            let many = input.withoutNull.kinds.contains(.array) || input == .any
            let single = !many && input.hasObject
            if !many, !single { report(&facts, .bindingType, join(at, "op")); return .any }
            let item = many ? input.element : input.withoutNull
            var shapes: [String: Shape] = [:]
            for name in fields.keys.sorted() {
                if !ServerUICompositionShape.matches(name, "^[A-Za-z_][A-Za-z0-9_]{0,63}$") { report(&facts, .invalidValue, join(at, "fields", name)) }
                shapes[name] = operand(fields[name]!, item, "fields", name, facts: &facts)
            }
            let built = Shape.record(shapes)
            return many ? .array(built) : built.orNull
        case .group(let by):
            let element = list(&facts)
            let key = operand(by, element ?? .any, "by", facts: &facts)
            expect(&facts, key, Self.scalarKinds, join(at, "by"))
            guard let element else { return .any }
            var keyShape = key.withoutNull
            if case .string = keyShape { keyShape = .text }
            return .array(.record(["key": keyShape.orNull, "count": .integer, "items": .array(element)]))
        case .count: return list(&facts) == nil ? .any : .integer
        case .sum(let value):
            let element = list(&facts)
            expect(&facts, operand(value, element ?? .any, "value", facts: &facts), [.number], join(at, "value"))
            return element == nil ? .any : .float
        case .first:
            guard let element = list(&facts) else { return .any }
            return element.orNull
        case .flatten(let path):
            guard let element = list(&facts) else { return .any }
            guard let inner = element.shape(at: path) else { report(&facts, .invalidReference, join(at, "path")); return .any }
            checkSegments(path, at: join(at, "path"), &facts)
            guard let items = inner.element else { report(&facts, .bindingType, join(at, "path")); return .any }
            return .array(items)
        case .unique(let by):
            let element = list(&facts)
            expect(&facts, operand(by, element ?? .any, "by", facts: &facts), Self.scalarKinds, join(at, "by"))
            return element == nil ? .any : input
        case .min(let value), .max(let value):
            // Two list aggregates reduce a list to one number (`null` when it holds none), as `sum` does.
            facts.flowExtras = true
            let element = list(&facts)
            expect(&facts, operand(value, element ?? .any, "value", facts: &facts), [.number], join(at, "value"))
            return element == nil ? .any : Shape.float.orNull
        case .runningSum, .annotate:
            // They keep the list and write a field onto every object in it.
            facts.flowExtras = true
            guard let element = list(&facts) else { return .any }
            guard element.hasObject else { report(&facts, .bindingType, join(at, "op")); return .any }
            var written: [(String, Shape, String)] = []
            switch step.operation {
            case .runningSum(let value, let into, let propagates):
                expect(&facts, operand(value, element, "value", facts: &facts), [.number], join(at, "value"))
                written.append((into, propagates ? Shape.float.orNull : .float, join(at, "into")))
            case .annotate(let fields):
                let names = fields.keys.sorted()
                if names.isEmpty || names.count > ServerUIFlow.Limits.mapFields { report(&facts, .limitExceeded, join(at, "fields")) }
                for name in names {
                    let own = join(at, "fields", name)
                    expect(&facts, operand(fields[name]!.value, element, "fields", name, "value", facts: &facts), [.number], join(own, "value"))
                    written.append((name, Shape.float.orNull, own))
                }
            default: break
            }
            var updated: Shape? = element
            for (name, shape, where_) in written {
                if !ServerUICompositionShape.matches(name, "^[A-Za-z_][A-Za-z0-9_]{0,63}$") { report(&facts, .invalidValue, where_); continue }
                updated = updated?.settingField(at: [name], to: shape)
            }
            return updated.map { .array($0) } ?? .any
        case .default(let path, let value):
            let many = input.withoutNull.kinds.contains(.array)
            let item = many ? input.element : input.withoutNull
            guard let item, item.hasObject else { report(&facts, .bindingType, join(at, "op")); return .any }
            checkSegments(path, at: join(at, "path"), &facts)
            let fill = operand(value, item, "value", facts: &facts)
            let leaf: Shape
            if let current = item.shape(at: path) { leaf = current.withoutNull.merged(with: fill.withoutNull) } else { leaf = fill }
            guard let updated = item.settingField(at: path, to: leaf) else { report(&facts, .invalidReference, join(at, "path")); return .any }
            return many ? .array(updated) : updated
        }
    }

    /// The shape after every step, with each step's shape on the way (what the Studio's outline shows at "After Step 3").
    public static func types(_ steps: [ServerUIFlow.Step], input: ServerUIFlowShape, parameters: [String: ServerUICompositionDocument.ScalarKind],
                             at: String, _ facts: inout Facts) -> [ServerUIFlowShape] {
        var shapes: [Shape] = []
        var current = input
        for (index, step) in steps.enumerated() {
            current = type(step, input: current, parameters: parameters, at: join(at, "steps", index), &facts)
            shapes.append(current)
        }
        return shapes
    }
}

private extension Character {
    var isASCIINumber: Bool { isASCII && isNumber }
}
