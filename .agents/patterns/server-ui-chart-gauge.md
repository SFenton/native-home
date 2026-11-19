# Chart and linear gauge

> **What:** the document-driven chart (`sh.chart@1`) and linear gauge (`sh.linear-gauge@1`), the generic parts that draw a series and a value on a rail. **Read when:** you change `UKChartView`, `UKLinearGaugeView`, `ServerUIChart*` or `ServerUILinearGauge`, or the weather chart and rail.

Contract: Studio `studio-ux2-integ11@e6629db` (`src/preview2/nodes/chart.tsx`, `gauge.tsx`, `chart-math.ts`, `gauge-math.ts`). Corpus: `accept/chart-*`, `accept/linear-gauge-*`, `evaluation/chart-*`, `evaluation/gauge-*`.

| Piece | File |
|---|---|
| Decoded chart, gauge, shape and compiler | `HassCore/ServerUIComposition/ServerUIChart*.swift`, `ServerUILinearGauge.swift` |
| Arithmetic (domain, axis levels, bar and line slots, rail layout), shared with the Studio by the corpus | `ServerUIChartMath.swift`, `ServerUIGaugeMath` |
| Chart view (bar, line, area, axis, thinned labels, audio graph) | `HassUI/UIKitPort/Design/UKChartView.swift`, `UKChartContent.swift` |
| Gauge view (track, gradient span, marker) | `HassUI/UIKitPort/Design/UKLinearGaugeView.swift`, `UKGaugeContent.swift` |
| Binding to state | `HassUI/UIKitPort/ServerUI/UKServerUIDataParts.swift` |

- **Values only.** The views take `UKChartContent`, `UKChartSpeech` and `UKGaugeReading`; the binder reads entities and flows in one observation, so one change is one update of one view. Nothing is written per layout or scroll frame.
- **Ink.** A document ink is drawn as stated; a `solid-appearance` pair takes the side of the surface it sits on; with no ink stated, grid, labels and unknown stubs follow the appearance. A single ink that fails on a light surface is the Studio's warning to give, never the renderer's to change.
- **VoiceOver.** The chart is one element named by `a11y.label`; its value is always the series read out and it always carries an `AXChartDescriptor`, whether or not the document writes `a11y.value` (HIG, Charting data, Best practices; HIG, Charts, Enhancing the accessibility of a chart). The gauge is hidden or one element named by the document.
- **Motion.** A chart never animates. A gauge glides with the standard token only when its `animates` is on and Reduce Motion is off; a marker that reappears appears in place.
- **Marker.** Kept wholly inside the track; mirrors in a right-to-left language.
- **Kept text.** Text slots keep through `UKServerUITextMemories` (`sh.text-keep@1`, rule in [kept-text](../design/kept-text.md)): a `keep` slot draws its last answer while unavailable, drawn and spoken as live.
- **Tests.** `ServerUIChartTests`, the corpus tests, and the hosted `ServerUIChartHostedTests` and `UKHostedChartShotsTests` on iPhone, Duo and iPad.

## Weather views

`UKWeatherRailView` and `UKWeatherBarChartView` (`HassUI/UIKitPort/Features/Home/UKWeatherViews.swift`) draw the weather sheet's rail and precipitation chart natively: the same two parts with weather values.
