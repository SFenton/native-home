import FentonActivityModel
import SwiftUI

/// The job card, Lock Screen layout L4 (`.agents/platforms/apple/live-activities-per-job.md` §8a): no ring.
///
/// - **Row 1:** the glyph (22 pt, in the job's tint), the title (17 pt semibold, wraps to two lines, then an ellipsis) and the
///   corner mark (24 pt) top-right. The hot flash puts its `detail` here ("Hot Flash · Your side").
/// - **Row 2:** the value (32 pt semibold, monospaced) on the left and the buttons on the right, in the same row. A card with
///   no `value` shows its headline here at 24 pt instead. No row holds only a button.
/// - **Row 3:** the 5 pt bar in the job's tint, only when the card has progress.
///
/// Height is about 96 to 110 pt at the default text size, at most 160 pt with a two-line title
/// (`LiveActivityJourneyTests`); at accessibility sizes the value wraps under the title and the controls stack. The title
/// and the value are two accessibility elements read in that order, followed by the buttons.
struct JobCardView: View {
    let card: ActivityCard
    var showsMark = true
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            valueRow
            if let bar = card.bar { ActivityBar(card: card, bar: bar) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            ActivityHeaderGlyph(card: card, size: ActivityStyle.headerGlyphSize)
            Text(card.headerLine)
                .font(.headline)
                .foregroundStyle(ActivityStyle.primaryText)
                .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(card.spokenTitle)
                .accessibilityIdentifier("liveactivity.title")
                .privacySensitive()
            if showsMark { CornerMark() }
        }
    }

    @ViewBuilder
    private var valueRow: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                ActivityValueLine(card: card)
                ActivityButtons(card: card, buttons: card.buttons)
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                ActivityValueLine(card: card)
                ActivityButtons(card: card, buttons: card.buttons, fillsRow: false)
                    .layoutPriority(1)
            }
            .frame(minHeight: card.buttons.isEmpty ? 0 : ActivityStyle.minimumHit)
        }
    }
}
