import Foundation

// MARK: - What each request hands the first step

/// What each live subscription pushes, as shapes. The list of kinds is closed because the app holds every subscription on its one Home
/// Assistant connection (resubscribing on reconnect, keeping the last answer), and a layout must not be able to send any other websocket
/// command. Both commands were read in Home Assistant core: `todo/item/subscribe` pushes `{items: [...]}` on subscribe and on every change;
/// `weather/subscribe_forecast` pushes `{type, forecast}`.
public enum ServerUIFlowSources {
    typealias Shape = ServerUIFlowShape

    /// The websocket command each subscription kind sends.
    public static func command(_ subscription: ServerUIFlow.Subscription) -> String {
        switch subscription {
        case .todoItems: "todo/item/subscribe"
        case .weatherForecast: "weather/subscribe_forecast"
        }
    }

    /// The entity domain each subscription kind takes.
    public static func domain(_ subscription: ServerUIFlow.Subscription) -> String {
        switch subscription {
        case .todoItems: "todo"
        case .weatherForecast: "weather"
        }
    }

    /// The shape of one to-do item as Home Assistant serialises it. `due` is a date or a date and time.
    public static let todoItem: ServerUIFlowShape = .record([
        "uid": .text, "summary": .text, "status": .string(format: nil, values: ["completed", "needs_action"]),
        "due": Shape.text(.date).merged(with: .text(.dateTime)).orNull, "description": Shape.text.orNull
    ], optional: ["due", "description"])

    /// The shape of one forecast entry. Every field but `datetime` is optional: a provider fills what it has.
    public static let forecastEntry: ServerUIFlowShape = {
        let number = Shape.float.orNull
        var fields: [String: Shape] = [
            "datetime": .text(.dateTime), "condition": Shape.text.orNull, "wind_bearing": Shape.float.merged(with: .text).orNull,
            "is_daytime": Shape.boolean.orNull
        ]
        let numbers = ["temperature", "templow", "apparent_temperature", "dew_point", "precipitation", "precipitation_probability", "humidity",
                       "pressure", "cloud_coverage", "uv_index", "wind_speed", "wind_gust_speed"]
        for name in numbers { fields[name] = number }
        return .record(fields, optional: Set(fields.keys).subtracting(["datetime"]))
    }()

    /// The shape of the data the request hands the first step. A `none` request is typed by the compiler, which has the scope.
    static func requestShape(_ request: ServerUIFlow.Request) -> Shape {
        switch request {
        case .entities(_, let attributes):
            var fields: [String: Shape] = ["entityId": .text(.entityId), "state": .text]
            for name in attributes { fields[name] = .any }
            return .array(.record(fields))
        case .none: return .any
        case .serviceResponse(_, _, _, _, _, let shape), .entityAttribute(_, _, let shape): return shape
        case .subscription(.todoItems): return .record(["items": .array(todoItem)])
        case .subscription(.weatherForecast):
            return .record(["type": .string(format: nil, values: ["daily", "hourly", "twice_daily"]), "forecast": .array(forecastEntry)])
        }
    }

    /// What the app holds about one entity.
    public struct HeldEntity: Equatable, Sendable {
        public var state: String
        public var attributes: [String: JSONValue]
        /// Creates what is held about an entity.
        public init(state: String, attributes: [String: JSONValue] = [:]) {
            self.state = state
            self.attributes = attributes
        }
    }

    /// The answer of an `entities` request: one row per listed entity in the order listed, `{entityId, state, ...attributes}`. An entity the
    /// app does not hold gives state `unavailable`; an attribute it lacks is `null`. A name that is `entityId` or `state` is the compiler's to refuse.
    public static func entityRows(entityIds: [String], attributes: [String], held: (String) -> HeldEntity?) -> JSONValue {
        .array(entityIds.map { entityId in
            let entity = held(entityId)
            var row: [String: JSONValue] = ["entityId": .string(entityId), "state": .string(entity?.state ?? "unavailable")]
            for name in attributes where row[name] == nil { row[name] = entity?.attributes[name] ?? .null }
            return .object(row)
        })
    }
}
