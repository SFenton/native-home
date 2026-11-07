import SwiftUI

public extension EnvironmentValues {
    /// The band content keeps clear of: the iPhone Duo's hinge in window coordinates **while the inner display is partly folded**
    /// (``WindowFold/band``; owner, 2026-11-01). Nil while it lies flat, on the folded outer display and on devices without one,
    /// so nothing avoids the hinge in those: a row of tiles has no gap, a split divides at the container's midpoint.
    ///
    /// The shell publishes it (`readsWindowHinge()` in HassUI). Avoidance reads it: ``DynamicGridLayout`` splits its tracks around
    /// it and ``ChipRail`` stops short of it (`.agents/patterns/hinge-avoidance.md`). Whether a hinge exists at all is
    /// ``windowFold``.
    @Entry var windowHinge: CGRect?

    /// The window's hinge in either pose (``WindowFold``): presence (the shell's style, sheet placement and height) reads it.
    /// ``windowHinge`` is its ``WindowFold/band``, published with it (owner, 2026-11-01).
    @Entry var windowFold: WindowFold = .none

    /// The window's width less the trailing vertical bar (the Duo's rail): the free space a flat page divides at its midpoint, and
    /// the width a sheet's leading half is taken from (``DuoSheetPolicy/leadingHalfWidth(fold:freeWidth:)``). 0 until measured.
    @Entry var windowFreeWidth: CGFloat = 0
}
