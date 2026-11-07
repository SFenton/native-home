import Foundation
@preconcurrency import HAKit

// MARK: - Raw websocket commands

extension HassConnection {
    /// Sends a websocket command once and returns HAKit's raw result. It never retries across reconnects, so a
    /// mutation is never applied twice. Every one-off command (service responses, schedules, todo lists, the
    /// service catalog, signed paths) goes through here rather than its own continuation bridge.
    ///
    /// HAKit drops a command that was in flight when the socket closed, or queued across a reset, **without calling
    /// its completion** (`HARequestController.resetActive`), so the await below would never return. Pass a
    /// `timeout` for any command that something is waiting on (the camera streams after a background).
    /// - Parameters:
    ///   - command: The websocket command type.
    ///   - data: Its fields.
    ///   - timeout: Fails with ``CommandTimeout`` if no answer comes in this time; nil waits as long as HAKit does.
    func sendCommand(_ command: String, data: [String: any Sendable], timeout: Duration? = nil) async throws -> HAData {
        let request = HARequest(type: .webSocket(command), data: data, shouldRetry: false)
        let answered = SingleUse()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HAData, Error>) in
            let pending = connection.send(request) { @Sendable result in
                guard answered.claim() else { return }
                switch result {
                case let .success(value): continuation.resume(returning: value)
                case let .failure(error): continuation.resume(throwing: error)
                }
            }
            guard let timeout else { return }
            Task {
                try? await Task.sleep(for: timeout)
                guard answered.claim() else { return }
                pending.cancel()
                continuation.resume(throwing: CommandTimeout(command: command))
            }
        }
    }

    /// ``sendCommand(_:data:)`` with the whole result as JSON.
    func requestJSON(_ command: String, data: [String: any Sendable]) async throws -> JSONValue {
        JSONValue(haData: try await sendCommand(command, data: data))
    }

    /// `call_service` with `return_response: true`, as the whole result (`{"response": ...}` from Home Assistant).
    func callServiceReturningResult(_ domain: String, _ service: String, data: [String: any Sendable]) async throws -> JSONValue {
        try await requestJSON("call_service", data: ["domain": domain, "service": service, "service_data": data, "return_response": true])
    }
}
