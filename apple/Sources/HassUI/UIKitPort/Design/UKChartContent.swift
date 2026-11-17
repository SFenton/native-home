#if os(iOS)
import HassCore
import UIKit

// MARK: - What a chart draws

/// Everything ``UKChartView`` draws, as values: the points, the scale they sit on, the axis texts and the look. The binder computes it from the
/// document and the entities (``UKServerUIDataParts``); the view never reads state, so one change of a point is one new value and one redraw.
struct UKChartContent: Equatable {
    /// Bars, a line or an area.
    var mark: ServerUIChart.Mark
    /// The points, in order.
    var points: [ServerUIChart.Point]
    /// The top and the base of the value axis.
    var top: Double
    var base: Double
    /// The text of each axis level from the top down, or `nil` for an axis with no labels (the lines can still show).
    var levelTexts: [String]?
    /// How many lines cross the plot, or 0 for none.
    var gridLines: Int
    /// The plot's height in points.
    var height: CGFloat
    /// The space between bars, the corner radius and the least height of a bar above zero or unknown.
    var gap: CGFloat
    var radius: CGFloat
    var minimum: CGFloat
    /// The width of a line and whether each known point gets a dot.
    var lineWidth: CGFloat
    var dots: Bool
    /// Which labels under the plot show.
    var labels: ServerUIChart.Labels
    /// The colour of the marks, and the optional inks of the grid, the labels and an unknown bar's stub.
    var tint: UIColor
    var gridInk: UIColor?
    var labelInk: UIColor?
    var unknownInk: UIColor?
    /// What shows where there is no series or no value is known.
    var emptyText: String

    /// Whether there is anything to draw: at least one known value.
    var hasData: Bool { points.contains { $0.value.map(\.isFinite) == true } }
}

/// What a chart tells an assistive technology: its name and the series read out, always (HIG, Charting data, Best practices).
struct UKChartSpeech: Equatable {
    /// The chart's name.
    var label: String
    /// The series read out (`Now 94%, 7 PM 40%`), whether or not the document writes `a11y.value`.
    var series: String
    /// The text of one value, for the audio graph and its axis.
    var describe: @Sendable (Double) -> String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.label == rhs.label && lhs.series == rhs.series }
}
#endif
