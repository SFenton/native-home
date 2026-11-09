import FentonActivityModel
import SwiftUI

/// The card's big line, shared by the Lock Screen and the expanded island: a notice for one update, else the `headline` of a
/// card with no `value` (24 pt, white even when paused), else the figure (32 pt, monospaced).
struct ActivityValueLine: View {
    let card: ActivityCard
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if let notice = card.notice {
                Text(notice)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ActivityStyle.noticeText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("liveactivity.notice")
            } else if let bigLine = card.bigLine {
                Text(bigLine)
                    .activityFont(24, weight: .semibold, relativeTo: .title)
                    .foregroundStyle(ActivityStyle.primaryText)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ActivityFigure(card: card)
            }
        }
        .accessibilityIdentifier("liveactivity.value")
    }
}
