import FentonActivityModel
import SwiftUI

/// The ring around a card's glyph: 64 pt on the Lock Screen, 34 pt beside the island's camera, 26 pt in the compact
/// island. It fills itself as time passes when the card has a time range (`ProgressView(timerInterval:)`, which counts
/// with no pushes), draws a reported fraction, stays full for a count-up, and becomes a filled ring with a check when
/// the job is Complete.
struct ActivityRing: View {
    let card: ActivityCard
    var diameter: CGFloat = ActivityStyle.ringSize
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.activityStaticTimerRing) private var staticTimerRing

    private var style: ActivityStyle { ActivityStyle(tint: card.tint) }
    private var lineWidth: CGFloat { max(3, diameter * 6 / 64) }
    /// Paused is the word and the Resume button, so the ring does not dim.
    private var accent: Color { style.accent }

    var body: some View {
        ZStack {
            ring
            center
        }
        // Always-On: the ring and its glyph keep a fraction of their brightness (``ActivityStyle/alwaysOnDimming``).
        .dimsWhenAlwaysOn()
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var ring: some View {
        switch card.ring {
        case let .timer(range):
            if staticTimerRing {
                fraction(elapsed(of: range))
            } else {
                ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular)
                    .tint(accent)
            }
        case let .fraction(value):
            fraction(value)
        case .steady:
            Circle().stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)).padding(lineWidth / 2)
        case .track:
            track
        case .complete:
            Circle().fill(style.accent.opacity(0.18)).padding(lineWidth / 2)
            Circle().stroke(style.accent, lineWidth: lineWidth).padding(lineWidth / 2)
        }
    }

    private func fraction(_ value: Double) -> some View {
        ZStack {
            track
            Circle().trim(from: 0, to: value)
                .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(lineWidth / 2)
        }
    }

    private func elapsed(of range: ClosedRange<Date>) -> Double {
        // The card only builds a ring range with its end after its start.
        let total = range.upperBound.timeIntervalSince(range.lowerBound)
        return min(max(card.now.timeIntervalSince(range.lowerBound) / total, 0), 1)
    }

    /// The ring's empty track; Always-On drops it (spec §8).
    @ViewBuilder
    private var track: some View {
        if !isLuminanceReduced {
            Circle().stroke(ActivityStyle.track, lineWidth: lineWidth).padding(lineWidth / 2)
        }
    }

    @ViewBuilder
    private var center: some View {
        if card.isComplete {
            Image(systemName: "checkmark")
                .font(.system(size: diameter * 0.40, weight: .heavy))
                .foregroundStyle(style.accent)
        } else {
            ActivityGlyphImage(glyph: card.glyph, size: diameter * 0.40, color: accent)
        }
    }
}
