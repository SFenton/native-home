import SwiftUI

/// The mark inside a selection tile's disc (``TileSelection``): an empty ring while not chosen; a white disc with a checkmark (single
/// choice) or the cleaning order (ordered choice) while chosen.
///
/// **Motion** (the approved mockup): choosing fills the ring white and scales the check in from 50% (`quick`, 0.2 s); the tile's own
/// fill cross-fades on the state token beside it. A number that changes (the order shifting when an earlier room is cleared) rolls
/// with `numericText`. Under Reduce Motion nothing scales or rolls: the fill and the mark cross-fade for 0.2 s
/// (``MotionTokens/stateReduced``). The test seam ``EnvironmentValues/reduceMotionOverride`` reaches both paths.
struct TileSelectionIndicator: View {
    var selection: TileSelection
    /// The chosen disc's fill and mark (white with the family fill as the mark).
    var ink: (disc: Color, glyph: Color)
    var isPressed: Bool

    @ScaledMetric(relativeTo: .body) private var scaledDiameter: CGFloat = TileSelectionIndicator.baseDiameter
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    // MARK: Metrics

    /// The ring and the chosen disc at the default size (the mockup's 28 pt, inside the 44 pt target).
    static let baseDiameter: CGFloat = 28
    /// The ring's stroke.
    static let ringWidth: CGFloat = 2
    /// The ring's opacity on the dark ground, which keeps it above 3:1 (WCAG 1.4.11).
    static let ringOpacity = 0.85

    /// The indicator's diameter: 28 pt, scaling with text but never more than 1.5×, and always inside a `target` of 44 pt scaled.
    static func diameter(scaled: CGFloat) -> CGFloat { min(max(scaled, baseDiameter), baseDiameter * 1.5) }

    /// The mark's point size inside the disc (`checkmark` or the number).
    static func markSize(diameter: CGFloat) -> CGFloat { (diameter * 0.54).rounded() }

    // MARK: Body

    var body: some View {
        let diameter = Self.diameter(scaled: scaledDiameter)
        let chosen = selection.isSelected
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(Self.ringOpacity), lineWidth: Self.ringWidth)
                .opacity(chosen ? 0 : 1)
            Circle()
                .fill(ink.disc)
                .opacity(chosen ? 1 : 0)
            mark(size: Self.markSize(diameter: diameter), chosen: chosen)
        }
        .frame(width: diameter, height: diameter)
        .overlay { if isPressed { Circle().fill((chosen ? ink.glyph : Color.white).opacity(0.22)) } }
        .animation(reduceMotion ? MotionTokens.stateReduced : MotionTokens.quick, value: selection)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func mark(size: CGFloat, chosen: Bool) -> some View {
        if chosen {
            Group {
                if let position = selection.position {
                    Text("\(position)")
                        .font(.system(size: size, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(position)))
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: size, weight: .bold))
                }
            }
            .foregroundStyle(ink.glyph)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
        }
    }
}
