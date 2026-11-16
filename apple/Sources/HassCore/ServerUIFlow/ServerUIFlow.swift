import Foundation

// MARK: - A Data Flow

/// A Data Flow (`sh.pipeline@1`): a document data source that asks Home Assistant for data (a service with a response, an entity attribute,
/// entities the app already holds, or a live subscription from a closed list), runs a closed, pure list of steps on the answer, and gives
/// rows, a record or one value. It never carries a URL, a header or a key: a request names a Home Assistant service, and Home Assistant
/// holds the secrets.
///
/// The flow is decoded from the document by ``ServerUIFlowDecoder`` after the structure check; ``ServerUIFlowCompiler`` proves its steps
/// against the authored shapes; ``ServerUIFlowEvaluator`` runs it.
public struct ServerUIFlow: Equatable, Sendable {
    /// The limits of a flow.
    public enum Limits {
        /// The most flows a document holds, entities and entity attributes a request lists, parameters, steps and sort keys a flow has.
        public static let flows = 128, entities = 64, entityAttributes = 8, parameters = 8, steps = 32, sortKeys = 4
        /// The most rows an output gives, the largest `limit` step, fields in a `map` step, ids in a refresh and segments in a path.
        public static let rows = 100, limit = 1_000, mapFields = 32, entityIds = 8, path = 8
        /// The most nodes an operand and a predicate hold.
        public static let operandNodes = 64, whereNodes = 32
        /// The seconds a service call may take, and the seconds a result may be old before it counts as stale.
        public static let timeout = 1...30, stale = 30...86_400
    }

    /// The title the Studio shows for the flow.
    public let title: String
    /// The declared parameters, evaluated in dependency order.
    public let parameters: [Parameter]
    /// How the flow gets its data.
    public let request: Request
    /// The closed list of steps run on the answer.
    public let steps: [Step]
    /// What the flow gives.
    public let output: Output
    /// The authored shape of the final value.
    public let schema: ServerUIFlowShape
    /// When the flow runs again; present for a `service-response` or an `entity-attribute` request only.
    public let refresh: Refresh?
    /// Which clock the flow's dates use.
    public let clockZone: ClockZone?

    /// A declared parameter: a name, the kind its value is read as and the operand that gives it.
    public struct Parameter: Equatable, Sendable {
        /// The name steps use to read it.
        public let name: String
        /// The kind its value is read as.
        public let kind: ServerUICompositionDocument.ScalarKind
        /// The operand that gives the value.
        public let value: ServerUIOperand
    }

    /// The live feeds a flow can hold on the app's one connection.
    public enum Subscription: Equatable, Sendable {
        /// `todo/item/subscribe`: pushes `{ items: [...] }` on subscribe and on every change.
        case todoItems(entityId: String)
        /// `weather/subscribe_forecast`: pushes `{ type, forecast }`.
        case weatherForecast(entityId: String, forecastType: ForecastType)

        /// The kind a document names it by.
        public var kindName: String {
            switch self {
            case .todoItems: "todo-items"
            case .weatherForecast: "weather-forecast"
            }
        }
        /// The entity the feed is about.
        public var entityId: String {
            switch self {
            case .todoItems(let id), .weatherForecast(let id, _): id
            }
        }
    }

    /// The forecast a weather feed asks for.
    public enum ForecastType: String, Sendable, CaseIterable { case daily, hourly, twiceDaily = "twice_daily" }

    /// How a flow gets its data.
    public enum Request: Equatable, Sendable {
        /// A Home Assistant service that answers with data; `responseShape` is the authored shape of the answer.
        case serviceResponse(domain: String, service: String, target: [String: ServerUIOperand]?, data: ServerUIOperand?,
                             timeoutSeconds: Int, responseShape: ServerUIFlowShape)
        /// An attribute of one entity the app already holds; `path` starts with the attribute.
        case entityAttribute(entityId: String, path: [String], responseShape: ServerUIFlowShape)
        /// The state and chosen attributes of up to 64 entities the app already holds.
        case entities(entityIds: [String], attributes: [String])
        /// No data; the value is an operand over the parameters, the viewer and the clock.
        case none(value: ServerUIOperand)
        /// A live feed from a closed list.
        case subscription(Subscription)
    }

    /// One step of a flow.
    public struct Step: Equatable, Sendable {
        /// The step's id, unique in the flow.
        public let id: String
        /// What the step does.
        public let operation: Operation
        /// The operation's name as a document writes it (`op`).
        public var name: String { operation.name }
    }

    /// What a step does.
    public enum Operation: Equatable, Sendable {
        case get(path: [String])
        case selectKey(ServerUIOperand)
        case filter(ServerUIPredicate)
        case sort([SortKey])
        case limit(Int)
        case map([String: ServerUIOperand])
        case group(by: ServerUIOperand)
        case count
        case sum(ServerUIOperand)
        case first
        case flatten(path: [String])
        case unique(by: ServerUIOperand)
        case `default`(path: [String], value: ServerUIOperand)

