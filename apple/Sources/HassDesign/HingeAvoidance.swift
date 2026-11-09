import CoreGraphics

// MARK: - Hinge avoidance

/// Pure geometry for keeping content off the iPhone Duo's hinge band (`.agents/patterns/hinge-avoidance.md`,
/// decided 2026-10-24 in `duo-ipad-fold-layout`).
///
/// The hinge arrives in window coordinates (``SwiftUI/EnvironmentValues/windowHinge``); a view knows its own frame in the same
/// space, so each helper takes the container's frame and answers in the container's local coordinates. Only a vertical
/// hinge (taller than wide: the unfolded Duo in landscape) is a band; the horizontal hinge of unfolded portrait and a
/// nil hinge answer "no band", so iPad and iPhone never change.
public enum HingeAvoidance {
    /// The hinge band across `container`, as a range of x offsets from the container's leading edge, or nil when no
    /// vertical hinge crosses the container's interior.
    /// - Parameters:
    ///   - container: The container's frame in window coordinates.
    ///   - hinge: The hinge in window coordinates, if the device reports one.
    public static func band(in container: CGRect, hinge: CGRect?) -> ClosedRange<CGFloat>? {
        guard let hinge, hinge.width > 0, hinge.height >= hinge.width,
              hinge.midX > container.minX, hinge.midX < container.maxX else { return nil }
        let lower = max(hinge.minX, container.minX) - container.minX
        let upper = min(hinge.maxX, container.maxX) - container.minX
        return lower...upper
    }

    /// Where a single object that cannot split (an alarm card, a dial, a sign-in form) sits in a container.
    ///
    /// Centred, as it would be anyway; but only when the band crosses its centred frame does it move, to the centre of the
    /// leading region (the part of the container before the band), narrowed to fit. Elsewhere it stays centred.
    /// - Parameters:
    ///   - objectWidth: The object's natural width, at most the container's.
    ///   - containerWidth: The container's width.
    ///   - band: The band from ``band(in:hinge:)``.
    /// - Returns: The object's x offset from the container's leading edge and the width it may use.
    public static func placement(objectWidth: CGFloat, containerWidth: CGFloat, band: ClosedRange<CGFloat>?)
        -> (x: CGFloat, width: CGFloat) {
        let width = min(max(objectWidth, 0), max(containerWidth, 0))
        let centred = (x: (containerWidth - width) / 2, width: width)
        guard let band, centred.x < band.upperBound, centred.x + width > band.lowerBound else { return centred }
        let leading = max(band.lowerBound, 0)
        let fitted = min(width, leading)
        return (x: (leading - fitted) / 2, width: fitted)
    }

    /// The larger side of the band, for content that must fill a region (a page-sheet form) rather than sit as one object.
    /// Ties go to the leading side. Without a band, the whole container.
    /// - Returns: The region's x offset from the container's leading edge and its width.
    public static func clearRegion(containerWidth: CGFloat, band: ClosedRange<CGFloat>?) -> (x: CGFloat, width: CGFloat) {
        guard let band else { return (0, containerWidth) }
        let leading = max(band.lowerBound, 0)
        let trailing = max(containerWidth - band.upperBound, 0)
        return leading >= trailing ? (0, leading) : (band.upperBound, trailing)
    }
}
