#if os(iOS)
import Foundation
import HassCore

// MARK: - Data Flows of a window

/// The Data Flows (`sh.pipeline@1`) of each window: one ``ServerUIFlowSession`` per flow that gives rows, and the collection it fills.
///
/// A session is kept while its flow stays in the publication and is replaced when the flow changes; the collection object is what the
/// list draws, so a republish that leaves a flow alone never blanks its rows. The validating window never starts a session.
@MainActor
final class UKServerUIFlowWindows {
    typealias D = ServerUICompositionDocument

    private var windows: [UUID: [String: ServerUIFlowSession]] = [:]

    /// The collections of the document's row flows for `window`, keyed by source id, with their sessions started when `start`.
    func collections(for document: D, window: UUID, start: Bool, host: () -> ServerUIFlowHost) -> [String: ServerUIRowCollection] {
        var current = windows[window] ?? [:]
        var kept: [String: ServerUIFlowSession] = [:]
        for source in document.dataSources {
            guard case .pipeline(let id, let flow) = source, flow.givesRows else { continue }
            if let existing = current.removeValue(forKey: id), existing.flow == flow {
                kept[id] = existing
            } else {
                current[id]?.stop()
                kept[id] = ServerUIFlowSession(flow: flow, collection: ServerUIRowCollection(), host: host())
            }
        }
        for stale in current.values { stale.stop() }
        windows[window] = kept
        if start { for session in kept.values { session.start() } }
        return kept.mapValues(\.collection)
    }

    /// The session of a flow, for a pull to refresh.
    func session(_ id: String, window: UUID) -> ServerUIFlowSession? { windows[window]?[id] }

    /// Stops a window's flows.
    func detach(_ window: UUID) {
        for session in windows.removeValue(forKey: window)?.values ?? [:].values { session.stop() }
    }

    /// Stops every flow (the session ended).
    func endSession() {
        for session in windows.values.flatMap(\.values) { session.stop() }
        windows.removeAll()
    }
}
#endif
