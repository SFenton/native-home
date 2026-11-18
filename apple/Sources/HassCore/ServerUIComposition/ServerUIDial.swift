import Foundation

// MARK: - Dial (`sh.dial@1`)

/// A circular gauge (`sh.dial@1`): ticks along a sweep, letters round the rim, a flag, a pointer at a value and up to three lines of text in
/// the middle. It is the weather panel's compass and barometer made generic, and the app's one dial: ``ServerUIDialLayout`` places the parts and
/// `UKDialView` draws them from values only.
///
/// The dial is as wide as ``size`` (scaled with the text size) or the room it has, up to ``maxWidth``, and ``aspect`` wide to 1 tall; the centre
/// sits ``centerY`` down. It is read as one meter when ``accessibility`` names it, else hidden; the text in the middle and the letters are not
/// read on their own.
public struct ServerUIDial: Equatable, Sendable {
    /// What points at the value.
    public enum Pointer: Equatable, Sendable {
        /// One lit tick across the ring, between `inner` and `outer` (shares of the radius).
        case tick(value: ServerUIOperand, inner: Double, outer: Double, width: Double, ink: ServerUIInk)
        /// The one closed needle style: a head, a tail and a dot, in three inks. It turns to the value and, on a full turn, the short way round
        /// unless Reduce Motion is on or `animates` is false.
        case needle(value: ServerUIOperand, ink: ServerUIInk, tailInk: ServerUIInk, dotInk: ServerUIInk, animates: Bool)

        /// The operand the pointer reads.
        public var value: ServerUIOperand {
            switch self {
            case .tick(let value, _, _, _, _), .needle(let value, _, _, _, _): value
            }
        }
    }

    /// One ring of tick marks, with its stroke.
    public struct Ticks: Equatable, Sendable {
        /// Where the ticks stand.
        public var ring: ServerUIDialLayout.Ring
        /// The stroke width in points.
        public var width: Double
        /// The colour.
        public var ink: ServerUIInk

        /// Creates ticks.
        public init(ring: ServerUIDialLayout.Ring, width: Double, ink: ServerUIInk) {
            self.ring = ring
            self.width = width
            self.ink = ink
        }
    }

    /// The letters round the rim and their colour.
    public struct Labels: Equatable, Sendable {
        /// The colour.
        public var ink: ServerUIInk
        /// The letters.
        public var items: [ServerUIDialLayout.Label]

        /// Creates labels.
        public init(ink: ServerUIInk, items: [ServerUIDialLayout.Label]) {
            self.ink = ink
            self.items = items
        }
    }

    /// A small triangle on the rim.
    public struct Flag: Equatable, Sendable {
        /// Its place along the sweep, 0 to 1.
        public var at: Double
        /// The colour.
        public var ink: ServerUIInk

        /// Creates a flag.
        public init(at: Double, ink: ServerUIInk) {
            self.at = at
            self.ink = ink
        }
    }

    /// A size that scales with the text size.
    public struct Size: Equatable, Sendable {
        /// The width at the default text size.
        public var points: Double
        /// The text style whose curve it follows; `nil` is a fixed width.
        public var relativeTo: ServerUITextSize?
        /// The most it grows to.
        public var maxPoints: Double?

        /// Creates a size.
        public init(points: Double, relativeTo: ServerUITextSize? = nil, maxPoints: Double? = nil) {
            self.points = points
            self.relativeTo = relativeTo
            self.maxPoints = maxPoints
        }
    }

    /// One line of text in the middle: the props of a `text`.
    public struct Line: Equatable, Sendable {
        /// The words.
        public var value: ServerUICompositionDocument.StringValue
        /// The text style.
        public var style: ServerUICompositionDocument.TextStyle
        /// What it says while the value is unavailable.
        public var unavailableText: String
        /// Weight, digits, scaled size, ink, lines, alignment and overflow over the style.
        public var look: ServerUITextLook

        /// Creates a line.
        public init(value: ServerUICompositionDocument.StringValue, style: ServerUICompositionDocument.TextStyle, unavailableText: String,
                    look: ServerUITextLook = ServerUITextLook()) {
            self.value = value
            self.style = style
            self.unavailableText = unavailableText
            self.look = look
        }
    }

    /// Where the middle of the block of centre lines stands: a share of the dial's height plus a distance in points that does not scale with the text.
    public struct TextPlace: Equatable, Sendable {
        /// How far down the height the block's middle stands, 0 to 1, or `nil` for the ring's `centerY`.
        public var share: Double?
        /// Points added below that; plain points, whatever the text size.
        public var offset: Double

