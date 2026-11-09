import FentonActivityModel
import HassDesign
import SwiftUI

private struct CornerMarkChoiceKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

public extension EnvironmentValues {
    /// The `AppIconChoice` raw value the corner mark follows; nil reads the app group's stored choice.
    var cornerMarkChoice: String? {
        get { self[CornerMarkChoiceKey.self] }
        set { self[CornerMarkChoiceKey.self] = newValue }
    }
}

/// The house and heart in a card's corner: 24 pt (40 pt on a problem card), no tile, tinted with the foreground colour of the app icon the person
/// picked (``CornerMarkPalette``). It is decoration: the card's own label says what it is.
struct CornerMark: View {
    var size: CGFloat = ActivityStyle.markSize
    @Environment(\.cornerMarkChoice) private var choice

    var body: some View {
        HouseHeartShape()
            .fill(Color(rgb: CornerMarkPalette.glyph(for: choice ?? ActivityAppIconStore.shared.choice)))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
