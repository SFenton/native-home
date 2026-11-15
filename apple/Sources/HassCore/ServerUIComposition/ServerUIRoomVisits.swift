import Foundation
import Observation

// MARK: - Pinned visit command lifetime

/// Keeps accepted visit commands alive after their source sheet closes.
@MainActor
@Observable
public final class ServerUIRoomVisits {
    public private(set) var pendingCount = 0
    @ObservationIgnored private let caller: any HassServiceCalling
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    /// Creates a server uiroom visits.
    public init(caller: any HassServiceCalling) { self.caller = caller }

    /// Starts only after navigation accepted the choice. Errors go to the host, never to a successful fallback.
    public func record(_ call: ServiceCall, onError: @escaping @MainActor (any Error) -> Void) {
        let id = UUID(), caller = caller
        pendingCount += 1
        tasks[id] = Task { [self] in
            defer { pendingCount -= 1; tasks[id] = nil }
            do { try await caller.call(call) }
            catch { onError(error) }
        }
    }

    /// Fixture callers can deterministically await all accepted visits.
    public func waitForCalls() async {
        for task in Array(tasks.values) { await task.value }
    }
}
