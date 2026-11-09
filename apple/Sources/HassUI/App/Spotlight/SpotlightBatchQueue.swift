/// Runs Spotlight batches one after another, in the order they were queued.
///
/// Each batch is a delete of the domain followed by an index, and `removeAll` is another delete. Run as independent
/// tasks they could interleave (A deletes, B deletes, B indexes, A indexes) and leave the older rooms, or index
/// after sign-out's removal. Chaining each batch on the one before makes the last call win.
@MainActor
final class SpotlightBatchQueue {
    private var tail: Task<Void, Never>?

    /// Queues `work` behind everything queued before it.
    /// - Parameter work: Runs off the main actor, after the previous batch has finished.
    func enqueue(_ work: @escaping @Sendable () async -> Void) {
        let previous = tail
        tail = Task.detached(priority: .utility) {
            await previous?.value
            await work()
        }
    }

    /// Resolves once everything queued so far has run (tests).
    func drain() async {
        await tail?.value
    }
}
