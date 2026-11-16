#if os(iOS)
import Observation

/// An observable stamp for the renderer's navigation busy state.
///
/// Whether an authored action is enabled depends on state UIKit owns and does not publish: a modal in flight,
/// a stack transition, a hand-off, a presented alert. The renderer bumps ``revision`` whenever one of those
/// changes, and ``UKServerUIRenderer/isEnabled(_:from:)`` reads it, so a bar item or button that observes its
/// enabled state is re-evaluated when navigation settles instead of keeping a stale answer.
@MainActor
@Observable
final class UKServerUIBusyState {
    /// Increases on every change of the busy inputs; its value carries no meaning.
    private(set) var revision = 0

    /// Records that a busy input changed.
    func changed() { revision &+= 1 }
}
#endif
