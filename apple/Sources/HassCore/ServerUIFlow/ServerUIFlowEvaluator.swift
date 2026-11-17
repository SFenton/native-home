import Foundation

// MARK: - What a run reads

/// What a flow reads besides its data: the clock, the signed-in person and the sources a parameter's `read` names.
public struct ServerUIFlowContext: Sendable {
    /// The clock `clock` and `date` operands and date styles use; `nil` makes them `null`.
    public var clock: ServerUIClock?
    /// The signed-in person.
    public var viewer: ServerUIViewer?
    /// The language and region date styles are drawn in.
    public var locale: Locale?
    /// The value at `path` of a declared source, as the app's operand evaluator reads it (a parameter's `read`); `nil` when it has none.
    public var read: @Sendable (_ sourceId: String, _ path: [String]) -> JSONValue?

    /// Creates a context.
    public init(clock: ServerUIClock? = nil, viewer: ServerUIViewer? = nil, locale: Locale? = nil,
                read: @escaping @Sendable (String, [String]) -> JSONValue? = { _, _ in nil }) {
        self.clock = clock
        self.viewer = viewer
        self.locale = locale
        self.read = read
    }
}

/// What a run gave.
public struct ServerUIFlowRun: Equatable, Sendable {
    /// One step's trace: how many items it left (`nil` when it holds one value).
    public struct Trace: Equatable, Sendable {
        /// The step's id.
        public let id: String
        /// The step's operation name.
        public let operation: String
        /// How many items the step left; `nil` when it holds one value.
        public let size: Int?
    }
    /// Whether the run finished or ran out of budget.
    public enum Status: Equatable, Sendable { case ok, overBudget }

    /// Whether the run finished.
    public let status: Status
    /// What the output asks for: rows as `{ id, title, subtitle?, value? }` objects, a record or one value. `null` over budget.
    public let output: JSONValue
    /// The final value of the steps.
    public let value: JSONValue
    /// Budget units spent.
    public let visits: Int
    /// The step that ran out of budget, if any.
    public let stepId: String?
    /// What each step left, in order.
    public let trace: [Trace]

    /// The records an output of kind `records` gave.
    public var records: [JSONValue] { output.array ?? [] }

    /// The rows an output of kind `rows` gave.
    public var rows: [ServerUIRowItem] {
        (output.array ?? []).compactMap { row in
            guard let id = row["id"]?.string, let title = row["title"]?.string else { return nil }
            return ServerUIRowItem(id: id, title: title, subtitle: row["subtitle"]?.string, value: row["value"]?.string)
        }
    }
}

// MARK: - The evaluator

/// The step evaluator of a Data Flow. It is pure and total: the same data, parameters and clock give the same answer in Swift and in
/// TypeScript (the shared corpus `contract/corpus/pipelines` pins it), nothing throws, and a step applied to the wrong kind of value gives
/// the empty result of its kind (`[]`, `0` or `null`) instead of failing. The one failure is running out of budget.
///
/// Budget: a run may spend ``budget`` units. A step costs one plus one per item it visits; every operand and condition node it evaluates
/// costs one (`all` and `any` evaluate every part, so the cost never depends on an earlier answer). A run over budget gives no data, and
/// the app keeps what it last had.
public enum ServerUIFlowEvaluator {
    /// The units one run may spend.
    public static let budget = 100_000

    /// The budget of one run.
    final class Meter {
        var spent = 0
        let limit: Int
        init(limit: Int) { self.limit = limit }
        var exceeded: Bool { spent > limit }
        func spend(_ count: Int = 1) { spent += count }
    }

    /// The names an operand can see: the item a step is looking at and the evaluated parameters.
    struct Environment: ServerUIReading {
        let context: ServerUIFlowContext
        let meter: Meter
        let parameters: Parameters
        var item: JSONValue?
        /// The 0-based position of ``item`` in the list a step is visiting (`index` operands, `sh.repeat@1`).
        var index: Int?

