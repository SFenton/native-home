import Foundation

// MARK: - Dial geometry (`sh.dial@1`)

/// Where the parts of a dial stand: the Studio's `dial-math.ts`, pinned by the shared evaluation corpus
/// (`ContractCorpus/evaluation/dial-*.json`), which is the weather compass and barometer made generic.
///
/// This is the one place the app's dial arithmetic lives. ``ServerUIDial`` (the authored node), `UKDialView` (the drawing) and the weather
/// panel's compass and barometer read it, and a control that draws a dial and takes a finger (a thermostat) builds on the same angles.
///
/// - Angles are degrees, clockwise on screen from 3 o'clock (UIKit's y axis points down, so `cos` is x and `sin` is y): a sweep `start` of 145
///   is lower left, 270 (or -90) is the top.
/// - A value is a share of the sweep from 0 to 1 (``Scale/unit``), 0 to 100 (``Scale/percent``) or, on a full turn, degrees (``Scale/degrees``).
///   A share outside the sweep is held at the nearest end; on a full turn it wraps instead, as a bearing does. A value that is not a number gives
///   no pointer.
/// - Ticks stand at `i / (count - 1)` of the sweep, both ends drawn; on a full turn at `i / count`, so the last does not repeat the first.
///   The radius is half the width; the centre is `centerY` of the height.
/// - A needle turns the short way round when the sweep is a full turn.
/// - A direction is not mirrored by default: a dial is an instrument in space. ``Input/mirrors`` flips the sweep about the vertical axis in a
///   right-to-left layout.
public enum ServerUIDialLayout {
    // MARK: Vocabulary

    /// How a pointer's value is read.
    public enum Scale: String, CaseIterable, Sendable {
        /// A share of the sweep from 0 to 1.
        case unit
        /// A share from 0 to 100.
        case percent
        /// Degrees of a full turn.
        case degrees
    }

    /// The arc the ticks and the pointer travel: its first angle and how far it goes, in degrees.
    public struct Sweep: Equatable, Sendable {
        /// The first angle, clockwise from 3 o'clock.
        public var start: Double
        /// How far it goes, 1 to 360.
        public var length: Double

        /// Creates a sweep.
        public init(start: Double, length: Double) {
            self.start = start
            self.length = length
        }

        /// Whether the ends meet, so a value wraps instead of being held.
        public var isFullTurn: Bool { length >= 360 }
    }

    /// One ring of tick marks, as shares of the radius.
    public struct Ring: Equatable, Sendable {
        /// How many ticks, 2 to 120.
        public var count: Int
        /// Where each tick starts.
        public var inner: Double
        /// Where each tick ends.
        public var outer: Double
        /// The inner end of every second tick (the odd ones), for long and short ticks.
        public var alternateInner: Double?
        /// The indexes that are not drawn, because something else stands there (a flag).
        public var skip: [Int]

        /// Creates a ring.
        public init(count: Int, inner: Double, outer: Double, alternateInner: Double? = nil, skip: [Int] = []) {
            self.count = count
            self.inner = inner
            self.outer = outer
            self.alternateInner = alternateInner
            self.skip = skip
        }
    }

    /// A letter round the rim.
    public struct Label: Equatable, Sendable {
        /// Its place along the sweep, 0 to 1.
        public var at: Double
        /// What it says, at most eight characters.
        public var text: String
        /// Whether it is drawn only while the pointer has a value.
        public var needsValue: Bool

        /// Creates a label.
        public init(at: Double, text: String, needsValue: Bool = false) {
            self.at = at
            self.text = text
            self.needsValue = needsValue
        }
    }

    /// What points at the value.
    public enum PointerKind: String, Sendable {
        /// One lit tick across the ring, between `inner` and `outer`.
        case tick
        /// The closed needle: a head, a tail and a dot.
        case needle
    }

    /// The pointer as the arithmetic sees it: its kind, its reading and, for a tick, where it starts and ends.
    public struct Pointer: Equatable, Sendable {
        /// The kind.
        public var kind: PointerKind
        /// The reading in the dial's ``Scale``, or `nil` when it is not known.
        public var value: Double?
        /// A tick's inner end, as a share of the radius.
        public var inner: Double
        /// A tick's outer end.
        public var outer: Double

        /// Creates a pointer.
        public init(kind: PointerKind, value: Double?, inner: Double = 0, outer: Double = 0) {
            self.kind = kind
            self.value = value
            self.inner = inner
            self.outer = outer
        }
    }

    /// The needle: a closed shape drawn at 0 turn in a square as wide as the dial, as shares of that square. The head is the triangle that
    /// points down, the tail the narrower quad above the centre, the dot sits on top.
    public enum Needle {
        /// The head's three corners.
        public static let head: [(x: Double, y: Double)] = [(0.45, 0.5), (0.55, 0.5), (0.5, 0.74)]
        /// The tail's four corners.
        public static let tail: [(x: Double, y: Double)] = [(0.45, 0.5), (0.55, 0.5), (0.52, 0.32), (0.48, 0.32)]
        /// The dot's centre.
        public static let dotAt: (x: Double, y: Double) = (0.5, 0.29)
        /// The dot's diameter as a share of the square.
        public static let dotSize = 0.07
    }

