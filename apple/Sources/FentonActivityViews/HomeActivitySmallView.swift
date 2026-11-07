import FentonActivityModel
import SwiftUI

/// The Apple Watch Smart Stack and CarPlay presentation (`.small` supplemental family, iOS 18): the glyph, the title and the
/// figure (or the headline of a card with no figure). No controls: buttons do nothing there until a device check says otherwise
/// (`.agents/platforms/apple/live-activities-per-job.md` §8).
public struct HomeActivitySmallView: View {
    private let card: ActivityCard
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Lines the title, problem and headline may take: one, and two at accessibility sizes so they wrap instead of truncating.
    private var lines: Int { typeSize.isAccessibilitySize ? 2 : 1 }

    /// Creates the view.
    public init(card: ActivityCard) { self.card = card }

    public var body: some View {
        HStack(spacing: 8) {
            if let problem = card.problem {
                SeverityCircle(glyph: problem.glyph, severity: problem.severity, diameter: 30)
            } else if card.showsRing {
                ActivityRing(card: card, diameter: 32)
            } else {
                ActivityHeaderGlyph(card: card, size: 26)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(card.problem == nil ? card.title : card.deviceTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ActivityStyle.primaryText)
                    .lineLimit(lines)
                    .privacySensitive()
                if let problem = card.problem {
                    Text(problem.problem)
                        .font(.subheadline)
                        .foregroundStyle(ActivityStyle.severity(problem.severity).lightText)
                        .lineLimit(lines)
                    .privacySensitive()
                } else if let bigLine = card.bigLine {
                    Text(bigLine)
                        .font(.headline)
                        .foregroundStyle(ActivityStyle.primaryText)
                        .lineLimit(lines)
                } else {
                    ActivityFigure(card: card, size: 17, relativeTo: .headline)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
