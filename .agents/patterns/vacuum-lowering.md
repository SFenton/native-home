# Vacuum kinds built from generic parts

> **What:** the `vacuum-control` kinds the compiler rewrites into generic parts, and the ones that stay native. **Read when:** you change `ServerUIVacuumLowering` or a vacuum card, row or command.

The compiler checks the document as written, then `ServerUIVacuumLowering` rewrites the kinds below. The node type, the capability ids and the corpus stay as they are. A lowered node reads `ha-entity` sources named `lowered.<entity id>`. Everything a lowering emits is authorable in the Studio.

| Kind | Lowers to | Parts |
|---|---|---|
| `card` | `state-tile` over a saved `robot` style | purple fill on cleaning, returning and paused (`sh.state-style-fills@1`); subtitle, progress, two discs (`sh.tile-disc-rules@1`); the grid keeps two tracks (`sh.grid-min-columns@1`), which never cap a card's span |
| `auto-clean` | `bound-control` toggle, row surface | glyph, Enabled or Paused subtitle, hint, failure caption (`sh.bound-row-parts@1`) |
| `choice` (`autoClean`) | `bound-control` toggle, tile surface | included while the skip switch is off |

## Stays native

`status`, `consumable`, every `command`, `map`, `area-editor`, `outcomes`, `notices`, `report`, `target`, `clear-area`, the `rooms` choice and the session and dock-cleaning commands draw from the native atoms.

- They need `VacuumController` or the map, or generic parts do not yet draw the same pixels and spoken labels.
- `settings` stays native too: a generic choice draws differently from the settings group, which also shows rows by mode and holds a choice until Home Assistant confirms it.

## Known differences

- The error subtitle appends the sensor's own words; the old tile capitalised each word.
- The Auto-Clean glyph is one fixed colour; the old one adapted to light and dark.
