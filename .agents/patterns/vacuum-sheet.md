# Vacuum sheet

> **What:** the robot vacuum sheet (map, status tiles, Controls/Rooms/Auto-Clean/Dock/Info tabs, area editor, cleaning report). **Read when:** opening a vacuum from any screen or changing vacuum controls.

The decided redesign (option B with amendments): [design/vacuum-sheet-redesign.md](../design/vacuum-sheet-redesign.md).

Web source: `ha-sfenton-react-dash@9ac2a46:src/components/hass/VacuumCard.tsx`, `vacuumModalRuntime.ts`, `vacuumStatus.ts`, `VacuumOutcomes.tsx`; config `src/constants/portedDashboard.ts`.

| Piece | File |
|---|---|
| Config (Main Floor, Studio, Media Room; auto-clean controls) | `HassCore/Config/VacuumConfig.swift` |
| Status contract, runtime mode, tabs | `HassCore/Vacuums/VacuumStatus.swift` |
| While-away report parsing and reconciliation | `HassCore/Vacuums/VacuumOutcomes.swift` |
| Commands, rooms, settings, queued clean | `HassCore/Vacuums/VacuumController.swift` |
| Lowered kinds | [vacuum-lowering](vacuum-lowering.md) |
| Sheet, tabs, layout, navigation | `HassUI/UIKitPort/ServerUI/UKServerUIVacuumView.swift`, `HassCore/Vacuums/VacuumSheetModel.swift` |
| Section bar symbols | `HassUI/UIKitPort/Features/Vacuums/UKVacuumTabs.swift` |
| Map panel, status summary, report | `HassUI/UIKitPort/Features/Vacuums/UKVacuumMapPanel.swift` |
| Area editor | `HassUI/UIKitPort/Features/Vacuums/UKVacuumAreaEditor.swift` |
| Style, sections, descriptions, buttons, rows, chips | `HassUI/UIKitPort/Features/Vacuums/UKVacuumComponents.swift` |

## Configured composition primitives

`ServerUIVacuumDescriptor` is the closed `vacuum@1` source contract. It supplies
targets, ordered rooms/consumables, map focus/rotation/scale, scripts and report
reconciliation entities explicitly. A composed source never consults the house
registry. `UKServerUIVacuumSource` retains the canonical `VacuumController` and
`VacuumMapState`; recording callers and fixture loaders are injectable.

`vacuum-control` selects one atomic primitive: card, map, status, notices,
settings, command, choice, consumable, report, outcomes, target, clear-area, auto-clean or
area-editor. The document explicitly places and orders each control and its
navigation attachment. There is no vacuum-sheet/page dispatcher. Card discs
use `VacuumActions` start/pause and dock with `OptimisticActions`; the sheet's
Clean intent uses the existing coordinated room/area script. They are not
interchangeable. Clean renders the canonical primary button, and commands absent
from the canonical runtime/dock action set are hidden rather than shown as stale
disabled tiles. Settings take authored role order, titles and hints.

The optional `autoCleanControl` descriptor names the page switch and its
`automation`/`pause` semantics. `auto-clean` renders the canonical module toggle
through `VacuumAutoCleanController` with an explicit control catalog; no house-global
lookup or duplicated inversion logic. Actual transport and optimistic state both
pin source identity. `UKServerUIVacuumEnvironment` injects fixture/read-only map
loaders, `serviceNames` and `mapURL` without replacing the command caller.

Capabilities are `sh.vacuum@1`, `sh.vacuum-controls@1`, `sh.vacuum-map@1`,
`sh.vacuum-outcomes@1`, `sh.vacuum-area@1` and `sh.vacuum-auto-clean@1`. Both compilers derive exact closure
without changing the frozen first-slice list. The generated Studio inspector
exposes the same closed variants and descriptor fields.

Actual service-call lifetime, pending settings/overlays, an open area draft and
a captured report pin the source. Publications cannot retarget/remove it or
change its consuming surface while pinned. Target switching retains the native
`AlertCopy` system alerts (HIG: **Alerts**); confirmation rechecks the captured
target, intent revision, service catalog, readiness and required map. An area
draft commits only on Use after revalidation; Discard or closing the mounted
editor preserves the original controller selection. Opening a report captures
its contract rather than following changes to the session sensor.

Existing gesture, transform, VoiceOver and native motion policies remain canonical (HIG: **Gestures**, **Accessibility**, **Motion**). A source runs one canonical map loader only while a map or editor consumer is mounted.

Recipes use ordered local tabs (up to five) with the runtime tab availability from `controller.tabs`, selected-room summary and local-tab routing, pinned modal chrome, geometric two-column layout, modal route lifecycle and the 0.13/0.17 s content swap.

## Behavior

