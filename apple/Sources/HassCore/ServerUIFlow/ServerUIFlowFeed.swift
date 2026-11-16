import Foundation
@preconcurrency import HAKit

// MARK: - The live feed of a flow

/// The live feed a `ha-subscription` request rides: `todo-items` and `weather-forecast`.
///
/// There is one implementation, ``HassFlowFeed``, over the app's one ``HassConnection``. It exists as a protocol only so the session can
/// be tested with a feed that is driven by hand.
@MainActor
public protocol ServerUIFlowFeed {
    /// Starts the subscription. `handler` gets each push (the request shape's value) or a failure, on any thread, in order.
    /// - Returns: A closure that ends the subscription.
    func subscribe(_ subscription: ServerUIFlow.Subscription, handler: @escaping @Sendable (Result<JSONValue, Error>) -> Void)
        -> @Sendable () -> Void
}

/// The websocket command a subscription kind is made of, and the fields it sends.
public enum ServerUIFlowSubscriptionCommand {
    /// The command of the subscription.
    public static func command(_ subscription: ServerUIFlow.Subscription) -> String {
        switch subscription {
        case .todoItems: "todo/item/subscribe"
        case .weatherForecast: "weather/subscribe_forecast"
        }
    }

    /// The fields of the command.
    public static func data(_ subscription: ServerUIFlow.Subscription) -> [String: String] {
        switch subscription {
        case .todoItems(let entityId): ["entity_id": entityId]
        case .weatherForecast(let entityId, let type): ["entity_id": entityId, "forecast_type": type.rawValue]
        }
    }
}

/// ``ServerUIFlowFeed`` over the one connection: a HAKit subscription that HAKit sends again after every reconnect, so the list is
/// followed across drops without anything else running.
public struct HassFlowFeed: ServerUIFlowFeed {
    private let connection: HassConnection

    /// Creates a feed over the connection.
    public init(connection: HassConnection) { self.connection = connection }

    public func subscribe(_ subscription: ServerUIFlow.Subscription, handler: @escaping @Sendable (Result<JSONValue, Error>) -> Void)
        -> @Sendable () -> Void {
        var request = HARequest(type: .webSocket(ServerUIFlowSubscriptionCommand.command(subscription)),
                                data: ServerUIFlowSubscriptionCommand.data(subscription), shouldRetry: true)
        // Like the entity subscription: one resend per socket, for as long as the connection lives.
        request.retryDuration = nil
        let cancellable = connection.connection.subscribe(
            to: request,
            initiated: { @Sendable result in
                if case let .failure(error) = result { handler(.failure(error)) }
            },
            handler: { @Sendable _, data in handler(.success(JSONValue(haData: data))) }
        )
        nonisolated(unsafe) let token = cancellable
        return { token.cancel() }
    }
}

// MARK: - The service a flow calls

extension HassConnection {
    /// Calls `domain.service` with `return_response` and a target, once (no retry across reconnects), and gives the service's `response`.
    ///
    /// HAKit never answers a command that was in flight when the socket closed, so the call ends with ``CommandTimeout`` after `timeout`
    /// (the flow's own `timeoutSeconds`) instead of waiting for ever.
    public func callServiceForFlow(_ domain: String, _ service: String, target: [String: JSONValue], data: [String: JSONValue],
                                   timeout: Duration) async throws -> JSONValue {
        var fields: [String: any Sendable] = ["domain": domain, "service": service, "return_response": true,
                                              "service_data": data.mapValues(\.foundationValue)]
        if !target.isEmpty { fields["target"] = target.mapValues(\.foundationValue) }
        return try await JSONValue(haData: sendCommand("call_service", data: fields, timeout: timeout))["response"] ?? .null
    }
}
