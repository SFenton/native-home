# Vacuum sheet redesign (proposal, decided)

> **What:** owner-review proposal (2026-10-28), decided the same day: option B (Recommended) with amendments. Section 6 of the page draws the final design. **Read when:** before touching the vacuum sheet, `patterns/vacuum-sheet.md` or `patterns/valetudo-map.md`.

- Mockup: [vacuum-sheet-redesign.html](vacuum-sheet-redesign.html) · status decided 2026-10-28 (owner picks: option B with amendments) · decision doc [vacuum-sheet-redesign.md](../../../vacuum-sheet-redesign.md) · shipped in PR #210
- Brief: `build/handoff/vacuum-sheet-redesign.md` ("Owner decision (2026-10-28)") · Source: `apple/Sources/HassUI/Features/Vacuums/` · Atlas: `modals/vacuums/vacuum-sheet`
- Decided: no room names on the map; Locate stays on the map; three equal read-only status tiles (Status, Battery, Dock); no segmented controls; Use Area and Use Rooms action tiles and alerts; pop-up rows for Mode, Fan, Water, Passes with footers; Water (and Fan) rows animate in and out (`standard`, content `quick`); five sections kept; Rooms and Auto-Clean as selection tiles (order disc, check disc); Pause and Stop and every dock command as action tiles with footers.
- Sections 1 to 5 stay as the record of the options (Today, Recommended, Alternative). Section 6 shows every state on iPhone, the docked sheet on iPad landscape, AX5, and the Water animation live (Replay, Reduce Motion) with a filmstrip.
- Open notes: the tile helpers are still proposal-local and the atlas mockups load them from here (the vacuum builders moved to `modals/vacuums/_devices-vacuums.js`; promote all to the kit with the build); long room names wrap to two lines instead of widening; "Fan" label kept; Clean reads "Clean" in both modes.
- Opens offline; sheets follow the Auto, Dark, Light control at the top.
