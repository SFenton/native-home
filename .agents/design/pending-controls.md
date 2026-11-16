# Pending controls

> **What:** what a bound control, button or tile shows between a tap and Home Assistant's answer: the optimistic value, the waiting arc, the failed face, the defaults by call and the authored settings. **Read when:** you build or author a control that calls a service.

Mockup: [core-grammar-surfaces](mockups/proposals/core-grammar-surfaces/core-grammar-surfaces.html), the Pending states. The surfaces: [core-grammar-surfaces](core-grammar-surfaces.md).

## Phases

A tap runs three phases ([optimistic-actions](../patterns/optimistic-actions.md)).

| Phase | Shows | Ends |
|---|---|---|
| Optimistic | The call's optimistic value, no indicator | Confirmation, silently, or the optimism timeout |
| Waiting | Home Assistant's value and the arc | The first change of the watched value, or the ceiling |
| Failed | The value back and the failed face for 4 s | By itself |

- A rejected call fails at once from either phase. The failed face is an inline error under a row or line, the failure caption under a slider, the error face on a tile.
- **Row or line.** The `inline` arc sits at the trailing end of the title line, before the accessory, half as large again at accessibility sizes. The control stays enabled; a new tap starts again at Optimistic.
- **Button.** The arc takes the symbol's place and the button takes no taps. With nothing optimistic to show, Waiting starts at the tap and the arc appears once it has lasted 150 ms.
- **Tile.** The arc stands in the disc's place with the in-progress look and its flap guard ([state-styled-tile](state-styled-tile.md)). A toggle tile reads "Turning On…" or "Turning Off…". A tile whose action authors a request phase follows [state-styles](state-styles.md) instead.
- The arc fades on `quick` in the title's ink. Reduce Motion keeps the fade and halves the turn. The control's accessibility value gains "in progress".

## Authored settings

A call may carry `pending`; a document without it gets the defaults.

| Field | Values |
|---|---|
| `watch` | `own`: the entities of the call's optimistic values. `entity`: a declared source and path. `script`: the called script's state. `none` |
| `optimistic[].revertAfterSeconds` | The optimism timeout, 0.5 to 60 |
| `ceilingSeconds` | From the timeout to 300 |
| `onCeiling` | `fail` (the default) or `quiet` |
| `arc` | On by default; off runs the phases and draws nothing in Waiting |

- `none` has no Waiting phase: the value goes back at the timeout.
- `script` waits while the script is `on`, with no ceiling; a script never seen `on` ends quietly.
- `failsOnTimeout` is a ceiling equal to the timeout.

| Call domain | Watch | Timeout | Ceiling |
|---|---|---|---|
| light, switch, fan, input helpers, select, number | `own` | 2 s | 10 s |
| climate, humidifier, water heater, vacuum, media player | `own` | 8 s | 30 s |
| cover, lock, valve, alarm | `own` | 2 s | 45 s |
| script | `script` | none | none |
| Anything else | `none` | none | 10 s for the call |

- The defaults are one shared file, `contract/corpus/pending-defaults.json`, read by the app and the Studio.
- The Studio adds an optimistic value for the entity a bound control reads; the author can remove it.
- The Studio rejects a ceiling below the timeout, an undeclared watch source, `script` on a call that is not a script and `own` with no optimistic value.
- The Studio warns for a script button that watches nothing, and for a cover, lock or alarm on a bound control, where it offers the state tile.

## HIG

- Buttons: "For actions that don't complete instantly, show an activity indicator in the button".
- Progress indicators: "Display progress indicators in a consistent location."; "Keep indicators moving. If a process stalls, explain the problem and what people can do."
- Motion: "Make motion optional: never make it the only way to communicate important information".
