import Foundation

/// Sends `mobile_app` webhook commands for location and sensors: `update_location`, `register_sensor`,
/// `update_sensor_states` and `get_zones` (Home Assistant native app integration docs, "Sending data home").
///
/// Plain REST over the injectable ``FeedbackHTTPTransport`` seam, like `HomeAssistantPushClient`: each command is a
/// one-off exchange, not entity state, so it stays off the websocket. Webhook calls carry no token; the webhook id
/// addresses the registration, so a background zone event can report before the app refreshes its access token.
public struct MobileAppWebhookClient: Sendable {
    private let source: any MobileAppWebhookSource
    private let transport: any FeedbackHTTPTransport

    /// Creates a client.
    /// - Parameters:
    ///   - source: Supplies the current registration's webhook.
    ///   - transport: The HTTP seam (tests use a stub).
    public init(source: any MobileAppWebhookSource, transport: any FeedbackHTTPTransport = URLSessionFeedbackTransport()) {
        self.source = source
        self.transport = transport
    }

    /// The webhook id of the current registration, nil when there is none. It changes with a new registration.
    public func currentWebhookID() async -> String? {
        await source.currentWebhook()?.webhookID
    }

    /// Sends one location update.
    public func updateLocation(_ report: LocationReport) async throws {
        _ = try await send(report.webhookBody)
    }

    /// Registers one sensor (or updates its name, icon and units if it already exists).
    public func registerSensor(_ sensor: MobileAppSensor) async throws {
        _ = try await send(sensor.registerBody)
    }

    /// Sends new states for `sensors` in one command.
    /// - Returns: Which sensors Home Assistant did not take; empty when `sensors` is empty (nothing is sent).
    public func updateSensorStates(_ sensors: [MobileAppSensor]) async throws -> SensorUpdateOutcome {
        guard !sensors.isEmpty else { return SensorUpdateOutcome() }
        let data = try await send(MobileAppSensor.updateBody(sensors))
        guard let outcome = SensorUpdateOutcome(json: data) else { throw MobileAppWebhookError.unexpectedResponse }
        return outcome
    }

    /// Reads every zone.
    public func zones() async throws -> [HAZone] {
        let data = try await send(["type": "get_zones"])
        guard let zones = HAZone.zones(json: data) else { throw MobileAppWebhookError.unexpectedResponse }
        return zones
    }

    /// Sends a webhook command that carries a `data` object: the Live Activity tokens and events
    /// (`.agents/platforms/apple/live-activities.md` §6).
    public func send(command type: String, data: [String: Any]) async throws {
        _ = try await send(["type": type, "data": data])
    }

    // MARK: - HTTP

    private func send(_ body: [String: Any]) async throws -> Data {
        guard let webhook = await source.currentWebhook() else { throw MobileAppWebhookError.notRegistered }
        var request = URLRequest(url: webhook.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let data: Data, response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MobileAppWebhookError.network
        }
        if response.statusCode == 410 { throw MobileAppWebhookError.registrationGone }
        guard (200..<300).contains(response.statusCode) else { throw MobileAppWebhookError.status(response.statusCode) }
        return data
    }
}