        var viewer: ServerUIViewer? { context.viewer }
        var clock: ServerUIClock? { context.clock }
        var locale: Locale? { context.locale }
        var isFlow: Bool { true }
        func read(sourceId: String, path: [String]) -> ServerUIReadResult { context.read(sourceId, path).map { .value($0) } ?? .unavailable }
        func viewerPersonState() -> ServerUIReadResult { .unavailable }
        func parameter(_ name: String) -> JSONValue? { parameters.value(name) }
        func spend() { meter.spend() }
        func with(item: JSONValue, index: Int = 0) -> Self { var copy = self; copy.item = item; copy.index = index; return copy }
    }

    /// The value of every declared parameter, evaluated in dependency order. A parameter that cannot be evaluated (a cycle the compiler
    /// refuses) is `null`.
    final class Parameters {
        private let declared: [String: ServerUIFlow.Parameter]
        private let context: ServerUIFlowContext
        private let meter: Meter
        private var values: [String: JSONValue] = [:]
        private var pending: Set<String> = []

        init(_ flow: ServerUIFlow, context: ServerUIFlowContext, meter: Meter) {
            declared = Dictionary(flow.parameters.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
            self.context = context
            self.meter = meter
            for parameter in flow.parameters { _ = value(parameter.name) }
        }

        func value(_ name: String) -> JSONValue? {
            if let held = values[name] { return held }
            guard let parameter = declared[name], !pending.contains(name) else { return .null }
            pending.insert(name)
            let environment = Environment(context: context, meter: meter, parameters: self, item: nil)
            let raw = ServerUIFlowEvaluator.json(parameter.value, environment)
            pending.remove(name)
            let value = Self.coerce(raw, parameter.kind)
            values[name] = value
            return value
        }

        /// A parameter's value as its declared kind: a Home Assistant state is text, so `"3"` reads as the number 3; anything else is `null`.
        private static func coerce(_ value: JSONValue, _ kind: ServerUICompositionDocument.ScalarKind) -> JSONValue {
            switch kind {
            case .string:
                if case .string = value { return value }
                return JSONValue.null
            case .number:
                if case .number(let number) = value, number.isFinite { return value }
                if value == JSONValue.null { return .null }
                return ServerUIOperand.coerce(value, to: .number) ?? .null
            case .boolean, .entityID:
                if value == JSONValue.null { return .null }
                return ServerUIOperand.coerce(value, to: kind) ?? .null
            }
        }
    }

    /// The value of an operand; `null` when it has none.
    static func json(_ operand: ServerUIOperand, _ environment: Environment) -> JSONValue {
        operand.evaluate(environment).json ?? .null
    }

    private static func isRecord(_ value: JSONValue) -> Bool { if case .object = value { true } else { false } }
    private static func list(_ value: JSONValue) -> [JSONValue] { value.array ?? [] }

    // MARK: Request

    /// The service call a `service-response` request makes: its domain, service, target and data with the parameters filled in. A target
    /// or data key whose operand is `null` is left out. `nil` for any other request, and when the run is over budget.
    public static func serviceCall(_ flow: ServerUIFlow, context: ServerUIFlowContext, budget: Int = budget)
        -> (domain: String, service: String, target: [String: JSONValue], data: [String: JSONValue])? {
        guard case .serviceResponse(let domain, let service, let target, let data, _, _) = flow.request else { return nil }
        let meter = Meter(limit: budget)
        let environment = Environment(context: context, meter: meter, parameters: Parameters(flow, context: context, meter: meter), item: nil)
        let present: ([String: ServerUIOperand]) -> [String: JSONValue] = { entries in
            var result: [String: JSONValue] = [:]
            for (key, operand) in entries { let value = json(operand, environment); if value != .null { result[key] = value } }
            return result
        }
        let targets = present(target ?? [:])
        var fields: [String: ServerUIOperand] = [:]
        if case .object(let items)? = data { fields = items }
        let sent = present(fields)
        return meter.exceeded ? nil : (domain, service, targets, sent)
    }

