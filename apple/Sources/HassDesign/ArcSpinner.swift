import SwiftUI

/// The app's one loading indicator: the web's arc (`DashboardPageLoading.module.css` `.arc`), not the system
/// petal spinner (owner, 2026-10-14: "For loading spinners, can we use native arc spinners like the web?";
/// `.agents/design/direction-g.md`, Loading and feedback).
///
/// A ring at 22% of the foreground style with its top quarter at 96% and its right quarter at 72%, turning once
/// every 0.82 s. It takes the colour of the text around it, so it can sit in a tinted button. With Reduce Motion it
/// turns at half speed rather than stopping, because a still arc reads as frozen.
public struct ArcSpinner: View {
    /// How big the arc is drawn.
    public enum Size: Sendable {
        /// 44 pt with a 3 pt ring: a page or sheet that is loading.
        case page
        /// 20 pt with a 2.5 pt ring: pills and rows ("Updating", "Looking for a Barcode").
        case compact
        /// 16 pt with a 2 pt ring: inside a button or next to a subtitle ("Sending Open", "Connecting").
        case inline

        public var diameter: CGFloat {
            switch self {
            case .page: 44
            case .compact: 20
            case .inline: 16
            }
        }

        /// Whether the arc grows with Dynamic Type: the in-line arcs sit beside text (`.footnote`) and follow it; the page
        /// arc is a hero and stays 44 pt.
        public var scalesWithText: Bool { self != .page }

        public var lineWidth: CGFloat {
            switch self {
            case .page: 3
            case .compact: 2.5
            case .inline: 2
            }
        }
    }

    /// Seconds per turn (web `dashboardPageLoadingSpin 820ms linear infinite`).
    public nonisolated static let period: TimeInterval = 0.82

    private let size: Size
    private let label: String
    private let maxScale: CGFloat?
    /// How much larger than the default the text around the arc is (`.footnote`).
    @ScaledMetric(relativeTo: .footnote) private var textScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.animationsPaused) private var paused

    /// Creates a spinner.
    /// - Parameters:
    ///   - size: How big to draw it.
    ///   - label: What VoiceOver says: "Loading", or the action it stands for ("Sending Open").
    ///   - maxScale: The most the arc may grow with Dynamic Type, as a multiple of its default diameter, for an arc that
    ///     lives in fixed chrome (the header's reconnecting arc is 1.5×); `nil` follows the text without a ceiling.
    public init(_ size: Size = .page, label: String = "Loading", maxScale: CGFloat? = nil) {
        self.size = size
        self.label = label
        self.maxScale = maxScale
    }

    /// The factor the arc is drawn at for text that is `textScale` times its default: 1 for the page arc, else the text
    /// scale up to `maxScale`.
    public static func scale(for size: Size, textScale: CGFloat, maxScale: CGFloat? = nil) -> CGFloat {
        guard size.scalesWithText else { return 1 }
        return Swift.max(1, Swift.min(textScale, maxScale ?? textScale))
    }

    public var body: some View {
        let scale = Self.scale(for: size, textScale: textScale, maxScale: maxScale)
        let lineWidth = size.lineWidth * scale
        TimelineView(.animation(paused: paused)) { context in
            ZStack {
                Circle()
                    .stroke(.foreground.opacity(0.22), lineWidth: lineWidth)
                quarter(centredAt: -90, opacity: 0.96, lineWidth: lineWidth)
                quarter(centredAt: 0, opacity: 0.72, lineWidth: lineWidth)
            }
            .padding(lineWidth / 2)
            .rotationEffect(.degrees(Self.angle(at: context.date, reduceMotion: reduceMotion)))
        }
        .frame(width: size.diameter * scale, height: size.diameter * scale)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityAddTraits(.updatesFrequently)
        // A status, not a control: the 16 pt inline arc would otherwise fail the audit's hit-area check.
        .accessibilityRespondsToUserInteraction(false)
    }

    /// One quarter of the ring, centred on `degrees` (0 is the trailing edge, -90 the top), like a CSS border side.
    private func quarter(centredAt degrees: Double, opacity: Double, lineWidth: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: 0.25)
            .stroke(.foreground.opacity(opacity), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            .rotationEffect(.degrees(degrees - 45))
    }

    /// The arc's rotation at `date`, in degrees: one turn per ``period``, or per twice that with Reduce Motion.
    public nonisolated static func angle(at date: Date, reduceMotion: Bool) -> Double {
        let period = reduceMotion ? Self.period * 2 : Self.period
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return phase * 360
    }
}

#Preview("Arc spinner sizes") {
    HStack(spacing: 24) {
        ArcSpinner(.page)
        ArcSpinner(.compact)
        ArcSpinner(.inline)
            .foregroundStyle(.orange)
    }
    .padding()
    .background(.black)
    .foregroundStyle(.white)
}
