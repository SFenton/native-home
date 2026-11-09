#if os(iOS)
import HassDesign
import UIKit

/// The one animation of a posture change (partly folded <-> lying flat on the iPhone Duo; owner 2026-11-01): layouts that read the
/// fold (grids, panes, splits, centred objects) reflow with ``MotionTokens/standard`` instead of jumping, and with Reduce Motion
/// the old picture cross-fades into the new in 0.2 s.
///
/// The fold is written once, in ``UKDeviceSignals/refresh()``. Observers apply it on the next turn of the run loop and mark their
/// views for layout; ``commit(_:before:)`` then lays the whole tree out inside the animation, one turn after those observers have
/// run. Nothing writes a layout input from a layout pass, so the animation cannot feed back (`FENTON_LAYOUT_CENSUS=1` confirms).
@MainActor
enum UKReflow {
    /// Before the fold is written: with Reduce Motion, a snapshot of `host` laid over it for the cross-fade; otherwise nil.
    static func begin(_ host: UIView) -> UIView? {
        guard UKMotion.reduceMotion, let snapshot = host.snapshotView(afterScreenUpdates: false) else { return nil }
        snapshot.frame = host.bounds
        snapshot.isUserInteractionEnabled = false
        snapshot.accessibilityElementsHidden = true
        host.addSubview(snapshot)
        return snapshot
    }

    /// After the fold is written: animates the reflow.
    static func commit(_ host: UIView, before snapshot: UIView?) {
        // Behind the observation hop (a main-queue task, then a run-loop block) that applies the new fold to the views.
        DispatchQueue.main.async {
            RunLoop.main.perform {
                MainActor.assumeIsolated {
                    if let snapshot {
                        host.layoutIfNeeded()
                        UIView.animate(withDuration: MotionTokens.stateReducedDuration, delay: 0, options: [.curveEaseInOut]) {
                            snapshot.alpha = 0
                        } completion: { _ in snapshot.removeFromSuperview() }
                    } else {
                        UKMotion.animate(.standard) { host.layoutIfNeeded() }
                    }
                }
            }
        }
    }
}
#endif
