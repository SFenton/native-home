import Foundation

// MARK: - The structure of a flow source

/// The closed structure of a `pipeline@1` data source: every object is strict, so an unknown field is refused rather than ignored (a
/// published layout that an older app reads half-way is worse than one it refuses). Operands and conditions are checked by the one grammar
/// parser in flow mode, the authored shapes by ``ServerUIFlowShape/issues(in:at:)``.
extension ServerUICompositionShape {
    private static let parameterName = Shape.pattern("^[A-Za-z_][A-Za-z0-9_]{0,31}$", 100_000)
    private static let service = Shape.pattern("^[a-z][a-z0-9_]{0,63}$", 100_000)
    private static let attribute = Shape.pattern("^[A-Za-z0-9_-]{1,64}$", 100_000)
    private static func path(minimum: Int) -> Shape { .array(.text(64, blank: true), minimum, ServerUIFlow.Limits.path) }

    /// The `inputs` of a flow.
    static let flowInputs: Shape = {
        let limits = ServerUIFlow.Limits.self
        let flowOperand = Shape.flowOperand
        let step: (String, [String: Shape]) -> Shape = { op, fields in
            object(["id": id, "op": fixed(op)].merging(fields) { $1 })
        }
        let steps = Shape.variant("op", [
            "get": step("get", ["path": path(minimum: 1)]),
            "select-key": step("select-key", ["key": flowOperand]),
            "filter": step("filter", ["where": .flowPredicate]),
            "sort": step("sort", ["by": array(object(["value": flowOperand, "direction": .choice(["ascending", "descending"]),
                                                      "kind": .choice(["text", "number", "date"])]), limits.sortKeys, minimum: 1)]),
            "limit": step("limit", ["count": .number(1, Double(limits.limit), integer: true)]),
            "map": step("map", ["fields": .dictionary(.text(10_000, blank: true), flowOperand, 100_000)]),
            "group": step("group", ["by": flowOperand]),
            "count": step("count", [:]),
            "sum": step("sum", ["value": flowOperand]),
            "first": step("first", [:]),
            "flatten": step("flatten", ["path": path(minimum: 0)]),
            "unique": step("unique", ["by": flowOperand]),
            "default": step("default", ["path": path(minimum: 1), "value": flowOperand]),
            // `sh.flow-extras@1`
            "min": step("min", ["value": flowOperand]),
            "max": step("max", ["value": flowOperand]),
            // `sh.flow-average@1`
            "average": step("average", ["value": flowOperand]),
            "running-sum": step("running-sum", ["value": flowOperand, "into": .text(160, blank: true), "nullPropagates": .bool]),
            "annotate": step("annotate", ["fields": .dictionary(.text(10_000, blank: true), object([
                "aggregate": .choice(ServerUIFlow.Annotation.Aggregate.allCases.map(\.rawValue)), "value": flowOperand]), 100_000)])
        ])
        let target = Shape.object(Dictionary(uniqueKeysWithValues: ["entity_id", "device_id", "area_id", "floor_id", "label_id"].map {
            ($0, Shape.optional(flowOperand))
        }))
        let subscription = Shape.variant("kind", [
            "todo-items": object(["type": fixed("ha-subscription"), "kind": fixed("todo-items"), "entityId": literalEntity]),
            "weather-forecast": object(["type": fixed("ha-subscription"), "kind": fixed("weather-forecast"), "entityId": literalEntity,
                                        "forecastType": .choice(ServerUIFlow.ForecastType.allCases.map(\.rawValue))])
        ])
        let request = Shape.variant("type", [
            "service-response": object([
                "type": fixed("service-response"), "domain": service, "service": service,
                "target": .optional(target),
                "data": .optional(object(["type": fixed("object"), "fields": .dictionary(.text(10_000, blank: true), flowOperand, 100_000)])),
                "timeoutSeconds": .number(Double(limits.timeout.lowerBound), Double(limits.timeout.upperBound), integer: true),
                "responseShape": .flowShape
            ]),
            "entity-attribute": object(["type": fixed("entity-attribute"), "entityId": literalEntity, "path": path(minimum: 1),
                                        "responseShape": .flowShape]),
            "entities": object(["type": fixed("entities"), "entityIds": array(literalEntity, limits.entities, minimum: 1),
                                "attributes": array(attribute, limits.entityAttributes)]),
            "none": object(["type": fixed("none"), "value": flowOperand]),
            "ha-subscription": subscription
        ])
        let output = Shape.variant("kind", [
            "rows": object(["kind": fixed("rows"), "max": .number(1, Double(limits.rows), integer: true),
                            "row": object(["id": flowOperand, "title": flowOperand, "subtitle": .optional(flowOperand),
                                           "value": .optional(flowOperand)])]),
            // `sh.repeat@1`
            "records": object(["kind": fixed("records"), "max": .number(1, Double(limits.rows), integer: true)]),
            "record": object(["kind": fixed("record")]),
            "scalar": object(["kind": fixed("scalar")])
        ])
        let refresh = Shape.object([
            "on": array(.choice(ServerUIFlow.Refresh.Trigger.allCases.map(\.rawValue)), 3, minimum: 1),
            "entityIds": .optional(array(literalEntity, limits.entityIds, minimum: 1)),
            "staleAfterSeconds": .number(Double(limits.stale.lowerBound), Double(limits.stale.upperBound), integer: true)
        ])
        return object([
            "title": .text(240, blank: false),
            "parameters": array(object(["name": parameterName, "type": .choice(["string", "number", "boolean", "entity-id"]),
                                        "value": flowOperand]), limits.parameters),
            "request": request, "steps": array(steps, limits.steps), "output": output, "schema": .flowShape,
            "refresh": .optional(refresh), "clock": .optional(object(["zone": .choice(["device", "home"])]))
        ])
    }()

    /// A `pipeline@1` source.
    static let pipelineSource: Shape = object([
        "id": id, "kind": fixed("model"), "model": fixed("pipeline@1"), "inputs": flowInputs
    ])
}
