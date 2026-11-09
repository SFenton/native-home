import SwiftUI

/// How a module on the wallpaper is filled (`.agents/design/direction-g.md`, Layers).
public enum ModuleDensity: Sendable, CaseIterable {
    /// `#1C1C1E` at 55% over a background blur: cards, inset lists and tiles with white and grey text.
    case thin
    /// `#141416` at 78%: a module that carries red or orange status text (overdue chores, expired food, an error
    /// tile), so that text stays readable over the lit windows of the photo.
    case dense
}

/// The page material for content on the wallpaper (``SwiftUICore/View/module(_:cornerRadius:)``).
///
/// A content-layer material: a translucent dark tint, 26 pt continuous corners, no rim or bevel. It is never
/// `.glassEffect`, which HIG reserves for the navigation layer (HIG: Materials, Liquid Glass). With Reduce
/// Transparency the tint turns opaque (HIG: Accessibility, Reduce Transparency).
///
/// No live background blur: modules only ever sit on the wallpaper, which is already blurred once and cached, so a
/// blur adds nothing visible, while a backdrop layer per tile is a real GPU cost on a page of tiles (and the
/// simulator's render server crashed under them, 2026-10-14). The tint is denser instead (direction-g.md, Layers).
struct ModuleBackground: ViewModifier {
    var density: ModuleDensity
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content.background {
            shape.fill(Self.tint(density, reduceTransparency: reduceTransparency))
        }
    }

    /// The translucent tint, or the opaque fill with Reduce Transparency.
    static func tint(_ density: ModuleDensity, reduceTransparency: Bool) -> Color {
        switch (density, reduceTransparency) {
        case (.thin, false): HassTokens.Surface.moduleThin
        case (.dense, false): HassTokens.Surface.moduleDense
        case (.thin, true): Color(rgb: HassTokens.Palette.moduleThin)
        case (.dense, true): Color(rgb: HassTokens.Palette.moduleDense)
        }
    }
}

public extension View {
    /// Draws this content on a direction G module: the page material for cards, inset lists and tiles on the
    /// wallpaper. Use `.dense` when the content carries red or orange text.
    /// - Parameters:
    ///   - density: ``ModuleDensity/thin`` (default) or ``ModuleDensity/dense``.
    ///   - cornerRadius: 26 pt for modules (default); tiles pass ``HassTokens/Radius/tile``.
    func module(_ density: ModuleDensity = .thin, cornerRadius: CGFloat = HassTokens.Radius.module) -> some View {
        modifier(ModuleBackground(density: density, cornerRadius: cornerRadius))
    }
}

#Preview("Modules on a photo") {
    VStack(spacing: 16) {
        Text("Thin module").frame(maxWidth: .infinity, minHeight: 80).module()
        Text("3 Chores Overdue").foregroundStyle(.red).frame(maxWidth: .infinity, minHeight: 80).module(.dense)
    }
    .padding()
    .background(LinearGradient(colors: [.orange, .blue], startPoint: .top, endPoint: .bottom))
    .foregroundStyle(.white)
}
