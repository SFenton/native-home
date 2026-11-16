# State styles

> **What:** the built-in styles of the [state-styled tile](state-styled-tile.md), the request phase, how the shipped door, lock and alarm tiles map onto them, and what the Studio's style library does. **Read when:** you add or change a built-in style, retire a fixed tile shape, or build style authoring in the Studio.

Mockup: [state-style-library](mockups/proposals/state-style-library/state-style-library.html).

## Built-in styles

Each row lists state: class, lit or unlit, disc glyph. Words are Home Assistant's state names unless given. `unavailable` and `unknown` are the unknown class in every style.

| Style | States | Request |
|---|---|---|
| Garage door | closed: resting, unlit, `door.garage.closed`. open: resting, lit, `door.garage.open`. opening, closing: in-progress, lit, `stop.fill` with Stop, else `arrow.uturn.down`, `arrow.uturn.up`. Pending words: "Sending Open…", "Sending Close…" | lockout 2 s, ack 10 s, settle 45 s, "Error" held 8 s |
| Lock | locked: resting, unlit, `lock.fill`. `unlocked`: resting, lit, `lock.open`. open: warning, `lock.open`, a tap locks. locking: in-progress, unlit. unlocking, opening: in-progress, lit. jammed: error, `lock.trianglebadge.exclamationmark`, a tap locks | taps ignored while moving; revert after 2 s; a rejected call shows "Didn't Respond" for 4 s |
| Blind | closed: resting, unlit, `blinds.horizontal.closed`. open: resting, lit, `blinds.horizontal.open`. opening, closing: in-progress, lit, `stop.fill` with Stop | ack 10 s, settle 45 s, "Didn't Respond" for 4 s |
| Alarm | disarmed: resting, unlit, `shield.lefthalf.filled`. armed modes: resting, lit, `shield.slash`. arming: in-progress, Disarm stays tappable. pending: warning, Disarm tappable. disarming: in-progress, taps ignored. triggered: error, Disarm tappable | Disarm asks first |
| Robot | docked: resting, unlit, `house`. idle: resting, unlit. paused: warning. cleaning, mowing: resting, lit, breathe. returning: in-progress. error: error. All others draw `robotic.vacuum` | none |
| Detector | off: resting, unlit. on: error | none |
| Notice | off: resting, unlit. on: warning; connectivity is reversed | none |
| Switch | off: resting, unlit. on: resting, lit | the [optimistic-actions](../patterns/optimistic-actions.md) defaults |

- The Studio suggests a style by domain and device class: Detector for smoke, gas, carbon monoxide, moisture, problem, tamper, safety; Notice for battery, heat, cold, update, connectivity.
- A style's colours are palette tokens; the colour-family fill comes from the tile's family.
- Robot glyph: the style's; a tile's authored symbol is the fallback.

## Request phase

- A tap on an action that authors a request phase is in-progress from the same frame, with that action's pending look, until the binding reaches a class in `holdUntil`.
- Client timings: `lockout`, `ackTimeout`, `settleTimeout`, `errorHold`, and `onTimeout` (`error` or `revert`).
- With a Home Assistant script the state map reads the script (`on`: in-progress) and its timer (`active`: error). The pending look and the script rule resolve to the same four layers, so the handover redraws nothing.
- Optimistic in-progress, the tap lock until acknowledgement and the flap guard stay in the app. A missing or unavailable script falls back to the client timings with no visible difference.

## Parity with the fixed shapes

| Shipped tile | Style | Kept |
|---|---|---|
| Garage door (`CoverActions`, `GarageDoorController`) | Garage door | Glyphs, words, the family fill, lockout, acknowledgement, settle and error-hold times, the error haptic, Stop or Reverse while moving |
| Lock (`LockActions`) | Lock | Glyphs, words, the lit face while unlocked or unlocking, taps ignored while locking and unlocking, the jammed face |
| Security System (`AlarmModeActions`) | Alarm | Arm Home and Disarm glyphs, the confirmation before Disarm, taps ignored only while disarming, Disarm tappable through arming and pending |

- The garage tile's 1 s "Sending" feedback is the tile's flap guard, not an authored time. `GarageDoorController` times none of it: the phase leaves `sending` when the call is acknowledged, and `UKStateTileTransition` holds the look.
- `StateStyleActions` is the provider over a style. `StateStyleParityTests` hold the fixed shapes' tables as golden rows and compare each built-in style with them state for state.
- The Studio authors styles and the app renders them. Capability `sh.state-style@1` carries a document `stateStyles` library and the `state-tile` node's binding, decoded in `ServerUIStateStyles.swift` onto `StateStyle`.
- A device without the capability, or a style id the library lacks, shows the tile's built-in style. Only validation errors reject.
- The built-in data is the shared fixture `ContractCorpus/state-styles/built-in.json`, compared with `StateStyle.builtIn` in `ServerUIStateStyleTests`.
- Announcements differ in one place: a change from one in-progress state to another is not spoken.
- The look differs in two places: the arc stands in the disc's place with the disc hidden, where the fixed shapes drew it inside the disc; alarm `pending` and lock `open` draw the warning face.