    // MARK: Steps

    private enum Key { case text(String), number(Double) }

    private static func sortKey(_ value: JSONValue, _ kind: ServerUIFlow.SortKey.Kind, _ context: ServerUIFlowContext) -> Key? {
        switch kind {
        case .text: if case .string(let text) = value { return .text(text) } else { return nil }
        case .number: if case .number(let number) = value { return .number(number) } else { return nil }
        case .date:
            guard case .string(let text) = value,
                  let time = ServerUIDates.wallTime(text, utcOffsetMinutes: context.clock?.utcOffsetMinutes ?? 0) else { return nil }
            return .number(Double(time.instant))
        }
    }

    private static func compareKeys(_ a: Key, _ b: Key) -> Int {
        switch (a, b) {
        case (.text(let x), .text(let y)): return ServerUIFlowText.compare(x, y)
        case (.number(let x), .number(let y)): return x < y ? -1 : x > y ? 1 : 0
        default: return 0
        }
    }

    private static func setDefault(_ item: JSONValue, _ path: ArraySlice<String>, _ fill: JSONValue) -> JSONValue {
        guard fill != .null, case .object(var fields) = item, let head = path.first else { return item }
        let rest = path.dropFirst()
        if !rest.isEmpty {
            guard let held = fields[head] else { return item }
            let inner = setDefault(held, rest, fill)
            if inner == held { return item }
            fields[head] = inner
            return .object(fields)
        }
        if let held = fields[head], held != .null { return item }
        fields[head] = fill
        return .object(fields)
    }

