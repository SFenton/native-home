# Swipe to adjust a tile (proposal)
> **What:** the design for swipe to adjust on any tile: absolute tracking, the band and bubble, detents, one call on release. **Read when:** you need the reasons behind the tile swipe.
- Mockup: [tile-swipe.html](tile-swipe.html) · status decided
- Asked for: swipe on a tile to adjust it, configured in the Studio, off by default
- Decided: absolute tracking; the tile's own band is the value at rest and in a drag; a bubble always shown while dragging; a selection tick per detent; one call on release; no in-drag cancel gesture
- Rejected: relative tracking (cannot reach the ends in one drag, the band stops being the thumb)
- Recorded departure: a swipe may set a Home Assistant media player's volume (HIG Sliders)
- Built: `sh.tile-swipe@1`, lanes TC6 (Studio) and NT6 (native, `fba79957`)
- Current design: [brightness-tile](../../components/tiles/brightness-tile/brightness-tile.html), [state-styled-tile](../../components/tiles/state-styled-tile/state-styled-tile.html)
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape
- Open notes: the page also draws the Studio inspector (a web surface). The Verifier's device run of the swipe is still to come