    /// How far from the centre a letter stands, as a share of the radius.
    public static let labelRadius = 0.58
    /// The flag on the rim: its tip and base as shares of the radius, and half its base.
    public static let flag = (tip: 0.94, base: 0.84, half: 0.06)

    // MARK: Angles

    /// `value` modulo 360 into `0..<360`.
    public static func normalizeDegrees(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return (remainder + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The signed shortest rotation from one angle to another, in `(-180, 180]`.
    public static func shortestTurn(from: Double, to: Double) -> Double {
        let delta = ((normalizeDegrees(to) - normalizeDegrees(from) + 540).truncatingRemainder(dividingBy: 360)) - 180
        return delta <= -180 ? 180 : delta
    }

    /// The angle a needle is turned to next so it turns the short way round: from where it is (`previous`, unwrapped, or `nil` for the first
    /// draw) to `target`. A 350 to 10 change is 20 degrees on, not 340 back.
    public static func nextTurn(previous: Double?, target: Double) -> Double {
        guard let previous else { return target }
        return previous + shortestTurn(from: previous, to: target)
    }

    /// A value as a share of the sweep from 0 to 1, or `nil` when it is not a number. Held at the ends, or wrapped on a full turn.
    public static func dialShare(_ value: Double?, scale: Scale, sweep: Sweep) -> Double? {
        guard let value, value.isFinite else { return nil }
        let share = switch scale {
        case .unit: value
        case .percent: value / 100
        case .degrees: value / 360
        }
        if sweep.isFullTurn { return (share.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) }
        return min(1, max(0, share))
    }

    /// The angle at a share of the sweep, mirrored about the vertical axis when asked: `start + share * length`.
    public static func dialAngle(share: Double, sweep: Sweep, mirrored: Bool = false) -> Double {
        let angle = sweep.start + share * sweep.length
        return mirrored ? 180 - angle : angle
    }

    /// The place of tick `index` of `count` along the sweep, 0 to 1.
    public static func tickShare(index: Int, count: Int, sweep: Sweep) -> Double {
        sweep.isFullTurn ? Double(index) / Double(count) : Double(index) / Double(count - 1)
    }

    /// The font size of a letter round the rim: a fifth of the radius, at least 10 points.
    public static func labelFontSize(radius: Double) -> Double { max(10, radius * 0.2) }

    // MARK: Layout

    /// What a dial needs to place its parts.
    public struct Input: Equatable, Sendable {
        /// The dial's width in points.
        public var width: Double
        /// Width over height.
        public var aspect: Double
        /// Where the centre sits down the height, 0 to 1.
        public var centerY: Double
        /// The arc the ticks and the pointer travel.
        public var sweep: Sweep
        /// How the pointer's value is read.
        public var scale: Scale
        /// The ring of ticks, if any.
        public var ring: Ring?
        /// The pointer, if any.
        public var pointer: Pointer?
        /// The letters round the rim.
        public var labels: [Label]
        /// A triangle on the rim at this place along the sweep.
        public var flag: Double?
        /// Whether a right-to-left layout flips the sweep.
        public var mirrors: Bool
        /// Whether the layout direction is right to left.
        public var rtl: Bool

        /// Creates an input.
        public init(width: Double, aspect: Double = 1, centerY: Double = 0.5, sweep: Sweep, scale: Scale = .unit, ring: Ring? = nil,
                    pointer: Pointer? = nil, labels: [Label] = [], flag: Double? = nil, mirrors: Bool = false, rtl: Bool = false) {
            self.width = width
            self.aspect = aspect
            self.centerY = centerY
            self.sweep = sweep
            self.scale = scale
            self.ring = ring
            self.pointer = pointer
            self.labels = labels
            self.flag = flag
            self.mirrors = mirrors
            self.rtl = rtl
        }
    }

    /// A line from `(x1, y1)` to `(x2, y2)`, in points from the dial's top left.
    public struct Segment: Equatable, Sendable {
        /// Start x.
        public let x1: Double
        /// Start y.
        public let y1: Double
        /// End x.
        public let x2: Double
        /// End y.
        public let y2: Double
    }

    /// A point in points from the dial's top left.
    public struct Point: Equatable, Sendable {
        /// Across.
        public let x: Double
        /// Down.
        public let y: Double
    }

    /// A needle's turn: `rotation` about the centre in degrees (0 is the head down, the dot up) and the sweep angle it stands for.
    public struct NeedleTurn: Equatable, Sendable {
        /// The turn of the shape drawn at 0.
        public let rotation: Double
        /// The pointer's angle on the sweep.
        public let angle: Double
    }

    /// A letter placed on the rim, centred at `(x, y)`.
    public struct PlacedLabel: Equatable, Sendable {
        /// What it says.
        public let text: String
        /// Centre x.
        public let x: Double
        /// Centre y.
        public let y: Double
        /// Its font size in points.
        public let fontSize: Double
    }

    /// The parts of a dial, in points from its top left. A part that is not drawn is `nil` or empty.
    public struct Layout: Equatable, Sendable {
        /// The width.
        public let width: Double
        /// The height.
        public let height: Double
        /// The centre's x.
        public let cx: Double
        /// The centre's y.
        public let cy: Double
        /// The radius.
        public let radius: Double
        /// The ticks, in index order, without the skipped ones.
        public let ticks: [Segment]
        /// The lit tick of a `tick` pointer.
        public let lit: Segment?
        /// The turn of a `needle` pointer.
        public let needle: NeedleTurn?
        /// The letters that are drawn.
        public let labels: [PlacedLabel]
        /// The flag's three corners.
        public let flag: [Point]?
        /// The pointer's share of the sweep, 0 to 1.
        public let share: Double?
    }

    /// The width a dial is drawn at in a room `available` wide and `height` tall (0 for no limit): all the width, but no wider than `aspect` times the
    /// height, so the dial's shape fits the room. The room's width is kept when the height cap is within half a point of it.
    public static func fittedWidth(available: Double, height: Double, aspect: Double) -> Double {
        height > 0 && aspect * height < available - 0.5 ? aspect * height : available
    }

    /// Rounds to four places the way the Studio does (`Math.round`: halves go up), and never gives a negative zero.
    static func round4(_ value: Double) -> Double { ((value * 10_000 + 0.5).rounded(.down) / 10_000) + 0 }

    /// Places every part of a dial.
    public static func layoutDial(_ input: Input) -> Layout {
        let width = input.width, sweep = input.sweep
        let mirrored = input.mirrors && input.rtl
        let height = width / input.aspect
        let radius = width / 2, cx = width / 2, cy = height * input.centerY
        func at(_ angle: Double, _ share: Double) -> Point {
            let radians = angle * .pi / 180
            return Point(x: cx + cos(radians) * radius * share, y: cy + sin(radians) * radius * share)
        }
        func segment(_ angle: Double, _ inner: Double, _ outer: Double) -> Segment {
            let from = at(angle, inner), to = at(angle, outer)
            return Segment(x1: round4(from.x), y1: round4(from.y), x2: round4(to.x), y2: round4(to.y))
        }
        var ticks: [Segment] = []
        if let ring = input.ring {
            for index in 0..<ring.count where !ring.skip.contains(index) {
                let angle = dialAngle(share: tickShare(index: index, count: ring.count, sweep: sweep), sweep: sweep, mirrored: mirrored)
                ticks.append(segment(angle, ring.alternateInner.flatMap { index % 2 == 1 ? $0 : nil } ?? ring.inner, ring.outer))
            }
        }
        let share = input.pointer.flatMap { dialShare($0.value, scale: input.scale, sweep: sweep) }
        var lit: Segment?, needle: NeedleTurn?
        if let pointer = input.pointer, let share {
            let angle = dialAngle(share: share, sweep: sweep, mirrored: mirrored)
            switch pointer.kind {
            case .tick: lit = segment(angle, pointer.inner, pointer.outer)
            case .needle: needle = NeedleTurn(rotation: round4(angle + 90), angle: round4(angle))
            }
        }
        let fontSize = labelFontSize(radius: radius)
        let labels = input.labels.filter { !$0.needsValue || share != nil }.map { label -> PlacedLabel in
            let place = at(dialAngle(share: label.at, sweep: sweep, mirrored: mirrored), labelRadius)
            return PlacedLabel(text: label.text, x: round4(place.x), y: round4(place.y), fontSize: round4(fontSize))
        }
        var flagPoints: [Point]?
        if let flagAt = input.flag {
            let angle = dialAngle(share: flagAt, sweep: sweep, mirrored: mirrored), radians = angle * .pi / 180
            // The base corners sit either side of the radius, along its normal.
            let base = at(angle, flag.base)
            let nx = -sin(radians) * radius * flag.half, ny = cos(radians) * radius * flag.half
            let tip = at(angle, flag.tip)
            flagPoints = [Point(x: round4(tip.x), y: round4(tip.y)), Point(x: round4(base.x + nx), y: round4(base.y + ny)),
                          Point(x: round4(base.x - nx), y: round4(base.y - ny))]
        }
        return Layout(width: round4(width), height: round4(height), cx: round4(cx), cy: round4(cy), radius: round4(radius), ticks: ticks, lit: lit,
                      needle: needle, labels: labels, flag: flagPoints, share: share)
    }
}
