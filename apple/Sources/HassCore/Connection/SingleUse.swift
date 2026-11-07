import Foundation

/// Lets exactly one of several racing callbacks (the answer, the timeout) resume a continuation.
final class SingleUse: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    /// Whether the caller won; later callers get false.
    func claim() -> Bool {
        lock.withLock {
            defer { used = true }
            return !used
        }
    }
}
