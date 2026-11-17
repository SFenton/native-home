# Studio state words: a fold of one row per word

Decision: options A (five rows always in the panel), B (one row that opens a page) and C (a closed State Words fold with one text row per word) were weighed for the editor of a tile's state words (`sh.state-words@1`: On, Off, Unavailable, the count text, the level text); C is picked. A lost on 180 px of panel height on every stateful tile. B lost because one row is one setting: a place could only replace all five words together, as a `value` setting the app cannot draw yet. Only the pick is drawn (`.agents/design/mockups/proposals/sim-fidelity-contract/`); the other two were judged on measurements kept locally by the design session (`build/design/templates/anyfield.md`, `build/design/tile-swipe.md`), not in the repository. The defaults are production's words, so a tile with no authored word is unchanged.
Replaces: none.
Rule home: SFenton/ha-native-home-app `docs/design.md` (the State Words fold, line 41 at the time of writing); the native drawing of the words is in `.agents/patterns/tile-swipe.md`, section "State words (`sh.state-words@1`)".
Gate: matches_request=yes
