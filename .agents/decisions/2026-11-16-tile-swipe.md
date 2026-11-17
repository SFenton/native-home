# Swipe to adjust, state words, tile ink and state groups

Decision: native draws the four Studio capabilities `sh.tile-swipe@1`, `sh.state-words@1`, `sh.tile-ink-default@1` (option A: the document declares it, the app never changes ink for a document that does not) and `sh.grid-state-groups@1` (heading option A: the title only). A swipe is off when absent; the default brightness swipe of existing light tiles is kept. A warning face's state line is the primary ink and its icon keeps the amber (owner pick A, `build/design/sim-fidelity-contract.md` section 1); an unavailable tile draws grey and groups as unavailable whatever its behaviour, a read-only state tile included, as the Studio does.
Replaces: the always-on dragger bullets of `.agents/patterns/entity-tile.md` and the grey idle-glyph and state-line clauses there.
Rule home: `.agents/patterns/tile-swipe.md`.
Owner's request (2026-11-16): "I believe native app allowed you to swipe on a light tile and change brightness- not sure if this was in the iOS or the React app, but we'll want to add that capability for tiles and allow users to configure swipe behavior. Swipe behavior will be off by default on tiles" and "Icons on tiles should default to white instead of gray, as should text".
Gate: matches_request=yes. The owner chose ink option A and heading option A (2026-11-16); the rest follows `build/design/tile-swipe.md` and `sim-fidelity-contract.md`.

## Judged without an owner answer

| Question | Pick | Why |
|---|---|---|
| Warning face ink under the primary default | State line primary, icon amber | The owner's option A: every state line is primary; the icon still carries the warning, so state is not colour alone (HIG, Accessibility: convey state with shapes or icons in addition to color) |
| Volume slider | Not moved to the swipe | Its handle is inside the tile (HIG, Sliders). A volume swipe on a media player is a departure from "Don't use a slider to adjust audio volume", recorded in `.agents/patterns/entity-tile.md` |
| Regroup motion | Slides only after a person's tap, fades under Reduce Motion | Motion section 6: the person caused it; HIG, Motion: offer a reduced alternative |
| Light group tile swipe default | Off | Absent means off in the contract |
