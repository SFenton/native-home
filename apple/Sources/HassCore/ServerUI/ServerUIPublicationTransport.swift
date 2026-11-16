import Foundation
@preconcurrency import HAKit

/// How the app follows the UI publication.
///
/// There is one implementation, ``HassServerUIPublicationTransport``, over the app's one websocket
/// (`fenton_home/ui_publication/subscribe`); tests pass a fake. Like ``HouseConfigTransport`` the subscription is the only
/// request: the integration sends the current state first and after every publish or rollback, and HAKit restarts the
/// subscription after a reconnect. There is no poll and no HTTP fetch of the document.
@MainActor
public protocol ServerUIPublicationTransport: Sendable {
    /// Follows the publication.
    ///
    /// The handler runs on any queue: first with the current state, then once per change; with a failure when the server refuses the
    /// subscription.
    /// - Parameters:
    ///   - capabilities: The capability set this build supports; the server chooses the newest publication within it.
    ///   - handler: Receives each reply's JSON or the failure.
    /// - Returns: A closure that ends the subscription.
    func subscribe(capabilities: [String], handler: @escaping @Sendable (Result<Data, any Error>) -> Void) -> @Sendable () -> Void
}

/// ``ServerUIPublicationTransport`` over ``HassConnection``'s websocket.
@MainActor
public struct HassServerUIPublicationTransport: ServerUIPublicationTransport {
    /// The command that follows the publication.
    public static let subscribeCommand = "fenton_home/ui_publication/subscribe"

    private let connection: HassConnection

    /// Creates a transport over the connection.
    public init(connection: HassConnection) {
        self.connection = connection
    }

    /// Subscribes to publications for the given capabilities.
    public func subscribe(capabilities: [String],
                          handler: @escaping @Sendable (Result<Data, any Error>) -> Void) -> @Sendable () -> Void {
        var request = HARequest(type: .webSocket(Self.subscribeCommand), data: ["capabilities": capabilities], shouldRetry: true)
        // Like the entity and house-config subscriptions: one resend per socket, for as long as the connection lives.
        request.retryDuration = nil
        let cancellable = connection.connection.subscribe(
            to: request,
            initiated: { @Sendable result in
                if case let .failure(error) = result { handler(.failure(error)) }
            },
            handler: { @Sendable _, data in handler(Self.json(data)) }
        )
        nonisolated(unsafe) let token = cancellable
        return { token.cancel() }
    }

    /// A reply as JSON; only an object is an event.
    nonisolated static func json(_ data: HAData) -> Result<Data, any Error> {
        guard case let .dictionary(object) = data else { return .failure(ServerUIStoreError.malformedEvent) }
        return Result { try JSONSerialization.data(withJSONObject: object) }
    }
}
