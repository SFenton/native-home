# Core grammar surfaces (lane L0 of the family decomposition)

Decision: the settled part of the generic authored controls is set as rules, and three new visible choices are left to the owner. Settled, each by a shipped look or a registered pattern, with no option built because the rule draws what ships: choice `segmented` (the system segmented control, its menu form at accessibility sizes) and `menu` (the pop-up button row accessory), with the shipped automatic rule when no surface is named; toggle `line` (the shipped label-and-switch line); the status line for unavailable (the shipped row subtitle and 50% control) and its precedence over a disabled reason; `enabledWhen` with a required reason, extending "Say why a control is disabled"; `ask` as the alerts pattern's dialog attached to its control, with the fixed Cancel, the destructive role and the popover on regular width, as the shipped bed scope sheet; slider range, format and commit modes on the shipped slider row; failure as the optimistic-actions pattern. Not picked, options built for the owner in `mockups/proposals/core-grammar-surfaces` on iPhone, iPhone Duo and iPad at the default size and Accessibility 5: Q1 a call in flight with no optimistic value (A the control holds the tapped value, B an arc at the end of the title line, C both); Q2 where a disabled reason sits (A the control's own status line and a tile's state line, B a footer under the group); Q3 the `chips` look (A the wrapping grid of the shipped choice grid, B a scrolling rail, C joined segments that wrap, the shipped fan timer row). The Designer recommends B, A and A and has not picked.
Replaces: none
Rule home: `.agents/design/core-grammar-surfaces.md`. The answers to Q1, Q2 and Q3 are added there when the owner picks.
Gate: matches_request not confirmed. `tools/jev_gate.py` printed `gate: park basis=request answer=unsure route=session` on the whole plan, so Q1, Q2 and Q3 go to the owner in session. The settled rules draw what ships or apply a registered pattern.

Owner's request (2026-11-14): "Decompose all".

## Why the recommendations

| Question | Recommended | Why the others lose |
|---|---|---|
| Q1 | B | A makes the control keep a copy of its value, which the controller-bound-controls decision rules out, and shows nothing during a slow call. C says one thing twice. HIG Progress indicators: "Display progress indicators in a consistent location."; Buttons: "For actions that don't complete instantly, show an activity indicator in the button". The Studio adds an optimistic value for the control's own entity by default, so the arc is the uncommon case |
| Q2 | A | With several rows disabled for different reasons a footer sits away from each. HIG Writing: "Show errors as close to the problem as possible". The sprinkler schedule's footer stays: its group has one cause |
| Q3 | A | B hides options past the edge; HIG Pop-up buttons keeps hidden options for when they "needn't stay visible", which is the menu surface. C reads as a segmented control past the HIG's "about 5 on iPhone" and wraps it. HIG Typography: "Reduce the number of text columns as size increases" |

## Details set inside the settled rules

| Detail | Set to | Settled by |
|---|---|---|
| A `line` on a bare page | The Studio warns and offers `row` | HIG Toggles: "Use the switch style only in a list row". The shipped line always sits in a card or sheet group |
| `ask` option count | 2 to 4 | HIG Action sheets: "Avoid letting an action sheet scroll." Not measured on a device at Accessibility 5 |
| `ask` Cancel | Fixed "Cancel" | The alerts pattern; HIG Alerts |
| `ask` refused at the tap | "This changed while you were choosing. Try again." as the control's failure | Modelled on the shipped vacuum line "The cleaning target changed. Choose the target again." New copy: the owner can reword it in the strings table |
| Slider with no commit mode | `debounced` | What ships, so published pages behave the same |
| Slider step warning | Above 40 steps | The Designer's choice, about 8 pt of travel per step on the iPhone track; HIG Sliders suggests a stepper for wide ranges |
| Unavailable slider | The value text goes; the status line carries the words | Today the slider row dims with no words. HIG Color: "Avoid relying solely on color" |
| Failure on a bound row | The inline error under the control | The optimistic-actions pattern. The bound rows draw no failure today |

## Departures and later lanes

- HIG Toggles: the toggle line is a switch with no list card of its own. It ships on six screens; kept so no screen changes.
- Not decided here, each a change to a shipped look for its own lane and the owner: the fan timer row if Q3 is A; the climate hub pickers, the lighting mode button and the vacuum setting row when they become `menu`.

## Not measured

No device capture: the mockup is drawn from the kit. Whether the system places the `ask` popover clear of the hinge on a partly folded Duo, and whether a four-option `ask` scrolls at Accessibility 5 on iPhone.