## The Studio's style library

- A style is a named document object: a state map, a look per state and the request settings. Tiles apply it by id.
- The library lists built-in and saved styles, each with "Used by N tiles".
- Built-in styles are read-only; Duplicate makes a saved one. Rename and Delete are for saved styles; Delete needs zero uses.
- Editing a saved style states how many tiles change before the edit is kept.
- A tile may override single layers of single states. Each override is marked on the tile and can be reset by itself; the tile keeps its link to the style.
- The colour layer is cosmetic. Its tokens are `unlit` and `lit`; they pick the face of a resting or in-progress state. Class, words, VoiceOver value, effects, haptics and announcements come from the state map alone.
- The warning and error inks follow the class and are never a colour choice. A colour on a warning, error or unknown state is rejected. A different meaning is a class change in a saved style's map. HIG, Color: "Avoid using the same color to mean different things".
- "Save as New Style" makes a saved style from a tile's style plus its overrides and points the tile at it.
- Choosing an entity fills the state map from Home Assistant's own states and names, with a default class and `active` per state. States seen only in history are listed as unclassified.
- Every map ends with a fallback rule.
- The indicator menu is the tile's closed list and names the iOS 17 fallback beside Breathe and Wiggle.
- Arc spinner is offered only for a state with no action; a state with an action says why beside the menu.
- New maps class alarm `pending`, lock `open` and vacuum `paused` as warning.
- The preview shows the tile at iPhone, iPhone Duo and iPad widths; picking a state plays the app's transition and prints the VoiceOver value.
- For a Home Assistant lifecycle the Studio asks for the script and the error timer, checks that both exist and warns when one is missing. It installs nothing.

## Doors lowered to the state tile

`door-tile` (`sh.security-door@1`) is a decodable alias: the compiler rewrites each node into a `state-tile` over the built-in `garage-door` or `lock` style, plus a saved style named `<node id>.door` in the document's library (`ServerUIDoorLowering`, `docs` pattern: [action-tiles](../patterns/action-tiles.md)). Nothing else draws a door.

- **Per state:** the authored icon, words and `active` and `error` flags become that state's rule, and the colour is the face fill when `active` and the disc glyph's ink when not (`discGlyph`, never authored); a state the door did not author reads as its fallback appearance and is not lit.
- **Words and verbs:** the open, close and reverse labels are the disc's verbs; the sending texts are `pendingWords`; `errorText` is `errorWords`; `hiddenText` is the style's `hiddenWords` (`sh.state-style-fills@1`).
- **Loading:** `loadingText` is an `expr` subtitle that reads the door source's `phase` and speaks only while it says `loading`. The source needs no Swift of its own: its `phase` is `loading`, `ready` or `unavailable` from the entity.
- **Request:** a tap shows the state it asked for (`opening`, `closing`, `locking`, `unlocking`) from the style's `pendingStates`, which are the app's own feedback and never authored.
- **Kept:** a dimmed disc while the entity cannot be read (`keepsDiscWhenUnknown`) and a disc on-state that differs from the tile's lit face (`StateRule.discOn`), neither authorable.
- **Proof:** `ServerUIDoorEquivalenceHostedTests` compares every state and request phase with the golden the bespoke atom drew, `fill` revised to none for states that are not active (`apple/Apps/iOSTests/Fixtures/ServerUIDoorGolden.json`); `ServerUIDoorLoweringTests` holds the tables.

## Tile ink and cell fit

`sh.tile-ink@1` adds four optional state tile fields; a pair resolves with the trait collection, with no clamp.

- **`glyphTint`:** the icon on a face that is neither filled (`filledWhen` or a style `fill`) nor an error. Not applied while unavailable, which keeps the muted grey at 50%.
- **`discGlyphTint`:** the button icons of an off disc on a dark face, an error face included. A filled face keeps its black 18% disc and white glyph.
- **`fillInk`** (rule or fallback, beside a `fill`): `soft` is the state line in white at 92%; the title stays white.
- **`cellFit`:** `natural` keeps the tile's own height, top-aligned, in a taller equal-height cell.

`AuthoredTileInk` decides where each applies.
