import Foundation

// MARK: - Decoding a flow

/// Reads a flow's `inputs` from the document's JSON into ``ServerUIFlow``. The structure check (``ServerUIFlowDecoder/shape``) runs first and
/// is the one that refuses a missing, unknown or wrongly typed field, so this reader trusts the form and only returns `nil` when it is wrong.
/// Operands and conditions go through the one grammar parser in flow mode, which also gives the `read` references the compiler checks.
struct ServerUIFlowDecoder {
    typealias Issue = ServerUICompositionError

    /// What reading one flow found.
    struct Result {
        var flow: ServerUIFlow?
        var issues: [Issue] = []
        /// Every source an operand reads, for the compiler's reference and dependency checks.
        var references: [ServerUIExpressionParser.Reference] = []
    }

    private var issues: [Issue] = []
    private var references: [ServerUIExpressionParser.Reference] = []

    /// Reads `inputs` (at `pointer`).
    static func decode(_ inputs: JSONValue, at pointer: String) -> Result {
        var decoder = Self()
        let flow = decoder.flow(inputs, pointer)
        return Result(flow: flow, issues: decoder.issues, references: decoder.references)
    }

    private mutating func operand(_ json: JSONValue?, _ pointer: String) -> ServerUIOperand? {
        guard let json else { return nil }
        var parser = ServerUIExpressionParser(flow: true)
        let value = parser.operand(json, at: pointer)
        issues += parser.issues
        references += parser.references
        return value
    }

    private mutating func predicate(_ json: JSONValue?, _ pointer: String) -> ServerUIPredicate? {
        guard let json else { return nil }
        var parser = ServerUIExpressionParser(flow: true)
        let value = parser.predicate(json, at: pointer)
        issues += parser.issues
        references += parser.references
        return value
    }

    private static func path(_ json: JSONValue?) -> [String] { json?.array?.compactMap(\.string) ?? [] }

    private static func entity(_ json: JSONValue?) -> String? { json?["value"]?.string }

    private mutating func flow(_ inputs: JSONValue, _ base: String) -> ServerUIFlow? {
        guard case .object(let object) = inputs, let title = object["title"]?.string else { return nil }
        var parameters: [ServerUIFlow.Parameter] = []
        for (index, item) in (object["parameters"]?.array ?? []).enumerated() {
            let own = "\(base)/parameters/\(index)"
            guard let name = item["name"]?.string, let kind = item["type"]?.string.flatMap(ServerUICompositionDocument.ScalarKind.init(rawValue:)),
                  let value = operand(item["value"], own + "/value") else { return nil }
            parameters.append(.init(name: name, kind: kind, value: value))
        }
        guard let request = request(object["request"], base + "/request"),
              let steps = steps(object["steps"], base + "/steps"),
              let output = output(object["output"], base + "/output"),
              let schema = object["schema"].flatMap(ServerUIFlowShape.init(json:)) else { return nil }
        let refresh = object["refresh"].flatMap(Self.refresh)
        return ServerUIFlow(title: title, parameters: parameters, request: request, steps: steps, output: output, schema: schema,
                            refresh: refresh, clockZone: object["clock"]?["zone"]?.string.flatMap(ServerUIFlow.ClockZone.init(rawValue:)))
    }

    private mutating func request(_ json: JSONValue?, _ pointer: String) -> ServerUIFlow.Request? {
        guard let json, let type = json["type"]?.string else { return nil }
        switch type {
        case "service-response":
            guard let domain = json["domain"]?.string, let service = json["service"]?.string,
                  let shape = json["responseShape"].flatMap(ServerUIFlowShape.init(json:)) else { return nil }
            var target: [String: ServerUIOperand]?
            if case .object(let entries)? = json["target"] {
                target = [:]
                for (key, value) in entries.sorted(by: { $0.key < $1.key }) {
                    guard let parsed = operand(value, ServerUICompositionJSON.pointer(pointer + "/target", key)) else { return nil }
                    target?[key] = parsed
                }
            }
            var data: ServerUIOperand?
            if let raw = json["data"] {
                guard let parsed = operand(raw, pointer + "/data") else { return nil }
                data = parsed
            }
            return .serviceResponse(domain: domain, service: service, target: target, data: data,
                                    timeoutSeconds: json["timeoutSeconds"]?.number.map { Int($0) } ?? 0, responseShape: shape)
        case "entity-attribute":
            guard let id = Self.entity(json["entityId"]), let shape = json["responseShape"].flatMap(ServerUIFlowShape.init(json:)) else { return nil }
            return .entityAttribute(entityId: id, path: Self.path(json["path"]), responseShape: shape)
        case "entities":
            let ids = (json["entityIds"]?.array ?? []).compactMap { Self.entity($0) }
            return .entities(entityIds: ids, attributes: (json["attributes"]?.array ?? []).compactMap(\.string))
        case "none":
            guard let value = operand(json["value"], pointer + "/value") else { return nil }
            return .none(value: value)
        case "ha-subscription":
            guard let id = Self.entity(json["entityId"]) else { return nil }
            switch json["kind"]?.string {
            case "todo-items": return .subscription(.todoItems(entityId: id))
            case "weather-forecast":
                guard let type = json["forecastType"]?.string.flatMap(ServerUIFlow.ForecastType.init(rawValue:)) else { return nil }
                return .subscription(.weatherForecast(entityId: id, forecastType: type))
            default: return nil
            }
        default: return nil
        }
    }

