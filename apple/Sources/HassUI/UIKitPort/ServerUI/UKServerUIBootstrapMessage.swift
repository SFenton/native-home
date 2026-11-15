#if os(iOS)
import HassCore
import UIKit

// MARK: - Authored read-only bootstrap state

/// Uses the canonical wrapping, Dynamic Type and accessibility state component without a feature controller.
@MainActor
final class UKServerUIBootstrapMessage: UIView {
    private var definition: ServerUICompositionDocument.BootstrapMessage?
    private var message: UKStateMessageView?

    func apply(_ value: ServerUICompositionDocument.BootstrapMessage) {
        guard value != definition else { return }
        definition = value
        message?.removeFromSuperview()
        let state = UKStateMessageView(symbol: value.icon.drawn, title: value.node.title,
                                      message: value.message, identifier: value.node.id)
        addSubview(state)
        state.ukPin(to: self)
        message = state
    }
}
#endif
