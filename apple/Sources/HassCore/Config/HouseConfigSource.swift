import Foundation
import Observation

/// The one place the `*Config` facades read the server's house document from.
///
/// **The facade pattern.** A house value (a status chip list, an entity id, a camera) is a computed `static var` on a
/// `*Config` enum that answers `HouseConfigSource.active.read { $0.<section>.<value> } ?? <empty>`. The app compiles in no
/// house data: with no document a facade answers an empty value (an empty string or list, a placeholder with no
/// entities), and a page that depends on the layout draws the skeleton or message (`HouseLayoutState`) instead of
/// content. Call sites do not change. Rules: no `static let` that reads a facade, no index subscript on a server-provided
/// array (`.first`, a lookup or a count guard), and always read through ``active``, never ``shared``.
///
/// **Who writes.** ``HouseConfigStore`` pushes every document it accepts (the cache first, then each server change)
/// and clears it at sign-out. Nothing else writes today. Widgets and Live Activities, once one reads a facade, call
/// ``seed(from:for:)`` once with the app-group ``HouseConfigCache`` (future work; no caller yet). The Watch cannot read
/// the iPhone's app-group container, so it has no house layout until it gets its own source.
///
/// **Who observes.** ``read(_:)`` and ``current`` register with Observation, so a UIKit `updateProperties()` or a
/// `withObservationTracking` block that reads a facade is re-run when the document changes, like any
/// ``EntityStore`` box. Reads and writes are thread-safe; ``read(_:)`` projects inside the lock and never copies the
/// whole document out.
///
/// **Tests.** The facades read ``active``: ``shared`` unless a task-local ``scoped`` source is set. A synchronous test
/// runs its body in `HouseConfigSource.$scoped.withValue(source) { ... }`, so parallel tests never see each other's
/// document and never touch ``shared``. The scope does **not** survive a main-queue hop, a UIKit observation re-run
/// or an `onChange` re-read, which run outside it and read ``shared``: a hosted test of a live update on a built screen
/// must inject a source (or use a serialized suite that sets and restores ``shared``). ``HouseConfigStore`` takes an
/// optional source and uses ``shared`` only when the app hands it in.
public final class HouseConfigSource: Observable, @unchecked Sendable {
    /// The source the facades read.
    public static let shared = HouseConfigSource()

    /// A source that replaces ``shared`` for the current task and its children (tests).
    @TaskLocal public static var scoped: HouseConfigSource?

    /// What the facades read: ``scoped`` when set, else ``shared``.
    public static var active: HouseConfigSource { scoped ?? shared }

    private let registrar = ObservationRegistrar()
    private let lock = NSLock()
    private var document: HouseConfig?

    /// Creates an empty source (the facades answer empty).
    public init() {}

    /// Projects a value out of the server's document, registering with Observation.
    ///
    /// This is what the facades call: `HouseConfigSource.active.read { $0.home.cameras } ?? []`.
    /// - Parameter project: Picks the value; runs under the lock, so keep it a plain property path.
    /// - Returns: The value, or `nil` when there is no document.
    public func read<T>(_ project: (HouseConfig) -> T) -> T? {
        registrar.access(self, keyPath: \.current)
        return lock.withLock { document.map(project) }
    }

    /// The server's document, or `nil` when there is none. Copies the whole document;
    /// facades use ``read(_:)``.
    public var current: HouseConfig? {
        registrar.access(self, keyPath: \.current)
        return lock.withLock { document }
    }

    /// Replaces the document, notifying observers when it changed.
    /// - Parameter config: The new document, or `nil` to clear it (sign-out).
    public func set(_ config: HouseConfig?) {
        guard lock.withLock({ document != config }) else { return }
        registrar.withMutation(of: self, keyPath: \.current) {
            lock.withLock { document = config }
        }
    }

    /// Fills the source from the app-group cache for a process without a store (a widget or Live Activity extension).
    /// No caller yet: the first extension that reads a flipped facade adds one.
    /// - Parameters:
    ///   - cache: The shared cache file.
    ///   - server: The signed-in server the file must belong to.
    public func seed(from cache: HouseConfigCache = .init(), for server: HassServer) {
        if let loaded = cache.load(for: server) { set(loaded.config) }
    }
}
