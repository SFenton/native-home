# Dial and arc track

> **What:** the document-driven dial (`sh.dial@1`) and arc track (`sh.arc-track@1`), and the weather compass, barometer and sun arc that draw through them. **Read when:** you change `UKDialView`, `UKArcTrackView`, `ServerUIDial*`, `WeatherDialSpecs`, or build a control that draws a dial and takes a finger.

Contract: Studio `studio-ux2-integ11@e6629db` (`src/shared/composition/schema.ts` `dialNode`, `arcTrackNode`; `dial-math.ts`, `arc-track-math.ts`; `docs/native-composition.md` "Gauge parts"). Corpus: `accept/dial-*`, `accept/arc-track-*`, `reject/dial-*`, `reject/arc-track-*`, `evaluation/dial-*`, `evaluation/arc-track-*` (106 publication and 80 evaluation cases). Research: `build/research/studio-edge-logic.md`, "Dial, compass, sun arc, thermostat".

| Piece | File |
|---|---|
| Decoded dial and arc, shape and compiler | `HassCore/ServerUIComposition/ServerUIDial.swift`, `ServerUIArcTrack.swift`, `ServerUIDialShape.swift`, `ServerUIDialCompiler.swift` |
| Geometry (share, angle, short turn, ticks, letters, flag, needle, curve, marker), shared with the Studio by the corpus | `ServerUIDialLayout.swift`, `ServerUIArcLayout.swift` |
| The weather panel's three parts as documents | `HassCore/Weather/WeatherDialSpecs.swift` |
| Dial view (ring, lit tick, flag, letters, needle, text in the middle) | `HassUI/UIKitPort/Design/UKDialView.swift`, `UKDialFaceView.swift`, `UKDialNeedleView.swift`, `UKDialContent.swift` |
| Arc view (curve, horizon, marker) | `HassUI/UIKitPort/Design/UKArcTrackView.swift` |
| Binding to state | `HassUI/UIKitPort/ServerUI/UKServerUIDataParts.swift` |
| Weather consumers | `UKWeatherCompassView`, `UKWeatherPressureGaugeView`, `UKWeatherSunArcView` in `HassUI/UIKitPort/Features/Home/UKWeatherViews.swift` |

- **One dial.** An authored `dial` and the weather compass and barometer are the same `UKDialView` over `ServerUIDialLayout`. The sun arc and an authored `arc-track` are the same `UKArcTrackView`.
- **Weather views hold a document.** They take a reading and draw nothing themselves. `WeatherPresentation`'s bearing helpers call `ServerUIDialLayout`, so the arithmetic exists once.
- **A control that takes a finger builds on the layout type.** `ServerUIDialLayout` (`dialShare`, `dialAngle`, `shortestTurn`, `tickShare`, `layoutDial`) is pure and public.
  - An interactive dial reads its angles and ticks from it and adds the gesture, haptics and trails.
  - This pattern builds no interaction: `UKDialView` has `isUserInteractionEnabled = false`.
- **Values only.** The views take `UKDialReading` (the pointer's number and one value for each line in the middle) or the arc's progress.
  - The binder reads entities in one observation: one change is one update of one view.
  - Nothing is written per layout or scroll frame; an unchanged reading draws nothing.
- **Geometry.** Angles are degrees clockwise from 3 o'clock. The corpus pins every number to four places.
  - Ticks stand at `i / (count - 1)` of a partial sweep and `i / count` of a full turn.
  - A value is held at the ends of a partial sweep and wraps on a full turn.
  - A needle on a full turn goes the short way round (`nextTurn`: 350 to 10 is 20 degrees on).
- **Size.** A dial is as wide as its `size` (scaled with the text size to `maxPoints`) or the room it has up to `maxWidth`, `aspect` wide to 1 tall, centre `centerY` down.
  - An arc is as wide as the room up to `maxWidth`, as tall as its box's shape, at the leading edge.
  - A `UIView` draws only inside its bounds: a tick past the dial's box (the barometer's top tick) is clipped.
