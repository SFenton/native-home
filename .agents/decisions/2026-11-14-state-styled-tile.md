# State classes and the state-styled tile

Decision: the state-styled tile's classes, indicator list, transition table, flap guard, warning pulse, error entry, accessibility, request-phase look, built-in styles and Studio style library are set as rules. The place of the in-progress arc was judged in three built options (A inside the disc while a tap does nothing, B beside the state text, C a ring round the disc); the owner picked none of them and gave D: the arc replaces the disc. A lost because the disc stays and still looks tappable; B because it moves the state line on a live update and has the smallest arc; C because a white ring round a white disc is faint and a tile with no disc needs a second geometry. The owner also set alarm `pending`, lock `open` and vacuum `paused` to default to warning.
Replaces: none
Rule home: `.agents/design/state-styled-tile.md` and `.agents/design/state-styles.md`.
Gate: matches_request=yes. The owner picked in session on 2026-11-14, the route the gate named: `tools/jev_gate.py`, run twice that day on A, B and C, printed `gate: park basis=request answer=unsure route=session`.

Owner's request (2026-11-14): "Could the user select 'terminal' states (open, closed), 'in-progress' states (opening, closing, locking, unlocking, etc.), 'error' states, 'warning' states, etc., and then assign icons or animations to them, and the native app would know whether to animate in or out to different icons/colors/states/animations, and if state changed but icon/animation/etc. stayed the same (e.g. opening -> closing would maintain an arc spinner), it would know to maintain state?"

## Set without a pick, and what settles each

