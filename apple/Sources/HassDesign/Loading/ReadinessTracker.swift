import Observation

/// Collects which pieces of content inside a ``ContentGate`` are still loading (pattern:
/// `.agents/patterns/content-gate.md`).
///
/// Content reports itself with ``SwiftUICore/View/contentReadiness(_:isReady:)``; ``CachedImage`` does so
/// automatically, so a gated page waits for the images on screen as well as its data.
@MainActor
@Observable
public final class ReadinessTracker {
    /// Ids of content that has reported and is not ready yet.
    public private(set) var pending: Set<String> = []

    /// Creates an empty tracker.
    public init() {}

    /// Whether every reported piece of content is ready.
    public var isSettled: Bool { pending.isEmpty }

    /// Records whether `id` is ready.
    public func set(_ id: String, ready: Bool) {
        if ready {
            if pending.contains(id) { pending.remove(id) }
        } else if !pending.contains(id) {
            pending.insert(id)
        }
    }
}
