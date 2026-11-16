#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Per-node rules and bound controls

extension UKServerUIPage {
    typealias Rules = ServerUICompositionDocument

    /// Shows or hides one node in place by its `visibleWhen`.
    ///
    /// The node's view is built once and only its `isHidden` changes, so a rule never reloads, re-fades or reorders a screen. The
    /// observation reads exactly the entities the predicate names (and the call runner's pending flag), so one entity change touches
    /// only the nodes that read it. A node is never hidden while a bound control inside it has a call on its way, so a tap in
    /// flight cannot disappear under the finger.
    func observeVisibility(of entry: UKServerUINode, rule: ServerUIVisibility, component: Rules.Component) {
        let guarded = Self.boundControlIDs(in: component)
        entry.bag.observe { [weak self, weak entry] in
            guard let self, let entry, let renderer = self.renderer else { return }
            var shown = rule.isShown(renderer.reader(), previous: entry.shown)
            if !shown, guarded.contains(where: { renderer.callRunner.isBusy(node: $0) }) { shown = true }
            entry.shown = shown
            guard entry.view.isHidden == shown else { return }
            entry.view.isHidden = !shown
            entry.view.ukRemeasureContainers()
            self.body?.contentChanged(animated: false)
            UIAccessibility.post(notification: .layoutChanged, argument: nil)
        }
    }

    /// The ids of every bound control in `component`'s subtree.
    static func boundControlIDs(in component: Rules.Component) -> [String] {
        var ids: [String] = []
        func visit(_ component: Rules.Component) {
            if case .boundControl(let control) = component { ids.append(control.node.id) }
            component.childComponents.forEach(visit)
        }
        visit(component)
        return ids
    }

    /// Binds a `bound-control` node to its canonical control and its authored calls.
    func bindBoundControl(_ control: Rules.BoundControl, entry: UKServerUINode, renderer: UKServerUIRenderer) {
        switch (control.kind, control.surface) {
        case (.button, _):
            guard let wrapper = entry.view as? UKServerUIPrimaryButton, let call = control.action else { return }
            entry.bag.observe { [weak self, weak wrapper, weak renderer] in
                guard let self, let wrapper, let renderer else { return }
                wrapper.button.title = control.node.title
                wrapper.button.accessibilityIdentifier = control.node.id
                wrapper.button.systemImage = control.icon?.drawn
                wrapper.button.isEnabled = renderer.isEnabled(.callService(call), from: self) && renderer.isEnabled(node: control.node)
                wrapper.button.action = { [weak self, weak wrapper] in
                    guard let self else { return }
                    self.renderer?.activate(.callService(call), from: self, source: wrapper?.button, symbol: control.icon?.drawn ?? "",
                                            site: control.node.id)
                }
            }
        case (.toggle, .tile):
            guard let view = entry.view as? UKGlassTileView else { return }
            var first = true
            entry.bag.observe { [weak self, weak view, weak renderer] in
                guard let self, let view, let renderer else { return }
                let reader = renderer.reader()
                let state = control.isOn?.evaluate(reader) ?? .unknown
                let isOn = state == .yes, unknown = state == .unknown
                let busy = renderer.callRunner.isBusy(node: control.node.id)
                let failed = renderer.callRunner.isFailed(node: control.node.id)
                let call = isOn ? control.offAction : control.onAction
                let allowed = renderer.isEnabled(node: control.node)
                let symbol = control.icon?.drawn ?? "power"
                var confirmation: TileActionSpec.Confirmation?
                if let call, call.asksConfirmation(of: reader.viewer, in: reader),
                   case .additional(let style, let title, let message, let confirmLabel, _, let destructive) = call.confirmation {
                    confirmation = .init(title: title, message: message, confirmVerb: confirmLabel, isDestructive: destructive,
                                         style: style == .dialog ? .dialog : .alert)
                }
                let spec = TileActionSpec(id: "toggle", verb: isOn ? "Turn Off" : "Turn On", symbol: symbol, isOn: isOn,
                                          phase: unknown || !allowed ? .unavailable : (busy ? .inFlight : .ready), feedback: .optimistic,
                                          isError: failed, confirmation: confirmation)
                var model = UKGlassTileModel(title: control.node.title, subtitle: unknown ? control.unavailableText : (isOn ? "On" : "Off"),
                                             symbol: symbol, family: .neutral, isActive: isOn, isUnavailable: unknown, isError: failed,
                                             behavior: .perform("toggle"), actions: [spec].items, identifier: control.node.id)
                model.stateCandidates = ["On", "Off", control.unavailableText]
                model.reapplyGeneration = self.context.store.reapplyGeneration
                view.configure(model, environment: UKTileEnvironment(context: self.context), animated: !first, perform: { [weak self, weak view] _ in
                    guard let self, let renderer = self.renderer else { return }
                    let now = control.isOn?.evaluate(renderer.reader()) ?? .unknown
                    guard now != .unknown, renderer.isEnabled(node: control.node), let call = now == .yes ? control.offAction : control.onAction else { return }
                    // The tile already asked the question it was configured with, when the direction has not flipped since.
                    renderer.activate(.callService(call), from: self, source: view, control: .bool(now != .yes),
                                      site: control.node.id + (now == .yes ? "#off" : "#on"), confirmed: (now == .yes) == isOn && confirmation != nil)
                })
                first = false
                view.ukRemeasureContainers()
            }
        default:
            guard let view = entry.view as? UKServerUILocalControl else { return }
            entry.bag.observe { [weak self, weak view, weak renderer] in
                guard let self, let view, let renderer else { return }
                // Read so the shown value is put back when a call ends, whether or not Home Assistant echoed it.
                _ = renderer.callRunner.isBusy(node: control.node.id)
                var binding = UKServerUIBoundBinding(control: control, reader: renderer.reader()) { [weak self, weak view] call, value, slot in
                    guard let self else { return }
                    self.renderer?.activate(.callService(call), from: self, source: view, control: value, site: control.node.id + "#" + slot)
                }
                // A row's own parts: its subtitle follows the house, and its failure words show while the failed face does.
                binding.strings = { renderer.bindings.string($0) }
                binding.failed = renderer.callRunner.isFailed(node: control.node.id)
                view.apply(binding, surface: self.context.surface, enabled: renderer.isEnabled(node: control.node))
            }
        }
    }
}
#endif