- **Runtime mode** (`VacuumRuntime`): full when docked or idle and ready; minimal while cleaning, paused, returning or resumable. Rooms, auto-clean rooms and settings lock outside full mode; the Dock tab shows only the active dock cycle in minimal mode.
- **Settings and rooms are intents.** Each change shows at once, sends `select_option` or `turn_on/off`, and reverts after 8 s unless Home Assistant confirms. Turning a room on picks `vacuum` or `vacuum_and_mop` from the selected rooms' `mop_required` hints.
- **Clean waits for settled settings.** With an unconfirmed intent the clean is queued; it starts once every intent confirms and the store has been quiet for 0.65 s. It fails with a message if settings never confirm (8 s), the vacuum stops being ready, Home Assistant rejects the script, or the robot does not start cleaning within 30 s.
- **Rooms or Area.** Area cleaning (Main Floor) and room selection exclude each other; choosing the other asks first and clears the first (alerts "Use Area?" and "Use Rooms?", `AlertCopy`, system `.alert` on every path: the tile, a room card and a map tap). Areas are drawn in the area editor and sent in centimetres (`x_min_cm`…).
- **Smooth tab and mode changes.** The tab column draws a displayed key (tab + runtime mode) through `SmoothContentSwap`: a tab change fades the old tab out (0.13 s), swaps it while hidden and fades the new one in (0.17 s), like the web's `useSmoothDisplayedModalTab`. Starting or ending a clean (full ⇄ minimal) does the same with a layout animation between (web `useVacuumRuntimeContentTransition`). Reduce Motion swaps at once.
- **Tab state lives outside the sheet's body**, so a tab change redraws only the tab column and never the map canvas. A tab change scrolls the column back to the tab control only when the control is under the bar or above it.
- **Status tiles.** Under the map, Status, Battery and Dock are three equal read-only flat tiles in one row (the read-only face of the tile pattern: caption over value, toned glyph, no sheen, press or chevron); values never size a tile; one column at accessibility sizes. Locate stays the floating glass circle on the map. Notices (unavailable, current issue) follow the tiles.
- **Settings are pop-up rows only** (section "Cleaning Settings"): Mode, Fan, Water and Passes, title left, value and `chevron.up.chevron.down` trailing, an inline `Picker` in a `Menu` with the value as the only menu source (a whole-row `Menu` label made the row vanish while open). No segmented controls in the sheet; at accessibility sizes the value sits under the title. A footer under the group replaces the long per-setting descriptions, which remain the VoiceOver hints. Mode values read "Vacuum", "Mop", "Vacuum and Mop" everywhere (`VacuumCleaningMode.label`); any other helper text is shown raw. This departs from the web, which shows the helper text as is.
- **Conditional Water and Fan rows.** Water is absent when Mode is Vacuum, Fan when Mode is Mop. The row animates out and in: height with `MotionTokens.standard`, content with `MotionTokens.quick`; the group's background, hairlines and 26 pt corners belong to the container so they stay correct at every frame. Reduce Motion cross-fades the row in place at 0.2 s and changes the height at once. The target group (rooms ⇄ area) resizes the column with `standard` under the same rules ([motion](../design/motion.md) section 6 exception).
- **Reveal guard rails.** The change never animates on a reconnect or a cold launch from the snapshot, and applies at once while the sheet scrolls. Signposts are `LayoutChange` pages `Vacuum.settingRows` and `Vacuum.target` ([performance](../testing/apple/performance.md), Layout changes).
- **Rung 0 for the row reveal** ([change-loop](../workflow/change-loop.md)). `if` plus `.transition` takes the card to its new height at once, so the row's height is animatable (a one-child `Layout` whose `animatableData` scales the content) and the content leaves the tree in the collapse's `completion`.
- **Cleaning Target.** Rooms mode: a "Selected Rooms" summary (order chips, or "Full Clean" with the every-area warning when none) and a **Use Area** action tile; the summary has no chevron. Area mode: **Edit Area** (subtitle: the area's size), **Clear Area** and **Use Rooms** tiles. A robot without room selection shows only Use Area and Edit/Clear Area. One blue Clean `PrimaryButton`, labelled "Clean" in both modes.
- **Rooms and Auto-Clean are selection tiles** ([action-navigation-tiles](../design/action-navigation-tiles.md), selection-tiles option C and A), two columns, a footer under the grid, long names wrap to two lines (the tile never widens or scrolls). Rooms: chosen is the filled face with the numbered order disc, unchosen is dark with an empty circle disc. Auto-Clean: a check disc, checked is **included**, unchecked reads "Skipped" and is hatched on the map; an unavailable room dims and says Unavailable. Colour cross-fades with `state`.
- **Commands are action tiles.** Pause, Stop, Resume, Dock and Cancel (the run section), Edit Area, Clear Area, Use Area, Use Rooms and every dock command (Clean Mop Dock, Dry Mops, Empty Bin, Stop Dock Clean, Stop Mop Drying) are action tiles (text then disc, `AT` option B). Pause and Stop carry no description; an explanation, when needed, is a footer **below** the tile. A running dock wash is the tracked disc (arc spinner) and the filled Stop Dock Clean tile; the Dock status tile reads "Washing". While the robot is on the dock for its wash during a run, the Dock section stays in minimal mode: only the active command shows, never dimmed Dry Mops or Empty Bin tiles beside it.
- **Direction G look** (mockups n6-vacuum-*): the subtitle is `.sheetSubtitle("Docked · 100%")`; sections sit in the bottom modal tab bar (five sections, symbols only: Controls, Rooms, Auto-Clean, Dock, Info); lists are module rows (`#2C2C2E` cells at 26 pt in the sheet); while cleaning the map grows to 460 pt and the controls collapse to the run tiles (a run keeps Controls, Auto-Clean, Info).
- **Room and auto-clean tiles** are at least 76 pt tall; every tile in a grid row matches the tallest (larger than the web's 58 px).
- **Two columns** only where splits are allowed and the sheet is wide (`MediaRemoteLayout.usesTwoColumns`): map and status on the left, tabs on the right.
- **Accessibility:** room tiles are toggles with their order in the label and Auto-Clean tiles read Included or Skipped; each status tile is one read-only element; pop-up rows are buttons with the value; the map is decorative and draws no names; the area editor offers Draw (a default area under VoiceOver) and move, grow and shrink actions; every control is at least 44 pt.
