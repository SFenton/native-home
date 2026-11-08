# Section sides on a partly folded Duo

> **What:** while the iPhone Duo is partly folded (book pose), every section of a page sits wholly on the leading or the trailing side of the hinge; the per-page side table, the one-section rule and the exceptions. **Read when:** you add or reorder a section on any page, add a page with sections, or touch `UKFoldColumns`, Home's columns or a page grid on the Duo.

Task T-section-sides. Mockups: [proposal](mockups/proposals/section-sides/section-sides.html) (Options A, B, C and D1-A, B, C, live size), and the `duo-part-fold` states of the atlas pages Security, Climate, Room page, Kitchen, Bedroom 1, Custom Lights, Sprinklers, Media and Home (the model). Hub: the owner's private mockup gallery (link kept outside the repo).

## The request

Owner, 2026-11-03: "One thing I'm noticing is that sections can go across the hinge of Duo when partial folded/the whole screen when unfolded. Unfolded looks good but folded, it looks weird when sections go across the whole screen. I want every section (e.g. Doors in Security, Cameras in Security, etc.) to be constrained to one side of the screen on a page. There can be exceptions. For example, on the Home screen, weather takes the whole span when unfolded, but a half-screen section when partial folded, which is great. I want you to do a design pass on each page in the app, especially ones where we have two columns available (e.g. split-views probably won't apply here) and implement consistency to this rule."

**Goal.** Partly folded, no section crosses the band; Home's weather is the model. Lying flat, iPhone, folded Duo, unfolded portrait and iPad (portrait and landscape) do not change.

**Evidence.** The Verifier's before captures, Duo partly folded (`build/evidence/claude-section-sides/before/duo-partial-fold/*-inner.png`; the full-window `*--uikit.png` files are black): Security (alarm modes 2 + 2 and Doors 2 + 1 around the band), Climate (dial already leading; contact tile and Advanced rows full width), Living Room (Remote with a hole beside it; Quick App Launch full width, its app tiles 2 + 2 around the band), Custom Lights (the switch row's toggle and the mode value beyond the band, lights 1 + 1), Sprinklers (one controller per side), Home (weather leading, Guests trailing). The note `build/research/section-sides-inventory.md` lists every page; no `manifest.json` was there when judged, so the built options are judged from these captures plus live-size mockups.

## Decisions

