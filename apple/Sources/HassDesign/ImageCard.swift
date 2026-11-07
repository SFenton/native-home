import SwiftUI

/// A tappable card with a remote image, a title and an optional subtitle (pattern: `.agents/patterns/image-card.md`).
///
/// Used for recipes on the Food hub carousel and the Recipes grid (web `ImageCard`). Pure UI: callers pass
/// values and an action.
///
/// Direction G (mockups n6): the photo fills a 22 pt card and the caption sits on it in white over a bottom scrim, as in
/// Photos and Music. At accessibility text sizes the card is a row with a small thumbnail on a module instead.
///
/// The caption is the card's one accessibility element, framed to the text alone: the whole card is still the tap
/// target, but VoiceOver and the rendered-contrast audit see the caption over its scrim rather than a card-sized
/// element that is mostly photo (audit item 12).
public enum ImageCard {
    /// The card's corner radius (direction G, Controls: 22 pt, as tiles). Callers drawing a selection outline use it.
    public static let cornerRadius = HassTokens.Radius.tile
    /// Width over height of the photo card (mockups n6: 1 : 0.78). Loading placeholders use it to keep the layout.
    public static let aspectRatio: CGFloat = 1 / 0.78

    /// Title lines: up to three; never truncated at accessibility text sizes, where a cut title fails the Dynamic
    /// Type audit.
    static func titleLines(accessibilitySize: Bool) -> ClosedRange<Int> {
        accessibilitySize ? 1...100 : 1...3
    }

    /// The scrim's black at each fraction of the card's height, top to bottom (also drawn by the UIKit port).
    public static let scrimStops: [(opacity: Double, location: Double)] = [(0, 0.2), (0.55, 0.5), (0.82, 1)]

    /// Lines the title may take: up to three; unlimited (0) at accessibility sizes.
    public static func titleLineLimit(accessibilitySize: Bool) -> Int { accessibilitySize ? 0 : 3 }

    /// The thumbnail's side at accessibility sizes.
    public static let thumbnailSide: CGFloat = 72
}
