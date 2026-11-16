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

    private struct Kept {
        let session: ServerUIFlowSession
        /// What the session's host reads besides the flow (see ``collections(for:window:start:hostKey:host:)``).
        let hostKey: [String: String]
    }

    private var windows: [UUID: [String: Kept]] = [:]

    /// The collections of the document's row flows for `window`, keyed by source id, with their sessions started when `start`.
    ///
    /// `hostKey` stands for what the host reads besides the flow (the entities its `ha-entity` sources name): a session built for another key is
    /// replaced, so a republish that moves a source to another entity never leaves a flow reading the old one.
    func collections(for document: D, window: UUID, start: Bool, hostKey: [String: String] = [:],
                     host: () -> ServerUIFlowHost) -> [String: ServerUIRowCollection] {
        var current = windows[window] ?? [:]
        var kept: [String: Kept] = [:]
        for source in document.dataSources {
            guard case .pipeline(let id, let flow) = source, flow.givesRows else { continue }
            let existing = current.removeValue(forKey: id)
            if let existing, existing.session.flow == flow, existing.hostKey == hostKey {
                kept[id] = existing
            } else {
                // A flow that changed (or reads other entities now) ends its session before the next one begins.
                existing?.session.stop()
                kept[id] = Kept(session: ServerUIFlowSession(flow: flow, collection: ServerUIRowCollection(), host: host()), hostKey: hostKey)
            }
        }
        for stale in current.values { stale.session.stop() }
        windows[window] = kept
        if start { for entry in kept.values { entry.session.start() } }
        return kept.mapValues(\.session.collection)
    }

    /// The session of a flow, for a pull to refresh.
    func session(_ id: String, window: UUID) -> ServerUIFlowSession? { windows[window]?[id]?.session }

    /// Stops a window's flows.
    func detach(_ window: UUID) {
        for entry in windows.removeValue(forKey: window)?.values ?? [:].values { entry.session.stop() }
    }

    /// Stops every flow (the session ended).
    func endSession() {
        for entry in windows.values.flatMap(\.values) { entry.session.stop() }
        windows.removeAll()
    }
}
#endif
