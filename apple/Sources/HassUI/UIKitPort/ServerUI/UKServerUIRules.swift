#if os(iOS)
import UIKit
import HassCore

// MARK: - Rules on controls and actions (`sh.enabled-when@1`, `sh.action-rules@1`)

/// A reader that knows nothing: every source is unavailable. A text slot read before a renderer exists draws as unavailable.
struct UKEmptyReading: ServerUIReading {
    var viewer: ServerUIViewer? { nil }
    func read(sourceId: String, path: [String]) -> ServerUIReadResult { .unavailable }
    func viewerPersonState() -> ServerUIReadResult { .unavailable }
}

/// The last answer of every `enabledWhen`, by node id, so `keep` repeats it while the condition cannot be answered.
@MainActor
final class UKEnabledMemory {
    private var answers: [String: Bool] = [:]

    /// Evaluates `rule` for the node `id`, remembers the answer when the condition gave one, and returns it.
    func isEnabled(_ rule: ServerUIEnabledRule?, id: String, in environment: some ServerUIReading) -> Bool {
        guard let rule else { return true }
        let answer = rule.isEnabled(previous: answers[id], in: environment)
        if rule.condition.evaluate(environment) != .unknown { answers[id] = answer }
        return answer
    }
}

extension UKServerUIRenderer {
    /// Whether the node's own `enabledWhen` lets it act now. Call it inside an observation: the entities it reads re-run the caller.
    func isEnabled(node: ServerUICompositionDocument.Node) -> Bool {
        enabledMemory.isEnabled(node.enabledWhen, id: node.id, in: reader())
    }
}
#endif
