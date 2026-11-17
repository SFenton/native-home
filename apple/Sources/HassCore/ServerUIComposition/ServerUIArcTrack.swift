import Foundation

// MARK: - Arc track (`sh.arc-track@1`)

/// An arc with a marker (`sh.arc-track@1`): a curve (a quadratic Bezier from `from` to `to`, bent toward `control`) in a `box` whose shape sets
/// the height, an optional horizon line, and a marker at `progress` along the curve. It is the weather panel's daylight arc made generic.
///
/// It is as wide as the room allows up to ``maxWidth``. Line widths, dashes and the marker are points and do not scale. No progress hides the
/// marker. ``ServerUIArcLayout`` places the parts; `UKArcTrackView` draws them from values only.
public struct ServerUIArcTrack: Equatable, Sendable {
    /// A dashed stroke: the line and the gap, in points.
    public struct Dash: Equatable, Sendable {
        /// The drawn length.
        public var stroke: Double
        /// The gap.
        public var gap: Double

        /// Creates a dash.
        public init(stroke: Double, gap: Double) {
            self.stroke = stroke
            self.gap = gap
        }
    }

    /// The horizon: a line with its own ink and width.
    public struct Horizon: Equatable, Sendable {
        /// Its two ends in the box's own units.
        public var line: ServerUIArcLayout.Line
        /// The colour.
        public var ink: ServerUIInk
        /// The stroke width in points.
        public var width: Double

        /// Creates a horizon.
        public init(line: ServerUIArcLayout.Line, ink: ServerUIInk, width: Double) {
            self.line = line
            self.ink = ink
            self.width = width
        }
    }

    /// The marker: a filled circle.
    public struct Marker: Equatable, Sendable {
        /// The diameter in points.
        public var size: Double
        /// The colour.
        public var ink: ServerUIInk

        /// Creates a marker.
        public init(size: Double, ink: ServerUIInk) {
            self.size = size
            self.ink = ink
        }
    }

    /// What an assistive technology makes of the arc.
    public enum Accessibility: Equatable, Sendable {
        /// Nothing: the arc is decoration.
        case hidden
        /// One element named `label` whose value is `value`, or the marker's percent when there is none.
        case value(label: ServerUICompositionDocument.StringValue, value: ServerUICompositionDocument.StringValue?)
    }

    /// The node's id, title and layout.
    public let node: ServerUICompositionDocument.Node
    /// The curve in the box's own units.
    public var curve: ServerUIArcLayout.Curve
    /// The box that sets the shape.
    public var box: ServerUIArcLayout.Box
    /// The most the arc is wide, in points.
    public var maxWidth: Double?
    /// The curve's colour.
    public var ink: ServerUIInk
    /// The curve's stroke width in points.
    public var width: Double
    /// The dashes, or `nil` for a solid line.
    public var dash: Dash?
    /// The horizon line.
    public var horizon: Horizon?
    /// The reading the marker stands at, or `nil` for no marker.
    public var progress: ServerUIOperand?
    /// How progress is read.
    public var scale: ServerUIArcLayout.Scale
    /// The marker.
    public var marker: Marker?
    /// Whether a right-to-left layout mirrors the arc, so progress still runs from the reading start.
    public var mirrors: Bool
    /// What an assistive technology makes of it.
    public var accessibility: Accessibility

    /// Creates an arc.
    public init(node: ServerUICompositionDocument.Node, curve: ServerUIArcLayout.Curve, box: ServerUIArcLayout.Box, maxWidth: Double? = nil,
                ink: ServerUIInk, width: Double, dash: Dash? = nil, horizon: Horizon? = nil, progress: ServerUIOperand? = nil,
                scale: ServerUIArcLayout.Scale = .unit, marker: Marker? = nil, mirrors: Bool = true, accessibility: Accessibility = .hidden) {
        self.node = node
        self.curve = curve
        self.box = box
        self.maxWidth = maxWidth
        self.ink = ink
        self.width = width
        self.dash = dash
        self.horizon = horizon
        self.progress = progress
        self.scale = scale
        self.marker = marker
        self.mirrors = mirrors
        self.accessibility = accessibility
    }

    /// The source ids the arc reads.
    public var sourceIds: Set<String> {
        var ids = progress?.sourceIds ?? []
        if case .value(let label, let spoken) = accessibility {
            ids.formUnion(ServerUIStringResolver.sourceIds(label))
            if let spoken { ids.formUnion(ServerUIStringResolver.sourceIds(spoken)) }
        }
        return ids
    }

    /// The arithmetic input for this arc across `width` points with the reading `value`, in the direction `rtl`.
    public func layoutInput(width: Double, value: Double?, rtl: Bool) -> ServerUIArcLayout.Input {
        ServerUIArcLayout.Input(curve: curve, box: box, maxWidth: maxWidth, horizon: horizon?.line, width: width,
                                progress: marker == nil ? nil : value, scale: scale, mirrors: mirrors, rtl: rtl)
    }
}
