# State-styled tile

> **What:** the one tile for doors, locks, blinds, the alarm, robots and sensors: state classes, the look per class, indicators, the transition table, the flap guard and accessibility. **Read when:** you build or change the tile or its transition component. Styles, the request phase and the Studio: [state-styles](state-styles.md).

Mockups: [state-styled-tile](mockups/components/tiles/state-styled-tile/state-styled-tile.html). The arc and the disc, with the rejected placements: [state-tile-indicator](mockups/proposals/state-tile-indicator/state-tile-indicator.html).

## Classes

A state map gives every state of a binding `{class, active}`. Rules are tried in order and the first match wins; the last rule is the fallback.

| Class | Means | Default look |
|---|---|---|
| `resting` | Settled. Includes active work: cleaning, playing, heating | Unlit face, or the family fill when `active`; no indicator |
| `in-progress` | Transitional: it ends without another tap | The resting face for its `active`; a present participle; the arc in the disc's place while a tap does nothing |
| `warning` | Needs attention, nothing has failed | Dense face, glyph and state text in the warning ink; one pulse |
| `error` | Failed, jammed, triggered, detected | Dense face, glyph and state text in the error ink; one wiggle |
| `unknown` | `unavailable`, `unknown`, or no rule matched | Unlit face, disc and glyph at 50%, taps ignored; never an arc, so busy and unavailable differ |

