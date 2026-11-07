import Foundation

/// Runs an asynchronous open exactly once and hands every caller the same result, including callers that arrive
/// while the open is still suspended.
///
/// A check-then-await cache (`if cached == nil { cached = await open() }`) is racy on an actor: the first caller
/// suspends inside `open()`, a second caller then sees `nil` and opens again. For a named `CLMonitor` that is fatal,
/// as Core Location allows one monitor per name and asserts on the second. Here the first call stores a `Task`
/// before anything suspends, so later callers await that same task instead of starting their own.
@MainActor
public final class OpenOnce<Value: Sendable> {
    private let open: @MainActor () async -> Value
    private var task: Task<Value, Never>?

    /// The opened value once the open has finished, `nil` before. Read it to act only on something already open
    /// without opening it just for that.
    public private(set) var value: Value?

    /// Creates the helper; `open` does not run until the first ``get()``.
    public init(_ open: @escaping @MainActor () async -> Value) {
        self.open = open
    }

    /// The opened value. The first call runs the open closure; every other call, whenever it arrives, awaits the
    /// same run, so the closure runs exactly once for the object's lifetime.
    public func get() async -> Value {
        if let task { return await task.value }
        let task = Task { @MainActor [open] in
            let opened = await open()
            self.value = opened
            return opened
        }
        self.task = task
        return await task.value
    }
}
