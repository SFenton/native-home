# The disc on a household toggle tile

Decision: three options were judged for the disc of a Settings household toggle once the tile is built from the published control kind: (1) the control's authored icon, (2) the fixed `power` glyph, (3) an action glyph that defaults to `power`. The pick is 3. The disc shows the action, `power`; Front Door Auto-Lock keeps its `lock.fill` / `lock.open` disc, named by the Auto-Lock role in house configuration, the way the guest face is named by the guest role. The authored icon is not drawn on a toggle, because an action tile has no leading glyph. Option 1 lost: an object glyph (a bulb, a drop) names the thing, not what a tap does, differs from tile to tile in one grid, and replaces the owner's pick that switches use `power`. Option 2 lost: it changes the approved Auto-Lock disc, a visible change nobody asked for. Judged from the rules and the code at `66d21673` and on `sdui-l11-hf01-dead`; no option was built, because the pick draws what shipped.
Replaces: none
Rule home: `.agents/patterns/action-tiles.md`, Rollout S.
Gate: app_wide=no. Settled by the precedence, so `tools/jev_gate.py` was not run: the owner's light-disc pick in `action-navigation-tiles.md` and the disc rule in `state-styled-tile.md`.

HIG: Buttons, "Try to use familiar icons for familiar actions"; Toggles, "A toggle-like button generally uses a purpose-conveying icon and changes appearance, typically its background, with state"; Icons, "Keep all icons consistent in size, detail, stroke thickness/weight, and perspective".

A document field for the action glyph can replace the role later with no visible change.
