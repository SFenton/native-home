import FentonActivityModel
import SwiftUI

/// The problem card, one design for every device (`.agents/platforms/apple/live-activities-per-job.md` §5, §8): a 44 pt
/// solid severity shape (octagon stopped, triangle carries on) with the problem glyph, the device as the title, the problem in the severity's light tint, the
/// instruction in body text, an optional chip, buttons bottom-right (Done last) and the corner mark. Red stopped and needs
/// you; amber carries on. The state is also a two-word label on the problem line, so it is never colour alone.
///
/// VoiceOver reads one phrase, "Main Floor Vacuum, needs help: Stuck in Kitchen. Move it somewhere flat, then tap
/// Resume.", then the buttons. A failure notice (`card.notice`) is its own element after that phrase and before the buttons,
/// drawn where `\.problemNoticePlacement` says; the phrase still speaks the instruction either way.
struct ProblemCardView: View {
    let card: ActivityCard
    let problem: ActivityProblem
    var showsMark = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.problemNoticePlacement) private var placement

    private var colors: ActivityStyle.Severity { ActivityStyle.severity(problem.severity) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 14) {
                SeverityCircle(glyph: problem.glyph, severity: problem.severity, diameter: ActivityStyle.severityCircle)
                    .accessibilityHidden(true)
                text
            }
            .accessibilityElement(children: .contain)
            ActivityButtons(card: card, buttons: card.buttons, chips: problem.chips)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: colors.gradient, startPoint: .top, endPoint: .bottom)
        )
        .overlay { ContainerRelativeShape().strokeBorder(colors.hairline, lineWidth: 1) }
        .overlay(alignment: .topTrailing) {
            if showsMark { CornerMark(size: ActivityStyle.problemMarkSize).padding(.top, 12).padding(.trailing, 14) }
        }
        .accessibilityElement(children: .contain)
    }

    /// The text column: the phrase block (one element), then the notice (its own element) when there is one.
    private var text: some View {
        VStack(alignment: .leading, spacing: 2) {
            phrase
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(card.spokenSummary)
                .accessibilityIdentifier("liveactivity.problem")
            if let notice = card.notice {
                Text(notice)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ActivityStyle.primaryText)
                    .lineLimit(noticeLineLimit)
                    .minimumScaleFactor(placement == .line && !typeSize.isAccessibilitySize ? 0.85 : 1)
                    .privacySensitive()
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("liveactivity.notice")
            }
        }
    }

    /// Two lines in place of the instruction at ordinary sizes, one on its own line; no limit at accessibility sizes.
    private var noticeLineLimit: Int? {
        typeSize.isAccessibilitySize ? nil : (placement == .line ? 1 : 2)
    }

    /// Whether the instruction is drawn: not while a notice stands in its place.
    private var showsInstruction: Bool { !(placement == .replace && card.notice != nil) }

    /// The device, the problem and the instruction.
    private var phrase: some View {
        VStack(alignment: .leading, spacing: 2) {
            // The first two lines share the corner with the mark; the instruction starts below it and runs full width.
            VStack(alignment: .leading, spacing: 2) {
                Text(card.deviceTitle)
                    .font(.headline)
                    .foregroundStyle(ActivityStyle.primaryText)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .privacySensitive()
                // The two-word state leads the problem line, bold in the severity tint, so the shape beside it has a word.
                (Text(problem.severity.stateLabel).bold() + Text(" · ") + Text(problem.problem))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(colors.lightText)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 1)
                    .minimumScaleFactor(typeSize.isAccessibilitySize ? 1 : 0.85)
                    .privacySensitive()
            }
            .padding(.trailing, showsMark ? 48 : 0)
            if showsInstruction {
                Text(problem.message)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(instructionLineLimit)
                    .minimumScaleFactor(0.9)
                    .privacySensitive()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Two lines; one while the `line` placement shares the column with a notice, except at accessibility sizes.
    private var instructionLineLimit: Int? {
        if typeSize.isAccessibilitySize { return nil }
        return placement == .line && card.notice != nil ? 1 : 2
    }
}
