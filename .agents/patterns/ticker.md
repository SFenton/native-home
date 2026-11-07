# Ticker label

> **What:** one line of text that scrolls through its column when it is too wide, instead of truncating. **Read when:** a label must stay on one line beside something that cannot give way (the weather card's condition next to the numeral).

- **Component:** `TickerLabel(_:font:wraps:)` (`HassDesign/TickerLabel.swift`); the timeline is `TickerPlan` (`HassDesign/TickerPlan.swift`), pure and unit-tested; the numbers are `MotionTokens.Ticker`.
- **What it does:** takes the width it is offered. If the text's natural width is wider (by more than 0.5 pt) it plays 3 passes after it appears or its text changes: hold 1.5 s, travel at 30 pt/s, hold 1.5 s, return in 0.3 s. Soft 12 pt fades at both edges (the leading one only once the text has moved, so the first letter stays aligned with what sits above it). Then it rests at the start.
- **Overflow is measured, never assumed.** A hidden one-line copy of the text gives the column (it truncates to the room it has); the visible copy is a masked overlay at its natural width. No string, size or device check anywhere.
- **It pauses** (and resumes where it stopped) while the page scrolls (`pausesTickersWhileScrolling()` on the page's scroll view, iOS 18 and later), while its view is off screen or its section is behind another tab (`\.tickerIsOnScreen`, `\.sectionIsShowing`), and while the scene is not active.
- **Reduce Motion** and `wraps: true` (accessibility sizes): no ticker; the whole text wraps.
- **Accessibility:** the ticker text is hidden from VoiceOver. The caller names the content another way (the weather card's button label speaks the condition).
- **Instrumentation:** `TickerRun` signpost interval, from a run starting to it pausing, finishing or restarting (the message says why).
- **Motion rules:** an explicit exception in [motion.md](../design/motion.md) §9. Do not use it for another label without the owner's approval.
- **In a bar:** `truncatesWhenStill: true` holds the label still as one line cut with an ellipsis under Reduce Motion (a bar cannot grow to wrap).
- **Consumers:** tiles whose line still overflows at the full-row or full-side cap (owner, 2026-10-26; `GlassTileText` `tickers`, [action-tiles](action-tiles.md)); the Home weather card's condition ([weather card header](../design/weather-card-header.md)); the page title in the navigation bar (owner, 2026-10-24: "Long titles should carousel"; [header-edge-fade R7](header-edge-fade.md)).

- **Owned files** (also in `contracts/patterns.json`): `PausesTickersWhileScrolling.swift`, `TickerClock.swift`.
