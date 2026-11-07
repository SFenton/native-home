# Vacuum sheet redesign

> **What:** the redesign of the robot vacuum sheet (map, status, settings, rooms, Auto-Clean, dock, run controls), decided 2026-10-28: option B (the Recommended column) with the owner's amendments. **Read when:** touching `HassUI/Features/Vacuums/*`, `ValetudoMapView`, `AlertCopy` (Use Area / Use Rooms) or any vacuum mockup.

Proposal: [vacuum-sheet-redesign.html](mockups/proposals/vacuum-sheet-redesign/vacuum-sheet-redesign.html) (in the [mockup hub](mockups/README.md); section 6 "Decided" draws the final design, the options weighed are folded away below it). Atlas, drawn as built (shipped in PR #210): [vacuum-sheet](mockups/modals/vacuums/vacuum-sheet/README.md), [vacuum-switch-dialog](mockups/modals/vacuums/vacuum-switch-dialog/README.md), [vacuum-area-editor](mockups/modals/vacuums/vacuum-area-editor/README.md), [vacuum-outcome-report](mockups/modals/vacuums/vacuum-outcome-report/README.md), [vacuum-map-canvas](mockups/components/vacuums/vacuum-map-canvas/README.md), [vacuum-status-chip](mockups/components/vacuums/vacuum-status-chip/README.md).

## Goal

The owner raised three things (2026-10-28), and a pass over every section of every vacuum modal found more of the same kind:

1. **Room names on the map are a non-starter.** The map drew every name, `.caption2` semibold, spilling past small rooms; on 11 rooms they collide with the badges and each other (`ValetudoMapView.drawNames`).
2. **Status chips under the map are uneven widths.** Status, Battery and Dock were pills in a `FlowLayout`, each as wide as its value ("Returning", "Dock Washing") and wrapping raggedly; the web has equal cells.
3. **Settings mix grammars.** Suction (5 options) was a pop-up, Passes a segmented control beside its title, Mode and Water segmented under theirs, Rooms/Area another segmented control.

Found in the deep pass: while cleaning the state was said three times (subtitle, Status chip, the run card's header); the Auto-Clean checkmark meant *skipped*, the inverse of every other tick in the app; the Selected Rooms row jumped to another section; commands were four different shapes (grey capsules, blue-title rows, glass Locate, pills); the switch dialog mockup drew an action sheet while `AlertCopy` raises an `.alert`.

## The decision (owner, option B with amendments, 2026-10-28)

| Area | Decision |
|---|---|
| Map | No room names anywhere (sheet, area editor, report). Selected rooms white with the numbered order badge, Auto-Clean skipped rooms hatched, the rest flat. **Locate stays the floating glass circle on the map** (no Locate tile). Reverses the 2026-10-24 "Room names are always drawn" rule ([valetudo-map](../patterns/valetudo-map.md)). |
| Status | Three equal read-only flat tiles in one row, Status, Battery, Dock (caption over value, toned glyph); one column at accessibility sizes. |
| Settings | One pop-up row grammar for Mode, Fan, Water and Passes under "Cleaning Settings", title left, value and `chevron.up.chevron.down` trailing in the action colour. No segmented controls. The long descriptions are a footer under the group and the VoiceOver hint. |
| Water and Fan rows | Water is absent when Mode is Vacuum; Fan is absent when Mode is Mop (the code already hid it; accepted with the page). The row animates out and in and its containers resize (see Motion). |
| Controls target | The Rooms/Area segmented control goes. Rooms mode: a Selected Rooms summary and a **Use Area** action tile; area mode: **Edit Area** (with its size), **Clear Area** and **Use Rooms** tiles. Copy: "Switch to Area" is **Use Area**, "Switch to Rooms" is **Use Rooms** (alerts "Use Area?" and "Use Rooms?" in `AlertCopy`). Clean reads "Clean" in both modes. |
| Sections | Five stay: Controls, Rooms, Auto-Clean, Dock, Info (Rooms is **not** merged into Clean). |
| Rooms | Selection tiles in two columns: chosen is the filled face with the numbered order disc, unchosen dark with an empty circle disc; long names wrap to two lines; a footer under the grid. |
| Auto-Clean | Selection tiles with a check disc: checked is included, unchecked says "Skipped" and is hatched on the map; an unavailable tile dims. Footer below. Not switches, not checkmark rows. |
| Run section | While a clean runs: the map grown, no duplicate state header, **Pause and Stop (or Resume, Dock, Cancel) as action tiles side by side with no description text**. A command that is unavailable says why in one footer. Three sections while a run is in progress (Controls, Auto-Clean, Info). |
| Dock | Every command (Clean Mop Dock, Dry Mops, Empty Bin, Stop Dock Clean, Stop Mop Drying) is an action tile; what it does is a **footer below the tile**. A running wash is the tracked disc and the filled Stop Dock Clean tile; the fake "Washing Mop Pads" row is gone (the Dock status tile says Washing); during a run's own wash the section is its footer alone. |
| Info, area editor, report | Info unchanged. The area editor and report maps have no names; nothing else changes. |

Decisions taken inside the option and accepted with the page: the row is titled **Fan** (the entity's name, not Suction); **Passes** (not "Cleaning Passes"); Mode values read "Vacuum", "Mop", "Vacuum and Mop"; Selected Rooms has no chevron.

Owner decisions, 2026-10-29: (1) **Dock while washing or drying stays minimal-mode**: only the active command shows; the dimmed Dry Mops and Empty Bin tiles do not appear during a wash. (2) **"Vacuum and Mop" everywhere**: the Mode row's value uses the menu's label when the helper text names a known mode (the web shows the helper text; recorded departure for consistency).

## Rules this adds

- **One tile grammar for commands.** Every clickable action in the vacuum modals is an action tile ([action-navigation-tiles](action-navigation-tiles.md)); explanation sits below the tile as a footer, never inside it. Locate is the one exception: it is a map control, not a command row.
- **One grammar for choices.** Rooms and Auto-Clean are selection tiles (option C face with order disc; option A check disc); Cleaning Settings are pop-up rows. No segmented control in the vacuum sheet. Departure from the HIG segmented-control guidance for short lists, recorded in [direction-g](direction-g.md) "Choosing one option".
- **Equal status tiles.** Facts about the robot are three equal flat tiles; values never size the tile.
- **No text on the map:** no names, only order badges. VoiceOver reads the map as one element with the selected rooms as its value, and the Rooms section and Selected Rooms summary name the rooms.
- **State is said once or twice, never three times.** The subtitle and the Status tile; the run section has no header.

## Motion

The Water and Fan rows are person-caused layout (they follow the person's Mode choice). The row's height collapses or expands with `MotionTokens.standard`, its content fades with `MotionTokens.quick`; the group's background, hairlines and 26 pt corners belong to the container, so they stay correct at every frame, and the footer and the Clean button slide with it. Reduce Motion: the row cross-fades in place at 0.2 s and the height changes at once. The same mechanism covers the target group changing between rooms and area mode. Guard rails as for the tile action-set exception in [motion](motion.md) section 6: never on a reconnect or a cold launch from the snapshot, and applied at once (not deferred) while the sheet scrolls, since only a change made elsewhere can arrive mid-scroll (build, 2026-10-29; [vacuum-sheet](../patterns/vacuum-sheet.md) has the rung-0 note). Ships with `LayoutChange` signposts (`Vacuum.settingRows`, `Vacuum.target`) and `testVacuumSettingRowCost` ([performance](../testing/apple/performance.md), `tools/ios_motionperf.sh`). Dropping per-room name text also removes a per-draw `Text` resolve and measure for every room; measure with `tools/ios_scrollcost.sh`.

## Build notes

- Reuse the tile components of #186 (action, selection and read-only tiles); do not add a parallel implementation. Status tiles are the read-only flat face.
- Tests: journeys that tap `vacuum.target` segments or read checkmark Auto-Clean rows change (`VacuumJourneyTests`, `VacuumFlowTests`); new unit, UX and accessibility tests on iPhone, Duo and iPad for the three status tiles at AX5 (one column), the pop-up rows, the selection and action tiles (name, role, value), Use Area / Use Rooms alerts and the Water/Fan animation.
- Update the atlas mockups in the same PR: done in PR #210 (`shipped`, "was" notes removed). The tile helpers (`proposals/action-navigation-tiles/_action-tiles.js`, `proposals/selection-tiles/_selection.js`) and the vacuum builders (`modals/vacuums/_devices-vacuums.js`) should be promoted to the kit then.
- Release note: this is visible to users (`Release-Note:` trailer).
