import SwiftUI

/// When every sheet on the iPhone Duo opens at full height, from the bottom (owner, 2026-10-31: "On duo landscape or folded, modals
/// can always just open full height and from the bottom").
///
/// The rule is geometric, never a device-name check, and one function serves both apps (`FentonHome` reads it in `hassSheet`, the
/// UIKit port in `UKHassModalController` and `UKSheetPlacement`). A sheet then takes the large detent only (no content-fitted or
/// medium detent, no resize between pages), rises with the standard sheet transition (no zoom from a source tile), and keeps its
/// grabber and swipe to dismiss. Pattern: `.agents/patterns/modal-sheet.md`.
public enum DuoSheetPolicy {
    /// A hinge has been seen on this device (``HingePresence`` in HassUI sets it, once, and it never clears): the folded Duo reports
    /// no hinge region, so this is what tells the outer screen from a phone without one.
    @MainActor public static var deviceHasHinge = false

    /// Whether a sheet fills the height.
    /// - Parameters:
    ///   - hasHinge: The window has a hinge: the device has reported one, or a hinge region is visible.
    ///   - hinge: The hinge band in window coordinates (``SwiftUICore/EnvironmentValues/windowHinge``): the active fold while partly
    ///     folded, else the flat hinge. Nil while no division region is visible, which is the folded outer screen.
    /// - Returns: True for the folded outer screen (no band) and for a vertical band (height > width: unfolded or partly folded in
    ///   landscape). False without a hinge, and for a horizontal band (unfolded portrait), which keep today's behaviour.
    public static func fillsHeight(hasHinge: Bool, hinge: CGRect?) -> Bool {
        guard hasHinge else { return false }
        guard let hinge else { return true }
        return hinge.height > hinge.width
    }

    /// ``fillsHeight(hasHinge:hinge:)`` for the SwiftUI environment's hinge, with the device's own record of having a hinge.
    @MainActor
    public static func fillsHeight(hinge: CGRect?) -> Bool {
        fillsHeight(hasHinge: deviceHasHinge || hinge != nil, hinge: hinge)
    }

    /// A sheet's inset from the window's leading, top and bottom edges in the leading half: the system's own partly folded placement
    /// (measured on the Duo simulator, 2026-10-31). The SDK has no sheet-margin API, so this is the one measured number.
    public static let halfMargin: CGFloat = 8

    /// The width of a sheet in the leading half beside a vertical hinge (unfolded or partly folded landscape), nil elsewhere (owner,
    /// 2026-10-31: placed `.leading` alone the sheet kept the page width, "about 66-75% of the screen, not half"). It ends where the
    /// page's own division begins (``WindowFold``, owner 2026-11-01), so a sheet and the page behind it divide the window alike:
    /// - Partly folded: where the hinge's division region begins. The system reports that region with the margins it keeps clear
    ///   around the hinge (`UIViewReservedRegion.frame` includes `margins`), so the trailing edge is the system's.
    /// - Lying flat: ``halfMargin`` before the midpoint of the free space (the window less the trailing rail), where a flat page divides.
    /// - Parameters:
    ///   - fold: The window's hinge in either pose.
    ///   - freeWidth: The window's width less the trailing vertical bar (the rail), in points: the space a flat page divides.
    public static func leadingHalfWidth(fold: WindowFold, freeWidth: CGFloat) -> CGFloat? {
        guard fold.isVertical, let hinge = fold.hinge else { return nil }
        let end = fold.isFolding ? hinge.minX : (freeWidth - midpointBand) / 2
        return max(0, (end - halfMargin).rounded(.down))
    }

    /// The pre-``WindowFold`` form: treats `hinge` as partly folded. Kept until both apps pass the fold.
    public static func leadingHalfWidth(hinge: CGRect?) -> CGFloat? {
        leadingHalfWidth(fold: WindowFold(hinge: hinge, isFolding: true), freeWidth: 0)
    }

    /// The width of the division between a flat page's halves (`SplitPolicy.midpointBandWidth` in HassUI).
    public static let midpointBand: CGFloat = 1
}
