#if os(iOS)
import HassCore
import UIKit

// MARK: - What a map button shows now (`sh.surface-controls@1`)

/// Decides each authored map button's state and runs its action, for one configured map.
///
/// A button follows the rules of the thing it does:
/// - **Locate** shows only while the robot is available, as it always has.
/// - **A source command** reuses the state rules of the command tiles: shown only when the vacuum offers it, dimmed while it is blocked, and the
///   reason spoken as its VoiceOver value (`VacuumController.Action.detail`).
/// - **A service call or navigation** follows its own `visibleWhen` and `enabledWhen`, and a symbol or label that follows a rule
///   (`sh.tile-disc-rules@1`), through the renderer's reader like a tile's buttons.
///
/// `item(_:)` reads the stores it needs, so call it inside an observation: what it reads re-runs the caller.
@MainActor
final class UKServerUIMapControls {
    private weak var source: UKServerUIVacuumSource?
    private weak var page: UKServerUIPage?
    /// The view a navigation or a call is sent from.
    weak var sender: UIView?
    /// The last answers, so `whenUnknown: keep` repeats them and a rule that is still loading keeps what was shown.
    private var memory = UKServerUILayoutMemory()
    private let owner: String

    init(source: UKServerUIVacuumSource?, page: UKServerUIPage, owner: String) {
        self.source = source
        self.page = page
        self.owner = owner
    }

    // MARK: State

    /// The button as it draws now, or `nil` while it is hidden.
    func item(_ button: ServerUIMapControlButton) -> UKMapControlItem? {
        guard let source, let controller = source.controller, let page, let renderer = page.renderer else { return nil }
        let reader = renderer.reader()
        var enabled = true
        var value: String?
        switch button.action {
        case .locate:
            guard controller.status.primaryAvailable else { return nil }
        case .sourceCommand(let kind):
            // Offered, or not drawn at all; blocked, or dimmed with the reason.
            guard let action = source.command(kind) else { return nil }
            enabled = !action.isDisabled
            value = action.detail
        case .perform:
            let key = "map:" + button.id
            let visible = button.look.visibility?.isShown(reader, previous: memory.discs[key]) ?? true
            memory.discs[key] = visible
            guard visible else { return nil }
            enabled = renderer.enabledMemory.isEnabled(button.look.enabledWhen, id: "\(owner):\(button.id)", in: reader)
            if enabled, case .perform(let action) = button.action { enabled = renderer.isEnabled(action, from: page) }
            if !enabled { value = "Not available right now" }
        }
        // A rule that is still loading keeps what the button last showed; one that cannot answer shows its own `otherwise` (the authored words).
        let symbol = button.look.resolvedIcon(in: reader, keeping: memory.discSymbols[button.id])
        var text = memory.discLabelText[button.id] ?? ServerUITextMemory()
        let label = button.look.resolvedLabel(read: { renderer.bindings.textResult($0) }, in: reader,
                                              keeping: memory.discLabels[button.id], memory: &text)
        memory.discLabelText[button.id] = text
        memory.discSymbols[button.id] = symbol
        memory.discLabels[button.id] = label
        return UKMapControlItem(id: button.id, symbol: ServerUISymbolFallback.resolve(symbol.name), label: label, hint: button.hint,
                                value: value, identifier: button.identifier, isEnabled: enabled)
    }

    // MARK: Actions

    /// Runs what the button does. A tap on a button that has gone away since it was drawn does nothing.
    func press(_ button: ServerUIMapControlButton) {
        guard let source else { return }
        switch button.action {
        case .locate:
            guard source.controller?.status.primaryAvailable == true, source.controller?.services?.contains("vacuum.locate") == true else {
                source.fail("Locate is unavailable.")
                return
            }
            source.controller?.locate()
        case .sourceCommand(let kind):
            source.run(kind)
        case .perform(let action):
            guard let page, let renderer = page.renderer else { return }
            renderer.activate(action, from: page, source: sender, site: button.identifier)
        }
    }
}
#endif
