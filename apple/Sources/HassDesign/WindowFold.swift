import CoreGraphics

/// The iPhone Duo's hinge as the window sees it, in either pose of the inner display (owner, 2026-10-24, made binding 2026-11-01).
///
/// | Pose | ``hinge`` | ``isFolding`` | ``band`` | Page division |
/// |---|---|---|---|---|
/// | Partly folded (book pose) | the division region | true | the hinge | on the hinge: the leading side ends at the band, the trailing side starts after it |
/// | Lying flat | the division region (reported inactive) | false | nil | the midpoint of the free space (the window less the trailing rail), 1 pt |
/// | Folded outer screen, iPhone, iPad | nil | false | nil | the midpoint (iPad) or none |
///
/// Content keeps clear of ``band`` only: while the Duo lies flat nothing avoids the hinge, so a row of like tiles has no gap in the
/// middle and a centred object centres in the free space. Presence (the shell's style, where sheets go, whether they fill the
/// height) reads ``hinge``, which is set in both poses. Both apps derive it from the same reserved regions: the active division
/// region while partly folded, else the inactive one.
public struct WindowFold: Equatable, Sendable {
    /// The hinge's division region in window coordinates, in either pose; nil without one (and on the folded outer screen).
    public var hinge: CGRect?
    /// The inner display is partly folded: the division region is active.
    public var isFolding: Bool

    public init(hinge: CGRect?, isFolding: Bool) {
        self.hinge = hinge
        self.isFolding = isFolding && hinge != nil
    }

    /// No hinge visible.
    public static let none = WindowFold(hinge: nil, isFolding: false)

    /// The band content keeps clear of: the hinge while partly folded; nil while flat or without a hinge.
    public var band: CGRect? { isFolding ? hinge : nil }

    /// The hinge runs top to bottom (landscape, either pose).
    public var isVertical: Bool { hinge.map { $0.height > $0.width } ?? false }
}
