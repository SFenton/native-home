# Icon colour by state

> **What:** how a state style rule sets the icon colour of a [state-styled tile](state-styled-tile.md) for one state (`sh.state-style-glyph-tint@1`, a rule's `glyphTint`). **Read when:** you author or draw a tile whose icon colour follows its state, change `AuthoredTileInk`, or build the field in the Studio.

Proposal: [bed-tile-glyph-tint](mockups/proposals/bed-tile-glyph-tint/bed-tile-glyph-tint.html). The tile's static inks: [state-styles](state-styles.md#tile-ink-and-cell-fit).

## Rules

1. **The field.** A state style rule and a style's fallback may carry `glyphTint`. It has the shape of the tile's `glyphTint`: a `solid-rgb`, or a `solid-appearance` pair that resolves with the trait collection, with no clamp.
2. **Order.** The matching rule's `glyphTint`, else the tile's static `glyphTint`, else the document's default ink. A style that authors none draws as before.
3. **Where it draws.** Exactly where the static tint draws (`AuthoredTileInk.glyphTintApplies`): a face that is neither filled nor an error. A lit face, a family fill and a style `fill` keep their fixed icon ink.
4. **Never while unavailable or unknown.** The rule's colour never draws; the tile's own icon ink shows at 50%.
5. **Accepted on** a resting or in-progress rule with no `fill`. On a warning, error or unknown rule, or beside a `fill`, it is rejected: those inks follow the class or the fill.
6. **Contrast.** The Studio measures each member against the face it lands on, the dark member on the page's off face at its lightest ground and the light member on a light sheet's white cell, and warns below 3:1. The app draws the authored value unchanged.
7. **One colour, one meaning** across a style's states.
8. **Never colour alone.** The state text carries the state. The icon colour is not spoken and changes no VoiceOver label, value, hint or trait, no announcement and no haptic.
9. **Motion.** The tint belongs to the tile's colour layer: a changed tint fades with the face, an equal one is untouched, and a first render, a cold launch or a reconnect sets it with no transition.
10. **Disc icons** are unchanged: `discGlyphTint` stays one colour per tile.
11. **Capability.** A publication needs `sh.state-style-glyph-tint@1` only when a rule or fallback writes the field. A build without it treats that publication as any layout naming a capability it lacks ([server-ui-boundary](server-ui-boundary.md)): a last good layout stays, and no style is half-applied.

## HIG

- Color: "Avoid using the same color to mean different things, especially for status or interactivity" (rule 7).
- Color, Inclusive color: "Avoid relying solely on color to differentiate objects, indicate interactivity or communicate essential information; be sure to also convey it another way, like text labels or glyph shapes." (rule 8).
- Accessibility: "Convey state and function with shapes or icons in addition to color".
- Dark Mode: "For custom colors, add an Xcode Color Set with bright and dim variants. Avoid hard-coded or non-adaptive values." An author who wants another colour in light sheets writes a pair. Departure: the pair has no Increase Contrast member, as with the tile's static `glyphTint`; the solid finish and the words carry that setting.
