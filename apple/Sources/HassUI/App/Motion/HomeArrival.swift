import HassDesign
import Observation
import SwiftUI

/// The state of a moment's entrance while it plays: today only Home's arrival after a sign-in (owner, 2026-10-17;
/// `.agents/design/direction-g.md`, "Launch and sign-in motion"). The sign-in layer lifts away while the house backdrop fades in
/// and settles, then the header, the status chips, the cards and the tab bar come in one after another, about 0.9 s in all.
///
/// One instance lives in the root and goes into the environment. Elements read ``isRevealed``; while no arrival is under way it
/// is true, so a relaunch, a reconnect or a tab switch animates nothing and the views keep their identity. Each element animates
/// itself with ``SwiftUICore/View/arrivalMotion(_:kind:index:)``, which is the identity when there is no instance in the
/// environment (galleries, previews). The root starts the arrival only while ``MotionPolicy`` says the moment has not played.
@MainActor
@Observable
public final class HomeArrival {
    /// The moment this state drives.
    public let moment: Moment = .signInArrival
    /// Whether an arrival is under way (the elements are held back until ``reveal()``).
    public private(set) var isActive = false
    /// Whether the elements are in place. True whenever no arrival is under way.
    public private(set) var isRevealed = true

    /// How long the whole arrival takes, from ``begin()`` to ``finish()``.
    public nonisolated static let duration: Duration = .milliseconds(900)

    /// Creates the arrival, at rest.
    public init() {}

    /// Holds the elements back; call before the signed-in views are created.
    public func begin() {
        isActive = true
        isRevealed = false
    }

    /// Lets the held-back elements animate into place.
    public func reveal() {
        isRevealed = true
    }

    /// Ends the arrival.
    public func finish() {
        isActive = false
        isRevealed = true
    }

    /// The delay before the element at `index` rises: its place in the stagger, after the chips have started.
    public nonisolated static func riseDelay(index: Int) -> TimeInterval {
        MotionTokens.Arrival.firstDelay + Double(min(max(index, 0), MotionTokens.Arrival.staggerLimit)) * MotionTokens.arrivalStagger
    }
}