        /// The name a document writes (`op`).
        public var name: String {
            switch self {
            case .get: "get"
            case .selectKey: "select-key"
            case .filter: "filter"
            case .sort: "sort"
            case .limit: "limit"
            case .map: "map"
            case .group: "group"
            case .count: "count"
            case .sum: "sum"
            case .first: "first"
            case .flatten: "flatten"
            case .unique: "unique"
            case .default: "default"
            }
        }
    }

    /// One key of a `sort` step.
    public struct SortKey: Equatable, Sendable {
        /// Which way the key orders.
        public enum Direction: String, Sendable { case ascending, descending }
        /// How the key's values compare.
        public enum Kind: String, Sendable { case text, number, date }
        /// The value of the key, read for each item.
        public let value: ServerUIOperand
        /// Which way it orders.
        public let direction: Direction
        /// How its values compare.
        public let kind: Kind
    }

    /// What a flow gives: a list of rows, one record, or one value.
    public enum Output: Equatable, Sendable {
        case rows(max: Int, row: Row)
        case record
        case scalar

        /// The operands of one row.
        public struct Row: Equatable, Sendable {
            public let id: ServerUIOperand
            public let title: ServerUIOperand
            public let subtitle: ServerUIOperand?
            public let value: ServerUIOperand?
        }
    }

    /// When a flow runs again. There is no timer: Home Assistant reports changes, and a person can pull to refresh.
    public struct Refresh: Equatable, Sendable {
        public enum Trigger: String, Sendable, CaseIterable { case open, manual, entityChange = "entity-change" }
        public let on: [Trigger]
        public let entityIds: [String]?
        public let staleAfterSeconds: Int
    }

    /// Which clock a flow's dates use.
    public enum ClockZone: String, Sendable { case device, home }

    // MARK: Derived facts

    /// Whether the flow gives rows (the only kind a list can show).
    public var givesRows: Bool { if case .rows = output { true } else { false } }

    /// Whether a person can pull the flow to run it again.
    public var refreshesManually: Bool { refresh?.on.contains(.manual) == true }

    /// The live feed the flow holds, if any.
    public var subscription: Subscription? { if case .subscription(let feed) = request { feed } else { nil } }

    /// The operands the flow evaluates, with where each stands (for the run's clock and source checks).
    var operands: [ServerUIOperand] {
        var result = parameters.map(\.value)
        switch request {
        case .serviceResponse(_, _, let target, let data, _, _): result += (target.map { Array($0.values) } ?? []) + (data.map { [$0] } ?? [])
        case .none(let value): result.append(value)
        default: break
        }
        for step in steps {
            switch step.operation {
            case .selectKey(let operand), .group(let operand), .sum(let operand), .unique(let operand), .default(_, let operand): result.append(operand)
            case .sort(let keys): result += keys.map(\.value)
            case .map(let fields): result += fields.values
            case .filter, .get, .limit, .count, .first, .flatten: break
            }
        }
        if case .rows(_, let row) = output { result += [row.id, row.title] + [row.subtitle, row.value].compactMap { $0 } }
        return result
    }

    /// The predicates the flow evaluates.
    var predicates: [ServerUIPredicate] {
        steps.compactMap { if case .filter(let predicate) = $0.operation { predicate } else { nil } }
    }

    /// The source ids the flow reads (a parameter's `read`).
    public var sourceIds: Set<String> {
        operands.reduce(into: Set<String>()) { $0.formUnion($1.sourceIds) }.union(predicates.reduce(into: Set<String>()) { $0.formUnion($1.sourceIds) })
    }

    /// How long a service call may take: the request's own `timeoutSeconds` (the schema holds it to 1 through 30; the Studio sets no other
    /// default). `nil` for a request that makes no call.
    public var timeout: Duration? {
        guard case .serviceResponse(_, _, _, _, let seconds, _) = request else { return nil }
        return .seconds(min(30, max(1, seconds)))
    }

    /// Whether the flow's data is the entities the app holds (an `entities` or `entity-attribute` request), so it has none before the first states arrive.
    public var readsHeldEntities: Bool {
        switch request {
        case .entities, .entityAttribute: true
        default: false
        }
    }

    /// The entities the flow watches while it runs: an `entities` request lists them, and a refresh may name more.
    public var watchedEntityIds: [String] {
        switch request {
        case .entities(let ids, _): ids
        case .entityAttribute(let id, _, _): [id]
        case .serviceResponse: refresh?.entityIds ?? []
        default: []
        }
    }

    /// Whether the flow reads the viewer anywhere, so a viewer change runs it again.
    public var readsViewer: Bool { operands.contains { $0.readsViewer } || predicates.contains { $0.readsViewer } }
    /// Whether the flow reads the clock anywhere, so a minute that passes runs it again (on the answer it already has).
    public var readsClock: Bool { operands.contains { $0.readsClock } || predicates.contains { $0.readsClock } }
}
