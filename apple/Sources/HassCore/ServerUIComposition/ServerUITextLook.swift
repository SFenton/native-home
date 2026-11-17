import Foundation

// MARK: - Text look (`sh.text-style@1`)

/// How a text is sized and set beyond its style (`sh.text-style@1`): weight, digits, a point size that scales with Dynamic Type, an ink,
/// a line limit, an alignment and what happens to a line that does not fit.
///
/// Every field is optional and an empty look draws the style as it always was. ``isDeclared`` says the document wrote any of the fields,
/// even an empty `font`, which is what makes it need the id.
public struct ServerUITextLook: Equatable, Sendable {
    /// The weights a font may take, light to heavy.
    public enum Weight: String, CaseIterable, Sendable {
        case ultraLight = "ultra-light", thin, light, regular, medium, semibold, bold, heavy, black
    }
    /// Whether digits share one width.
    public enum Digits: String, CaseIterable, Sendable { case proportional, monospaced }
    /// Where a line sits across the text's width: `start` and `end` are the logical edges, so they swap in a right-to-left language.
    public enum Align: String, CaseIterable, Sendable { case start, center, end }
    /// What happens to a line that does not fit.
    public enum Overflow: String, CaseIterable, Sendable {
        /// Wrap onto more lines (the default).
        case wrap
        /// Cut with an ellipsis.
        case truncate
        /// Slide as a ticker, one line only. It holds still under Reduce Motion.
        case ticker
    }
    /// A fixed point size that scales as a text style does, up to a cap.
    public struct Scale: Equatable, Sendable {
        /// The size at the default text size.
        public var points: Double
        /// The style whose Dynamic Type curve the size follows.
        public var relativeTo: ServerUITextSize
        /// The most it may grow to, or `nil` for no limit.
        public var maxPoints: Double?

        /// Creates a scale.
        public init(points: Double, relativeTo: ServerUITextSize, maxPoints: Double? = nil) {
            self.points = points
            self.relativeTo = relativeTo
            self.maxPoints = maxPoints
        }
    }

    /// The weight over the style's own, or `nil`.
    public var weight: Weight?
    /// The digit spacing, or `nil` for the style's own.
    public var digits: Digits?
    /// The scaled point size, or `nil` for the style's own size.
    public var scale: Scale?
    /// The colour of the words, or `nil` for the style's own ink.
    public var ink: ServerUIInk?
    /// The most lines; `0` is as many as it needs. `nil` is the style's own.
    public var lines: Int?
    /// The alignment, or `nil` for the leading edge.
    public var align: Align?
    /// The overflow, or `nil` for wrap.
    public var overflow: Overflow?
    /// Whether the document wrote any look field.
    public var isDeclared = false

    /// Creates an empty look.
    public init() {}

    /// Whether the text slides as a ticker.
    public var isTicker: Bool { overflow == .ticker }

    /// Whether the text can give room to a neighbour: a line cut or slid does, a wrapped one asks for its whole width.
    public var shrinks: Bool { overflow == .truncate || overflow == .ticker }
}

/// The eleven text styles a size can follow (`sh.text-style@1`), named as the document names them.
public enum ServerUITextSize: String, CaseIterable, Sendable {
    case largeTitle = "large-title", title1, title2, title3, headline, body, callout, subheadline, footnote, caption1, caption2
}
