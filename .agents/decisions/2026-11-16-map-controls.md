# Map controls and map orientation

Decision: a map card draws up to four corner groups of buttons and a vacuum source may flip its map, as the owner asked. The app handles overflow; the Studio only warns.
Replaces: none
Rule home: `.agents/patterns/map-controls.md` and the orientation rule in `.agents/patterns/valetudo-map.md`.
Gate: matches_request=yes. The owner asked for the flip and for several buttons in any corner, as a row or a column, in any order, and said "the native app should handle that layer" for overflow.

Owner's request (2026-11-16): "Users should be given a configurator option to invert/flip/change map horizontally and vertically." "Users should be able to add multiple buttons (right now we only have locate) and position them vertically or horizontally in any of the four corners and re-order them. Users should be able to have a row or a column of buttons in each corner."

## Set without a pick, and what settles each

| Rule | Settled by |
|---|---|
| Groups: one per corner, a row or a column, 1 to 8 buttons, 44 pt, 8 pt in, 12 pt apart, authored order | The owner's words; HIG, Buttons (44 pt target); the Studio contract `sh.surface-controls@1` |
| Overflow: the crossing neighbour takes a slot, `k = floor(available / 44)`, more than `k` shows `k - 1` plus a More menu | Owner answer (the app handles it); HIG, Menus. One rule and one set of counts shared with the Studio |
| Source commands take the command tiles' state rules (shown only when offered, dimmed when blocked, the reason as the VoiceOver value) | Owner answer; the tile rules already shipped |
| The flip is set once, on the vacuum source, after the rotation, in screen space, so the picture and its overlays move together; badges, markers and buttons never mirror | Owner answer; `sh.surface-orientation@1` |
| Nothing authored draws today's map (Locate at top leading) | The vacuum pair gate: pixels within 0.4% at defaults |
| Accessibility: label, optional hint, button trait, `notEnabled` and a reason when dimmed, large content viewer, opaque plate under Reduce Transparency, outline under Increase Contrast | HIG, Accessibility; accessibility.md |