    /// Runs one step on a value.
    static func run(_ step: ServerUIFlow.Step, on value: JSONValue, _ environment: Environment) -> JSONValue {
        let meter = environment.meter, context = environment.context
        meter.spend()
        func each(_ items: [JSONValue]) { meter.spend(items.count) }
        switch step.operation {
        case .get(let path): return ServerUIOperand.value(at: path, in: value)
        case .selectKey(let operand):
            let key = json(operand, environment)
            if case .string(let name) = key, case .object(let fields) = value, let found = fields[name] { return found }
            return .null
        case .filter(let condition):
            let items = list(value)
            each(items)
            var kept: [JSONValue] = []
            for (at, item) in items.enumerated() {
                if meter.exceeded { break }
                if condition.evaluate(environment.with(item: item, index: at)) == .yes { kept.append(item) }
            }
            return .array(kept)
        case .sort(let keys):
            let items = list(value)
            each(items)
            var keyed: [(item: JSONValue, index: Int, keys: [Key?])] = []
            for (index, item) in items.enumerated() {
                if meter.exceeded { break }
                let own = environment.with(item: item, index: index)
                keyed.append((item, index, keys.map { sortKey(json($0.value, own), $0.kind, context) }))
            }
            keyed.sort { a, b in
                for (position, by) in keys.enumerated() {
                    let x = a.keys[position], y = b.keys[position]
                    guard let x, let y else {
                        if (x == nil) != (y == nil) { return x != nil }
                        continue
                    }
                    let difference = compareKeys(x, y)
                    if difference != 0 { return by.direction == .ascending ? difference < 0 : difference > 0 }
                }
                return a.index < b.index
            }
            return .array(keyed.map(\.item))
        case .limit(let count): return .array(Array(list(value).prefix(count)))
        case .map(let fields):
            func build(_ item: JSONValue, _ at: Int = 0) -> JSONValue {
                let own = environment.with(item: item, index: at)
                return .object(fields.mapValues { json($0, own) })
            }
            if case .array(let items) = value {
                each(items)
                var built: [JSONValue] = []
                for (at, item) in items.enumerated() { if meter.exceeded { break }; built.append(build(item, at)) }
                return .array(built)
            }
            return isRecord(value) ? build(value) : .null
        case .group(let by):
            let items = list(value)
            each(items)
            var order: [String] = []
            var groups: [String: (key: JSONValue, items: [JSONValue])] = [:]
            for (at, item) in items.enumerated() {
                if meter.exceeded { break }
                let key = json(by, environment.with(item: item, index: at)), slot = ServerUIFlowText.identity(key)
                if groups[slot] == nil {
                    order.append(slot)
                    switch key {
                    case .array, .object: groups[slot] = (.null, [])
                    default: groups[slot] = (key, [])
                    }
                }
                groups[slot]!.items.append(item)
            }
            return .array(order.map { slot in
                let group = groups[slot]!
                return .object(["key": group.key, "count": .number(Double(group.items.count)), "items": .array(group.items)])
            })
        case .count: return .number(Double(list(value).count))
        case .sum(let operand):
            let items = list(value)
            each(items)
            var total = 0.0
            for (at, item) in items.enumerated() {
                if meter.exceeded { break }
                if case .number(let part) = json(operand, environment.with(item: item, index: at)) { total += part }
            }
            return .number(total == 0 ? 0 : total)
        case .first: return list(value).first ?? .null
        case .flatten(let path):
            let items = list(value)
            each(items)
            return .array(items.flatMap { list(ServerUIOperand.value(at: path, in: $0)) })
        case .unique(let by):
            let items = list(value)
            each(items)
            var seen: Set<String> = []
            var kept: [JSONValue] = []
            for (at, item) in items.enumerated() {
                if meter.exceeded { break }
                if seen.insert(ServerUIFlowText.identity(json(by, environment.with(item: item, index: at)))).inserted { kept.append(item) }
            }
            return .array(kept)
        case .default(let path, let operand):
            func fill(_ item: JSONValue, _ at: Int = 0) -> JSONValue { setDefault(item, path[...], json(operand, environment.with(item: item, index: at))) }
            if case .array(let items) = value {
                each(items)
                var filled: [JSONValue] = []
                for (at, item) in items.enumerated() { if meter.exceeded { break }; filled.append(fill(item, at)) }
                return .array(filled)
            }
            return isRecord(value) ? fill(value) : value
        case .min(let operand), .max(let operand):
            let items = list(value)
            each(items)
            var parts: [JSONValue] = []
            for (at, item) in items.enumerated() {
                if meter.exceeded { break }
                parts.append(json(operand, environment.with(item: item, index: at)))
            }
            let kind: ServerUIFlow.Annotation.Aggregate
            if case .min = step.operation { kind = .min } else { kind = .max }
            return extreme(kind, parts).map { .number($0) } ?? .null
        case .runningSum(let operand, let into, let propagates):
            let items = list(value)
            each(items)
            // A total that has gone unknown stays unknown when `nullPropagates`; otherwise a part that is not a number adds nothing. An item
            // that is not an object passes through unchanged.
            var total: Double? = 0
            var scanned: [JSONValue] = []
            for (at, item) in items.enumerated() {
                if meter.exceeded { break }
                let part = json(operand, environment.with(item: item, index: at))
                var number: Double?
                if case .number(let held) = part, held.isFinite { number = held }
                if propagates {
                    if let held = total, let number { total = held + number } else { total = nil }
                } else if let number, let held = total { total = held + number }
                guard case .object(var fields) = item else { scanned.append(item); continue }
                fields[into] = total.map { .number($0 == 0 ? 0 : $0) } ?? .null
                scanned.append(.object(fields))
            }
            return .array(scanned)
        case .annotate(let annotations):
            let items = list(value)
            each(items)
            // Each aggregate is taken over the whole list first, then written onto every object in it.
            var written: [String: JSONValue] = [:]
            for (name, field) in annotations {
                var parts: [JSONValue] = []
                for (at, item) in items.enumerated() {
                    if meter.exceeded { break }
                    parts.append(json(field.value, environment.with(item: item, index: at)))
                }
                written[name] = extreme(field.aggregate, parts).map { .number($0) } ?? .null
            }
            return .array(items.map { item in
                guard case .object(var fields) = item else { return item }
                fields.merge(written) { _, new in new }
                return .object(fields)
            })
        }
    }

