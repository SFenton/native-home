# Reconnecting spinner

> **What:** the reconnecting sign is a white arc spinner in the header, left of Quick Links, replacing the "Reconnecting…" chip (owner request 2026-10-23). **Read when:** touching `ReconnectingArc`, `ReconnectingIndicator`, `ShellHeaderItems` or any connection-lost UI.

Mockups: [reconnecting-spinner.html](mockups/proposals/reconnecting-spinner/reconnecting-spinner.html) (self-contained; also on the owner's gallery, the owner's private mockup gallery (link kept outside the repo)).

## The bug

The chip under the header was text, a second colour (orange) and sat over page content.

## The decision

- A 20 pt `ArcSpinner(.compact)`, white, no text, in the header's trailing group before Quick Links. It is a status, not a control: no tap, no 44 pt target.
- Spacing: edge to edge, the arc is the same gap from Quick Links as Quick Links is from Profile (12 pt on iOS 27, 16 pt on iOS 26.5, see [HeaderButtonsJourneyTests](../../apple/Apps/iOSUITests/HeaderButtonsJourneyTests.swift)). The group grows to its left, so Quick Links and Profile never move.
- Timing: nothing for the first 2 s down (`ReconnectingPolicy.delay`), then the arc is placed and fades up 0.35 s (`MotionTokens.crossFade`, also under Reduce Motion: opacity is not motion). Live again: fades down 0.35 s, then leaves the bar. Down again mid-fade-out: it lights where it is, with no wait. `ReconnectingIndicator` owns this as two flags, present (a bar item) and lit (opacity 1), because bar items cannot fade themselves.
- iOS 26: a bar item with its shared glass hidden, so it floats on the wallpaper. The bar gives it a 44 pt cell and centres it, so the arc is drawn 12 pt right to end at the cell's edge, the way Profile's disc fills its cell; the gap to Quick Links is then the bar's own spacer. Measured on the iPhone 17 Pro simulator (iOS 27): an arc with its trailing padding cancelled instead sat 19 pt from Quick Links. On iOS 26.5, where Quick Links to Profile is 16 pt, the shift is 4 pt smaller so the arc is 16 pt out too (measured on the iPad simulator). Before iOS 26: a plain bar item.
- Duo vertical rail (owner, 2026-10-23): the arc still appears in the page header, on the trailing side, opposite the title. It is a custom view, so like the Profile monogram it stays in the horizontal bar and never joins the rail; nothing sits beside it, so it keeps the bar's own padding. To be confirmed on the Duo simulator.
- Offline (no network path) is not reconnecting: no arc. The offline chip and the Profile badge stay as they were.
- Accessibility: one element, "Reconnecting to Home Assistant", `updatesFrequently`, no action. Reduce Motion turns the arc at half speed, never still.

## Code

`HassCore/Connection/ReconnectingPolicy.swift` (delay, fade, lead), `ReconnectingIndicator.swift` (the two flags); `HassUI/App/Shell/ReconnectingArc.swift` (arc and host modifier), `ShellHeader.swift` (`ShellHeaderItems`), `OfflineChip.swift` and `OfflineOverlay.swift` (what is left of the old chip). Tests: `ReconnectingPolicyTests` (indicator phases), `SignInMotionTests` (arc, offline chip), `HeaderButtonsJourneyTests.testReconnectingArcSitsLeftOfQuickLinksAtTheSameGap` (gallery `FENTON_GALLERY_RECONNECTING=1`).

## Dynamic Type (owner, 2026-10-24)

The header's arc follows the text size like every in-line `ArcSpinner` (`.compact` and `.inline` scale with `.footnote`; `.page` stays 44 pt) but is capped at 1.5x its default diameter (`ReconnectingArc.Metrics.maxScale`) so the bar item stays in its 44 pt cell. The trailing shift is recomputed from the scaled diameter so the arc still ends at the cell's trailing edge.
