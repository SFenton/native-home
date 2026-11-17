# Swipe to adjust, state words, tile ink and state groups

Decision: native draws the four Studio capabilities `sh.tile-swipe@1`, `sh.state-words@1`, `sh.tile-ink-default@1` (option A: the document declares it, the app never changes ink for a document that does not) and `sh.grid-state-groups@1` (heading option A: the title only). A swipe is off when absent; the default brightness swipe of existing light tiles is kept. The warning face keeps its amber though the Studio text lists it; an unavailable tile stays grey.
Replaces: none
Rule home: `.agents/patterns/tile-swipe.md`.
Gate: matches_request=yes. The owner chose ink option A and heading option A (2026-11-16); the rest follows `build/design/tile-swipe.md` and `sim-fidelity-contract.md`.

## Judged without an owner answer

| Question | Pick | Why |
|---|---|---|
| Warning face ink under the primary default | Keeps its amber | Amber is the state's colour; the primary ink would erase it (HIG, Color: use colour to communicate state consistently) |
| Volume slider | Not moved to the swipe | Its handle is inside the tile (HIG, Sliders); departure recorded in entity-tile |
| Regroup motion | Slides only after a person's tap, fades under Reduce Motion | Motion section 6: the person caused it; HIG, Motion: offer a reduced alternative |
| Light group tile swipe default | Off | Absent means off in the contract |
