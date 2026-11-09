import Foundation

/// Streams a response body as the chunks the network delivers, instead of one byte per `AsyncBytes` iteration.
///
/// A notification content extension has a small memory budget and a camera stream is endless, so the per-byte
/// suspension of `URLSession.AsyncBytes` is the cost this avoids. Cancelling the consuming task cancels the request.
public enum MJPEGChunkStream {
    /// The HTTP status and the body chunks of one request.
    public struct Result: Sendable {
        /// The response status, delivered once the headers arrive.
        public let statusCode: @Sendable () async -> Int
        /// The body chunks in arrival order; throws if the transfer fails.
        public let chunks: AsyncThrowingStream<Data, Error>
    }

    /// Starts `request` and returns the status and body chunks.
    /// - Parameter configuration: The session configuration; defaults to an ephemeral one.
    public static func open(_ request: URLRequest, configuration: URLSessionConfiguration = .ephemeral) -> Result {
        let delegate = Delegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            delegate.continuation = continuation
            let task = session.dataTask(with: request)
            continuation.onTermination = { _ in
                task.cancel()
                session.invalidateAndCancel()
            }
            task.resume()
        }
        return Result(statusCode: { await delegate.status.value }, chunks: stream)
    }

    private final class Delegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation?
        let status = StatusBox()

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            status.set((response as? HTTPURLResponse)?.statusCode ?? 0)
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            continuation?.yield(data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            status.set(0)
            if let error, (error as? URLError)?.code != .cancelled { continuation?.finish(throwing: error) } else { continuation?.finish() }
        }
    }

    /// A one-shot value that can be awaited before or after it is set.
    private final class StatusBox: @unchecked Sendable {
        private let lock = NSLock()
        private var code: Int?
        private var waiters: [CheckedContinuation<Int, Never>] = []

        func set(_ value: Int) {
            lock.lock()
            guard code == nil else { lock.unlock(); return }
            code = value
            let pending = waiters
            waiters = []
            lock.unlock()
            pending.forEach { $0.resume(returning: value) }
        }

        var value: Int {
            get async {
                await withCheckedContinuation { continuation in
                    lock.lock()
                    if let code { lock.unlock(); continuation.resume(returning: code) } else { waiters.append(continuation); lock.unlock() }
                }
            }
        }
    }
}
