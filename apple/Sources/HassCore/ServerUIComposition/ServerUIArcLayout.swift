import Foundation

// MARK: - Arc geometry (`sh.arc-track@1`)

/// Where the parts of an arc stand: the Studio's `arc-track-math.ts`, pinned by the shared evaluation corpus
/// (`ContractCorpus/evaluation/arc-track-*.json`), which is the weather panel's daylight arc made generic.
///
/// - The arc is as wide as the room allows up to `maxWidth`, and as tall as the box's shape gives. Positions scale with the width; line widths,
///   dashes and the marker's size are points and do not.
/// - Progress is a share of the curve from 0 to 1 (``Scale/unit``) or 0 to 100 (``Scale/percent``); outside it is held at the nearest end, and one
///   that is not a number hides the marker.
/// - The marker stands on the curve at parameter `t`: `B(t) = (1-t)^2 from + 2t(1-t) control + t^2 to`.
/// - Progress runs from the curve's `from` end to its `to` end, the reading direction: a right-to-left layout mirrors it, unless the document says
///   `mirrors: false`.
public enum ServerUIArcLayout {
    /// How progress is read.
    public enum Scale: String, CaseIterable, Sendable {
        /// A share from 0 to 1.
        case unit
        /// A share from 0 to 100.
        case percent
    }

    /// A point in the box, `[x, y]`.
    public struct Point: Equatable, Sendable {
        /// Across.
        public var x: Double
        /// Down.
        public var y: Double

        /// Creates a point.
        public init(_ x: Double, _ y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// The curve's two ends and its control point, in the box's own units.
    public struct Curve: Equatable, Sendable {
        /// Where it starts.
        public var from: Point
        /// What it bends toward.
        public var control: Point
        /// Where it ends.
        public var to: Point

        /// Creates a curve.
        public init(from: Point, control: Point, to: Point) {
            self.from = from
            self.control = control
            self.to = to
        }
    }

    /// A line's two ends, in the box's own units.
    public struct Line: Equatable, Sendable {
        /// Where it starts.
        public var from: Point
        /// Where it ends.
        public var to: Point

        /// Creates a line.
        public init(from: Point, to: Point) {
            self.from = from
            self.to = to
        }
    }

    /// The box's width and height in its own units: its shape is the arc's.
    public struct Box: Equatable, Sendable {
        /// Width.
        public var width: Double
        /// Height.
        public var height: Double

        /// Creates a box.
        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    /// What an arc needs to place its parts.
    public struct Input: Equatable, Sendable {
        /// The curve.
        public var curve: Curve
        /// The box's width and height in its own units: it sets the shape.
        public var box: Box
        /// The most the arc is wide, in points, or `nil` for the room it has.
        public var maxWidth: Double?
        /// The horizon line, if any.
        public var horizon: Line?
        /// The width the arc has to fill, in points.
        public var width: Double
        /// Progress along the curve; `nil` when it is not known.
        public var progress: Double?
        /// How progress is read.
        public var scale: Scale
        /// Whether a right-to-left layout mirrors the positions.
        public var mirrors: Bool
        /// Whether the layout direction is right to left.
        public var rtl: Bool

        /// Creates an input.
        public init(curve: Curve, box: Box, maxWidth: Double? = nil, horizon: Line? = nil, width: Double,
                    progress: Double? = nil, scale: Scale = .unit, mirrors: Bool = true, rtl: Bool = false) {
            self.curve = curve
            self.box = box
            self.maxWidth = maxWidth
            self.horizon = horizon
            self.width = width
            self.progress = progress
            self.scale = scale
            self.mirrors = mirrors
            self.rtl = rtl
        }
    }

    /// The marker's centre and its parameter on the curve, from 0 to 1.
    public struct Marker: Equatable, Sendable {
        /// Centre x in points.
        public let x: Double
        /// Centre y in points.
        public let y: Double
        /// The parameter on the curve.
        public let t: Double
    }

    /// The parts of an arc in points from its top left. A part that is not drawn is `nil`.
    public struct Layout: Equatable, Sendable {
        /// The width drawn.
        public let width: Double
        /// The height drawn.
        public let height: Double
        /// The curve.
        public let curve: Curve
        /// The horizon.
        public let horizon: Line?
        /// The marker.
        public let marker: Marker?
    }

    /// Progress as a parameter on the curve, 0 to 1, or `nil` when it is not a number.
    public static func progress(_ value: Double?, scale: Scale = .unit) -> Double? {
        guard let value, value.isFinite else { return nil }
        let share = scale == .unit ? value : value / 100
        return min(1, max(0, share))
    }

    /// The point at parameter `t` of a quadratic curve.
    public static func curvePoint(_ curve: Curve, t: Double) -> Point {
        let a = (1 - t) * (1 - t), b = 2 * t * (1 - t), c = t * t
        return Point(a * curve.from.x + b * curve.control.x + c * curve.to.x, a * curve.from.y + b * curve.control.y + c * curve.to.y)
    }

    private static func round4(_ value: Double) -> Double { ServerUIDialLayout.round4(value) }
    private static func round6(_ value: Double) -> Double { ((value * 1e6 + 0.5).rounded(.down) / 1e6) + 0 }

    /// Places the curve, the horizon and the marker of an arc.
    public static func layoutArc(_ input: Input) -> Layout {
        let drawWidth = min(input.width, input.maxWidth ?? .infinity)
        let scale = drawWidth / input.box.width
        let mirrored = input.mirrors && input.rtl
        func place(_ point: Point) -> Point {
            Point(round4((mirrored ? input.box.width - point.x : point.x) * scale), round4(point.y * scale))
        }
        var marker: Marker?
        if let t = progress(input.progress, scale: input.scale) {
            let point = place(curvePoint(input.curve, t: t))
            marker = Marker(x: point.x, y: point.y, t: round6(t))
        }
        return Layout(width: round4(drawWidth), height: round4(input.box.height * scale),
                      curve: Curve(from: place(input.curve.from), control: place(input.curve.control), to: place(input.curve.to)),
                      horizon: input.horizon.map { Line(from: place($0.from), to: place($0.to)) }, marker: marker)
    }
}
