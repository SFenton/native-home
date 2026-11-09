#if os(iOS)
import HassCore
import HassDesign
import UIKit

/// What the window knows about the iPhone Duo's hinge and vertical bar: the UIKit counterparts of ``DeviceSignalsProbe`` and
/// ``WindowHingeReader`` (iOS 27.1 SDK APIs; older SDKs and systems report nothing, as the SwiftUI code does).
///
/// - The hinge's frame in window coordinates (`UIView.reservedRegions(kind: .division)`, the active region, else the first inactive
///   one), published as ``UKShellEnvironment/windowHinge`` so the sign-in form and the hinged panes move off it.
/// - Whether the system moved the bar items into a vertical bar (`UITraitCollection.verticalBarEdge`), published as
///   ``UKShellEnvironment/inVerticalBar``: the header leaves out its fixed spacer there.
/// - ``HingePresence``: the first hinge ever seen asks UIKit to re-read the supported orientations (a Duo rotates freely).
@MainActor
final class UKDeviceSignals {
    private weak var view: UIView?
    private let environment: UKShellEnvironment
    private var lastSize: CGSize = .zero

    init(view: UIView, environment: UKShellEnvironment) {
        self.view = view
        self.environment = environment
        #if !FENTON_IOS_SDK_BEFORE_27_1
        if #available(iOS 27.1, *) {
            view.addInteraction(UIHingeInteraction { [weak self] _, update in
                self?.hingeChanged(update.hinge.map { Self.hingeState($0.status) })
            })
        }
        #endif
    }

    #if !FENTON_IOS_SDK_BEFORE_27_1
    @available(iOS 27.1, *)
    static func hingeState(_ status: UIHinge.Status) -> HingeState {
        switch status {
        case .closed: .closed
        case .fullyOpen: .fullyOpen
        default: .partiallyOpen
        }
    }
    #endif

    /// The hinge interaction reported a hinge (or none): the first one ever seen asks UIKit to re-read the supported orientations.
    func hingeChanged(_ state: HingeState?) {
        HingePresence.shared.record(hinge: state)
        // A posture change (partly folded <-> flat) may not run a layout pass: read the fold again on the next turn.
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    /// Reads the signals; call from the owner's `viewDidLayoutSubviews` (and it runs again from the hinge interaction's update).
    ///
    /// The fold is published in both forms (``WindowFold``, owner 2026-11-01): ``UKShellEnvironment/windowFold`` for presence (the shell
    /// style, sheets) and ``UKShellEnvironment/windowHinge`` as the band only, set while partly folded, so a flat Duo avoids nothing.
    /// A change at an unchanged window size (a posture change, not a rotation) reflows with the standard spring
    /// (``UKReflow``); the write happens here, once, and the animation runs a turn later, outside layout.
    func refresh() {
        guard let view else { return }
        let fold = Self.fold(in: view)
        if fold != environment.windowFold {
            UKLayoutCensus.note("fold \(String(describing: environment.windowFold)) -> \(String(describing: fold)) in \(view.bounds.size)")
            let posture = environment.windowFold.hinge != nil && fold.hinge != nil && lastSize == view.bounds.size
            let before = posture ? UKReflow.begin(view) : nil
            environment.windowFold = fold
            environment.windowHinge = fold.band
            UKHinge.publish(fold)
            if posture { UKReflow.commit(view, before: before) }
        }
        lastSize = view.bounds.size
        let bar = Self.hasVerticalBar(view.traitCollection)
        if bar != environment.inVerticalBar {
            UKLayoutCensus.note("bar -> \(bar) in \(view.bounds.size)")
            environment.inVerticalBar = bar
            HingePresence.shared.record(hinge: nil, hasVerticalBar: bar)
        }
    }

    /// The hinge's frame in `view`'s coordinate space, in either pose (presence; see ``fold(in:)``).
    static func hinge(in view: UIView) -> CGRect? { fold(in: view).hinge }

    /// The window's fold in `view`'s coordinate space: the hinge's division region, and whether it is active (partly folded). A flat Duo reports its (inactive) hinge to the app's own
    /// views but not to a window or a presentation's transition view, so a view with no answer asks the window's root view and
    /// converts the frame (a sheet's container needs the hinge for the placement and the full-height rule).
    static func fold(in view: UIView) -> WindowFold {
        // The app's root view is the one that tells the poses apart: a window (and a presentation's views) report the hinge as active
        // whatever the pose (measured 2026-11-01: a flat Duo's window read `isFolding` while the root view read it inactive).
        if let window = view.window ?? (view as? UIWindow), let root = window.rootViewController?.view, root !== view,
           let reported = reportedFold(in: root), let frame = reported.hinge {
            return WindowFold(hinge: view.convert(frame, from: root), isFolding: reported.isFolding)
        }
        return reportedFold(in: view) ?? .none
    }

    /// What the window reserves as the hinge, with its frame and whether it is active (partly folded). A hosted test replaces this to
    /// stand in for a Duo; nil (always, outside tests) asks the system.
    nonisolated(unsafe) static var regionsOverride: ((UIView, _ includeInactive: Bool) -> [(frame: CGRect, isActive: Bool)])?

    private static func regions(in view: UIView, includeInactive: Bool) -> [(frame: CGRect, isActive: Bool)] {
        if let regionsOverride { return regionsOverride(view, includeInactive) }
        #if !FENTON_IOS_SDK_BEFORE_27_1
        if #available(iOS 27.1, *) {
            return view.reservedRegions(kind: .division, options: includeInactive ? [.includeInactive] : []).map { ($0.frame, $0.isActive) }
        }
        #endif
        return []
    }

    private static func reportedFold(in view: UIView) -> WindowFold? {
        if let active = regions(in: view, includeInactive: false).first(where: \.isActive) { return WindowFold(hinge: active.frame, isFolding: true) }
        if let flat = regions(in: view, includeInactive: true).first { return WindowFold(hinge: flat.frame, isFolding: false) }
        return nil
    }

    /// The window's width less the trailing vertical bar (the rail): the space a flat page divides at its midpoint.
    static func freeWidth(in window: UIWindow) -> CGFloat {
        window.bounds.width - railWidth(in: window)
    }

    /// The width the system's trailing vertical bar takes; zero without one.
    static func railWidth(in window: UIWindow) -> CGFloat {
        guard hasVerticalBar(window.traitCollection) else { return 0 }
        return window.safeAreaInsets.right
    }

    /// A hosted test replaces this to stand in for the Duo's vertical bar.
    nonisolated(unsafe) static var verticalBarOverride: ((UITraitCollection) -> Bool)?

    static func hasVerticalBar(_ traits: UITraitCollection) -> Bool {
        if let verticalBarOverride { return verticalBarOverride(traits) }
        #if !FENTON_IOS_SDK_BEFORE_27_1
        if #available(iOS 27.1, *) { return traits.verticalBarEdge != .unspecified }
        #endif
        return false
    }
}
#endif
