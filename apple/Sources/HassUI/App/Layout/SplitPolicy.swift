import CoreGraphics
import HassDesign

// MARK: - Hinge

/// iPhone Duo hinge status, platform-neutral so policies test on macOS.
public enum HingeState: Sendable, Hashable {
    case closed
    case partiallyOpen
    case fullyOpen
}

// MARK: - Split policy

/// When a page may show its on-demand split (owner rules, 2026-10-10; `.agents/design/apple/split-view.md`).
///
/// | Device / pose | Split |
/// |---|---|
/// | iPhone (portrait-locked) | never |
/// | iPhone Duo folded (outer display) | never |
/// | iPhone Duo unfolded portrait | never |
/// | iPad portrait | never |
/// | iPhone Duo unfolded landscape, iPad landscape | allowed |
///
/// Expressed by geometry, never by device name: a split needs a regular-width window that is wider
/// than tall, with each half at least ``minimumPaneWidth``. iPad Split View/Stage Manager windows
/// follow the same rule from their own size.
public enum SplitPolicy {
    /// Narrowest pane a split may produce (FestivalNativeApps `OnDemandSplitPolicy`).
    public static let minimumPaneWidth: CGFloat = 360

    /// Whether the window may split.
    /// - Parameters:
    ///   - size: The window (or content area) size in points.
    ///   - isRegularWidth: Horizontal size class is regular.
    public static func allowsSplit(size: CGSize, isRegularWidth: Bool) -> Bool {
        guard isRegularWidth, size.width > size.height else { return false }
        return size.width / 2 >= minimumPaneWidth
    }

    /// Where the divider sits: the hinge's x when a vertical fold crosses the window, else the midpoint.
    /// - Parameters:
    ///   - width: Content width.
    ///   - hingeMidX: The vertical fold's centre, if the device reports one inside the window.
    public static func dividerX(width: CGFloat, hingeMidX: CGFloat?) -> CGFloat {
        if let hingeMidX, hingeMidX > 0, hingeMidX < width { return hingeMidX }
        return width / 2
    }

    /// Width of the band between panes when no hinge crosses the window: the panes meet at the midpoint
    /// with no drawn line (Festival `split-panes` R1; a 1 pt hairline only under Increase Contrast).
    public static let midpointBandWidth: CGFloat = 1

    /// Pane widths for a split container, or nil when the container may not split.
    ///
    /// The band is the vertical hinge when one crosses the container (the leading pane ends at its
    /// leading edge, the trailing pane starts at its trailing edge), else ``midpointBandWidth`` centred
    /// on the container's midpoint. Each pane must be at least ``minimumPaneWidth``.
    /// - Parameters:
    ///   - container: The split container's frame in window coordinates.
    ///   - isRegularWidth: Horizontal size class is regular.
    ///   - hinge: The device's division frame in window coordinates, if any (iPhone Duo).
    public static func geometry(container: CGRect, isRegularWidth: Bool, hinge: CGRect?) -> SplitGeometry? {
        guard allowsSplit(size: container.size, isRegularWidth: isRegularWidth) else { return nil }
        var band: ClosedRange<CGFloat>
        var isHinge = false
        if let hinge, hinge.height >= hinge.width, hinge.midX > container.minX, hinge.midX < container.maxX {
            band = hinge.minX...hinge.maxX
            isHinge = true
        } else {
            band = container.midX...container.midX
        }
        if band.upperBound - band.lowerBound < midpointBandWidth {
            let mid = (band.lowerBound + band.upperBound) / 2
            band = (mid - midpointBandWidth / 2)...(mid + midpointBandWidth / 2)
        }
        let leading = band.lowerBound - container.minX
        let trailing = container.maxX - band.upperBound
        guard leading >= minimumPaneWidth, trailing >= minimumPaneWidth else { return nil }
        return SplitGeometry(
            leadingWidth: leading, bandWidth: band.upperBound - band.lowerBound,
            trailingWidth: trailing, isHinge: isHinge
        )
    }
}

extension SplitPolicy {
    /// Pane widths for two columns the caller has already decided to show side by side (the Food hub, Recipes, Inventory and
    /// Vacuums pages, which split when ``allowsSplit(size:isRegularWidth:)`` says so).
    ///
    /// The band is the vertical hinge when one crosses the container and leaves each pane at least
    /// ``minimumPaneWidth``; otherwise the panes share the container equally with `gutter` between them (iPad, and a Duo
    /// whose hinge would leave a pane too narrow). Widths are never negative. Section 1 of `duo-ipad-fold-layout`
    /// (decided 2026-10-24): two-pane screens take their widths from here, not from halving.
    /// - Parameters:
    ///   - container: The columns' container in window coordinates.
    ///   - hinge: The device's division frame in window coordinates, if any.
    ///   - gutter: The gap between panes when no hinge is used.
    public static func columnWidths(container: CGRect, hinge: CGRect?, gutter: CGFloat) -> SplitGeometry {
        if let band = HingeAvoidance.band(in: container, hinge: hinge) {
            let leading = band.lowerBound
            let trailing = container.width - band.upperBound
            if leading >= minimumPaneWidth, trailing >= minimumPaneWidth {
                return SplitGeometry(leadingWidth: leading, bandWidth: band.upperBound - band.lowerBound,
                                     trailingWidth: trailing, isHinge: true)
            }
        }
        let gap = max(gutter, 0)
        let each = max((container.width - gap) / 2, 0)
        return SplitGeometry(leadingWidth: each, bandWidth: gap, trailingWidth: each, isHinge: false)
    }
}

/// Resolved pane widths for an open split.
public struct SplitGeometry: Sendable, Equatable {
    /// Leading (list) pane width.
    public var leadingWidth: CGFloat
    /// Gap between the panes: the hinge, or the 1 pt midpoint band.
    public var bandWidth: CGFloat
    /// Trailing (detail) pane width.
    public var trailingWidth: CGFloat
    /// The band is the device hinge.
    public var isHinge: Bool
}

