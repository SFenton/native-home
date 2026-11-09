import HassCore

/// Runs scheduled work (optimistic reverts, holds) only when a test says so.
@MainActor
public final class ManualScheduler: RevertScheduler {
    /// One scheduled piece of work.
    public final class Item: ScheduledWork {
        public let delay: Duration
        /// The scheduled work; ``ManualScheduler/fireAll()`` runs it.
        public let work: @MainActor () -> Void
        public var cancelled = false

        init(delay: Duration, work: @escaping @MainActor () -> Void) {
            self.delay = delay
            self.work = work
        }

        public func cancel() { cancelled = true }
    }

    public var items: [Item] = []

    public init() {}

    public func schedule(after delay: Duration, _ work: @escaping @MainActor () -> Void) -> any ScheduledWork {
        let item = Item(delay: delay, work: work)
        items.append(item)
        return item
    }

    /// Live (not cancelled, not yet run) items.
    public var pending: [Item] { items.filter { !$0.cancelled } }

    /// Runs every live item.
    public func fireAll() {
        let live = pending
        for item in live {
            item.cancelled = true
            item.work()
        }
    }
}
