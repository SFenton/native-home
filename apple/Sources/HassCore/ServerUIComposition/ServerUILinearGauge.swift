import Foundation

// MARK: - Linear gauge (`sh.linear-gauge@1`)

/// A rail: a track, an optional span and an optional marker (`sh.linear-gauge@1`).
///
/// It is the weather panel's temperature rail made generic. The ``value`` and the span's start and size are number operands from 0 to 1
/// (``Scale/unit``, the default) or 0 to 100 (``Scale/percent``); no value hides the marker. ``Fill`` says whether the ``stops`` gradient colours
/// the whole track or only the span. ``ServerUIGaugeMath`` places the parts; `UKLinearGaugeView` draws them from values only.
public struct ServerUILinearGauge: Equatable, Sendable {
    /// How a value is read.
    public enum Scale: String, CaseIterable, Sendable { case unit, percent }

    /// What the gradient colours.
    public enum Fill: String, CaseIterable, Sendable { case scale, span }

    /// One colour of the gradient, at a share of the rail from 0 to 1.
    public struct Stop: Equatable, Sendable {
        /// Where the colour stands, from 0 to 1.
        public var at: Double
        /// The colour.
        public var ink: ServerUIInk

        /// Creates a stop.
        public init(at: Double, ink: ServerUIInk) {
            self.at = at
            self.ink = ink
        }
    }

    /// The span's start and size, as operands.
    public struct Span: Equatable, Sendable {
        /// Where the span starts.
        public var start: ServerUIOperand
        /// How long the span is.
        public var size: ServerUIOperand

        /// Creates a span.
        public init(start: ServerUIOperand, size: ServerUIOperand) {
            self.start = start
            self.size = size
        }
    }

    /// The marker: a circle kept wholly inside the track.
    public struct Marker: Equatable, Sendable {
        /// The border of the marker.
        public struct Border: Equatable, Sendable {
            /// The colour of the border.
            public var ink: ServerUIInk
            /// The width in points.
            public var width: Double

            /// Creates a border.
            public init(ink: ServerUIInk, width: Double) {
                self.ink = ink
                self.width = width
            }
        }

        /// The diameter in points.
        public var size: Double
        /// The colour.
        public var ink: ServerUIInk
        /// The border, or `nil` for none.
        public var border: Border?

        /// Creates a marker.
        public init(size: Double, ink: ServerUIInk, border: Border? = nil) {
            self.size = size
            self.ink = ink
            self.border = border
        }
    }

    /// What an assistive technology makes of the gauge.
    public enum Accessibility: Equatable, Sendable {
        /// Nothing: the rail is decoration.
        case hidden
        /// One element named `label` whose value is `value`, or the marker's percent when there is none; it cannot be adjusted.
        case value(label: ServerUICompositionDocument.StringValue, value: ServerUICompositionDocument.StringValue?)
    }

    /// The rail's height when the document gives none.
    public static let defaultHeight = 12.0

    /// The node's id, title and layout.
    public let node: ServerUICompositionDocument.Node
    /// The reading the marker shows, or `nil` for no marker.
    public var value: ServerUIOperand?
    /// How values are read.
    public var scale: Scale
    /// The span, for a `span` fill.
    public var span: Span?
    /// What the gradient colours.
    public var fill: Fill
    /// The gradient, two to eight stops that never fall back.
    public var stops: [Stop]
    /// The colour of the track.
    public var track: ServerUIInk
    /// The marker, or `nil` for none.
    public var marker: Marker?
    /// The rail's height in points.
    public var height: Double
    /// Whether a change glides (unless Reduce Motion is on).
    public var animates: Bool
    /// What an assistive technology makes of it.
    public var accessibility: Accessibility

    /// Creates a gauge.
    public init(node: ServerUICompositionDocument.Node, value: ServerUIOperand? = nil, scale: Scale = .unit, span: Span? = nil, fill: Fill,
                stops: [Stop], track: ServerUIInk, marker: Marker? = nil, height: Double = defaultHeight, animates: Bool = true,
                accessibility: Accessibility = .hidden) {
        self.node = node
        self.value = value
        self.scale = scale
        self.span = span
        self.fill = fill
        self.stops = stops
        self.track = track
        self.marker = marker
        self.height = height
        self.animates = animates
        self.accessibility = accessibility
    }

