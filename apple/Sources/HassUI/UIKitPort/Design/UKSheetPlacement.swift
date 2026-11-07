#if os(iOS)
import HassDesign
import UIKit

/// Where a sheet sits on the iPhone Duo, and when it fills the height (owner, 2026-10-31: "Modals still opening centered when unfolded").
///
/// **Placement is the system's.** iOS 27 adds `UISheetPresentationController.preferredPlacement` (`.automatic`, `.leading`, `.center`,
/// `.trailing`; "ignored when sourceView is non-nil"). Unfolded in landscape `.automatic` centres a sheet and `.leading` puts it against
/// the left edge; partly folded the system keeps a sheet off the fold whatever is asked; on the folded outer screen and on a phone
/// without a hinge placement changes nothing. So every sheet on a device with a hinge asks for `.leading` (``place(_:in:)``) and
/// iPad and iPhone keep `.automatic` (an iPad sheet stays centred). Source: sarunw.com/posts/presentation-placement-on-iphone-duo/ and
/// the iOS 27.1 SDK header. `.trailing` also moves the controls into the vertical bar and is not wanted. Never set a `sourceView` on a
/// sheet (it cancels the placement); a zoom `preferredTransition` source is not one.
///
/// ```swift
/// configureSheet(sheet)                       // detents, grabber ...
/// UKSheetPlacement.place(sheet, in: window)   // the one placement call every sheet path makes
/// ```
/// **Full height is ours** (``fillsHeight(in:)``, ``DuoSheetPolicy``): the folded Duo or a vertical hinge band. A sheet then takes the large
/// detent only. ``PoseWatch`` tells a presenter when the rule changes under an open sheet (fold, unfold, rotation) so it can
/// `animateChanges` its detents and grabber. Nothing here sets a sheet's width or frame.
@MainActor
enum UKSheetPlacement {
    /// Whether every sheet fills the height now (``DuoSheetPolicy``, owner 2026-10-31): the folded Duo, or landscape beside the
    /// vertical hinge. `view` is any view in the window (the sheet's container, or the presenter's); nil reads the device record only.
    static func fillsHeight(in view: UIView?) -> Bool {
        let hinge = view.flatMap { UKDeviceSignals.hinge(in: $0) }
        return DuoSheetPolicy.fillsHeight(hasHinge: hasHinge(in: view, hinge: hinge), hinge: hinge)
    }

    /// Whether the device has a hinge: one has been reported (``HingePresence``), or `view` sees one.
    static func hasHinge(in view: UIView?) -> Bool {
        hasHinge(in: view, hinge: view.flatMap { UKDeviceSignals.hinge(in: $0) })
    }

    private static func hasHinge(in view: UIView?, hinge: CGRect?) -> Bool {
        if HingePresence.shared.hasHinge || DuoSheetPolicy.deviceHasHinge || hinge != nil { return true }
        // The folded outer screen reports no hinge region, and a cold launch has not always seen a hinge change yet; but its system
        // vertical bar (`verticalBarEdge`) is set on any view of the window, so a sheet asked for before the shell has said so still
        // knows (owner, 2026-10-31: cameras "don't open all the way": they were content-fitted because the device read as hinge-less).
        if let view, UKDeviceSignals.hasVerticalBar(view.traitCollection) {
            HingePresence.shared.record(hinge: nil, hasVerticalBar: true)
            return true
        }
        return false
    }

    /// The size a sheet takes in the leading half beside a vertical hinge (``DuoSheetPolicy/leadingHalfWidth(fold:freeWidth:)``, shared
    /// with the SwiftUI app), full height less the system's margin; nil elsewhere. Partly folded it ends at the hinge; lying flat at the
    /// midpoint of the free space (the window less the trailing rail), where the page divides.
    static func leadingHalfSize(in view: UIView?) -> CGSize? {
        guard let view, let window = view.window ?? (view as? UIWindow) else { return nil }
        let fold = UKDeviceSignals.fold(in: window)
        guard let width = DuoSheetPolicy.leadingHalfWidth(fold: fold, freeWidth: UKDeviceSignals.freeWidth(in: window)) else { return nil }
        return CGSize(width: width, height: (window.bounds.height - 2 * DuoSheetPolicy.halfMargin).rounded(.down))
    }

