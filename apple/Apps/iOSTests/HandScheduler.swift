import HassCore

/// A scheduler a test fires by hand.
@MainActor
final class HandScheduler: RevertScheduler {
    final class Item: ScheduledWork {
        let delay: Duration
        let work: @MainActor () -> Void
        var cancelled = false
        init(delay: Duration, work: @escaping @MainActor () -> Void) { self.delay = delay; self.work = work }
        func cancel() { cancelled = true }
    }

    var items: [Item] = []
    var pending: [Item] { items.filter { !$0.cancelled } }

    func schedule(after delay: Duration, _ work: @escaping @MainActor () -> Void) -> any ScheduledWork {
        let item = Item(delay: delay, work: work)
        items.append(item)
        return item
    }

    func fire() {
        for item in pending { item.cancelled = true; item.work() }
    }
}
