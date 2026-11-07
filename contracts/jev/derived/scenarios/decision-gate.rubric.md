# Labelling rubric: design.user_visible v2 and decision.kind (owner rule, 2026-11-02)

The owner's rule: a change that only alters **when or how often an existing state appears** is not visible. Visible means a person would see a *different design*: something drawn, said or animated differently, or a different way to get around.

## Field `visible` (true / false)

**true** when the change alters any of:
- what is drawn: layout, sizes, spacing, colour, icons, images, materials, the order or grouping of items, a new or removed element, control or setting;
- what is said: on-screen copy, labels, formats of numbers or dates, VoiceOver labels, values or hints;
- how something moves or feels: animation, transitions, haptics, gestures;
- how a person gets around: navigation, tabs, sheets and their detents, what a tap opens.

**false** when the change only alters:
- timing or frequency of a state that already exists, with the same look, words and motion: delays, timeouts, debounce, retry or backoff, refresh or polling intervals, cache lifetimes, how long something stays connected, thresholds that decide *when* an existing banner, spinner or badge shows;
- a default value of an existing setting (the same control, a different starting value), unless the default changes what a screen shows when it opens (sort order, grouping, which items appear): that is drawn differently, so true;
- a wrong value corrected to what the design already shows (a temperature, a count, a state that was stale or wrong);
- crashes, hangs, memory, CPU, battery, network use, scroll smoothness, launch time;
- tests, tooling, CI, docs, refactors, logging, telemetry.

When a change does both, it is **true**.

## Field `kind` (none / policy / design)

What must happen before anything is built?
- **none**: no pick from the owner is needed. The change is invisible and has one sensible answer, or it is visible but already decided: it follows an existing pattern, a recorded owner decision, web-dashboard parity, Apple's HIG with one obvious answer, or it fixes the app back to its documented design.
- **policy**: the owner must pick between trade-offs, and nothing drawn, said or animated changes (only timing, frequency, thresholds, defaults, cost or privacy trade-offs with the same screens).
- **design**: the owner must pick, and something drawn, said, animated or navigated changes with no decision on record.

`kind` is judged from the **plan** text (after research), which says whether a rule, decision or parity exists. `visible` is judged from both the request and the plan.

## Consistency

- `kind = design` implies `visible = true`; `kind = policy` implies `visible = false`. `kind = none` goes with either.
- Never write the label words into the text ("this is a policy decision", "visible change", "design choice"). The plan may say what the research found ("the pattern already says…", "the web does…", "no decision on record", "two options: …").
