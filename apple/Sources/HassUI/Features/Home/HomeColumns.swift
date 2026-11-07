import CoreGraphics
import HassDesign

/// Home's two columns on the unfolded iPhone Duo in landscape (direction G mockup n1-duo-unfolded; plan Phase 4,
/// decision 5): chips and weather lead, cameras and guests trail, and nothing straddles the hinge.
///
/// Built on ``SplitPolicy/geometry(container:isRegularWidth:hinge:)`` so it is geometric, never a device-name check, and
/// follows the same rules as the on-demand split (regular width, wider than tall, each half at least 360 pt). Unlike
/// the split it applies only where a hinge divides the window: iPad landscape stays one column (n1-ipad-home).
enum HomeColumns {
    /// The container to resolve columns from, given the measured view's frame in window coordinates: the frame without its
    /// vertical position. Home scrolls, so its frame moves up the window on every frame of a scroll; resolving from the
    /// moving frame wrote state per frame and re-evaluated the page each time (`.agents/testing/apple/performance.md`).
    /// The columns read the horizontal position and the size only (``SplitPolicy/geometry(container:isRegularWidth:hinge:)``).
    static func container(from frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: 0, width: frame.width, height: frame.height)
    }

    /// The column widths when Home splits on a hinge, else nil (one column).
    /// - Parameters:
    ///   - container: The space Home's content is offered, in window coordinates.
    ///   - isRegularWidth: Horizontal size class is regular.
    ///   - hinge: The window's hinge in window coordinates, if any.
    static func resolve(container: CGRect, isRegularWidth: Bool, hinge: CGRect?) -> SplitGeometry? {
        FoldColumns.resolve(container: container, isRegularWidth: isRegularWidth, hinge: hinge)
    }

    /// The column widths for a window's fold in either pose (owner, 2026-11-01): partly folded, the columns meet on the band
    /// (``resolve(container:isRegularWidth:hinge:)``); lying flat, they divide at the container's midpoint with a 1 pt band
    /// (the container is the free space, so that is the free space's midpoint). One column without a hinge.
    static func resolve(container: CGRect, isRegularWidth: Bool, fold: WindowFold) -> SplitGeometry? {
        if fold.isFolding { return resolve(container: container, isRegularWidth: isRegularWidth, hinge: fold.band) }
        guard fold.hinge != nil, fold.isVertical else { return nil }
        return SplitPolicy.geometry(container: container, isRegularWidth: isRegularWidth, hinge: nil)
    }
}
