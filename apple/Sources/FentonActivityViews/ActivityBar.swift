import FentonActivityModel
import SwiftUI

/// The 5 pt progress bar under the value, in the job's tint. A time range fills itself (`ProgressView(timerInterval:)`, which
/// counts with no pushes); a fraction and a finished job's full bar are drawn as given. Present only when the card has
/// progress (``ActivityCard/bar``). Decoration: the value above it says the same in words.
struct ActivityBar: View {
    let card: ActivityCard
    let bar: ActivityCard.Bar
    @Environment(\.activityStaticTimerRing) private var staticTimer

    private var accent: Color { ActivityStyle(tint: card.tint).accent }

    var body: some View {
        content
            .progressViewStyle(.linear)
            .tint(accent)
            // The system draws the linear bar about 4 pt thick; this makes it 5.
            .scaleEffect(x: 1, y: ActivityStyle.barHeight / 4, anchor: .center)
            .frame(height: ActivityStyle.barHeight)
            .dimsWhenAlwaysOn()
            .accessibilityHidden(true)
            .accessibilityIdentifier("liveactivity.bar")
    }

    @ViewBuilder
    private var content: some View {
        switch bar {
        case let .timer(range):
            if staticTimer {
                ProgressView(value: elapsed(of: range))
            } else {
                ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            }
        case let .fraction(value):
            ProgressView(value: value)
        case .full:
            ProgressView(value: 1.0)
        }
    }

    private func elapsed(of range: ClosedRange<Date>) -> Double {
        // The card only builds a bar range with its end after its start.
        let total = range.upperBound.timeIntervalSince(range.lowerBound)
        return min(max(card.now.timeIntervalSince(range.lowerBound) / total, 0), 1)
    }
}
