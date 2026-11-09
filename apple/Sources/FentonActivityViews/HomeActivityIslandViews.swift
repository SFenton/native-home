import FentonActivityModel
import SwiftUI

/// The Dynamic Island's regions for one activity (`.agents/platforms/apple/live-activities-per-job.md` §8a). The widget
/// extension places each in `DynamicIsland { ... }`; the gallery and the tests draw them in a black capsule.
///
/// **Expanded (E2c).** Beside the camera sit two small things only, with **no fixed frames**: the job glyph (24 pt) on the left
/// and the corner mark (24 pt) on the right. Below the camera, in the full width, the title over the value on the left
/// (both white), up to two buttons on the right in line with that block, and a 5 pt bar when the card has progress. The
/// system sizes the regions for each phone's camera, so nothing here measures a device. The centre region stays empty.
///
/// **Compact.** The leading side is a 24 pt ring (the glyph alone when there is no time). The trailing time has a **rigid
/// width**: `Text(timerInterval:)` reports the width of its widest possible value, which stretched the island nearly edge to
/// edge, so the time is drawn over a hidden template of the same font ("00:00", or "0:00:00" from an hour).
public enum HomeActivityIsland {
    /// Compact, leading: the 24 pt ring with the glyph (the glyph alone when the card has no time or progress); a problem
    /// shows the severity circle.
    public struct CompactLeading: View {
        let card: ActivityCard

        public init(card: ActivityCard) { self.card = card }

        public var body: some View {
            Group {
                if let problem = card.problem {
                    SeverityCircle(glyph: problem.glyph, severity: problem.severity, diameter: 24)
                } else if card.showsRing {
                    ActivityRing(card: card, diameter: 24)
                } else {
                    ActivityHeaderGlyph(card: card, size: 20)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.problem == nil ? card.title : card.spokenSummary)
        }
    }

    /// Compact, trailing: the time at 15 pt semibold (a text style) in the job's tint over a hidden template, so its width is the template's;
    /// a card with no time shows its `short` word at 13 pt, capped at 56 pt and ending in an ellipsis; a problem shows one
    /// word ("Stuck", "Refill water"). In a limited width (`isDynamicIslandLimitedInWidth`, iOS 27) it is empty and only the
    /// leading side shows.
    public struct CompactTrailing: View {
        let card: ActivityCard
        let isLimitedWidth: Bool

        public init(card: ActivityCard, isLimitedWidth: Bool = false) {
            self.card = card
            self.isLimitedWidth = isLimitedWidth
        }

        private var accent: Color { ActivityStyle(tint: card.tint).accent }

        public var body: some View {
            if isLimitedWidth {
                EmptyView()
            } else {
                content
            }
        }

        @ViewBuilder
        private var content: some View {
            switch card.compactTrailing {
            case let .timer(template):
                CompactTime(card: card, template: template)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(card.spokenFigure ?? "")
            case let .label(text):
                Text(text)
                    .font(ActivityStyle.compactLabelFont)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: ActivityCard.compactLabelWidth, alignment: .trailing)
            case let .problem(word):
                Text(word)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(card.problem.map { ActivityStyle.severity($0.severity).lightText } ?? accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .accessibilityLabel("Complete")
            case .none:
                EmptyView()
            }
        }
    }

    /// A live time with a rigid width: the template is laid out (and hidden) at the same font, and the live text is an overlay
    /// that cannot widen it. `lineLimit(1)` and a 0.8 scale floor cover a value a little wider than the template.
    struct CompactTime: View {
        let card: ActivityCard
        let template: String

        private var font: Font { ActivityStyle.compactTimeFont }

        var body: some View {
            Text(template)
                .font(font)
                .hidden()
                .overlay(alignment: .trailing) {
                    if let live = ActivityFigure.liveText(card.figure) {
                        live
                            .font(font)
                            .foregroundStyle(ActivityStyle(tint: card.tint).accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
        }
    }

    /// Minimal: the ring alone, which fits a 24 pt circle (the glyph alone when the card has no time or progress); a problem
    /// shows the severity circle.
    public struct Minimal: View {
        let card: ActivityCard

        public init(card: ActivityCard) { self.card = card }

        public var body: some View {
            Group {
                if let problem = card.problem {
                    SeverityCircle(glyph: problem.glyph, severity: problem.severity, diameter: 24)
                } else if card.showsRing {
                    ActivityRing(card: card, diameter: 24)
                } else {
                    ActivityHeaderGlyph(card: card, size: 20)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.problem == nil ? card.title : card.spokenSummary)
        }
    }

    /// Expanded, leading (beside the camera): the job glyph at 24 pt, or the severity circle on a problem.
    public struct ExpandedLeading: View {
        let card: ActivityCard

        public init(card: ActivityCard) { self.card = card }

        public var body: some View {
            Group {
                if let problem = card.problem {
                    SeverityCircle(glyph: problem.glyph, severity: problem.severity, diameter: 28)
                } else {
                    ActivityHeaderGlyph(card: card, size: ActivityStyle.islandGlyphSize)
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// Expanded, trailing (beside the camera): the corner mark at 24 pt, mirroring the glyph, with no fixed width. A problem
    /// says its severity in the severity circle opposite and the problem line below, not in a word here (the island's text
    /// is capped, so a word beside the mark could not grow with the person's text size).
    public struct ExpandedTrailing: View {
        let card: ActivityCard

        public init(card: ActivityCard) { self.card = card }

        public var body: some View {
            CornerMark()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Expanded, bottom (below the camera, in the full width). A job: the title (16 pt semibold, wraps to two lines) over the
    /// value (32 pt semibold, monospaced; a card with no value shows its headline at 24 pt), both white, with up to two
    /// buttons on the right in line with that block, then the 5 pt bar when there is progress. A problem: the device, the
    /// problem line, and the buttons.
    public struct ExpandedBottom: View {
        let card: ActivityCard

        public init(card: ActivityCard) { self.card = card }

        public var body: some View {
            if let problem = card.problem {
                problemBlock(problem)
            } else {
                jobBlock
            }
        }

        private var jobBlock: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(card.headerLine)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(ActivityStyle.primaryText)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(card.spokenTitle)
                            .accessibilityIdentifier("liveactivity.title")
                        ActivityValueLine(card: card)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ActivityButtons(card: card, buttons: card.islandButtons, fillsRow: false)
                        .fixedSize(horizontal: true, vertical: false)
                }
                if let bar = card.bar { ActivityBar(card: card, bar: bar) }
            }
        }

        private func problemBlock(_ problem: ActivityProblem) -> some View {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(card.deviceTitle)
                        .font(.headline)
                        .foregroundStyle(ActivityStyle.primaryText)
                        // Two lines in the expanded island: the device and the problem are the critical text, and the
                        // compact presentations stay one line.
                        .lineLimit(2)
                        .truncationMode(.tail)
                    Text(problem.problem)
                        .font(.footnote)
                        .foregroundStyle(ActivityStyle.severity(problem.severity).lightText)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                ActivityButtons(card: card, buttons: card.islandButtons)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}