        /// Creates a place.
        public init(share: Double? = nil, offset: Double = 0) {
            self.share = share
            self.offset = offset
        }
    }

    /// What an assistive technology makes of the dial.
    public enum Accessibility: Equatable, Sendable {
        /// Nothing: the dial is decoration.
        case hidden
        /// One element named `label` whose value is `value`, or the pointer's percent when there is none.
        case value(label: ServerUICompositionDocument.StringValue, value: ServerUICompositionDocument.StringValue?)
    }

    /// The node's id, title and layout.
    public let node: ServerUICompositionDocument.Node
    /// The arc the ticks and the pointer travel.
    public var sweep: ServerUIDialLayout.Sweep
    /// How the pointer's value is read.
    public var scale: ServerUIDialLayout.Scale
    /// Width over height, 0.5 to 2.
    public var aspect: Double
    /// How far down the height the centre sits, 0 to 1.
    public var centerY: Double
    /// The width that scales with the text size, or `nil` for the room it has.
    public var size: Size?
    /// The most the dial is wide, in points.
    public var maxWidth: Double?
    /// The ring of ticks.
    public var ticks: Ticks?
    /// The pointer.
    public var pointer: Pointer?
    /// The letters.
    public var labels: Labels?
    /// The flag.
    public var flag: Flag?
    /// The lines of text in the middle, from the top.
    public var center: [Line]
    /// Where the block of lines stands when it is not on the ring's centre, or `nil` for the ring's centre. A document does not carry it yet.
    public var textPlace: TextPlace?
    /// Whether a right-to-left layout flips the sweep. A dial is an instrument in space: it does not by default.
    public var mirrors: Bool
    /// What an assistive technology makes of it.
    public var accessibility: Accessibility

    /// Creates a dial.
    public init(node: ServerUICompositionDocument.Node, sweep: ServerUIDialLayout.Sweep, scale: ServerUIDialLayout.Scale = .unit, aspect: Double = 1,
                centerY: Double = 0.5, size: Size? = nil, maxWidth: Double? = nil, ticks: Ticks? = nil, pointer: Pointer? = nil, labels: Labels? = nil,
                flag: Flag? = nil, center: [Line] = [], textPlace: TextPlace? = nil, mirrors: Bool = false, accessibility: Accessibility = .hidden) {
        self.node = node
        self.sweep = sweep
        self.scale = scale
        self.aspect = aspect
        self.centerY = centerY
        self.size = size
        self.maxWidth = maxWidth
        self.ticks = ticks
        self.pointer = pointer
        self.labels = labels
        self.flag = flag
        self.center = center
        self.textPlace = textPlace
        self.mirrors = mirrors
        self.accessibility = accessibility
    }

    /// The source ids the dial reads.
    public var sourceIds: Set<String> {
        var ids = pointer?.value.sourceIds ?? []
        for line in center { ids.formUnion(ServerUIStringResolver.sourceIds(line.value)) }
        if case .value(let label, let spoken) = accessibility {
            ids.formUnion(ServerUIStringResolver.sourceIds(label))
            if let spoken { ids.formUnion(ServerUIStringResolver.sourceIds(spoken)) }
        }
        return ids
    }

    /// The top of the block of centre lines, down from the dial's top: its middle stands at ``TextPlace/share`` of `height` (the ring's ``centerY`` when
    /// the dial states no place) plus ``TextPlace/offset`` points.
    /// - Parameters:
    ///   - height: The dial's height in points.
    ///   - blockHeight: The height of all the lines together, in points.
    public func textBlockTop(height: Double, blockHeight: Double) -> Double {
        height * (textPlace?.share ?? centerY) + (textPlace?.offset ?? 0) - blockHeight / 2
    }

    /// The arithmetic input for this dial at `width` with the pointer's reading, in the direction `rtl`.
    public func layoutInput(width: Double, value: Double?, rtl: Bool) -> ServerUIDialLayout.Input {
        let placed: ServerUIDialLayout.Pointer? = switch pointer {
        case .tick(_, let inner, let outer, _, _)?: .init(kind: .tick, value: value, inner: inner, outer: outer)
        case .needle?: .init(kind: .needle, value: value)
        case nil: nil
        }
        return ServerUIDialLayout.Input(width: width, aspect: aspect, centerY: centerY, sweep: sweep, scale: scale, ring: ticks?.ring, pointer: placed,
                                        labels: labels?.items ?? [], flag: flag?.at, mirrors: mirrors, rtl: rtl)
    }
}
