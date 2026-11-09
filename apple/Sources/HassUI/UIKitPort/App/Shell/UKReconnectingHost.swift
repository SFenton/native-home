#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// Drives the quiet arc left of Quick Links while the connection is retrying: the UIKit counterpart of
/// ``ReconnectingIndicatorHost``. A task per state, cancelled when the state changes, so a blip never shows the arc and coming
/// back mid-fade-out lights it again where it is; the first connect has no delay (the pills already read "Loading"). The arc
/// is silent for anyone not looking at it, so a change is announced.
@MainActor
final class UKReconnectingHost {
    let indicator = ReconnectingIndicator()
    private weak var connection: HassConnection?
    private let bag = UKObservationBag()
    private var task: Task<Void, Never>?
    private var last: Following?
    private var lastLit: Bool?

    private struct Following: Equatable {
        var isRetrying: Bool
        var awaitingFirstState: Bool
    }

    init(connection: HassConnection?) {
        self.connection = connection
        bag.observe { [weak self] in
            guard let self else { return }
            let awaiting = !(self.connection?.store.hasReceivedFirstState ?? true)
            let retrying: Bool
            if let status = self.connection?.status {
                retrying = ReconnectingPolicy.showsArc(status, isOffline: self.connection?.isOffline ?? false, hasReceivedFirstState: !awaiting)
            } else {
                retrying = false
            }
            self.follow(Following(isRetrying: retrying, awaitingFirstState: awaiting))
        }
        bag.observe { [weak self] in
            guard let self else { return }
            let lit = self.indicator.isLit
            defer { self.lastLit = lit }
            guard let last = self.lastLit, last != lit else { return }
            Announcer.announce(ReconnectingIndicatorHost.announcement(isLit: lit, isFirstConnect: self.indicator.isFirstConnect))
            if !lit { self.indicator.isFirstConnect = false }
        }
    }

    private func follow(_ state: Following) {
        guard state != last else { return }
        last = state
        task?.cancel()
        let indicator = indicator
        task = Task {
            if state.awaitingFirstState { indicator.isFirstConnect = true }
            await indicator.follow(isDown: state.isRetrying, delay: state.awaitingFirstState ? .zero : ReconnectingPolicy.delay)
        }
    }
}
#endif
