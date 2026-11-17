# Map controls and the overlay stay two capabilities

Decision: buttons over a map belong to `sh.surface-controls@1` and `UKMapControlsView`; `sh.overlay@1` and `UKServerUIOverlayView` stay for one node over a tile and a status pill or text over a map. Neither is retired or folded into the other.
Replaces: none
Rule home: `.agents/patterns/overlay.md` and `.agents/patterns/map-controls.md`.
Gate: matches_request=yes. The owner's request for several buttons in any corner, as a row or a column, in any order, settles it; no options were built.

## Why each other pick lost

- **One capability, the overlay survives.** It would need groups, an axis, order, the fit rule, More, Locate and the source-command rules: `UKMapControlsView` rebuilt in a generic container, with the map's buttons outside the map frame.
- **One capability, surface controls survive and the overlay is retired.** The overlay's centre anchor, its pill and text, and a tile as base go with it, and seven accepted corpus cases need a new capability version.

## Why the map frame owns its buttons

- Locate and source commands are the map's own actions with the map's own state rules.
- The fit rule and the loading text's inset under an occupied corner need the card.
- Taps outside a group reach the rooms; a flip moves the picture, never the buttons.
- A future pan and zoom must be reachable by Fit and Recenter, which only a component inside the map frame can do.

## Known gap

An overlay child at the top leading corner of a map overlaps the map's default Locate and takes the tap. The app draws what the document says; the Studio warns.
