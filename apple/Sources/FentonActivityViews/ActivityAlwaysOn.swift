import SwiftUI

extension ActivityStyle {
    /// How much of its brightness a fill, a ring or a bar keeps on an Always-On Lock Screen (luminance reduced). Text is not
    /// dimmed: it stays legible, and it is the fills (a white pill, the progress ring) that draw the eye at low luminance
    /// (HIG Always On: reduce brightness; owner, 2026-10-26, `live-activity-job-card`).
    public static let alwaysOnDimming = 0.6

    /// The opacity for a fill, ring or bar.
    /// - Parameter luminanceReduced: The Lock Screen is Always-On (`isLuminanceReduced`).
    public static func fillOpacity(luminanceReduced: Bool) -> Double { luminanceReduced ? alwaysOnDimming : 1 }
}

/// Dims a fill, ring or bar on an Always-On Lock Screen (``ActivityStyle/fillOpacity(luminanceReduced:)``).
private struct DimsWhenAlwaysOn: ViewModifier {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    func body(content: Content) -> some View {
        content.opacity(ActivityStyle.fillOpacity(luminanceReduced: isLuminanceReduced))
    }
}

extension View {
    /// Lowers the brightness of a fill, ring or bar when the Lock Screen is Always-On; text is left alone.
    func dimsWhenAlwaysOn() -> some View { modifier(DimsWhenAlwaysOn()) }
}
