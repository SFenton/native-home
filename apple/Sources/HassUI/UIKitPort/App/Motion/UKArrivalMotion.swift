#if os(iOS)
import HassDesign
import UIKit

/// How an element comes in as Home arrives (``SwiftUICore/View/arrivalMotion(_:kind:index:)``): held back (transparent, and 16 pt
/// below or 30 pt to the right of its place) while the arrival is under way, then fading in and moving into place when it is
/// revealed, staggered by `index`. When no arrival is under way (a relaunch, a reconnect, a tab switch) it is simply there and
/// nothing animates. Reduce Motion keeps a cross-fade and drops the movement.
@MainActor
enum UKArrivalMotion {
    /// Plays `moment`'s entrance for `view`. Keep `bag` for as long as the view lives (a page's or a cell's bag).
    /// - Parameters:
    ///   - view: The element.
    ///   - shell: ``UKContext/shell``; nil outside the shell, where nothing arrives.
    ///   - moment: The moment the element belongs to (Home's arrival after a sign-in).
    ///   - kind: `.rise` (cards, tiles) or `.slideIn` (status chips).
    ///   - index: Its place in the 60 ms stagger (`.rise`).
    ///   - bag: Where the observation lives.
    static func apply(to view: UIView, shell: UKShellEnvironment?, moment: Moment = .signInArrival, kind: ArrivalKind = .rise, index: Int = 0,
                      bag: UKObservationBag) {
        var previous: Bool?
        bag.observe { [weak view] in
            guard let view else { return }
            // Held back only while this moment's arrival is under way; at all other times the element is simply there.
            let shown = shell?.arrival.map { $0.moment != moment || $0.isRevealed } ?? true
            let reduceMotion = shell?.reduceMotion ?? UIAccessibility.isReduceMotionEnabled
            let offset: CGAffineTransform
            switch kind {
            case .rise: offset = CGAffineTransform(translationX: 0, y: MotionTokens.Arrival.riseDistance)
            case .slideIn: offset = CGAffineTransform(translationX: MotionTokens.Arrival.slideDistance, y: 0)
            }
            let held: CGAffineTransform = reduceMotion || shown ? .identity : offset
            let apply = {
                view.alpha = shown ? 1 : 0
                view.transform = held
            }
            defer { previous = shown }
            guard let previous, previous != shown, view.window != nil else {
                apply()
                return
            }
            if reduceMotion {
                UIView.animate(withDuration: MotionTokens.crossFadeDuration, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: apply)
                return
            }
            let delay: TimeInterval
            switch kind {
            case .rise: delay = HomeArrival.riseDelay(index: index)
            case .slideIn: delay = MotionTokens.Arrival.slideDelay
            }
            UIView.animate(springDuration: MotionTokens.standardDuration, bounce: 0, initialSpringVelocity: 0, delay: delay,
                           options: [.allowUserInteraction], animations: apply)
        }
    }
}
#endif
