# A state style rule can set the icon colour of its state

Decision: C, colour by state. A state style rule may carry a `glyphTint`, so a state-styled tile draws its icon in a colour keyed to the state; the bed tiles, rebuilt as generic state tiles, keep the heating or cooling icon colour while off or read-only. The owner picked it on 2026-11-19 ("C: colour by state") from the mockup of A, B and C on iPhone, iPhone Duo and iPad.
Replaces: none
Rule home: .agents/design/state-glyph-tint.md
Gate: parked as `basis=request answer=unsure route=session`; the owner then picked C in the gate session, so `matches_request=yes`.

## Goal

The two bed tiles become Studio-authored state tiles over a Home Assistant sensor, with no bed code in the app. A state tile had one icon colour per tile (`glyphTint`), so the bed icon could not keep following the side's level on the dark face.

## Options judged

- A, grey. Lost: an off or read-only bed side draws the neutral grey icon. It needs no code, but it replaces the rule on record for bed sides ("Never grey, except an unavailable bed side", direction-g, Colour families), and grey would mean both off and unavailable on the icon.
- B, one fixed colour per bed. Lost: the tile's existing `glyphTint`, no code. It keeps "never grey" but drops the part that says the off icon follows the level, and the heating orange would sit on an off side that leans cooling (HIG, Color: "Avoid using the same color to mean different things, especially for status or interactivity").
- C, colour by state. Won: off and read-only draw as they do today, orange at or above zero and teal below. The rule on record stays whole and moves from app code into the authored style. Cost: one optional field on a state style rule behind a new capability in the Studio, a small generic change in the app, and a sensor state that says which way an off side leans.

Only the off and read-only faces differ between the options; heating, cooling, hot flash and unavailable draw the same in all three.

## Rules it adds

- A state style rule, or a style's fallback, may carry `glyphTint` (`sh.state-style-glyph-tint@1`): the icon colour while that rule matches, in the tile's own `glyphTint` shape.
- A rule with none falls back to the tile's static `glyphTint`, then to the document's default ink.
- It applies only where the static tint applies: a face that is neither filled nor an error, and never an unavailable tile.
- It is accepted on a resting or in-progress rule with no `fill`, and rejected elsewhere.
- Colour stays a second channel: the state text and the VoiceOver value are unchanged, and the colour is never spoken.
- direction-g's bed-side rule is unchanged: a bed side keeps its family icon when off and is never grey except when unavailable.

## Evidence

Mockup only (`.agents/design/mockups/proposals/bed-tile-glyph-tint/`): no option was built before the pick, so there is no device capture of A, B or C. The build's evidence pack covers C on the three families.
