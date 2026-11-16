import Foundation

// MARK: - Subscription

/// Follows the UI publication and hands each judged event to a store, in order.
///
/// Replies arrive on HAKit's queue. They go through a one-slot stream (only the newest unprocessed reply survives, because
/// every reply is the full current state), and a background task judges them (parses and compiles the envelope) before one hop
/// to the main actor. Nothing here polls: HAKit restarts the subscription after a reconnect and the server answers again.
@MainActor
public final class ServerUIPublicationSubscription {
    /// Receives each event on the main actor, one at a time.
    public typealias Deliver = @MainActor @Sendable (ServerUIPublicationEvent) async -> Void

    private let transport: any ServerUIPublicationTransport
    private let capabilities: [String]
    private let deliver: Deliver
    private var cancel: (@Sendable () -> Void)?
    private var consumer: Task<Void, Never>?

    /// Creates a subscription; nothing happens until ``start()``.
    /// - Parameters:
    ///   - transport: How to reach the server (``HassServerUIPublicationTransport``).
    ///   - capabilities: What this build supports; sent with the subscription.
    ///   - deliver: Where events go.
    public init(transport: any ServerUIPublicationTransport,
                capabilities: [String] = ServerUICompositionPublication.supportedCapabilities,
                deliver: @escaping Deliver) {
        self.transport = transport
        self.capabilities = capabilities
        self.deliver = deliver
    }

    deinit { consumer?.cancel() }

    /// Whether the subscription is open.
    public var isStarted: Bool { cancel != nil }

    /// Opens the subscription. Safe to call repeatedly: only the first call after ``stop()`` acts.
    public func start() {
        guard cancel == nil else { return }
        let (stream, continuation) = AsyncStream<Result<Data, any Error>>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let deliver = deliver
        consumer = Task.detached(priority: .userInitiated) {
            for await reply in stream {
                if Task.isCancelled { return }
                await deliver(ServerUIPublicationEvent.judge(reply))
            }
        }
        let end = transport.subscribe(capabilities: capabilities) { continuation.yield($0) }
        cancel = {
            end()
            continuation.finish()
        }
    }

    /// Ends the subscription; a later ``start()`` asks the server again.
    public func stop() {
        cancel?()
        cancel = nil
        consumer?.cancel()
        consumer = nil
    }

    /// Stops and starts again, which makes the server send the current state once more.
    public func restart() {
        stop()
        start()
    }
}
