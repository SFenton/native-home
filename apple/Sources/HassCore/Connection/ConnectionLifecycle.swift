import Foundation
import HassTelemetry

/// Maps app scene phases to connection actions so reopening the app never reloads it.
///
/// See `.agents/platforms/apple/connection-lifecycle.md`.
@MainActor
public final class ConnectionLifecycle {
    /// How long the socket stays open after the app leaves the foreground (30 s).
    ///
    /// DEBUG builds only: `FENTON_BACKGROUND_GRACE_SECONDS=<n>` shortens it so a journey can prove the
    /// torn-down-socket resume without waiting out 30 s. Release builds always use the default.
    public static var backgroundGrace: Duration {
        #if DEBUG
        resolveGrace(environment: ProcessInfo.processInfo.environment, debugBuild: true)
        #else
        resolveGrace(environment: [:], debugBuild: false)
        #endif
    }

    /// The default grace.
    static let defaultGrace: Duration = .seconds(30)

    /// The grace for `environment`: the override is honoured only in a debug build and only when it is a positive number.
    static func resolveGrace(environment: [String: String], debugBuild: Bool) -> Duration {
        guard debugBuild, let text = environment["FENTON_BACKGROUND_GRACE_SECONDS"],
              let seconds = Double(text), seconds > 0 else { return defaultGrace }
        return .seconds(seconds)
    }

    private let connection: HassConnection
    private var disconnectTask: Task<Void, Never>?
    private var census: ResourceCensus.Registration?

    /// Creates a lifecycle controller for a connection.
    public init(connection: HassConnection) {
        self.connection = connection
        census = ResourceCensus.shared.register { [weak self] in self?.liveResources ?? [:] }
    }

    /// What the lifecycle holds right now (`ResourceCensus`).
    var liveResources: [String: Int] { ["Lifecycle.pendingDisconnect": disconnectTask == nil ? 0 : 1] }

    /// The app became active: cancel any pending disconnect and make sure we're connected.
    public func didBecomeActive() {
        disconnectTask?.cancel()
        disconnectTask = nil
        connection.connect()
    }

    /// The app went to the background: save now, disconnect after the grace period.
    public func didEnterBackground() {
        connection.saveSnapshotNow()
        connection.didEnterBackground()
        disconnectTask?.cancel()
        disconnectTask = Task { [connection] in
            try? await Task.sleep(for: Self.backgroundGrace)
            guard !Task.isCancelled else { return }
            connection.disconnect()
        }
    }
}
