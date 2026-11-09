import Foundation
@preconcurrency import HAKit

/// How ``HouseConfigStore`` reaches the server's house document.
///
/// There is one implementation, ``HassHouseConfigTransport``, over the app's one websocket
/// (`fenton_home/house_config/subscribe`); tests pass a fake. The subscription is the only request: the server sends the
/// current document first (`SFenton/ha-fenton-home#13`) and HAKit restarts the subscription after a reconnect, so a
/// separate one-shot get would only add a command HAKit can drop when the socket resets. The handler gets raw JSON so
/// the decoding happens off the main thread, in the store.
@MainActor
public protocol HouseConfigTransport: Sendable {
    /// Follows the document.
    ///
    /// The handler runs on any queue: first with the current document, then once per reload; with a failure when the
    /// server refuses the subscription. HAKit restarts the subscription after a reconnect, which delivers the
    /// current document again.
    /// - Parameter handler: Receives each reply's JSON or the failure.
    /// - Returns: A closure that ends the subscription.
    func subscribe(_ handler: @escaping @Sendable (Result<Data, Error>) -> Void) -> @Sendable () -> Void
}

/// ``HouseConfigTransport`` over ``HassConnection``'s websocket, so there is no second socket and no REST call.
@MainActor
public struct HassHouseConfigTransport: HouseConfigTransport {
    /// The command that follows the document.
    public static let subscribeCommand = "fenton_home/house_config/subscribe"

    private let connection: HassConnection

    /// Creates a transport over the connection.
    public init(connection: HassConnection) {
        self.connection = connection
    }

    public func subscribe(_ handler: @escaping @Sendable (Result<Data, Error>) -> Void) -> @Sendable () -> Void {
        var request = HARequest(type: .webSocket(Self.subscribeCommand), data: [:], shouldRetry: true)
        // Like the entity subscription: one resend per socket, for as long as the connection lives.
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

    /// A reply as JSON; only an object is a document.
    nonisolated static func json(_ data: HAData) -> Result<Data, Error> {
        guard case let .dictionary(object) = data else {
            return .failure(HouseConfig.DecodeError.malformed("reply is not an object"))
        }
        return Result { try JSONSerialization.data(withJSONObject: object) }
    }
}
