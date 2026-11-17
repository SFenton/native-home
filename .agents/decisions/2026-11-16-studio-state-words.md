# Studio state words: a fold of one row per word

- Decision: three placements for the editor of a tile's state words (`sh.state-words@1`: On, Off, Unavailable, the count text, the level text) were weighed: five rows always in the panel, one row that opens a page, and a closed State Words fold with one text row per word. The fold is picked. Five rows lost on 180 px of panel height on every stateful tile. The page lost because one row is one setting: a place could only replace all five words together, as a `value` setting the app cannot draw yet. Only the pick is drawn (`.agents/design/mockups/proposals/sim-fidelity-contract/`); the other two were judged on the measurements in `build/design/templates/anyfield.md` and the page in `build/design/tile-swipe.md`. The defaults are production's words, so a tile with no authored word is unchanged.
- Replaces: none.
- Rule home: `build/design/sim-fidelity-contract.md`, section 2, until the lane lands; then `.agents/patterns/entity-tile.md`.
- Gate: `matches_request=yes`.
