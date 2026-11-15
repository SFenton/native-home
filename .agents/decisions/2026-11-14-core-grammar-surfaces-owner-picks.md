# Core grammar surfaces: the owner's answers

Decision: the owner answered the three questions of `2026-11-14-core-grammar-surfaces.md`. Q2, where a disabled reason sits: A, the control's own status line (a tile after its state), over B, a footer under the group. Q3, the chips look: A, the wrapping grid of the shipped choice grid, over B, a scrolling rail, and C, joined segments that wrap. Q1, a call in flight: none of A (held value), B (arc alone) or C (both); the owner gave a new direction, built as the Pending states of `mockups/proposals/core-grammar-surfaces` on iPhone, iPhone Duo and iPad at the default size, Accessibility 5 and Reduce Motion: the optimistic value, then the arc after an optimism timeout until a change or a failure ceiling, with authored per-control settings.
Replaces: the "Not picked" part of `2026-11-14-core-grammar-surfaces.md`; in `optimistic-actions.md`, the plain revert at `revertAfter` and the unbuilt pending spinner with its static ellipsis under Reduce Motion.
Rule home: `.agents/design/core-grammar-surfaces.md` (Q2, Q3), `.agents/design/pending-controls.md` (Q1), `.agents/patterns/optimistic-actions.md` (the timeout and the pending state).
Gate: matches_request=yes. `tools/jev_gate.py` printed `gate: park basis=request answer=unsure route=session`; the owner answered in session, recorded in `build/decisions/sdui-review.md`.

Owner's request (2026-11-14), Q1: "Need you to intelligently define an optimism timeout that's then changed to the arc spinner until a change occurs. Users should also be able to configure- ex a button might just trigger a script or something?"

## Settled inside the owner's Q1 direction, and what settles each

| Choice | Set to | Settled by |
|---|---|---|
| What the control shows under the arc | Home Assistant's value, not the tapped one | The owner: the optimism is "changed to" the arc. AGENTS.md: optimistic state is feedback only. The owner-approved table in `controller-bound-controls.md`: no echo reverts after 2 s. The owner confirmed it in session on 2026-11-15 ("Home Assistant's value") over the drawn `pending-keep` |
| The optimism timeout | The existing `revertAfter`, authored as `optimistic[].revertAfterSeconds` | One name for one time; the pattern's 2 s default stays |
| `.confirmation` and `.liveChange` | Unchanged in the optimistic phase; the waiting phase ends on any change of the watched value | The owner: "until a change occurs" |
| `failsOnTimeout` | A ceiling equal to the timeout: failed at once, no arc | Keeps the shipped vacuum switches as they are |
| The failed face | Unchanged: 4 s, after a rejected call or at the ceiling | The pattern. HIG Progress indicators: "If a process stalls, explain the problem and what people can do." |
| Arc on a row or line | `inline`, end of the title line before the accessory; the control stays enabled | HIG Progress indicators: "Display progress indicators in a consistent location."; the shipped form switch row draws its arc there. HIG: "When it's feasible, let people halt processing" |
| Arc in a button | In the symbol's place; no taps | HIG Buttons: "show an activity indicator in the button"; "The system shows it beside the label and hides any button image." |
| Arc on a tile | The state-styled tile's in-progress look: the arc in the disc's place, the 1.0 s flap guard, "Turning On…" and "Turning Off…" | The owner's option D and the tile's rules; the words ship on a tile today |
| A row's arc and the flap guard | No hold: the arc leaves with the change | It appears only after the timeout, so it cannot flash at a tap; holding it past the change would say "waiting" over a settled value |
| A tile with an authored request phase | Follows its state style | `state-styles.md`; its lockout, acknowledgement and settle times are that style's |
| A button with nothing to hold | Waiting from the tap; the arc after 150 ms | The content gate's spinner wait, so a fast call never flashes it |
| Reduce Motion | The fade stays; the arc turns at half speed | `motion.md` and the tile. Replaces the pattern's static ellipsis: a still arc reads as frozen |

## Defaults and their sources

| Call domain | Watch | Timeout | Ceiling | Source |
|---|---|---|---|---|
| light, switch, fan, input helpers, select, number | own | 2 s | 10 s | `ha-sfenton-react-dash@7c4ebf9e:src/hooks/useOptimisticState.ts:3` (2000 ms). 10 s: the acknowledgement time of the garage and blind styles; `src/components/hass/wakeLights/useWakeLightController.ts:14` |
| climate, humidifier, water heater, vacuum, media player | own | 8 s | 30 s | `src/components/hass/HumidifierModalContent.tsx:95`, `VacuumCard.tsx:98`, `GuestPresenceSecurity.tsx:25` (8000 ms); `VacuumCard.tsx:99`, `src/pages/DashboardViewPage.tsx:3468,3475` (30000 ms) |
| cover, lock, valve, alarm | own | 2 s | 45 s | Home Assistant's cover states "The cover is opening." and "The cover is closing.", and lock states "The lock is being locked." and "The lock is being unlocked." (contributors.home-assistant.io, core/entities/cover and lock), give an early first change. 45 s: the settle time of the garage and blind styles |
| script | script | none | none | home-assistant.io/integrations/script: "Its state is `on` while the script is running, and `off` otherwise." |
| anything else | none | none | 10 s for the call | No state to watch |

The dashboard also holds longer times for single devices (`src/constants/mediaRemotes.ts:188-198`, 20 s to 180 s; `SprinklerController.tsx:31`, 10 s; `DashboardViewPage.tsx:2286`, 60 s). Those are authored per control, not defaults.

## Not sourced, not measured

- Home Assistant publishes no settle time per domain. The 8 s and 30 s row rests on the dashboard's values for its cloud devices.
- The dashboard's garage constants were not read; the 10 s and 45 s come from `state-styles.md`.
- Whether a fast script is always seen `on` by the app was not tested; the rule ends quietly when it is not.
- Whether the connection times a call out by itself was not read; the 10 s call ceiling is the app's to enforce.
- Nothing was timed on a device, and the mockup is drawn from the kit.
