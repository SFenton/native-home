# Weather card header

> **What:** the layout for the Home weather card's header (glyph, condition, range, temperature), chosen 2026-10-22 after the temperature clipped to "4…" beside long conditions. **Read when:** touching `WeatherCardContent.header` or any condition label.

Mockups: [weather-card-header.html](mockups/proposals/weather-card-header/weather-card-header.html) (self-contained, open in a browser; also on the owner's gallery, https://claude.ai/artifact/EMActh2ZvDe8bjY2N7wQLv). It compares four options (A to D) at Large, xxxLarge and Accessibility 2; **D** is the decision.

## The bug

`layoutPriority(1)` on the numeral sat inside the `Button`, so the outer `HStack` never saw it: at Large with "Partly Cloudy" on a 353 pt card the numeral truncated to "4…". Priority on the button alone fixes Large but breaks at xLarge.

## The decision (owner, option D)

- Left column, left-aligned: glyph, condition, then H/L. The glyph's ink edge lines up with the text's left edge (SF Symbols have 2 to 5 pt of leading space at 40 pt, so `WeatherSymbols` keeps a per-symbol inset, checked by a test that measures the rendered ink).
- Right: the numeral, with the chevron centred on the numeral (not on the whole header).
- The numeral never truncates. The condition never wraps or truncates below accessibility sizes; when it does not fit its column it scrolls like a ticker, 30 pt/s, 1.5 s holds, soft fade at both edges, three passes then rests. H/L stays on one line.
- Accessibility sizes stack: glyph, numeral and chevron on the top row, the condition under it at full width (wraps), H/L under that.
- Reduce Motion: no ticker, the condition wraps.
- The card is about 19 pt taller at the default size.

## Rules this adds

- The ticker is an exception to [motion.md](motion.md) section 9.6 (durations) and 9.10 (no animating while scrolling or off screen): it pauses on scroll, off screen and while the scene is inactive, and only runs when the label overflows.
- Motion ships with signposts and performance tests ([performance](../testing/apple/performance.md)).

## Shipped (2026-10-23)

Screenshots from the iPhone journey run (`WeatherHeaderJourneyTests.testCaptureWeatherHeader*`, one test per size and length): [Large short](mockups/proposals/weather-card-header/shipped/iPhone-header-large-short.png), [Large long](mockups/proposals/weather-card-header/shipped/iPhone-header-large-long.png), [xxxLarge short](mockups/proposals/weather-card-header/shipped/iPhone-header-xxxlarge-short.png), [xxxLarge long](mockups/proposals/weather-card-header/shipped/iPhone-header-xxxlarge-long.png), [AX2 short](mockups/proposals/weather-card-header/shipped/iPhone-header-ax2-short.png), [AX2 long](mockups/proposals/weather-card-header/shipped/iPhone-header-ax2-long.png).

The card's one accessibility button sits behind the whole header (not on the numeral), so no drawn text lacks an element; the numeral, condition and glyph are hidden from VoiceOver and the button label names them.