    /// The lowest or highest of the numbers among `parts`; `nil` when there is none. A part that is not a finite number is skipped, as `sum` skips it,
    /// and zero is never negative zero.
    private static func extreme(_ kind: ServerUIFlow.Annotation.Aggregate, _ parts: [JSONValue]) -> Double? {
        var found: Double?
        for part in parts {
            guard case .number(let number) = part, number.isFinite else { continue }
            found = found.map { kind == .min ? Swift.min($0, number) : Swift.max($0, number) } ?? number
        }
        return found == 0 ? 0 : found
    }

    // MARK: Run

    private static func text(_ value: JSONValue) -> String? {
        guard let out = ServerUIFlowText.scalarText(value), !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return out
    }

    /// The rows an output asks for from the final list: items with no id or no title are skipped, the first of a repeated id wins, at most
    /// `max` are kept.
    private static func rows(_ maximum: Int, _ row: ServerUIFlow.Output.Row, _ items: [JSONValue], _ environment: Environment) -> [JSONValue] {
        environment.meter.spend(items.count)
        var rows: [JSONValue] = []
        var seen: Set<String> = []
        for item in items {
            if rows.count >= maximum || environment.meter.exceeded { break }
            let own = environment.with(item: item)
            let id = text(json(row.id, own)), title = text(json(row.title, own))
            let subtitle = row.subtitle.flatMap { text(json($0, own)) }, value = row.value.flatMap { text(json($0, own)) }
            guard let id, let title, seen.insert(id.precomposedStringWithCanonicalMapping).inserted else { continue }
            var fields: [String: JSONValue] = ["id": .string(id), "title": .string(title)]
            if let subtitle { fields["subtitle"] = .string(subtitle) }
            if let value { fields["value"] = .string(value) }
            rows.append(.object(fields))
        }
        return rows
    }

    /// Runs a flow on the data its request returned. `response` is the answer (an attribute's value, a service's response, a subscription's
    /// push, or the rows ``ServerUIFlowSources/entityRows(entityIds:attributes:held:)`` builds); a `none` request has no answer and ignores it.
    /// Never throws; over budget gives `overBudget` and no data.
    public static func run(_ flow: ServerUIFlow, response: JSONValue, context: ServerUIFlowContext, budget: Int = budget) -> ServerUIFlowRun {
        let meter = Meter(limit: budget)
        let parameters = Parameters(flow, context: context, meter: meter)
        let environment = Environment(context: context, meter: meter, parameters: parameters, item: nil)
        var value = response
        if case .none(let operand) = flow.request { value = json(operand, environment) }
        var trace: [ServerUIFlowRun.Trace] = []
        func over(_ stepId: String?) -> ServerUIFlowRun {
            ServerUIFlowRun(status: .overBudget, output: .null, value: .null, visits: meter.spent, stepId: stepId, trace: trace)
        }
        if meter.exceeded { return over(nil) }
        for step in flow.steps {
            value = run(step, on: value, environment)
            if meter.exceeded { return over(step.id) }
            trace.append(.init(id: step.id, operation: step.name, size: value.array?.count))
        }
        let given: JSONValue
        switch flow.output {
        case .rows(let maximum, let row): given = .array(rows(maximum, row, list(value), environment))
        case .records(let maximum):
            let items = list(value)
            environment.meter.spend(items.count)
            given = .array(Array(items.filter(isRecord).prefix(maximum)))
        case .record: given = isRecord(value) ? value : .null
        case .scalar:
            switch value {
            case .null, .array, .object: given = .null
            default: given = value
            }
        }
        if meter.exceeded { return over(nil) }
        return ServerUIFlowRun(status: .ok, output: given, value: value, visits: meter.spent, stepId: nil, trace: trace)
    }
}
