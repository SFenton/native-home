#if os(iOS)
import HassCore

// MARK: - Kept text on a retained node (sh.text-keep@1)

/// The last answers of one node's text slots, so a `keep` slot (`sh.text-keep@1`) still draws its text after the node is drawn again.
///
/// A node is bound again on every publication update, content-size change and layout-direction change; the node itself is retained, so the
/// memories live on it (``UKServerUINode/textMemories``), keyed by slot name, beside ``UKServerUINode/layoutMemory``. A memory is written
/// only for a `keep` slot, inside the evaluation that already runs, so nothing here grows with the house.
@MainActor
final class UKServerUITextMemories {
    private var slots: [String: ServerUITextMemory] = [:]

    /// The text slot `value` gives now, drawing the slot's last answer while its value is unavailable and the slot is `keep`.
    ///
    /// - Parameters:
    ///   - value: The slot's authored value.
    ///   - slot: The slot's name on the node (for example `"subtitle"` or `"center.0"`); one memory per name.
    ///   - bindings: The reader of the house.
    func string(_ value: ServerUICompositionDocument.StringValue, slot: String, bindings: UKServerUIBindings) -> UKServerUIValue<String> {
        var memory = slots[slot] ?? ServerUITextMemory()
        let result = bindings.string(value, memory: &memory)
        slots[slot] = memory
        return result
    }
}
#endif
