import Foundation

// MARK: - Scoped forecast reads

/// Read-only access for an isolated composition host. It cannot issue arbitrary service calls.
/// The owner supplies the existing connection, never a second session or a writable preview caller.
@MainActor
public struct ServerUIWeatherReader {
    /// The authored failure choices.
    public enum Failure: Error, Equatable { case unapprovedEntity }
    public let entityIds: Set<String>
    private let fetch: @MainActor (String, WeatherForecastKind) async throws -> JSONValue
    private let connected: @MainActor () -> Bool

    /// Creates a server uiweather reader.
    public init(entityIds: Set<String>, caller: any WeatherForecastCalling,
                connected: @escaping @MainActor () -> Bool = { true }) {
        self.init(entityIds: entityIds, connected: connected) { entity, kind in
            try await caller.callServiceForResponse("weather", "get_forecasts",
                                                    data: ["entity_id": entity, "type": kind.rawValue])
        }
    }

    /// Synthetic providers use the same scoped, typed interface as the authenticated connection.
    public init(entityIds: Set<String>, connected: @escaping @MainActor () -> Bool = { true },
                fetch: @escaping @MainActor (String, WeatherForecastKind) async throws -> JSONValue) {
        self.entityIds = entityIds
        self.connected = connected
        self.fetch = fetch
    }

    public var isConnected: Bool { connected() }

    /// Fetches the forecast of the given kind for the entity.
    public func forecast(entityId: String, kind: WeatherForecastKind) async throws -> JSONValue {
        guard entityIds.contains(entityId), entityId.hasPrefix("weather."), entityId.count > 8 else {
            throw Failure.unapprovedEntity
        }
        return try await fetch(entityId, kind)
    }
}