    private mutating func steps(_ json: JSONValue?, _ pointer: String) -> [ServerUIFlow.Step]? {
        guard let items = json?.array else { return nil }
        var result: [ServerUIFlow.Step] = []
        for (index, item) in items.enumerated() {
            let own = "\(pointer)/\(index)"
            guard let id = item["id"]?.string, let op = item["op"]?.string else { return nil }
            let operation: ServerUIFlow.Operation
            switch op {
            case "get": operation = .get(path: Self.path(item["path"]))
            case "select-key":
                guard let key = operand(item["key"], own + "/key") else { return nil }
                operation = .selectKey(key)
            case "filter":
                guard let where_ = predicate(item["where"], own + "/where") else { return nil }
                operation = .filter(where_)
            case "sort":
                var keys: [ServerUIFlow.SortKey] = []
                for (offset, entry) in (item["by"]?.array ?? []).enumerated() {
                    guard let value = operand(entry["value"], "\(own)/by/\(offset)/value"),
                          let direction = entry["direction"]?.string.flatMap(ServerUIFlow.SortKey.Direction.init(rawValue:)),
                          let kind = entry["kind"]?.string.flatMap(ServerUIFlow.SortKey.Kind.init(rawValue:)) else { return nil }
                    keys.append(.init(value: value, direction: direction, kind: kind))
                }
                operation = .sort(keys)
            case "limit": operation = .limit(item["count"]?.number.map { Int($0) } ?? 0)
            case "map":
                guard case .object(let entries)? = item["fields"] else { return nil }
                var fields: [String: ServerUIOperand] = [:]
                for (key, value) in entries.sorted(by: { $0.key < $1.key }) {
                    guard let parsed = operand(value, ServerUICompositionJSON.pointer(own + "/fields", key)) else { return nil }
                    fields[key] = parsed
                }
                operation = .map(fields)
            case "group", "unique":
                guard let by = operand(item["by"], own + "/by") else { return nil }
                operation = op == "group" ? .group(by: by) : .unique(by: by)
            case "count": operation = .count
            case "sum":
                guard let value = operand(item["value"], own + "/value") else { return nil }
                operation = .sum(value)
            case "first": operation = .first
            case "flatten": operation = .flatten(path: Self.path(item["path"]))
            case "default":
                guard let value = operand(item["value"], own + "/value") else { return nil }
                operation = .default(path: Self.path(item["path"]), value: value)
            case "min", "max":
                guard let value = operand(item["value"], own + "/value") else { return nil }
                operation = op == "min" ? .min(value) : .max(value)
            case "average":
                guard let value = operand(item["value"], own + "/value") else { return nil }
                operation = .average(value)
            case "running-sum":
                guard let value = operand(item["value"], own + "/value"), let into = item["into"]?.string,
                      case .bool(let propagates)? = item["nullPropagates"] else { return nil }
                operation = .runningSum(value: value, into: into, nullPropagates: propagates)
            case "annotate":
                guard case .object(let entries)? = item["fields"] else { return nil }
                var fields: [String: ServerUIFlow.Annotation] = [:]
                for (key, entry) in entries.sorted(by: { $0.key < $1.key }) {
                    guard let aggregate = entry["aggregate"]?.string.flatMap(ServerUIFlow.Annotation.Aggregate.init(rawValue:)),
                          let parsed = operand(entry["value"], ServerUICompositionJSON.pointer(own + "/fields", key) + "/value") else { return nil }
                    fields[key] = .init(aggregate: aggregate, value: parsed)
                }
                operation = .annotate(fields)
            default: return nil
            }
            result.append(.init(id: id, operation: operation))
        }
        return result
    }

    private mutating func output(_ json: JSONValue?, _ pointer: String) -> ServerUIFlow.Output? {
        guard let json, let kind = json["kind"]?.string else { return nil }
        switch kind {
        case "rows":
            guard let row = json["row"], let id = operand(row["id"], pointer + "/row/id"), let title = operand(row["title"], pointer + "/row/title")
            else { return nil }
            let subtitle = row["subtitle"] == nil ? nil : operand(row["subtitle"], pointer + "/row/subtitle")
            let value = row["value"] == nil ? nil : operand(row["value"], pointer + "/row/value")
            return .rows(max: json["max"]?.number.map { Int($0) } ?? 0, row: .init(id: id, title: title, subtitle: subtitle, value: value))
        case "records": return .records(max: json["max"]?.number.map { Int($0) } ?? 0)
        case "record": return .record
        case "scalar": return .scalar
        default: return nil
        }
    }

    private static func refresh(_ json: JSONValue) -> ServerUIFlow.Refresh? {
        guard let triggers = json["on"]?.array else { return nil }
        return .init(on: triggers.compactMap { $0.string.flatMap(ServerUIFlow.Refresh.Trigger.init(rawValue:)) },
                     entityIds: json["entityIds"]?.array.map { $0.compactMap { entity($0) } },
                     staleAfterSeconds: json["staleAfterSeconds"]?.number.map { Int($0) } ?? 0)
    }
}
