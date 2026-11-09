import FentonActivityModel
import SwiftUI

/// The job's glyph in its tint (a check once the job is Complete), at a fixed square so a title beside it lines up whichever
/// glyph the engine named. Hidden from VoiceOver: the card's title says what it is.
struct ActivityHeaderGlyph: View {
    let card: ActivityCard
    var size: CGFloat

    private var accent: Color { ActivityStyle(tint: card.tint).accent }

    var body: some View {
        Group {
            if card.isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.9, weight: .heavy))
                    .foregroundStyle(accent)
            } else {
                ActivityGlyphImage(glyph: card.glyph, size: size, color: accent)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
