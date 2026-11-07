import FentonActivityModel
import HassDesign
import SwiftUI

/// Direction G for the Live Activity (`.agents/design/direction-g.md`, Colour families): a card's ring, glyph and
/// figure take its device family's colour, on the activity's dark ground, and a problem takes its severity's colour
/// (`.agents/platforms/apple/live-activities-per-job.md` §8).
///
/// The Lock Screen background is a dark tint and the Dynamic Island is always black, so these use the dark values
/// of the family (never `ColorFamily.glyph`, which adapts to the appearance of a page or sheet).
public struct ActivityStyle: Sendable, Equatable {
    /// The family.
    public let family: ColorFamily

    /// The style for a card's `tint` name (a `ColorFamily` raw value; unknown names read neutral).
    public init(tint: String) {
        family = ColorFamily(rawValue: tint) ?? .neutral
    }

    /// The ring, glyph and Complete accent on the dark ground (at least 6.4:1 on black for every family, so the compact island's 15 pt semibold text clears 4.5:1; pinned by `ActivityStyleTests`).
    public var accent: Color { Color(rgb: family.spec.glyph) }

    /// The ring's track: the accent's family at a low opacity.
    public static let track = Color.white.opacity(0.14)

    // MARK: Text

    /// White at full strength: titles and figures.
    public static let primaryText = Color.white
    /// Supporting text: 78% white, 4.5:1 or better on ``cardFill`` over any wallpaper (`ActivityStyleTests`).
    public static let secondaryText = Color.white.opacity(0.78)
    /// A notice in place of the figure ("Couldn't reach Home").
    public static let noticeText = Color(rgb: 0xFFD59A)

    // MARK: Job card ground

    /// The job card's glass: `rgba(23, 24, 30, .78)` (canvas board 6).
    public static let cardFill = Color(rgb: 0x17181E).opacity(0.78)
    /// The opacity of ``cardFill`` (the contrast test blends with it).
    public static let cardOpacity = 0.78
    /// The card's hairline.
    public static let hairline = Color.white.opacity(0.08)
    /// The system's background tint for a job activity.
    public static let ground = cardFill

    // MARK: Buttons

    /// A primary button's fill (white pill, black text).
    public static let primaryButtonFill = Color.white
    /// A primary button's text.
    public static let primaryButtonText = Color.black
    /// A secondary button's fill (dark pill, white text).
    public static let secondaryButtonFill = Color.white.opacity(0.14)

    // MARK: Problems

    /// How a problem's severity paints the card.
    public struct Severity: Sendable {
        /// The solid circle behind the glyph.
        public let circle: Color
        /// The problem line, in the severity's light tint.
        public let lightText: Color
        /// The card's gradient, top to bottom.
        public let gradient: [Color]
        /// The card's hairline.
        public let hairline: Color
        /// A solid colour for the system's background tint (the gradient cannot be one).
        public let ground: Color
        /// The hex of ``circle`` (the contrast test reads it).
        public let circleRGB: UInt32
        /// The hex of ``lightText``.
        public let lightTextRGB: UInt32
    }

    /// The red of a critical problem: it stopped and needs you.
    public static let critical = Severity(
        circle: Color(rgb: 0xFF453A), lightText: Color(rgb: 0xFFB4AE),
        gradient: [Color(.sRGB, red: 1, green: 69 / 255, blue: 58 / 255, opacity: 0.30), Color(.sRGB, red: 120 / 255, green: 20 / 255, blue: 20 / 255, opacity: 0.55)],
        hairline: Color(.sRGB, red: 1, green: 120 / 255, blue: 110 / 255, opacity: 0.45), ground: Color(rgb: 0x3E1614).opacity(0.92),
        circleRGB: 0xFF453A, lightTextRGB: 0xFFB4AE)

    /// The amber of a warning: it carries on but needs attention.
    public static let warning = Severity(
        circle: Color(rgb: 0xFF9F0A), lightText: Color(rgb: 0xFFD59A),
        gradient: [Color(.sRGB, red: 1, green: 159 / 255, blue: 10 / 255, opacity: 0.26), Color(.sRGB, red: 110 / 255, green: 62 / 255, blue: 0, opacity: 0.50)],
        hairline: Color(.sRGB, red: 1, green: 190 / 255, blue: 90 / 255, opacity: 0.45), ground: Color(rgb: 0x3A2808).opacity(0.92),
        circleRGB: 0xFF9F0A, lightTextRGB: 0xFFD59A)

    /// The colours for a severity.
    public static func severity(_ severity: ActivityProblem.Severity) -> Severity {
        severity == .critical ? critical : warning
    }

    /// The system's background tint for a card.
    public static func ground(for card: ActivityCard) -> Color {
        if case let .problem(level) = card.style { return severity(level).ground }
        return cardFill
    }

    // MARK: Metrics

    /// Smallest comfortable hit area for a button (HIG: 44 pt).
    public static let minimumHit: CGFloat = 44
    /// The button pill's visible height (the 44 pt hit area extends past it).
    public static let buttonHeight: CGFloat = 36
    /// The job card's ring.
    public static let ringSize: CGFloat = 64
    /// The corner mark (house and heart) on a job card and beside the island's camera (spec §8a).
    public static let markSize: CGFloat = 24
    /// The corner mark on a problem card, which keeps its own layout.
    public static let problemMarkSize: CGFloat = 40
    /// The glyph in the Lock Screen's first line.
    public static let headerGlyphSize: CGFloat = 22
    /// The glyph beside the island's camera.
    public static let islandGlyphSize: CGFloat = 24
    /// The thin bar under the value.
    public static let barHeight: CGFloat = 5
    /// The compact island's time: 15 pt semibold at the default size (spec: 13 to 15), monospaced. A text style rather than a
    /// fixed size, so the template under it and the live text scale together and the width stays the template's.
    public static let compactTimeFont: Font = .subheadline.weight(.semibold).monospacedDigit()
    /// The compact island's word (a vacuum's `short`): 13 pt semibold at the default size.
    public static let compactLabelFont: Font = .footnote.weight(.semibold)
    /// The problem card's severity circle.
    public static let severityCircle: CGFloat = 44
    /// The card's corner radius.
    public static let cornerRadius: CGFloat = 24
    /// The Lock Screen limit; a taller view is cut off by the system (HIG: 160 pt, measured by `LiveActivityJourneyTests`).
    public static let lockScreenHeightLimit: CGFloat = 160
}
