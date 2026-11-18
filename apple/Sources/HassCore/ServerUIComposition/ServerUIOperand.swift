import Foundation

// MARK: - Operands

/// A closed, pure expression an authored document uses wherever a value is needed: a text, a service-call field, a bound
/// control's value. There is no template language and no client-side Jinja; the whole grammar is the cases below.
///
/// Evaluation is total (see ``ServerUIReadResult``) and reads only through ``ServerUIReading``, so the set of entities an
/// evaluation touches is the set ``sourceIds`` reports.
public indirect enum ServerUIOperand: Hashable, Sendable {
    /// A fixed JSON value.
    case literal(JSONValue)
    /// The value at `path` of a declared source, as one kind.
    case read(sourceId: String, path: [String], as: ServerUICompositionDocument.ScalarKind)
    /// The new value of the control that sent the action (valid only inside an action).
    case control
    /// A fact about the signed-in person.
    case viewer(ViewerField)
    /// A text with `{name}` holes filled from `args`; `formats` draws a hole as a number or a date (``ServerUIFormatSpec``).
    case format(pattern: String, args: [String: ServerUIOperand], formats: [String: ServerUIFormatSpec])
    /// The first case whose `equals` matches the value of `of`, else `otherwise`.
    case map(of: ServerUIOperand, cases: [MapCase], otherwise: ServerUIOperand)
    /// Arithmetic over numbers.
    case math(MathOp, [ServerUIOperand])
    /// A JSON object of operands (service data).
    case object([String: ServerUIOperand])
    /// A JSON array of operands.
    case list([ServerUIOperand])
    /// The value at `path` of the item a flow step is looking at (`sh.pipeline-operands@1`; only inside a flow).
    case item(path: [String])
    /// The evaluated value of a flow parameter (`sh.pipeline-operands@1`; only inside a flow).
    case param(name: String)
    /// Today's date or the wall time now, from the clock (`sh.pipeline-operands@1`).
    case clock(ClockPart)
    /// Whole calendar days from the date of `from` to the date of `to` (`sh.pipeline-operands@1`).
    case date(from: ServerUIOperand, to: ServerUIOperand)
    /// How far the clock is from the moment `from` to the moment `to`, from 0 to 1 (`sh.flow-extras@1`): `null` when either is not a date, the
    /// clock does not parse, or `to` is not after `from`.
    case progress(from: ServerUIOperand, to: ServerUIOperand)
    /// Whole seconds from the moment `from` to the moment `to`, signed (`sh.countdown@1`): `unavailable` when either is not a date or a date and time.
    case secondsBetween(from: ServerUIOperand, to: ServerUIOperand)
    /// The 0-based position of the item a flow step or a `repeat` cell is looking at (`sh.repeat@1`).
    case index
    /// The first case whose condition holds gives the value, else `otherwise` (`sh.rules@1`). An undecided case stops the rule:
    /// the operand is `loading` and the slot keeps what it showed (``ServerUIRule``).
    case choose(cases: [ChooseCase], otherwise: ServerUIOperand)
    /// The state text of an `ha-entity` source exactly as Home Assistant reports it, `unknown` and `unavailable` included (`sh.raw-state@1`).
    case rawState(sourceId: String)
    /// When the state of an `ha-entity` source last changed, as `YYYY-MM-DDTHH:MM:SS.sssZ` (`sh.entity-time@1`); `unavailable` while the entity is.
    case lastChanged(sourceId: String)
    /// How many items the list attribute `path` of an `ha-entity` source holds (`sh.list-read@1`).
    case listCount(sourceId: String, path: [String])
    /// Whether some scalar item of the list attribute `path` of an `ha-entity` source equals `value` (`sh.list-read@1`).
    case listIncludes(sourceId: String, path: [String], value: ServerUIOperand)

    /// A viewer fact.
    public enum ViewerField: String, Sendable, CaseIterable { case userId, isAdmin, personEntityId }

    /// One branch of a ``map(of:cases:otherwise:)``.
    public struct MapCase: Hashable, Sendable {
        public let equals: JSONValue
        public let then: ServerUIOperand
        init(equals: JSONValue, then: ServerUIOperand) {
            self.equals = equals
            self.then = then
        }
    }

    /// What the `clock` operand reads: today's date, the wall time now (published once a minute), or the wall time to the second
    /// (`sh.countdown@1`, published once a second, and only while something reads it).
    public enum ClockPart: String, Sendable, CaseIterable {
        case today, now
        case nowSecond = "now-second"
    }

    /// One branch of a ``choose(cases:otherwise:)``.
    public struct ChooseCase: Hashable, Sendable {
        public let when: ServerUIPredicate
        public let then: ServerUIOperand
        init(when: ServerUIPredicate, then: ServerUIOperand) {
            self.when = when
            self.then = then
        }
    }

    /// An arithmetic operation. `scale` takes `[value, fromMin, fromMax, toMin, toMax]`.
    public enum MathOp: String, Sendable, CaseIterable {
        case add, subtract, multiply, divide, min, max, round, clamp, scale
        /// Toward zero, to 0 to 6 places (`sh.math-truncate@1`).
        case truncate

        /// The number of arguments the operation accepts.
        public var arity: ClosedRange<Int> {
            switch self {
            case .add, .multiply, .min, .max: 2...8
            case .subtract, .divide: 2...2
            case .round, .truncate: 1...2
            case .clamp: 3...3
            case .scale: 5...5
            }
        }
    }

    /// The source ids this operand reads, computed from the tree (the compiler stores nothing per change).
    public var sourceIds: Set<String> {
        switch self {
        case .literal, .control, .viewer, .item, .index, .param, .clock: []
        case .read(let id, _, _), .rawState(let id), .lastChanged(let id), .listCount(let id, _): [id]
        case .listIncludes(let id, _, let value): value.sourceIds.union([id])
        case .date(let from, let to), .progress(let from, let to), .secondsBetween(let from, let to): from.sourceIds.union(to.sourceIds)
        case .choose(let cases, let otherwise):
            cases.reduce(otherwise.sourceIds) { $0.union($1.when.sourceIds).union($1.then.sourceIds) }
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
        case .literal, .read, .control, .item, .index, .param, .clock, .rawState, .lastChanged, .listCount: false
        case .listIncludes(_, _, let value): value.readsViewer
        case .date(let from, let to), .progress(let from, let to), .secondsBetween(let from, let to): from.readsViewer || to.readsViewer
        case .choose(let cases, let otherwise):
            otherwise.readsViewer || cases.contains { $0.when.readsViewer || $0.then.readsViewer }
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
        case .literal, .read, .viewer, .item, .index, .param, .clock, .rawState, .lastChanged, .listCount: false
        case .listIncludes(_, _, let value): value.usesControl
        case .date(let from, let to), .progress(let from, let to), .secondsBetween(let from, let to): from.usesControl || to.usesControl
        case .choose(let cases, let otherwise): otherwise.usesControl || cases.contains { $0.then.usesControl }
        case .format(_, let args, _): args.values.contains { $0.usesControl }
        case .map(let of, let cases, let otherwise): of.usesControl || otherwise.usesControl || cases.contains { $0.then.usesControl }
        case .math(_, let args), .list(let args): args.contains { $0.usesControl }
        case .object(let fields): fields.values.contains { $0.usesControl }
        }
    }

    /// Whether the operand reads the clock anywhere, so the app ticks it once a minute only while something does.
    public var readsClock: Bool {
        switch self {
        case .clock: true
        case .literal, .read, .control, .viewer, .item, .index, .param, .rawState, .lastChanged, .listCount: false
        case .listIncludes(_, _, let value): value.readsClock
        case .format(_, let args, let formats):
            formats.values.contains { if case .date(let style) = $0 { style.needsClock } else { false } }
                || args.values.contains { $0.readsClock }
        case .map(let of, let cases, let otherwise): of.readsClock || otherwise.readsClock || cases.contains { $0.then.readsClock }
        case .math(_, let args), .list(let args): args.contains { $0.readsClock }
        case .object(let fields): fields.values.contains { $0.readsClock }
        case .date(let from, let to), .secondsBetween(let from, let to): from.readsClock || to.readsClock
        case .progress: true
        case .choose(let cases, let otherwise):
            otherwise.readsClock || cases.contains { $0.when.readsClock || $0.then.readsClock }
        }
    }

    /// Evaluates against `environment`. Never throws; anything missing is ``ServerUIReadResult/unavailable``.
    ///
    /// In flow mode (``ServerUIReading/isFlow``) there is no `loading` or `unavailable`: a gap is `null`.
    public func evaluate(_ environment: some ServerUIReading) -> ServerUIReadResult {
        environment.spend()
        let result = outcome(environment)
        if environment.isFlow, result.json == nil { return .value(.null) }
        return result
    }

    private func outcome(_ environment: some ServerUIReading) -> ServerUIReadResult {
        switch self {
        case .literal(let value): return .value(value)
        case .rawState, .lastChanged, .listCount, .listIncludes: return evaluateEntityRead(environment)
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
        case .item(let path):
            guard let item = environment.item else { return .unavailable }
            return .value(Self.value(at: path, in: item))
        case .index:
            return environment.index.map { .value(.number(Double($0))) } ?? .unavailable
        case .param(let name):
            return environment.parameter(name).map { .value($0) } ?? .unavailable
        case .clock(let part):
            // `now-second` reads the second clock: a reader of it is what starts the app's 1 Hz tick.
            guard let clock = part == .nowSecond ? environment.secondClock : environment.clock,
                  let today = ServerUIDates.today(of: clock) else { return .unavailable }
            return .value(.string(part == .today ? today : clock.now))
        case .date(let from, let to):
            let start = from.evaluate(environment), end = to.evaluate(environment)
            if let blocked = ServerUIReadResult.combine([start, end]) { return blocked }
            guard case .string(let first)? = start.json, case .string(let second)? = end.json,
                  let days = ServerUIDates.daysBetween(first, second, utcOffsetMinutes: environment.clock?.utcOffsetMinutes ?? 0)
            else { return .unavailable }
            return .value(.number(Double(days)))
        case .secondsBetween(let from, let to):
            let start = from.evaluate(environment), end = to.evaluate(environment)
            if let blocked = ServerUIReadResult.combine([start, end]) { return blocked }
            guard case .string(let first)? = start.json, case .string(let second)? = end.json,
                  let seconds = ServerUIDates.secondsBetween(first, second, utcOffsetMinutes: environment.clock?.utcOffsetMinutes ?? 0)
            else { return .unavailable }
            return .value(.number(Double(seconds)))
        case .progress(let from, let to):
            let start = from.evaluate(environment), end = to.evaluate(environment)
            if let blocked = ServerUIReadResult.combine([start, end]) { return blocked }
            guard case .string(let first)? = start.json, case .string(let second)? = end.json, let clock = environment.clock,
                  let fraction = ServerUIDates.progress(from: first, to: second, clock: clock) else { return .unavailable }
            return .value(.number(fraction))
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
                guard let value = values[name]?.json, let plain = Self.scalarText(value) else { return .unavailable }
                switch formats[name] {
                case .date(let style)?:
                    // A date style draws a date or a date and time; any other value has no text, so the whole format is unavailable.
                    guard case .string(let text) = value,
                          let drawn = ServerUIDateFormat.text(style, of: text, clock: environment.clock, locale: environment.locale)
                    else { return .unavailable }
                    output += drawn
                case .number(let format)?:
                    output += value.finiteNumber.map(format.text) ?? plain
                case .text(let letterCase)?:
                    output += letterCase.apply(to: plain)
                case .duration(let format)?:
                    // A duration draws a number; anything else, or a number with no text, leaves the whole format without one.
                    guard let drawn = value.finiteNumber.flatMap(format.text) else { return .unavailable }
                    output += drawn
                case nil: output += plain
                }
                rest = rest[rest.index(after: close)...]
            }
            output += rest
            return .value(.string(output))
        case .map(let of, let cases, let otherwise):
            let subject = of.evaluate(environment)
            guard case .value(let value) = subject else { return subject }
            if value == .null { return .unavailable }
            for branch in cases where Self.matches(value, branch.equals) { return branch.then.evaluate(environment) }
            return otherwise.evaluate(environment)
        case .choose(let cases, let otherwise):
            // An undecided case stops the rule: nothing later may stand in for it, and the slot keeps what it showed.
            switch ServerUIRule.pick(count: cases.count, answer: { cases[$0].when.evaluate(environment) }) {
            case .stalled: return .loading
            case .otherwise: return otherwise.evaluate(environment)
            case .matched(let index): return cases[index].then.evaluate(environment)
            }
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
        case (.string, .string), (.boolean, .bool): return value
        case (.entityID, .string(let text)):
            return ServerUICompositionShape.matches(text, "^[a-z][a-z0-9_]*\\.[a-z0-9_]+$") ? value : nil
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

    /// The value at `path` of an object tree, or `null` when a segment is missing or not an object. An empty path is the value itself.
    static func value(at path: [String], in root: JSONValue) -> JSONValue {
        var current = root
        for segment in path {
            guard case .object(let fields) = current, let next = fields[segment] else { return .null }
            current = next
        }
        return current
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
        case .truncate:
            let places = n.count == 2 ? n[1] : 0
            guard places.rounded() == places, (0...6).contains(places) else { return nil }
            let factor = pow(10, places)
            // Toward zero; adding zero turns a result of -0 into 0.
            return (n[0] * factor).rounded(.towardZero) / factor + 0
        case .scale:
            guard n[1] != n[2] else { return nil }
            return n[3] + (n[0] - n[1]) / (n[2] - n[1]) * (n[4] - n[3])
        }
    }
}