    /// Places `sheet`: against the leading edge on a device with a hinge (`preferredPlacement`, iOS 27; every other device and system
    /// keeps `.automatic`), and beside a vertical hinge sized to the leading half through the system's own sizing
    /// (`prefersPageSizing = false` plus `preferredContentSize`), so the system lays the sheet out at that size and nothing resizes it
    /// in a layout pass. Every sheet path calls it after configuring the sheet, and again (outside layout) when ``PoseWatch`` reports
    /// a change.
    static func place(_ sheet: UISheetPresentationController?, in view: UIView?) {
        guard let sheet else { return }
        #if !FENTON_IOS_SDK_BEFORE_27_1
        if #available(iOS 27.0, *) {
            sheet.preferredPlacement = hasHinge(in: view) ? .leading : .automatic
        }
        #endif
        let presented = sheet.presentedViewController
        if let size = leadingHalfSize(in: view) {
            // The sheet's own size, kept for when it leaves the half (a rotation to portrait, a fold).
            if objc_getAssociatedObject(presented, &ownSizeKey) == nil {
                objc_setAssociatedObject(presented, &ownSizeKey, NSValue(cgSize: presented.preferredContentSize), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            sheet.prefersPageSizing = false
            if presented.preferredContentSize != size { setContentSize(size, on: presented) }
        } else {
            sheet.prefersPageSizing = presented.modalPresentationStyle == .pageSheet
            if let own = objc_getAssociatedObject(presented, &ownSizeKey) as? NSValue {
                objc_setAssociatedObject(presented, &ownSizeKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                setContentSize(own.cgSizeValue, on: presented)
            }
        }
    }

    /// Sets `size` so that the controller reports it back. A navigation controller adds its visible bar's height to the
    /// `preferredContentSize` it is given (measured: 684 reads back 738 with a 54 pt bar), which would make a sheet taller than the
    /// half it should fill; the bar is taken off first. On a Duo whose bar is vertical it adds the bar's width instead, once the
    /// sheet is up (measured 2026-11-04: 580 read back 668 with the 88 pt vertical bar, so a sheet resized while presented came out
    /// 88 pt wider), so whatever it still adds on either axis is read back and taken off once.
    static func setContentSize(_ size: CGSize, on presented: UIViewController) {
        var adjusted = size
        if let navigation = presented as? UINavigationController, !navigation.isNavigationBarHidden {
            adjusted.height = max(0, size.height - navigation.navigationBar.frame.height)
        }
        presented.preferredContentSize = adjusted
        let reported = presented.preferredContentSize
        guard reported != size else { return }
        presented.preferredContentSize = CGSize(width: max(0, adjusted.width - (reported.width - size.width)),
                                                height: max(0, adjusted.height - (reported.height - size.height)))
    }

    nonisolated(unsafe) private static var ownSizeKey: UInt8 = 0

    /// Notices the pose changing under an open sheet: the full-height rule, or the leading-half size (folded to unfolded landscape
    /// keeps the rule but gains the half). A presenter calls ``changed(in:)`` from its layout pass and, when it answers true, re-applies
    /// its detents, grabber and ``place(_:in:)`` inside `animateChanges`, on the next turn of the run loop.
    @MainActor struct PoseWatch {
        private struct Pose: Equatable {
            var fills: Bool
            var half: CGSize?
        }
        private var applied: Pose?

        private static func pose(in view: UIView?) -> Pose {
            Pose(fills: UKSheetPlacement.fillsHeight(in: view), half: UKSheetPlacement.leadingHalfSize(in: view))
        }

        /// Records the pose now (as the sheet is configured) so the first layout pass is not read as a change.
        mutating func record(in view: UIView?) { applied = Self.pose(in: view) }

        /// Whether the pose differs from the one recorded; records the new one.
        mutating func changed(in view: UIView?) -> Bool {
            let pose = Self.pose(in: view)
            defer { applied = pose }
            guard let applied else { return false }
            return applied != pose
        }
    }
}
#endif
