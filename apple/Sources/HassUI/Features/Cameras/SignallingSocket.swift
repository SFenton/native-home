import Foundation
import HassTelemetry
import os

/// The signalling websocket of one camera stream, with a session of its own.
///
/// Every WebRTC stream opens one of these (go2rtc's `/api/webrtc/ws`), and the app closes and reopens all of them
/// on every background and foreground. On `URLSession.shared` a cancelled task stays allocated until the server
/// answers the close handshake, and the shared session keeps its buffers (about 170 KB each, four per resume, found by the
/// resume-stutter lane 2026-10-16). A session per socket is invalidated with the socket, which cancels the task
/// and frees both at once; ``liveCount`` shows that none is left behind (`ResourceCensus`, `Camera.signallingSockets`).
///
/// The session's delegate only counts: it must not retain the socket, or neither would ever be released.
final class SignallingSocket: Sendable {
    /// Sockets created and not yet fully released by their session.
    static var liveCount: Int { counter.withLock { $0 } }

    private static let counter = OSAllocatedUnfairLock(initialState: 0)

    /// One gauge for the whole app, registered with the first socket.
    private static let census = ResourceCensus.shared.register { ["Camera.signallingSockets": SignallingSocket.liveCount] }

    /// Counts the end of the session's life.
    private final class Delegate: NSObject, URLSessionDelegate, Sendable {
        func urlSession(_ session: URLSession, didBecomeInvalidWithError error: (any Error)?) {
            SignallingSocket.counter.withLock { $0 -= 1 }
        }
    }

    private let session: URLSession
    private let task: URLSessionWebSocketTask

    /// Creates the socket; nothing connects until ``resume()``.
    /// - Parameter url: The signed signalling URL.
    init(url: URL) {
        _ = Self.census
        Self.counter.withLock { $0 += 1 }
        session = URLSession(configuration: .ephemeral, delegate: Delegate(), delegateQueue: nil)
        task = session.webSocketTask(with: url)
    }

    deinit {
        // A socket dropped without ``cancel()`` still ends its session.
        session.invalidateAndCancel()
    }

    /// Opens the connection.
    func resume() { task.resume() }

    /// Reads the next message.
    func receive(_ handler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, any Error>) -> Void) {
        task.receive(completionHandler: handler)
    }

    /// Sends one text message.
    func send(_ text: String, completion: @escaping @Sendable ((any Error)?) -> Void) {
        task.send(.string(text), completionHandler: completion)
    }

    /// Closes the connection and releases the task and its session. Safe to call more than once.
    func cancel() {
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}
