import FentonActivityModel
import SwiftUI

/// The big figure: a live countdown or count-up, a frozen time, a percentage, a word, or **Complete**. Always white, paused
/// or not (owner, 2026-10-17: paused is the word and the Resume button), except **Complete**, which takes the job's tint.
///
/// `Text(timerInterval:)` and `Text(_:style: .timer)` count on their own with no pushes, which is how a Live Activity shows
/// a ticking time. They take all the width offered and have **no fixed frame** here, so the regions size them
/// (spec §8a): `lineLimit(1)` with a 0.8 scale floor covers an `H:MM:SS` value at 32 pt in the narrowest region.
struct ActivityFigure: View {
    let card: ActivityCard
    /// The size at the default text setting; 32 pt on the Lock Screen and in the expanded island.
    var size: CGFloat = 32
    var relativeTo: Font.TextStyle = .largeTitle
    var alignment: Alignment = .leading

    private var style: ActivityStyle { ActivityStyle(tint: card.tint) }

    /// A word may shrink further than a time before it truncates.
    private var scaleFloor: CGFloat {
        switch card.figure {
        case .text: 0.5
        default: 0.8
        }
    }

    var body: some View {
        content
            .activityFont(size, weight: .semibold, relativeTo: relativeTo)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(scaleFloor)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    @ViewBuilder
    private var content: some View {
        if card.isComplete {
            Text("Complete").foregroundStyle(style.accent)
        } else if let text = Self.liveText(card.figure) {
            text.foregroundStyle(ActivityStyle.primaryText)
        }
    }

    /// The text for a figure: the live timer for a countdown or count-up, the frozen time, a percentage or a word. nil for
    /// ``ActivityCard/Figure/complete`` (which takes the job's tint) and ``ActivityCard/Figure/none``.
    static func liveText(_ figure: ActivityCard.Figure) -> Text? {
        switch figure {
        case let .countdown(range, showsHours, _): Text(timerInterval: range, pauseTime: nil, countsDown: true, showsHours: showsHours)
        case let .countup(start): Text(start, style: .timer)
        case let .frozen(seconds): Text(ActivityCard.clock(seconds: seconds))
        case let .percent(value): Text("\(value)%")
        case let .text(text): Text(text)
        case .complete, .none: nil
        }
    }
}
