import Foundation

// MARK: - Operands

/// A closed, pure expression an authored document uses wherever a value is needed: a text, a service-call field, a bound
/// control's value. There is no template language and no client-side Jinja; the whole grammar is the cases below.
///
/// Evaluation is total (see ``ServerUIReadResult``) and reads only through ``ServerUIReading``, so the set of entities an
/// evaluation touches is the set ``sourceIds`` reports.
public indirect enum ServerUIOperand: Equatable, Sendable {
    /// A fixed JSON value.
    case literal(JSONValue)
    /// The value at `path` of a declared source, as one kind.
    case read(sourceId: String, path: [String], as: ServerUICompositionDocument.ScalarKind)
    /// The new value of the control that sent the action (valid only inside an action).
    case control
    /// A fact about the signed-in person.
    case viewer(ViewerField)
    /// A text with `{name}` holes filled from `args`.
    case format(pattern: String, args: [String: ServerUIOperand], formats: [String: ServerUINumberFormat])
    /// The first case whose `equals` matches the value of `of`, else `otherwise`.
    case map(of: ServerUIOperand, cases: [MapCase], otherwise: ServerUIOperand)
    /// Arithmetic over numbers.
    case math(MathOp, [ServerUIOperand])
    /// A JSON object of operands (service data).
    case object([String: ServerUIOperand])
    /// A JSON array of operands.
    case list([ServerUIOperand])

    /// A viewer fact.
    public enum ViewerField: String, Sendable, CaseIterable { case userId, isAdmin, personEntityId }

    /// One branch of a ``map(of:cases:otherwise:)``.
    public struct MapCase: Equatable, Sendable {
        public let equals: JSONValue
        public let then: ServerUIOperand
        init(equals: JSONValue, then: ServerUIOperand) {
            self.equals = equals
            self.then = then
        }
    }

    /// An arithmetic operation. `scale` takes `[value, fromMin, fromMax, toMin, toMax]`.
    public enum MathOp: String, Sendable, CaseIterable {
        case add, subtract, multiply, divide, min, max, round, clamp, scale

        /// The number of arguments the operation accepts.
        public var arity: ClosedRange<Int> {
            switch self {
            case .add, .multiply, .min, .max: 2...8
            case .subtract, .divide: 2...2
            case .round: 1...2
            case .clamp: 3...3
            case .scale: 5...5
            }
        }
    }

    /// The source ids this operand reads, computed from the tree (the compiler stores nothing per change).
    public var sourceIds: Set<String> {
        switch self {
        case .literal, .control, .viewer: []
        case .read(let id, _, _): [id]
        case .format(_, let args, _): args.values.reduce(into: Set<String>()) { $0.formUnion($1.sourceIds) }
        case .map(let of, let cases, let otherwise):
            cases.reduce(of.sourceIds.union(otherwise.sourceIds)) { $0.union($1.then.sourceIds) }
        case .math(_, let args), .list(let args): args.reduce(into: Set<String>()) { $0.formUnion($1.sourceIds) }
        case .object(let fields): fields.values.reduce(into: Set<String>()) { $0.formUnion($1.sourceIds) }
        }
    }

    /// Whether the operand depends on the signed-in person anywhere.
    public var readsViewer: Bool {
        switch self {
        case .viewer: true
        case .literal, .read, .control: false
        case .format(_, let args, _): args.values.contains { $0.readsViewer }
        case .map(let of, let cases, let otherwise): of.readsViewer || otherwise.readsViewer || cases.contains { $0.then.readsViewer }
        case .math(_, let args), .list(let args): args.contains { $0.readsViewer }
        case .object(let fields): fields.values.contains { $0.readsViewer }
        }
    }

    /// Whether the operand uses ``control`` anywhere.
    public var usesControl: Bool {
        switch self {
        case .control: true
        case .literal, .read, .viewer: false
        case .format(_, let args, _): args.values.contains { $0.usesControl }
        case .map(let of, let cases, let otherwise): of.usesControl || otherwise.usesControl || cases.contains { $0.then.usesControl }
        case .math(_, let args), .list(let args): args.contains { $0.usesControl }
        case .object(let fields): fields.values.contains { $0.usesControl }
        }
    }

    /// Evaluates against `environment`. Never throws; anything missing is ``ServerUIReadResult/unavailable``.
    public func evaluate(_ environment: some ServerUIReading) -> ServerUIReadResult {
        switch self {
        case .literal(let value): return .value(value)
        case .control: return environment.controlValue.map { .value($0) } ?? .unavailable
        case .viewer(let field):
            guard let viewer = environment.viewer else { return .loading }
            switch field {
            case .userId: return viewer.userId.map { .value(.string($0)) } ?? .unavailable
            case .isAdmin: return viewer.isAdmin.map { .value(.bool($0)) } ?? .unavailable
            case .personEntityId: return viewer.personEntityId.map { .value(.string($0)) } ?? .unavailable
            }
        case .read(let sourceId, let path, let kind):
            let result = environment.read(sourceId: sourceId, path: path)
            guard case .value(let value) = result else { return result }
            return Self.coerce(value, to: kind).map { .value($0) } ?? .unavailable
        case .format(let pattern, let args, let formats):
            var values: [String: ServerUIReadResult] = [:]
            for (name, operand) in args { values[name] = operand.evaluate(environment) }
            if let blocked = ServerUIReadResult.combine(Array(values.values)) { return blocked }
            var output = ""
            var rest = Substring(pattern)
            while let open = rest.firstIndex(of: "{") {
                output += rest[..<open]
                guard let close = rest[open...].firstIndex(of: "}") else { output += rest[open...]; rest = ""; break }
                let name = String(rest[rest.index(after: open)..<close])
                guard let value = values[name]?.json else { return .unavailable }
                output += Self.text(value, format: formats[name])
                rest = rest[rest.index(after: close)...]
            }
            output += rest
            return .value(.string(output))
        case .map(let of, let cases, let otherwise):
            let subject = of.evaluate(environment)
            guard case .value(let value) = subject else { return subject }
            for branch in cases where Self.matches(value, branch.equals) { return branch.then.evaluate(environment) }
            return otherwise.evaluate(environment)
        case .math(let op, let args):
            let evaluated = args.map { $0.evaluate(environment) }
            if let blocked = ServerUIReadResult.combine(evaluated) { return blocked }
            let numbers = evaluated.compactMap { $0.json?.finiteNumber }
            guard numbers.count == evaluated.count, op.arity.contains(numbers.count),
                  let result = Self.compute(op, numbers), result.isFinite else { return .unavailable }
            return .value(.number(result))
        case .object(let fields):
            var result: [String: JSONValue] = [:]
            var parts: [ServerUIReadResult] = []
            for (key, operand) in fields {
                let value = operand.evaluate(environment)
                parts.append(value)
                if let json = value.json { result[key] = json }
            }
            return ServerUIReadResult.combine(parts) ?? .value(.object(result))
        case .list(let items):
            let evaluated = items.map { $0.evaluate(environment) }
            return ServerUIReadResult.combine(evaluated) ?? .value(.array(evaluated.compactMap(\.json)))
        }
    }

    // MARK: - Helpers shared with predicates

    /// A scalar as the one kind a read asked for, or `nil` when it cannot be that kind. A numeric string is a number
    /// (a Home Assistant state is always text) and `"true"`/`"false"` are booleans.
    static func coerce(_ value: JSONValue, to kind: ServerUICompositionDocument.ScalarKind) -> JSONValue? {
        switch (kind, value) {
        case (.string, .string), (.entityID, .string), (.boolean, .bool): return value
        case (.number, .number(let number)): return number.isFinite ? value : nil
        case (.number, .string): return value.finiteNumber.map { .number($0) }
        case (.boolean, .string(let text)):
            if text == "true" { return .bool(true) }
            return text == "false" ? .bool(false) : nil
        default: return nil
        }
    }

    /// A scalar as text: strings as they are, whole numbers without a fraction, booleans as `true`/`false`.
    static func scalarText(_ value: JSONValue) -> String? {
        switch value {
        case .string(let text): text
        case .number(let number):
            number.rounded() == number && abs(number) < 1e15 ? String(Int64(number)) : String(number)
        case .bool(let flag): flag ? "true" : "false"
        default: nil
        }
    }

    static func matches(_ value: JSONValue, _ expected: JSONValue) -> Bool {
        if value == expected { return true }
        guard let left = scalarText(value), let right = scalarText(expected) else { return false }
        return left == right
    }

    private static func text(_ value: JSONValue, format: ServerUINumberFormat?) -> String {
        if let format, let number = value.finiteNumber { return format.text(number) }
        return scalarText(value) ?? ""
    }

    private static func compute(_ op: MathOp, _ n: [Double]) -> Double? {
        switch op {
        case .add: return n.reduce(0, +)
        case .multiply: return n.reduce(1, *)
        case .min: return n.min()
        case .max: return n.max()
        case .subtract: return n[0] - n[1]
        case .divide: return n[1] == 0 ? nil : n[0] / n[1]
        case .round:
            let places = n.count == 2 ? n[1] : 0
            guard places.rounded() == places, (0...6).contains(places) else { return nil }
            let factor = pow(10, places)
            return (n[0] * factor).rounded() / factor
        case .clamp: return n[1] <= n[2] ? Swift.min(Swift.max(n[0], n[1]), n[2]) : nil
        case .scale:
            guard n[1] != n[2] else { return nil }
            return n[3] + (n[0] - n[1]) / (n[2] - n[1]) * (n[4] - n[3])
        }
    }
}

// MARK: - Number format

/// How a number fills a `format` hole. Locale independent on purpose: authored copy is English and a published document must
/// read the same on every phone.
public struct ServerUINumberFormat: Equatable, Sendable {
    /// The most digits after the decimal point, 0 to 6. Trailing zeros are dropped, so 2.50 shows as 2.5.
    public let maximumFractionDigits: Int

    /// Creates a format; the digit count is clamped to 0...6.
    public init(maximumFractionDigits: Int) { self.maximumFractionDigits = max(0, min(6, maximumFractionDigits)) }

    /// `number` rounded to at most ``maximumFractionDigits`` digits.
    public func text(_ number: Double) -> String {
        var text = String(format: "%.\(maximumFractionDigits)f", number)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }
}
