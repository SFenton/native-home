import Foundation

// MARK: - Closed grammar of the chart and the linear gauge

/// The closed shapes of the `chart` (`sh.chart@1`) and `linear-gauge` (`sh.linear-gauge@1`) nodes, kept apart from ``ServerUICompositionShape``'s
/// tables so the lanes that extend those tables do not collide. They follow the Studio's `schema.ts` (`chartNode`, `gaugeNode`) field for field.
extension ServerUICompositionShape {
    private static let chartPoint: Shape = object(["label": .text(40, blank: true), "value": .nullableNumber(-1e9, 1e9)])

    private static let chartSeries: Shape = .variant("type", [
        "literal": object(["type": fixed("literal"), "points": array(chartPoint, 100, minimum: 1)]),
        "source": object([
            "type": fixed("source"), "providerId": .optional(id), "limit": .number(1, 100, integer: true),
            "x": object(["label": operand]), "y": operand
        ])
    ])

    private static let chartDomain: Shape = .variant("type", [
        "ceiling": object(["type": fixed("ceiling"), "step": .number(0.000001, 1e9, integer: false),
                           "min": .number(0, 1e9, integer: false), "max": .number(0, 1e9, integer: false)]),
        "fixed": object(["type": fixed("fixed"), "min": .number(-1e9, 1e9, integer: false), "max": .number(-1e9, 1e9, integer: false)]),
        "two-step": object([
            "type": fixed("two-step"), "minimumStep": operand, "maximumFractionDigits": .optional(.number(0, 6, integer: true)),
            "factors": .optional(array(.number(0.000001, 10, integer: false), 16, minimum: 2))
        ])
    ])

    private static let chartAxis: Shape = object([
        "levels": .number(2, 6, integer: true),
        "label": .optional(object(["pattern": .text(40, blank: false), "digits": .optional(.number(0, 6, integer: true))])),
        "gridInk": .optional(inkSlot), "labelInk": .optional(inkSlot)
    ])

    private static let chartBar: Shape = object([
        "gap": .optional(.number(0, 16, integer: false)), "radius": .optional(.number(0, 16, integer: false)),
        "minimum": .optional(.number(0, 8, integer: false)), "unknownInk": .optional(inkSlot)
    ])

    private static let gaugeStop: Shape = object(["at": .number(0, 1, integer: false), "ink": inkSlot])

    /// The nodes `sh.chart@1` and `sh.linear-gauge@1` add, over the fields every node has.
    static func chartNodes(base: [String: Shape]) -> [String: Shape] {
        func node(_ type: String, _ extra: [String: Shape]) -> Shape {
            object(base.merging(["type": fixed(type)]) { _, rhs in rhs }.merging(extra) { _, rhs in rhs })
        }
        return [
            "chart": node("chart", [
                "props": object([
                    "mark": .choice(ServerUIChart.Mark.allCases.map(\.rawValue)), "series": chartSeries, "domain": chartDomain, "tint": inkSlot,
                    "axis": .optional(chartAxis), "bar": .optional(chartBar),
                    "line": .optional(object(["width": .optional(.number(0.5, 8, integer: false)), "dots": .optional(.bool)])),
                    "height": .optional(.number(40, 320, integer: true)),
                    "labels": .optional(.choice(ServerUIChart.Labels.allCases.map(\.rawValue))),
                    "emptyText": .text(240, blank: false)
                ]),
                "a11y": object(["label": textValue(.text(240, blank: false)), "value": .optional(fixed("series"))])
            ]),
            "linear-gauge": node("linear-gauge", [
                "props": object([
                    "value": .optional(operand), "scale": .optional(.choice(ServerUILinearGauge.Scale.allCases.map(\.rawValue))),
                    "span": .optional(object(["start": operand, "size": operand])),
                    "fill": .choice(ServerUILinearGauge.Fill.allCases.map(\.rawValue)), "stops": array(gaugeStop, 8), "track": inkSlot,
                    "marker": .optional(object([
                        "size": .number(6, 32, integer: false), "ink": inkSlot,
                        "border": .optional(object(["ink": inkSlot, "width": .number(0.5, 4, integer: false)]))
                    ])),
                    "height": .optional(.number(4, 32, integer: false)), "animates": .optional(.bool)
                ]),
                "a11y": .variant("element", [
                    "hidden": object(["element": fixed("hidden")]),
                    "value": object(["element": fixed("value"), "label": textValue(.text(240, blank: false)),
                                     "value": .optional(textValue(.text(240, blank: true)))])
                ])
            ])
        ]
    }
}