// MARK: - Number format

/// How a number fills a `format` hole. Locale independent on purpose: authored copy is English and a published document must
/// read the same on every phone.
public struct ServerUINumberFormat: Hashable, Sendable {
    /// The most digits after the decimal point, 0 to 6. Trailing zeros are dropped down to ``minimumFractionDigits``, so 2.50 shows as 2.5.
    public let maximumFractionDigits: Int
    /// The fewest digits after the decimal point, 0 to ``maximumFractionDigits`` (`sh.pipeline-operands@1`): 1 keeps `72` as `72.0`.
    public let minimumFractionDigits: Int
    /// Whether the document wrote a minimum at all (even `0`), which is what needs `sh.pipeline-operands@1`. Not part of equality.
    public let declaresMinimum: Bool

    /// Creates a format; the maximum is clamped to 0...6 and the minimum to 0...maximum.
    public init(maximumFractionDigits: Int, minimumFractionDigits: Int? = nil) {
        let most = max(0, min(6, maximumFractionDigits))
        self.maximumFractionDigits = most
        self.minimumFractionDigits = max(0, min(most, minimumFractionDigits ?? 0))
        declaresMinimum = minimumFractionDigits != nil
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.maximumFractionDigits == rhs.maximumFractionDigits && lhs.minimumFractionDigits == rhs.minimumFractionDigits
    }

    /// `number` rounded to at most ``maximumFractionDigits`` digits (the exact binary value, an exact tie to the even digit, as C `printf`
    /// does), its trailing zeros trimmed down to ``minimumFractionDigits`` and a signed zero drawn without its sign.
    public func text(_ number: Double) -> String {
        var text = String(format: "%.\(maximumFractionDigits)f", number)
        if let dot = text.firstIndex(of: ".") {
            let whole = text[..<dot]
            var fraction = String(text[text.index(after: dot)...])
            while fraction.hasSuffix("0") { fraction.removeLast() }
            if fraction.count < minimumFractionDigits { fraction += String(repeating: "0", count: minimumFractionDigits - fraction.count) }
            text = fraction.isEmpty ? String(whole) : "\(whole).\(fraction)"
        }
        if text.hasPrefix("-"), text.dropFirst().allSatisfy({ $0 == "0" || $0 == "." }) { text.removeFirst() }
        return text
    }
}