    /// The source ids the gauge reads.
    public var sourceIds: Set<String> {
        var ids = Set<String>()
        for operand in [value, span?.start, span?.size].compactMap({ $0 }) { ids.formUnion(operand.sourceIds) }
        if case .value(let label, let spoken) = accessibility {
            ids.formUnion(ServerUIStringResolver.sourceIds(label))
            if let spoken { ids.formUnion(ServerUIStringResolver.sourceIds(spoken)) }
        }
        return ids
    }
}

// MARK: - Gauge arithmetic

/// Where the parts of a ``ServerUILinearGauge`` stand: the Studio's `gauge-math.ts` (`layoutGauge`), pinned by the shared evaluation corpus
/// (`ContractCorpus/evaluation/gauge-*.json`), which is the weather rail's `UKWeatherRailView.applyFrames` made generic.
///
/// - A value is a share of the track from 0 to 1, or from 0 to 100 when the gauge says `percent`; one outside it is held at the nearest end, one that
///   is not a number is 0.
/// - A `scale` gauge colours the whole track; a `span` gauge colours only the span, which is held inside the track (its size at most `100 - start`)
///   and not drawn when it is empty.
/// - The marker is a circle kept wholly inside the track; with no value there is none.
/// - A right-to-left layout mirrors every position.
public enum ServerUIGaugeMath {
    /// What the gauge needs to place its parts. A `nil` value is "not known".
    public struct Input: Equatable, Sendable {
        /// How values are read.
        public var scale: ServerUILinearGauge.Scale
        /// The marker's reading, or `nil`.
        public var value: Double?
        /// The span's start and size, in the same scale.
        public var spanStart: Double?
        /// The span's size.
        public var spanSize: Double?
        /// What the gradient colours.
        public var fill: ServerUILinearGauge.Fill
        /// The track's width in points.
        public var width: Double
        /// The marker's diameter in points.
        public var markerSize: Double
        /// Whether positions are mirrored.
        public var rtl: Bool

        /// Creates an input.
        public init(scale: ServerUILinearGauge.Scale = .unit, value: Double? = nil, spanStart: Double? = nil, spanSize: Double? = nil,
                    fill: ServerUILinearGauge.Fill, width: Double, markerSize: Double, rtl: Bool = false) {
            self.scale = scale
            self.value = value
            self.spanStart = spanStart
            self.spanSize = spanSize
            self.fill = fill
            self.width = width
            self.markerSize = markerSize
            self.rtl = rtl
        }
    }

    /// The span as drawn: shares of the track and where it sits in points from the left edge.
    public struct SpanFrame: Equatable, Sendable {
        /// Where it starts, from 0 to 100.
        public let startPercent: Double
        /// How long it is, from 0 to 100.
        public let sizePercent: Double
        /// The left edge in points.
        public let left: Double
        /// The width in points.
        public let width: Double
    }

    /// The marker as drawn: its share of the track and where its left edge sits in points.
    public struct MarkerFrame: Equatable, Sendable {
        /// Where it stands, from 0 to 100.
        public let percent: Double
        /// The left edge in points.
        public let left: Double
    }

    /// The parts of a gauge; `nil` for a part that is not drawn.
    public struct Layout: Equatable, Sendable {
        /// The span.
        public let span: SpanFrame?
        /// The marker.
        public let marker: MarkerFrame?
    }

    /// A reading as a share of the track from 0 to 100. Not a number is 0; the result is held between the ends.
    public static func percent(_ value: Double?, scale: ServerUILinearGauge.Scale = .unit) -> Double {
        guard let value, value.isFinite else { return 0 }
        let share = scale == .unit ? ServerUIChartMath.roundedAxisValue(value * 100) : value
        return min(100, max(0, share))
    }

    /// Places the span and the marker of a gauge.
    public static func layout(_ input: Input) -> Layout {
        let width = input.width
        func mirror(_ origin: Double, _ length: Double) -> Double { input.rtl ? width - origin - length : origin }
        var span: SpanFrame?
        let start = input.fill == .scale ? 0 : percent(input.spanStart, scale: input.scale)
        let size = input.fill == .scale ? 100 : min(percent(input.spanSize, scale: input.scale), 100 - start)
        if size > 0 {
            let length = width * size / 100
            span = SpanFrame(startPercent: start, sizePercent: size, left: mirror(width * start / 100, length), width: length)
        }
        var marker: MarkerFrame?
        if let value = input.value, value.isFinite {
            let share = percent(value, scale: input.scale)
            let offset = max(0, min(width - input.markerSize, width * share / 100 - input.markerSize / 2))
            marker = MarkerFrame(percent: share, left: mirror(offset, input.markerSize))
        }
        return Layout(span: span, marker: marker)
    }
}
