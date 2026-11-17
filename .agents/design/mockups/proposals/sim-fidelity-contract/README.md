# Tile ink, state words and grid groups (proposal)
> **What:** the options for the default tile ink and the group heading, with the picked state words editor. **Read when:** you need the reasons behind the tile ink, state words or state groups.
- Mockup: [sim-fidelity-contract.html](sim-fidelity-contract.html) · status decided · decision: `.agents/decisions/2026-11-16-tile-swipe.md`
- Owner's requests (2026-11-16): white tile icons and text by default; customizable state strings; group by state on any grid
- Tile ink, owner picked A: an icon with no colour of its own and every state line on a dark face draw the primary ink; idle family icons keep their tint; unavailable stays grey
- Rejected ink: B every idle icon (changes more than asked), C a softer state line (leaves the text grey-white)
- Group heading, owner picked A: the title only, as production
- Rejected heading: B title and count (its number contradicts the sheet's subtitle), C collapsible (hides state, needs per-device memory)
- State words: the Designer picked a State Words fold under the gate (`autonomous`)
- Built: `sh.tile-ink-default@1`, `sh.state-words@1`, `sh.grid-state-groups@1`, lanes TC7 (Studio) and NT7 (native, `fba79957`)
- Current design: [brightness-tile](../../components/tiles/brightness-tile/brightness-tile.html), [state-styled-tile](../../components/tiles/state-styled-tile/state-styled-tile.html), [dynamic-grid-layout](../../components/grids/dynamic-grid-layout/dynamic-grid-layout.html)
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape
- Open notes: the page also draws the Studio inspector (a web surface). Not captured on a device: Increase Contrast, a hinge band crossing a grouped page grid, a tile leaving from under the finger