| Rule | Settled by |
|---|---|
| Classes resting, in-progress, warning, error, unknown; `{class, active}` per state; in-progress means transitional, active work is resting | The owner's words and proposal 10; research note 12 (the active flag, active-work states, per-domain fallback) |
| Looks per class | The registered tile faces (unlit, family fill, error, unavailable). Warning has no tile on record: it takes the error face's recipe with the existing warning ink |
| Indicators none, arc-spinner, pulse, breathe; bounce and wiggle once; iOS 17 falls back breathe to pulse and wiggle to bounce | Note 12 (Apple's availability data); motion.md section 6, which allows a repeating effect only for a live state and a one-shot bounce |
| An unchanged layer is never touched; the arc is its own view | The owner's words; `CoverActions` and `UKTileActions` already keep one disc view |
| Colour on `state`, icon by the system symbol replace, text at once | The motion pattern's tokens and the shipped tiles |
| Flap guard 1.0 s, the whole in-progress look held | The garage tile's 1 s "Sending" feedback, which the owner kept as the default (answer 1) |
| Warning pulses once on arrival and once per page visit; nothing under Reduce Motion | Owner answer 2 |
| Error entry: wiggle once (bounce on iOS 17), with the existing face, haptic and announcement | Proposal 10 section 4 ("a one-shot effect, then static"); HIG SF Symbols, Animations |
| Reduce Motion: arc at half speed, no effects, colour cross-fade, icon cut | accessibility.md and motion.md section 8; the icon cut is today's behaviour |
| VoiceOver value and the three announcements | Proposal 10 section 4; the Announcer rule in accessibility.md. One change from today: the garage tile no longer speaks "Opening" after "Sending Open…" |
| A Home Assistant lifecycle draws the same layers as the client request phase | Research note 11; follows from the layer rule |
| Styles are shared document objects with built-ins, saved styles and per-tile layer overrides | Owner answer 3 |
| Built-in Garage door, Lock and Alarm equal the shipped tiles except where the owner's two picks change them | Proposal 10 (parity before a shape is deleted) |

Blind, Robot, Detector, Notice and Switch are added built-ins; they draw no tile that ships today.

## The arc: owner's pick D

Owner (2026-11-14): "It should replace the disc entirely. Still smaller than the actual disc, but the actual disc should fade in/out appropriately; this signifies that the user can't currently interact with the tile."

Built in `mockups/proposals/state-tile-indicator` beside A, B and C, for iPhone, iPhone Duo folded and unfolded, and iPad, at the default size and AX5. D is drawn from the rules in the mockup kit; it has no device capture, because the tile is not built.

Settled inside D by the Designer, each by the precedence (the owner's words, then the HIG):

| Choice | Pick | Settled by |
|---|---|---|
| An in-progress state that still takes a tap (stop, reverse, cancel, disarm) | It keeps its disc and has no arc | The owner: the arc means the tile cannot be used, so it cannot sit on a tile a tap will stop. HIG Progress indicators: "When it's feasible, let people halt processing". The alternative, every in-progress tile going non-interactive, removes Stop, Reverse and Disarm from three shipped tiles |
| Cross-fade or sequence | Cross-fade: disc and arc opacity on `MotionTokens.quick`, 0.2 s, from the same frame, both ways | HIG Motion: "Keep feedback animations brief and precise." A sequence takes 0.4 s and leaves the slot empty between the two |
| Reduce Motion | The same cross-fade; the arc at half speed | HIG Accessibility lists "replacing axis transitions with fades": the swap is already a fade |
| Arc size | 28 pt with a 3 pt ring in the 44 pt slot; 7/11 of the disc at every text size, 42 pt in the 66 pt disc; the same on every family | The owner: "smaller than the actual disc". 28 pt is the selection ring's size in the same target (`TileSelectionIndicator`). The tile knows no device |
| Arc tint | The face's primary ink, the title's colour | It must read on the unlit and the filled face with no disc behind it. HIG Color: "Avoid using the same color to mean different things", so never the warning or error ink |
| The hidden disc's glyph | Set with no effect while hidden | The symbol replace on an invisible glyph is wasted, and the disc must return showing the settled state |
| Not available now, for VoiceOver | The button trait stays, not-enabled is added, no hint, no response to Voice Control or Switch Control; the arc is not an element | HIG VoiceOver: "be sure to keep labels current as interface and content change". Spoken as "Front Door, Unlocking, in progress, dimmed" |
| Busy against unavailable | Unknown keeps a dimmed disc and no arc | The arc promises an end; unavailable does not |
| A tile with no disc | Its glyph fades out and a glyph-sized arc takes its place | The rule already set; HIG Progress indicators: "Display progress indicators in a consistent location." |

Where D departs from the HIG: Buttons, iOS and iPadOS, says to "show an activity indicator in the button", where the system "hides any button image". The tile is the button and the arc is inside it; D also hides the disc's fill. That is the owner's choice and is recorded as a departure in the rule home.

What D changes on a shipped tile: on a garage door that can reverse, the arc shows through "Sending Open…" and the disc returns with Reverse once the door moves, so opening to closing keeps one arc only in a style whose moving states author no action. The owner's first example ("opening -> closing would maintain an arc spinner") holds for those styles and for a lock, and not for a door with Reverse or Stop.

## Warning defaults: owner's pick

Alarm `pending`, lock `open` and vacuum `paused` default to warning. Each keeps its action: Disarm stays tappable through `pending`. The alarm and lock tiles therefore differ from the shipped look in those two states; the parity table in `state-styles.md` says so.

## Not measured

Whether an indefinite symbol effect survives a symbol replace, whether symbol effects stop by themselves under Reduce Motion, and the cost of several effects on one page (note 12's open questions). The rules assume none of them: the arc is a separate view, effects are gated by hand and re-added after a replace.

## Build history

- Lane L7a, 2026-11-14: `StateStyleParityTests` passed against the fixed shapes state for state. `CoverActions`, `LockActions` and `AlarmModeActions` were then deleted, as the rule required ("a fixed shape is deleted only after its parity test passes against the style"). The parity tests keep the shapes' tables as golden rows.
- Lane L7a, 2026-11-14: `GarageDoorController` stopped timing the 1 s "Sending" feedback and `Timing.sendingFeedback` was removed. The tile's flap guard holds that look.
- Lane L9a, 2026-11-14: the capability `sh.state-style@1` was added, so the Studio authors styles and the app renders them.