- `active` only picks the lit or unlit face. It is separate from the class: open and closed are both resting.
- The fallback class is `unknown`, or `resting` for open-ended states (a person's zone, a sensor value, a select).
- `unavailable` and `unknown` share a look and keep their own words.
- Warning is the error face's recipe with the warning ink; no full-face fill.

## Layers

A look is four layers: **icon** (SF Symbol), **colour** (face and ink, palette tokens), **indicator**, **text**.

- On every change each layer's resolved value is compared with the one on screen. An unchanged layer is not touched: same view, no restart, no phase reset.
- The arc is its own view (`UKArcSpinnerView`), never an effect on the glyph. A symbol effect is re-added after a symbol replace when it is not running.
- A first render, a cold launch and a reconnect reapply set all layers at once: no transition, no effect, no flap guard, no announcement.

## Disc and arc

- The arc means a tap does nothing now. While it shows, the disc's fill and glyph are at zero opacity and the arc stands in the disc's slot; the slot keeps its size.
- An in-progress state that authors an action (stop, reverse, cancel, disarm) keeps its disc and resolves its indicator to `none`; its words and face carry the progress. A style whose in-progress states author no action keeps one arc through them all.
- While the arc shows, the disc and body ignore taps and draw no press state. A navigation tile's body still opens its page.
- Size, on every family: `ArcSpinner.Size.tile`, 7/11 of the disc with a ring 3/44 of it. 28 pt and 3 pt in the 44 pt disc; 42 pt and 4.5 pt in the 66 pt disc of the accessibility sizes.
- Tint: the face's primary ink, the title's colour, fading with the face; never the warning or error ink.
- A hidden disc takes its next glyph and colours with no effect.
- A tile with no disc fades its glyph out and draws the `compact` arc, scaled with the glyph, in its place.

## Indicators (closed list)

| Indicator | Plays | iOS 17 | iOS 18 and later | Reduce Motion |
|---|---|---|---|---|
| `none` | | | | |
| `arc-spinner` | While the state holds | Arc | Arc | Half speed |
| `pulse` | While the state holds | Pulse | Pulse | Still |
| `breathe` | While the state holds | Pulse | Breathe | Still |
| `bounce` | Once, on arrival | Bounce | Bounce | Not played |
| `wiggle` | Once, on arrival | Bounce | Wiggle | Not played |

- Bounce and wiggle never repeat. Nothing else is authorable: no rotate, variable colour, draw or keyframes.
- A known percentage uses the tile's progress band, not an indicator.
- Every indicator is still while `UKDesign.animationsPaused` is set.

## Transitions

Tokens: colour `MotionTokens.state` (`stateReduced` under Reduce Motion); disc and arc opacity `MotionTokens.quick`, cross-faded, also under Reduce Motion; icon the system symbol replace, on a visible disc only; text replaced at once. All layers start together.

| From, to | Icon | Colour | Indicator | Text | Also |
|---|---|---|---|---|---|
| resting to in-progress | Replace if changed | Fade if changed | Disc out, arc in; none with an action | At once | Announce when the person's own request starts it |
| in-progress to in-progress | Replace if changed | Untouched if equal | Untouched if equal; cross-fade when the action comes or goes | At once | Nothing announced |
| in-progress to resting | Replace | Fade | Arc out, disc in | At once | Announce the state |
| any to error | Replace | Fade to the error face | Arc out, disc in; then wiggle once | At once | Error haptic after the person's own request; announce |
| error to resting | Replace | Fade | None | At once | Announce the state |
| any to warning | Replace | Fade to the warning face | Pulse once | At once | No haptic, no announcement |
| any to unknown | Replace | Fade | Arc out, disc in, dimmed | At once | Nothing announced |

## Flap guard

- Once the in-progress look is shown it stays at least `MotionTokens.StateTile.minimumInProgress`, 1.0 s. The whole look is held, words included, never the arc alone.
- States that arrive during the hold are coalesced; the latest is applied when it ends. An error waits too.
- A request that cannot be sent never shows in-progress: it goes straight to error.
- The value is the app's, not authored.

## Warning pulse and error entry

- A warning pulses once when it arrives on a visible page, and once each time its page becomes visible: a push or pop that reveals it, a tab switch, a sheet dismissal, a launch or a return to the app.
- All warnings on the page pulse together, after the transition ends. Scrolling a tile into view plays nothing.
- Error entry plays once on arrival and is never replayed.

## Reduce Motion and VoiceOver

- Reduce Motion: the arc turns at half speed; pulse, breathe, bounce and wiggle do not play; colour cross-fades on `stateReduced`; the icon swaps with no effect. Words, glyph and colour carry every class.
- One element per tile. Label: the title. Value: the state text, then "in progress", "warning" or "error" unless the text already says it.
- Hint: what a tap does now.
- While the arc replaces the disc, or the class is unknown: the button trait stays, not-enabled is added, no hint, `accessibilityRespondsToUserInteraction` false. The arc is not an element.
- A navigation tile's body keeps its traits; a tile with no disc changes only its value.
- `Announcer.announce`, focus unmoved, for a tile on a visible page: the start of the person's own request, arrival at resting after in-progress or error, arrival at error. Nothing else is announced.

## HIG

- Motion: "Make motion optional: never make it the only way to communicate important information"; "Keep feedback animations brief and precise." Departure: the warning pulse replays on a page visit, against "generally avoid animation on frequently repeated custom interactions".
- SF Symbols, Animations: Pulse is "useful for ongoing activity"; Breathe is "for status or ongoing activity (such as recording)"; Wiggle is to "highlight change, a call to action"; Bounce "signals an action occurred or needs to occur".
- Progress indicators: "Keep indicators moving."; "Display progress indicators in a consistent location."; "When it's feasible, let people halt processing", so a state with an action keeps its disc. Departures: the arc, not the system indicator; indeterminate, because Home Assistant gives no duration.
- Buttons, iOS and iPadOS: "For actions that don't complete instantly, show an activity indicator in the button". The tile is the button. Departure: the disc's fill is hidden with its glyph.
- Color: "Avoid using the same color to mean different things".
- Accessibility: "Convey state and function with shapes or icons in addition to color"; "When **Reduce Motion** is on, reduce automatic and repetitive animation", with "replacing axis transitions with fades".
- VoiceOver: "Inform VoiceOver of visible content or layout changes"; "be sure to keep labels current as interface and content change".
- Designing for iPhone Duo: "Prefer a layout container that adapts automatically, and even grid column counts." The tile lives in the dynamic grid and knows no device.