Decision: 2026-11-03, judged Option A (row grid: the band-aware section grid rooms use today, on every page), B (fold columns: two stacks, a fixed side per section, Home's model) and C (one column in the leading region); picked B, because it is the only one that keeps every section on one side at every text size with no holes and no wasted half, and it is the layout the owner already called great on Home. A lost: rows take their taller member's height, so short sections leave holes (the Living Room capture: Remote with nothing beside it; Security's alarm card beside Doors), VoiceOver reads across rows, and its 340 pt minimum scales with `.body`, so one size above Large it falls back to one track across the band, which breaks the rule; on Security and Climate it would also change iPad and the flat Duo. C lost: it leaves the 372 pt trailing region empty, doubles the page height, and undoes Home; HIG Designing for iPhone Duo, "Expand the existing layout with space".

Decision: 2026-11-03, judged D1-A (a page with one section puts all of it on the leading side), D1-B (an exception: keep today) and D1-C (divide only at whole blocks: a card, a whole tile set, a titled controller card; a section that is one block leads); picked D1-C, because it removes what the owner called weird (a card or row across the band, tiles split around it) without leaving a page of 1000 pt in one column beside an empty one. D1-A lost: Custom Lights becomes one column of eight lights under the card, about 1000 pt tall, with the trailing side empty, and Sprinklers stacks two 400 pt cards. D1-B lost: it keeps exactly the shape the owner asked to remove (Custom Lights' switch row has its toggle past the hinge).

Gate: matches_request=unsure (tools/jev_gate.py, 2026-11-03, on the request and on the picked option; the owner asked for this in an interactive session and declined a check-in question, so the build proceeds and the landing gate in tools/pr_land.sh decides)

Within B, the details below were decided by the Designer (propose-first: details inside the picked option).

Amendment: 2026-11-03, owner correction after viewing the hub ("Cameras top right like home page"): rule 11. The default-size drawings of Home and Security already put Cameras top right; the rule makes it explicit, and the accessibility-size detail (the wrapped rail heads the leading column) is the Designer's, so Cameras stays top right at AX5 too. No options were judged and `tools/jev_gate.py` was not run: this is the owner's own instruction on the layout they requested, not a pick (app_wide=no: it changes only the partly folded Duo).

## Rules this adds

1. **Where.** Only while the band exists: `UKShellEnvironment.windowHinge` non-nil and `SplitPolicy.geometry(container:isRegularWidth:hinge:)` returns `isHinge` with each pane at least 360 pt (as `HomeColumns.resolve`). Anywhere else the page draws exactly what it draws today. Never a device-name check.
2. **The unit is the section** (its header and everything under it). It sits wholly in the leading region (ends at the band) or the trailing region (starts after it). Each side stacks its sections top to bottom; the page has one scroll and the shorter side ends early (D4: no per-column scrolling; that is for panes).
3. **Sides are fixed per page** (D2), from the table below. Never balanced by live height: cameras loading, Guests or Open Contact Sensors appearing must not move any section to the other side (invariant: no reorder on reopen). A conditional section keeps its side and the others on that side move up or down only.
4. **How sides are chosen.** The page's hero leads (weather, the alarm card, Whole Home): HIG Layout, "Place important content toward the top/leading side in reading order". A section shared by pages keeps its side everywhere (Cameras, Guests Staying Over: trailing). The leading region is the wider one (455 pt against 372 pt), so the heavier side leads.
5. **Config-driven pages** (rooms, Media, Sprinklers' controllers): a section's side is the parity of its index in the configured list (even leads, odd trails), counted after static config filtering (Studio's hidden launcher is not in the list) and before runtime hiding (a section that hides keeps its slot). That is the side today's two-track grid gives it, so nothing that complies today changes side (HIG Duo, "move only what's necessary"). A room may set an explicit side in `RoomsConfig` if parity reads badly once built.
6. **One section on a page** (D1-C). Divide only at whole blocks; a tile set is one block, never cut. Custom Lights: header and the switch/mode card lead; the light tiles and Reset All Lights trail. Sprinklers: the header and the first controller card lead, the second trails. A section that is one block (every one-section room) leads and the trailing side stays empty (no placeholder). A trailing block with no header of its own starts level with the first block under the leading header.
7. **The alarm card leads** (D3), with its four modes in one row. This replaces the 2026-10-30 rule (card full width, modes 2 + 2 around the band) **only while partly folded**; lying flat and everywhere else the card stays full width. Its two reasons no longer hold here: Doors no longer sit on four columns below it, and the trailing side is not empty (Cameras).
8. **Text size** (D5). Two columns at every size, AX5 included: the band is physical. Tiles reflow to the tracks their side fits; nothing falls back to a full-width track while the band exists.
9. **Reading order** (D6). Column-major: the top strip, the leading column top to bottom, then the trailing column. The container sets `shouldGroupAccessibilityChildren` (which UIKit's header advises for items in vertical columns) and lists its sections in that order through `accessibilityElements` while split, so VoiceOver reads the columns one after the other; the columns are not separate groups. Right-to-left mirrors the columns, as Home does.
10. **Motion.** A pose change (flat to partly folded and back, rotation) reflows through `UKReflow` on `MotionTokens.standard`; Reduce Motion cross-fades in `quick` (0.2 s). Sections slide from their old frames to their new ones and nothing re-fades. Prefer moving frames (the columns precedent: "one host moved by frame; nothing is reparented"); a page whose flat layout is another container (the rooms' grid) may re-parent as Home does today, provided the reflow still starts from the old frames.
11. **Cameras top right** (owner, 2026-11-03, after viewing the hub: "Cameras top right like home page"). Wherever a page shows the Cameras section (Home, Security), while the Duo is partly folded Cameras is the first trailing section: its top edge is level with the top of the leading column (weather on Home, the alarm card on Security), directly under the top strip, as on Home. Guests Staying Over sits below it. Nothing is placed above Cameras on the trailing side, and it never moves down while other sections load or appear (rule 3). The debug gallery builds Security without cameras (`UKSecurityViewController`, `showsCameras: false`, because cameras need a live connection), so a gallery capture shows Guests at the top right; the app, and the mockups, show Cameras there.
    - **At accessibility text sizes** (Designer, a detail inside B): the rail wraps and stops 24 pt short of the fold (`ChipRailMode.wrap`, `ChipRailMetrics.trailingInset`, [status-rail](../patterns/status-rail.md)), so it can no longer span; it heads the leading column instead, and Cameras still starts at the top right, level with the rail's first chip. Spanning would leave the trailing side empty beside a rail about 260 pt (Security, two chips) to 800 pt (Home, six) tall in the AX5 drawings and push Cameras off the first screen, which is what the owner asked to avoid. The same holds for every page whose rail is the top strip over fold columns (the rooms: their first trailing section starts level with the rail); the rail is not a section and stays outside the parity count of rule 5. Reading order is unchanged: the rail, the rest of the leading column, then the trailing column. A text-size change while partly folded reflows as rule 10.

## Per-page sides (partly folded only)

| Page | Top (spans) | Leading | Trailing | Change from today |
|---|---|---|---|---|
| Home | Banner (a leading half wide), status rail (heads the leading column at accessibility sizes, rule 11) | Weather | Cameras (top right, rule 11), Guests Staying Over | None at default sizes: first consumer of the shared container; at accessibility sizes the wrapped rail now leads instead of spanning |
| Security | Status rail (heads the leading column at accessibility sizes, rule 11) | Alarm card, Doors, car (gallery only) | Cameras (top right, rule 11), Guests Staying Over | Was one column, card and tiles across the band |
| Climate | none | Whole Home (dial, hub pill, notices) | Open Contact Sensors (while any is open), Advanced Controls | Was one 720 pt column |
| Custom Lights | none | Front Yard header, switch and mode card | Light tiles, Reset All Lights (Custom mode only) | Was one 960 pt column |
| Sprinklers | none | Controllers header, Front Yard | Garden Faucet | Same sides; now safe at every text size |
| Living Room | Status rail | Climate, Remote | Devices, Quick App Launch | Launcher no longer spans; no row hole |
| Media Room | Status rail | Climate, Quick App Launch, Devices | Remote, Media Room Computers | Launcher no longer spans |
| Bedroom 1 | Status rail | Wake Light, Media | Bed, Climate | Same sides, stacked |
| Kitchen | Status rail | Groceries, Climate | Appliances | Same sides, stacked |
| Office | Status rail | Climate | Computers | None |
| Studio | Status rail | Climate, Devices | Remote | Same sides, stacked |
| Garage | Status rail | Appliances | Garage Doors | None |
| Guest Room, Gym, Dining Room, Guest Bathroom, Bathroom 1 (Climate); Back Deck (Grill) | Status rail | The one section | Empty | Was full width, tiles around the band |
| Hallway, Downstairs Hallway, Entryway | Status rail | "Nothing Here Yet!", centred in the leading region (E4) | Empty | Check it is not centred across the band |
| Media | none | Living Room, Media Room | Studio | Same sides, stacked; safe at every text size |

Pages that need nothing (each is already a pane or column split on the band): Vacuums, Food hub, Inventory, Chores and every todo page, Settings and its topic pages, the household pages, Vacation chooser, Vacation Mode, Solo Trip.

## Exceptions

- **E1 The status rail** (and Home's banner) spans the top above both columns and scrolls over the hinge (owner, 2026-10-26). It is a strip of chips, not a section. At accessibility text sizes it wraps and stops short of the fold, so it heads the leading column instead (rule 11).
- **E2 Collection pages.** Recipes' card grid is the page itself, one collection with no section header; its cards fill both regions on even tracks around the band (hinge-avoidance, Tiles). A rule built for sections would leave half a browsing page empty.
- **E3 Sheets** are placed by the system in the leading half (hinge-avoidance, Sheets).
- **E4 Empty states and other single objects** use `HingeAvoidance.placement`: centred, and moved into the leading region only when the band crosses them.

## Families

Changes only on the iPhone Duo, unfolded, landscape, partly folded. Unchanged by construction (no band): iPhone, folded Duo, unfolded portrait, flat unfolded landscape, iPad portrait and landscape. The Security mockup draws `duo-part-fold` beside `duo-flat` to show the contrast.

## HIG

- Designing for iPhone Duo, reserved regions: "Folding region | Present when partially open; divides the inner display into usable regions while excluding the center fold."
- Designing for iPhone Duo, arrangement views: "Overlay: layers the views; while partially folded they occupy separate sides". Fold columns are that arrangement for a page's sections.
- Designing for iPhone Duo: "Avoid extreme changes: move only what's necessary to keep elements visible and easy to tap" (rule 5).
- Layout, Hierarchy: "Place important content toward the top/leading side in reading order ... Group related information/functions using negative space, containers, or separators" (rule 4; the band separates the groups).
- The HIG does not ask for whole sections on one side; that is the owner's choice, and it wins over web parity (the web has no fold).

## Rung 0

| Need | iOS 17 | iOS 18 | iOS 26 | Verdict |
|---|---|---|---|---|
| Know where the hinge is | none | none | none; `UIView.reservedRegions(kind: .division)` and `UIHingeInteraction` are **iOS 27.1** (`UIViewReservedRegion.h`, `UIHinge.h` in the iPhoneOS27.1 SDK; measured by reading the headers 2026-11-03) | We already use both (`UKDeviceSignals.swift:25-33, 107-113`). They return rects, not layout. |
| Lay sections out around a region | none | none | none; the 27.1 headers expose queries only | Custom, as Home and `UKHingedPanes` already are. |
| Two columns of variable-height sections | `UICollectionViewCompositionalLayout` (iOS 13): groups lay out items in the order given; a group's `custom(layoutSize:itemProvider:)` returns frames you compute from the environment's container size. `orthogonalScrollingBehavior` scrolls sections horizontally only. | same | same | Not enough: sections here are live-bound hand-laid views with observation bags created once; cells are reused (`UKTileCell.prepareForReuse` clears the bag, `UKDynamicGrid.swift:377`), and a custom group needs the same width and height math we already have. |
| Equal-width columns split on a hinge | `UISplitViewController` (iOS 14 columns) | same | same | It owns navigation, not content flow; the repo replaced it with `UKColumnsViewController` (`split-view.md` l.33). |
| Pair of `UIStackView`s | iOS 17 | same | same | Possible, but the width of each stack is `band.lowerBound` and `container.maxX - band.upperBound`, which needs a pure function (`columnWidths`) and an observer anyway; Home's hand-laid columns avoid Auto Layout between page and cards by house rule (`UKLayoutViews.swift:292`). |
| VoiceOver order across columns | `shouldGroupAccessibilityChildren` (iOS 6); UIKit header says to set it on a parent of items "in vertical columns" (`UIAccessibility.h:169-176` in the 27.1 SDK) | same | same | System API, enough. |

Precedent in repo: Home (`UKHomeViewController.swift:107-266`), `UKHingedPanes` (50 lines), `UKColumnsViewController`, and the room/Media section grid. Apple: HIG Designing for iPhone Duo (read via the `apple-hig` skill, `designing-for-iphone-duo.md`, source dated 2026-09-09 per the file): "avoid extreme changes: move only what's necessary", "prefer a layout container that adapts automatically, and even grid column counts"; split views give equal panes when folded. It says nothing about keeping a whole section on one side, so the owner's rule is a product choice, not a HIG one.

**Verdict.** `UKFoldColumns` is custom layout machinery. No system API on iOS 17, 18 or 26 lays out variable-height, live-bound sections around a reserved region (the 27.1 `UIView.reservedRegions` and `UIHingeInteraction` only report it, and we already read them); compositional layout and split view need cells or own navigation; stack views need the same observer and geometry. The one system API that fits, `shouldGroupAccessibilityChildren`, is used. Audit entry: [system-api-audit](apple/system-api-audit.md).

## Verdict (round 1), 2026-11-04

Designer, on the Verifier's after pack (`build/evidence/claude-section-sides/after/`, sha 4fe0eb38), judged from the inner-panel screenshots against rules 1 to 11, the per-page table and the atlas. **Changes: one item (V1).** Everything else passes or is a note.

**Passes.** Duo partly folded at default size: every multi-section page has each section wholly on one side, with the sides the table gives. Security has the alarm card leading with its four modes in one row, Doors 2 + 1 and car below, and Cameras top right level with the card (rule 11). Custom Lights' tiles trail, level with the switch card (rule 6). Home, Climate, the rooms, Media and Sprinklers match. xLarge passes. AX5 passes on Home and Living Room for placement (the wrapped rail leads, and the first trailing section starts level with it). Lying flat, Home, Security and Living Room are unchanged (the card spans, Doors have no middle gap). Rotate in and out returns identical end states, with no reorder and no blanking (rule 3 and the no-reload invariant). iPhone and iPad portrait are unchanged.

**V1 (changes, real): a status chip's text overflows its capsule when the chip is narrower than its one-line text.** Security at AX5 while partly folded: "Contact Sensors" runs past the capsule's trailing edge to the band, in the gallery and live. The same defect shows in Home's AX5 capture (the Contact Sensors chip at the bottom of the frame). It is not fold-specific. The leading column (about 439 pt) made it visible, but any wrapped rail narrower than a chip's one-line width hits it: iPhone and the folded Duo at AX5 (about 361 pt), and Air Quality's state line ("AQI … · PM2.5 …") on Home. The cause is in `UKStatusChipView` (Home's and Security's chips). Its title and state labels keep `numberOfLines = 1`, and `layoutValues` places each label at its one-line `sizeThatFits` width, while the capsule is clamped to the row (`min(width, …)`). The flow (`UKFlowSolver`) correctly narrows the chip, so the text alone spills out. The room chip (`UKRoomChipView`) already wraps (`numberOfLines = 0`, text clamped to the space available).
- **Decision: wrap.** Truncating, shrinking the text and moving the chip are all rejected. HIG Typography, Supporting Dynamic Type: "Keep text truncation to a minimum as font size increases ... You can prevent label truncation by allowing as many lines as needed (`numberOfLines`)", and "Make sure your layout adapts to all font sizes". A `minimumScaleFactor` undoes the size the person chose. The chip already has a row of its own in a wrapped rail, so moving it gains nothing. Shrinking the capsule is what happens today, and it is the bug.
- **Shape (Designer detail).** A chip that wraps keeps the corner radius of a one-line chip at the current text size: `cornerRadius = min(height, oneLineHeight) / 2`. An unwrapped chip stays a capsule, unchanged. A wrapped one becomes a rounded rectangle with the same ends as its siblings, so the trailing curve of a 190 pt-tall stadium never clips the first line's end. Both chip views use the same rule (today `UKRoomChipView` draws its module ground at `minHeight / 2` and its tint at `height / 2`, which disagree once it wraps).
- Spec: `implementation_specs` V1 in the round-1 status block (Designer report, 2026-11-04). It adds a status-rail pattern rule: "A chip narrower than its text wraps its title and state at word boundaries inside the capsule; it never truncates or shrinks its text."

**V2 (note, no change): Admin settings, Guest controls and the Vacation chooser are gallery artefacts.** In the app they are reached only from Settings rows (`UKSettingsViewController.show`). Partly folded, `SplitPolicy.allowsSplit` is true, so they open in Settings' trailing pane (372 pt, after the band), and `syncColumnRoutes` moves a pushed one into the pane when the window starts splitting. No other caller pushes `.household` (`UKSectionNavigationController.push(_:)` has no callers outside Settings), and Vacation is `SettingsRoute.vacation` only. Standalone, the gallery has no Settings host, so it lays them out full window, as before this task. They stay in "Pages that need nothing". A gallery capture of them partly folded is not evidence for or against this rule. Vacation Mode and Solo Trip push inside the pane, which keeps them on the trailing side.

**V3 (note, separate defect): Vacuums' trailing pane header.** Partly folded, the Auto-Clean pane's header is a translucent bar whose title is blurred past reading, and it covers the top of the first row (Main Floor's switch is cut). The before capture (`before/duo-partial-fold/vacuums--uikit-inner.png`) shows it identically, so this task did not cause it. It is worth its own task (a pane's header must show its title and start its content below it; HIG Materials and the scroll-edge rule). File it apart from T-section-sides, with these two captures as evidence.

**V4 (not covered): none of it blocks the design verdict.**
- iPad landscape has no band, so rule 1 leaves it unchanged by construction, and iPad portrait shows no change. The ledger check `evid` names it, so the Verifier captures it in round 2 with the V1 recapture.
- Vacation topics in the Settings pane: the pane geometry is `SplitPolicy`'s and is shown correct for Settings' other topics, and V2 explains why the pages cannot cross the band. The debug hook (`FENTON_DEBUG_SETTINGS_PANE`) still opens only the placeholder in the retry. Capture it when the hook is fixed; this can follow later.
- Inner-panel accessibility trees: XCUITest cannot reach the inner panel. Rule 9 is covered by `UKHostedSectionSidesTests.testReadingOrderIsColumnMajorWhileSplit` and `FoldColumnsTests` (reading order). Acceptable here; no VoiceOver run on the physical Duo (deploy only).
- The transition frames of a pose change were not captured. Rule 10 is covered by `testEveryPageMovesItsSectionsWhenThePoseChanges` and the posture reflow cost test. This can follow later.

**Round 2 needs:** after V1 lands, Duo partly folded at AX5 (Security and Home, gallery and live), iPhone at AX5 (Home, Security) and iPad landscape (Home, Security).

## Verdict (round 2), 2026-11-04

Designer, on `build/evidence/claude-section-sides/after-r2/` (sha 8eebc871, the V1 fix). **Pass.**

- **V1 passes on Duo partly folded at AX5.** Home and Security, gallery and live: every chip's text sits inside its capsule. "Contact Sensors" wraps to "Contact / Sensors / All Closed" with the glyph centred, and the wrapped chip has the same end radius as its one-line siblings (`UKChipShape.cornerRadius`). Nothing truncates or shrinks. The capsule stops short of the band, and Cameras (live) and Guests (gallery) still start top right, level with the first chip (rule 11). HIG Typography, Supporting Dynamic Type ("allowing as many lines as needed").
- **iPhone at AX5:** Home and Security, gallery and live: chips wrap inside the capsule (Home's "Contact Sensors / 1 Open", Security's "Contact Sensors / All Closed"), and one-line chips are unchanged capsules.
- **No regression at Large.** Duo partly folded, Home and Security: the rail scrolls across the top (E1), weather and the alarm card lead, and Cameras is top right, level with them.
- **iPad landscape is non-blocking.** The Security capture is a single page with no band: the card and Doors span, as before. The XCUITest image is the portrait framebuffer holding a landscape frame (black top, right edge cropped), which is a capture artefact, not a layout. Home failed to capture twice for infra reasons. Both are unchanged by construction (rule 1: no band, no fold columns), and `testTheFlatPoseKeepsASingleColumn` asserts the layout without the band.
- **Vacation topics in the Settings pane:** still only the placeholder (debug hook). This stays a non-blocking follow-up, as in V4.
- **Room chips** (`UKRoomChipView`) take the shared corner rule. They were not recaptured at AX5; the hosted AX5 tests at 320, 361 and 439 pt cover containment and radius. Recapture them in the next nightly three-family run.

Open follow-ups, outside this verdict: V3, the Vacuums pane header (a separate task); fixing the Settings-pane debug hook; merging `UKRoomChipView` into `UKStatusChipView` (pattern first).
