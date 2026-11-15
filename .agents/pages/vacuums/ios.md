# Vacuums: iPhone and iPad

> **What:** how the renderer draws the Vacuums page and sheet. **Read when:** changing the published Vacuums pages or `HassCore/Vacuums`.

Vacuums are composed from the publication ([architecture](../../platforms/apple/architecture.md#server-driven-root)). `ServerUIVacuum*` (Core) describes the robots and `UKServerUIVacuumView` draws the page and sheet; the map is the canonical Valetudo map ([valetudo-map](../../patterns/valetudo-map.md)).

- **Page.** A summary line under the large title ("1 Cleaning · 1 Needs Attention"), then Robot Vacuums as cleaning tiles (filled while working, off when docked, the error face with the issue appended) and Auto-Clean as switch rows, under section headers.
- **Split.** Where `SplitPolicy.allowsSplit` the two sit side by side, each scrolling on its own; everywhere else they stack. HIG: Layout, Split views.
- **Auto-Clean rows.** The Main Floor pause switch is inverted (enabled when off). Optimistic, cleared on confirmation, reverted after 8 s. Inside the vacuum sheet the Auto-Clean section is room tiles with a check disc, not switches ([vacuum-sheet-redesign](../../design/vacuum-sheet-redesign.md)).
- **Sheet.** Tapping a robot opens the vacuum sheet ([vacuum-sheet](../../patterns/vacuum-sheet.md)); room vacuum cards open the same sheet.
- **Map.** The Mapped map camera's `entity_picture` PNG with the map JSON in its `zTXt` chunk. An unavailable robot shows its last reported map without paths.
- **Services.** The sheet reads `get_services` once, so scripts the server lacks (area clean, dock) disable their buttons instead of failing.
- **Selection tiles.** Room and Auto-Clean tiles are selection tiles (one choice disc), not toggles, so there is no On or Off value. A chosen tile carries the `isSelected` trait. A room reads "<Room>" (with ", cleaning order N" when chosen) and the value "Selected" or "Not selected".
- **Area editor.** Draw, move, resize, pan, pinch and the VoiceOver actions route through `MapAreaEdit` (HassCore). Page scrolling is gated on gesture state, not the drag job: a cancelled drag never ends.