- **Text in the middle.** One `UKServerUIText` for each line, so a line has a `text`'s style, weight, digits, ink, lines, alignment, overflow and pending bar. The block is centred on the ring unless the dial states a centre-text place.
- **Centre-text place.** A share of the height (the ring's `centerY` when absent) plus points that do not scale with text. The barometer says 0.5 and 4. A document cannot carry it yet.
  - A single line shrinks to 0.6 of its size before it is cut (`UKServerUIText.shrinksToFit`), so a value stays inside the ring at large text sizes.
- **Motion.** Only a needle moves. With `animates` on (the default) and Reduce Motion off it turns with the `standard` token, from where it stood.
  - A needle that appears (no direction, then a direction) appears in place.
  - A tick pointer, a letter, a line and an arc's marker change at once.
- **VoiceOver.** A dial or an arc is hidden, or one element named by `a11y.label` whose value is `a11y.value` or the percent of the sweep (the curve for an arc).
  - Letters and the text in the middle are never read on their own.
  - The weather panel's three are hidden: the tile that holds them carries the name and the value.
- **Direction.** A dial is an instrument in space: it keeps its places in a right-to-left layout unless `mirrors` is true. An arc mirrors unless `mirrors` is false, and then it also keeps its left-to-right place; the weather sun arc says false.
- **Ink.** A document ink is drawn as stated (`rgba` and light and dark pairs too), resolved against the view's own appearance. The weather panel's inks live in `WeatherDialSpecs`.
- **Tests.** `ServerUIDialTests` (decode, geometry), `ServerUIExpressionCorpusTests` (the 80 evaluation cases, byte for byte), `WeatherDialSpecsTests`, and the hosted `ServerUIDialHostedTests` and `UKHostedSharedWeatherViewsTests` on iPhone, Duo and iPad. `UKHostedDialPerformanceTests` turns 20 needles under `XCTOSSignpostMetric` on `LayoutChange` (page `Dial`).

## Where the native views differ from the Studio's preview

The schema leaves these to the renderer; the native dial fixes one answer for every document. The letter font (semibold, rounded), the lit tick's round cap and the arc's caps (round curve, butt horizon) are the weather panel's own, so nothing moved there.

| What | Native | Why |
|---|---|---|
| Letter font | Semibold, rounded design, a fifth of the radius, at least 10 points | The schema has no weight or design; the compass drew this |
| Lit tick end | Round cap | The schema has no cap; the barometer drew this |
| Arc caps | Round on the curve, butt on the horizon | The schema has no cap; the sun arc drew this |
| Arc anchor | An arc that mirrors stands at the leading edge; one that does not (the weather arc) stands at the left in every direction | Production's pixels: the sun arc never moved |
| Needle glide | `standard` token: a spring of 0.3 s, no bounce, as the compass had; it also begins from the pose it is in, which only shows when a second turn interrupts the first | The contract gives no duration |
| Barometer text | Half the dial's height down plus 4 pt | A dial can state a centre-text place; the barometer does |
| Centre line fit | A single line shrinks to 0.6 before it is cut; the weather value does (as it did), the unit cuts (as it did) | A line says `overflow: truncate` to opt out |
| Amber | 255, 209, 77 and the sun 255, 217, 77, whole-number channels | The panel's `UIColor` values (1, 0.82, 0.30 and 1, 0.85, 0.30) are 209.1, 76.5 and 216.75, 76.5 of 255; an ink is whole channels, so at most half a channel |
| Dial sample amber | The Studio's samples use 255, 159, 10 | A sample, not the panel's ink; the weather document says its own |

## Weather panel

- The compass is `WeatherDialSpecs.compass()`: 104 pt scaled with `footnote` to 160, 48 ticks, north a flag, E and W only with a bearing.
- The barometer is `barometer(hasUnit:)`: 49 ticks over 250 degrees from 145, one lit, 1.4 wide, centre 0.56 down, value and unit in the middle.
- The barometer's value and unit say a scaled size (20 and 12 points) so they grow with the text as `UIFontMetrics` does. The ring fits its tile's height as well as its width.
- The sun arc is `sunArc()`: a 100 by 48 box, 200 pt at most.
- The wind tile does not measure the compass: the dial's own size is its intrinsic size.
