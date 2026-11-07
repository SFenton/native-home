# Direction G build plan

> **What:** the phases, components and verification for moving the app to [direction G](direction-g.md). **Read when:** picking up any direction G work, or touching a file a G phase owns.

## Update 2026-10-14

- **Go-ahead:** Alex: "Once chores thread is done you are permitted to proceed with the design refactor." Then, a minute later: "Sorry, Chores *and* Media. Once those are done, begin." Then (04:51Z): "In the meantime, you're free to begin work on what you can, so that once that work goes in you have a strong base to start from." So Phase 1 is being built now on `claude/project-thread-06krou`, and it stays off the files Chores (#35) and Media (#39) change. Its PR opens once both have merged.
- **Already merged:** App chrome (#44, `c5240c3`-era main) and the performance pass. The pieces Phase 1 restyles exist on main:
  - `HassUI/Common/HouseBackdrop.swift`: a cached, Core Image–blurred photo through `ImagePipeline`. The G scrim and the dark-only look go here.
  - `HassDesign/HassModal.swift`: `HassModal`, `SheetCloseItem` and `SheetCloseButton`.
  - `HassDesign/HeaderEdgeFade.swift`.
  - `HassUI/Common/ModalTabBar.swift`: it already has a `.bottom` placement reserved for this direction, so the bottom section bar is a restyle plus a default change.
  - `HassDesign/Loading/ContentGate.swift`: the spinner it shows becomes `ArcSpinner`.
  - `HassUI/Common/RoomOverview/*`: the shared room chip modal, with tints in `RoomOverviewStyle`. The colour families go there.
- **Phase 2 (shell), 2026-10-14:** `AppSection` has four cases; Settings lives in `AccountSheet` behind the profile avatar (Settings and its topics push inside the sheet; Sign Out sits behind an alert). The iPad flyout lists the four tabs, then Quick Links, which presents the sheet. Sign-in is dark with `PrimaryButtonStyle`. Recorded departures:
  - **Quick Links on iPhone stays the trailing tab page**, not a circle that presents the sheet: iOS 26 draws a `Tab(role: .search)` inside the bar unless its page is searchable, and selects it even when the selection binding refuses (measured 2026-10-14).
  - **No split page is left:** Settings was `OnDemandSplitStack`'s only adopter. The component and its hosted tests stay for the next list/detail page.
  - **People at Home and Your Summary** wait on the Daily Report port.
- **Colour families and the arc spinner** (Alex, 2026-10-14) are part of Phase 1. See direction-g.md.
- **Arc spinner sweep (Phase 1 step 2):** `ArcSpinner` replaced the system spinner in `ContentGate` and every `ProgressView()` spinner outside the open PRs. Titled spinners keep their words with `.progressViewStyle(.arc)` (`ArcProgressViewStyle`); a determinate `ProgressView(value:)` keeps its bar. The Chores and Cameras files skipped while #35 and #39 were open (`DonetickTaskSheet`, `TodoListSection`, `CameraLiveView`) were swept after they merged (2026-10-14).

## Update 2026-10-16: shell decisions reversed (owner, Alex)

Phase 2's shell rules changed after the owner used the app. These replace the "Phase 2 (shell), 2026-10-14" bullets above and decision 4 below:
1. **Settings is its own page, the last tab** (Home, Security, Climate, Chores, Settings), as on the web. The iPad and unfolded-Duo flyout lists the same five. Settings' topics push inside the Settings tab (household topics, Vacation, To-Do, Performance, Feedback; Home Assistant settings stays a full-screen modal). Settings is gone from the Account sheet. On macOS it stays the Settings window.
2. **Quick Links is a header button beside Profile on every page**, tab roots and pushed pages, on iPhone, Duo and iPad. The trailing Quick Links tab (iPhone) and the floating circle (iPad, #84) are removed; the flyout has no Quick Links row. Identifiers `quickLinks.open` and `nav.profile` are unchanged. The sheets hang once on each section's stack, so a pushed page never presents a second copy; a page Quick Links chooses pushes on the section's path.
3. **The Profile (Account) sheet is the web's profile modal**: Your Summary (overdue and upcoming chores, expired food) plus People at Home, with the account, Location and Sign Out. The Profile button carries the web's attention badge (overdue chores plus expired food, "9+").
4. **Title in the header on iPhone and the folded Duo:** `toolbarTitleDisplayMode(.inlineLarge)` from `pageChrome()`. Found by trying it on iOS 27 (2026-10-16): the large title sits leading in the header row beside the trailing circles, collapses to a centred inline title on scroll and returns at the top, and a pushed page with a Back button keeps the system's large title below the bar. Nothing custom was needed, so there is no departure to record. iOS 17 to 25 get the same behaviour from the same API without glass. **Superseded on iPhone 2026-10-20:** Owner, 2026-10-20 (supersedes the 2026-10-16 inlineLarge rule on iPhone): the hamburger (`nav.open`, `.topBarLeading`) is the leading-most bar item; Quick Links and Profile stay trailing; the title is the standard large title below the bar (`.automatic` from `pageChrome()`) and collapses to a centred inline title on scroll. `.inlineLarge` would take the leading slot and push the hamburger right, so it is kept only where there is no hamburger (Duo rail, compact iPad).

## Phase 1 status (2026-10-14)

Built on `claude/project-thread-06krou`, one commit per step, in the order the coordinator set:

| Step | Where | Notes |
|---|---|---|
| Arc spinner | `ArcSpinner`, `ArcProgressViewStyle` (`.progressViewStyle(.arc)`) | Every `ProgressView()` spinner outside the open PRs; skips listed above. `ContentGate` builds the arc only while it shows. |
| Palette | `HassTokens.Palette`, `Ink.warning/actionFill/badge`, `Surface`, radii 22/26 | Raw values with contrast tests (`HassTokensTests`); light-appearance values kept. Accent colour follows the G tint in dark. |
| Wallpaper | `HouseBackdrop`, `HouseBackdropStyle` | Blur 16.8 pt (the web's, user-adjustable), saturation 1.1, scale 1.06, G's scrim; `preferredColorScheme(.dark)` on the signed-in shell. |
| Module | `.module(.thin/.dense)` (`HassDesign/Module.swift`) | Content layer only; Reduce Transparency makes it opaque. `navigationGlass(in:)` is the navigation-layer counterpart. |
| Tiles | `TileFaceStyle`, `GlassTile(family:isError:)`, `BrightnessTile` | Off, lit, filled, tinted (no family yet) and error faces; dragger bubble, lift, 10% haptic. Filled progress shades the part still to go (a white band failed contrast). |
| Chips | `StatusChipButton(family:)`, `ColorFamily.chipFill/chipGlyph`, `ColorFamily.climate` | Web colours; AQI-coloured glyph is a follow-up. |
| Section bar | `ModalTabBar` on glass, `modalTabBar(placement: .bottom)` by default | Climate and Media Remote still place it inline at the top; their lanes move them. |
| Primary button | `PrimaryButton`, `PrimaryButtonStyle` | |
| Gallery | `ComponentGallery` page `direction-g` (`DirectionGGallery`), `DirectionGJourneyTests` | Names, targets, taps, drag, audits (top and lower sections, AX5), sheet bar at the bottom; iPhone, Duo and iPad. |

## Starting point on main (surveyed 2026-10-13, before the merges above)

| Area | Today | G needs |
|---|---|---|
| Tokens (`HassDesign/HassTokens.swift`) | Spacing, three radii, web-derived tints, `Ink` (label, danger, action) that adapt to light and dark | One dark palette: tint text `#409CFF`, tint fill `#0071E3`, red `#FF6961`, orange `#FFB340`, badge `#D93025`, owner hues, heat `#CD5401`, cool `#2C8E98`. Radii 22 (tile), 26 (module), 50pt capsule. Material specs. |
| Appearance | Follows the system; nothing sets a colour scheme | Pages are always dark on the wallpaper. Sheets are dark in v1 (see Decisions). |
| Shell (`MainTabView`, `AppSection`) | `TabView` with five sections, Settings is a tab; iPad flyout | Four tabs plus a Quick Links glass circle; Settings moves into the Account sheet behind the Profile avatar. The App chrome thread is already building the tab bar, Quick Links and profile button. |
| Page background | Per page; the App chrome thread is adding `HouseBackdrop` and a header fade | One cached, pre-blurred wallpaper bitmap with G's scrim on every tab root and pushed page. |
| Tiles (`GlassTile`, `BrightnessTile`) | Material tiles with a tint and wash; `BrightnessTile` already does tap to toggle and horizontal drag for brightness | Same behaviour, G looks: dark off, warm lit tile with dark ink, other devices filled with their colour family, red error state, % bubble and lift while dragging, 10% haptic ticks. |
| Status chips (`StatusPill`, `StatusRail`) | App chrome thread is turning them into tinted pills | Capsule with glyph, title and state; owner tint when active. |
| Sheet chrome | About 20 hand-rolled copies; App chrome thread is consolidating into `HassModal`, `.hassSheet()`, `SheetCloseItem` and a top `ModalTabBar` | Close x trailing; Cancel x leading with a blue check trailing on edit sheets; sections in a **bottom** glass segmented control. |
| Thermostat dial (`HassDesign/ThermostatDial`) | Already G's signature dial | Keep as is. Bed and humidifier dials reuse its geometry. |
| Section pickers (`SheetTabPicker`) | Top segmented control, menu at accessibility sizes | Bottom glass section bar (same fallback to a menu at accessibility sizes). |
| Deployment target | iOS 17 | Liquid Glass on iOS 26 and later; `.ultraThinMaterial` capsules on 17–25. |

## Decisions I'm taking (defaults, change any of them)

1. **Build on the App chrome thread's pieces, not beside them.** Its `HouseBackdrop`, `HassModal`, `.hassSheet()`, `SheetCloseItem`, tab bar, profile button and pill chips get restyled to G. No second set of components.
2. **Sections move to the bottom.** The chrome thread's `ModalTabBar` sits at the top. G puts sections in a bottom glass control, as in the mockups Alex approved, so `ModalTabBar` gains bottom placement and every sheet switches to it.
3. **Dark everywhere in v1.** Pages are dark by design. Sheets ship dark too, since that is what the mockups show; light-appearance sheets are a follow-up.
4. ~~**Settings leaves the tab bar** and is pushed inside the Account sheet.~~ Reversed 2026-10-16: Settings is the last tab (see the update above). On macOS it is the Settings window (⌘,).
5. **The open questions in direction-g.md keep their mockup defaults** until Alex answers.
6. **One look change per screen, no behaviour changes.** G threads restyle; they don't change what a control does, except where G names a new behaviour (the % bubble, Hub and Fan pop-up menus, garage button states, the "Updating" pill).

## Phases

### Phase 0: now, no code
- This plan and [direction-g.md](direction-g.md), text only (no images; the repo is public).
- The design skill installer (`tools/install_design_skills.sh`) and its `.gitignore` lines go in the same PR. app-designer-pro stays uncommitted.

### Phase 1: foundation (one thread, starts when App chrome and Performance have merged)
Everything later phases need, shown in `ComponentGallery` with snapshot tests and screenshots against the mockups.

| Piece | Where | Notes |
|---|---|---|
| `HassTokens` G palette, radii, type ramp | `HassDesign/HassTokens.swift` | Replace `Ink.action` uses with the G tint. Keep names stable where callers exist. |
| `Wallpaper` | Extends `HouseBackdrop` | Decode once at screen size, blur and saturate once (Core Image), cache in memory and on disk next to the image cache from #36. Draw the scrim gradient on top. Never a live `.blur`. |
| `.module(.thin / .dense)` | `HassDesign` | `rgba(28,28,30,.55)` with a 30pt background blur, or dense `rgba(20,20,22,.78)` for red and orange text. 26pt corners, no rim. Content layer only, never `.glassEffect`. |
| Sheet ground | `HassModal` | `#1C1C1E` ground, `#2C2C2E` cells; the presenting page scales back and dims (system behaviour). |
| Toolbar circles | `SheetCloseItem` and siblings | Close, Cancel, Confirm (filled `#0071E3` check), Back, Profile avatar. 44pt glass circles. |
| `SectionBar` | Replaces `SheetTabPicker` and the top `ModalTabBar` | Bottom glass segmented control; symbols only at five segments; hides empty sections; cross-fade with no layout jump; menu at accessibility sizes. |
| `PrimaryButton` | `HassDesign` | 50pt capsule, `#0071E3` with white label, or an owner hue with dark text. |
| Tile restyle | `GlassTile`, `BrightnessTile` | Off, lit, family-fill and error faces (colour families in direction-g.md); equal heights per grid row; chevron only when it opens something. Dragger adds the % bubble, lift and 10% haptics. |
| `LightSlab` | New, from `BrightnessTile` | Full-width slab for a room's lights, and the 168pt brightness slab in the light detail. |
| Status chip restyle | The chrome thread's pill | Web chip colours (direction-g.md), horizontal scroll, Duo stops 24pt short of the hinge. |
| Inset lists | `SettingsSection`, list rows | 26pt radius on pages, 52/60pt rows, inset hairlines; explanations inside the card on the wallpaper. |
| Loading | With #36's `ContentGate` | One centred `ArcSpinner` on the wallpaper with nothing saved; the "Updating" glass pill by Profile with a snapshot. |
| `ArcSpinner` | `HassDesign` | The web's arc: a `Circle` track at 22% plus a 25%-trimmed arc with an angular gradient from 72% to 96%, rotating linearly every 0.82 s. Sizes 44, 20 and 16; tints from `foregroundStyle`. Replaces every `ProgressView()` spinner. Half speed with Reduce Motion. |

Gate to leave Phase 1: compiles on the Mac, `HassDesignTests` and `HassUITests` pass, the rendered contrast audit (`RenderedContrast.swift`) passes on the wallpaper and in sheets, Reduce Transparency swaps materials for opaque fills, and gallery screenshots sit beside the mockups in the thread.

### Phase 2: shell (same thread as Phase 1, or right after it)
- Four tabs plus Quick Links circle, Chores overdue badge, Profile avatar into the Account sheet (People at Home, Your Summary, Settings pushed inside, Sign Out with an iOS 26 alert).
- Pushed pages: glass Back circle, large title, tab bar hidden only where the page has its own bottom toolbar.
- iPad flyout lists the four tabs then Quick Links. Duo unfolded keeps each half its own column.
- Login screen (`n1-signin`).

### Phase 3: pages, five lanes in parallel
Each lane restyles its screens against its mockups, uses only Phase 1 pieces, and posts before and after screenshots per device as it goes.

| Lane | Mockups | Code |
|---|---|---|
| **Home** | n1 home, weather, daily report, Quick Links, Account and Settings; n2 lights, light detail, security, doors, climate, occupancy and air quality sheets, cameras | `Features/Home/*` (HomeScreen, StatusRail, CameraGrid, WeatherSummaryCard, GuestPresenceSection), `HassUI/Common/RoomOverview/*` (the chip sheets, LightGroupTile; added 2026-10-15), `Features/Cameras/*`, `Features/Settings/*`, `Features/Rooms/QuickLinksSheet` |
| **Security and Climate** | n3 | `Features/Security/*`, `Features/Climate/*`, `Controls/Thermostat/*`. Hub mode and Fan become `Picker(.menu)`; garage buttons get Sending, Opening, Closing and Error. |
| **Rooms and devices** | n4 rooms, room pages, fan, purifier, bath fan, humidifier, grill, wake light, bed | `Features/Rooms/*`, `Features/RoomDevices/*`, `Features/Bedroom/*` |
| **Media and outdoors** | n4 media, remote, custom lights, sprinklers | `Features/Media/*`, `Features/MediaRemote/*`, `Features/CustomLights/*`, `Features/Sprinklers/*` |
| **Chores, Food and Vacuums** | n5 and n6 | `Features/Chores/*`, `Features/Vacation/*`, `HassDesign/FilterSheet`, `FloatingActionBar`, `Features/Food/*`, `Features/Inventory/*`, `Features/Vacuums/*` |

Shared helpers lanes add for each other (use them, don't copy): `HassDesign/SheetSubtitle.swift` (`.sheetSubtitle(_:)`, a sheet's one-line subtitle: the system navigation subtitle on iOS 26 and later, none earlier; never a custom principal title or `minimumScaleFactor`).

The fifth lane is the largest; if it runs long it splits into Chores and Vacation, and Food, Inventory and Vacuums.

### Phase 4: platforms and polish
- iPad 4-column grids, form and page sheets, flyout. Duo unfolded once the Duo simulator can unfold again (blocked today).
- macOS sidebar, toolbar Quick Links, Settings window, panels for the thermostat and remote (only if a Mac target is in scope by then).
- Light-appearance sheets (done 2026-10-15, `PROGRESS.md`).
- A full-app pass of the contrast audit, Dynamic Type at AX5, VoiceOver order and Reduce Motion.

#### Phase 4 spec (2026-10-15)

Alex, 2026-10-15: "continue Phase 4 ... when done commit and merge." Three lanes in parallel, each its own branch and PR, reviewed by the planner before merge. Mockups: n1-ipad-home, n1-ipad-nav, n1-duo-unfolded and fc-families in the owner's gallery.

**Decisions taken (change any of them):**
1. **Grids:** columns still grow with width (`DynamicGridLayout`, web UX contract), and a full-width tile grid reaches at least 4 columns at iPad portrait width. That settles direction-g.md ("4 columns") against ipados.md ("no fixed ceilings"): 4 is a floor on iPad, not a cap. Caps of 3 on tile grids go. On a window with a hinge (unfolded Duo) the count rounds down to an even number so no tile straddles the hinge.
2. **Chips:** they scroll in compact width and wrap (`FlowLayout`) in regular width. With a hinge, the rail stops 24pt short of it.
3. **Quick Links on iPad and the unfolded Duo** is a floating 56pt glass circle bottom-trailing on section roots (n1-ipad-home), replacing the toolbar button; the flyout row stays.
4. **Sheets on iPad:** every sheet names its size. Viewing and control sheets with tile grids, dials or maps use `.page`; lists, editors and prompts use `.form`. Sheets that bypass `.hassSheet` adopt it.
5. **Home on the unfolded Duo in landscape** splits into two columns on the hinge (n1-duo-unfolded): chips and weather leading, cameras and guests trailing. iPad landscape stays one column (n1-ipad-home).
6. **Light-appearance sheets:** sheets follow the system appearance; pages stay dark on the wallpaper. The sheet tokens (`Surface.sheetGround`, `sheetCell`, `secondaryInSheet`, `separator`) become light/dark pairs, and tiles and module lists inside sheets get light faces (white cell, dark ink; family fills and the lit tile are unchanged). Sheets drawn over a photo or always dark by design (Weather, Login, Location permission, the camera viewer) stay dark.
7. **Off glyphs keep their family** (fc-families): an idle or off bed side draws the Heating glyph (Cooling when its level is below zero); an idle or off thermostat card draws Heating in heat mode and Cooling otherwise. Before this they fell back to neutral grey.
8. **macOS:** out of scope. There is no Mac target (`project.yml`), so the macOS items wait until one is added.

**Lanes:**

| Lane | Owns | Work |
|---|---|---|
| iPad and Duo layout | `HassDesign/DynamicGridLayout*`, `HassDesign/FlowLayout`, `HassUI/App/Shell/*`, `Features/Home/StatusRail`, `Features/Home/HomeScreen`, `Features/Rooms/QuickLinksSheet` (button), grid caps and `.hassSheet` sizes in feature files | Decisions 1–5; `dynamic-grid.md`, `ipados.md`, `duo.md` updated |
| Light sheets | `HassDesign/HassTokens`, `HassModal`, `GlassTile`, `ModuleList`, `PrimaryButton*`, and sheet colours in feature files | Decision 6; journeys gain a light-appearance pass for sheets; contrast audit passes in both |
| Accessibility pass | `Features/Bedroom/BedroomComponents`, `Features/Rooms/RoomSupport` (tile faces), Reduce Motion fixes, `Apps/iOSUITests/*` additions | Decision 7; every `withAnimation` / `.animation` honours Reduce Motion (motion, not opacity); journey launch options for Reduce Motion, Reduce Transparency and Increase Contrast; an AX5 + audit sweep over every tab root and main sheet on iPhone, Duo and iPad; fixes for what it finds |

Feature files are shared between lanes for one-line edits (a grid cap, a sheet size, a colour token); whichever lane merges second resolves.

#### Phase 4 status (2026-10-16)

Merged: iPad and Duo layout (#84), light-appearance sheets (#85), accessibility pass (#86), each reviewed by the planner.

Still open:
- **Unfolded Duo:** landscape is verified (#84); unfolded portrait, the partly folded pose, light sheets and the accessibility sweep were not run there.
- **Light sheets:** iPad landscape, iOS 17–25 fallbacks and a real Control Center toggle on a device are unverified.
- **Vacuums:** two element-less contrast issues on iPhone are unattributed (`.agents/testing/apple/accessibility.md`, Open findings).
- **macOS:** deferred until a Mac target exists (decision 8).

## Dependencies on wave-2 threads

| Thread | Why G waits for it |
|---|---|
| App chrome and modals | G restyles its components; building beside them would create duplicates. Hard dependency for Phase 1. |
| Performance, telemetry and loading (PR #36) | The wallpaper cache uses its image pipeline, and loading uses `ContentGate`. Hard dependency for Phase 1. |
| Home modals, lights and weather | Owns the shared room chip modal and weather; Home lane restyles after it merges. |
| Media, cameras and security | Media and Security lanes start after it merges. |
| Climate and vacuum modals | Security and Climate lane and the vacuum part of lane five start after it merges. |
| Chores, To-Do, Vacation, Solo Trip (PR #35) | Lane five starts after it merges. |
| Code audit and Swift skills | Its shared helpers and the SwiftUI Pro review apply to every G PR. Soft dependency. |
| Simulator capacity gate (PR #30) | All G screenshot and journey runs go through `devcap.py`. Soft dependency. |
| Bug reports and triage | No overlap. |

## How each G PR is verified
- Compiles on the Mac; unit tests and the lane's UI journeys pass under the capacity gate.
- `/swiftui-pro` on the diff before opening the PR.
- Screenshots on iPhone 17 Pro and iPad, each next to its mockup in the thread (attached to replies, never committed).
- The rendered contrast audit passes on the wallpaper and in sheets, including the red and orange text on dense modules.
- Reduce Transparency, Increase Contrast and AX5 Dynamic Type checked on the lane's main page and one sheet.
- Before merge, the PR head tree is compared with current main so no recently merged work is reverted (the PR #36 gotcha).

## Risks
- **Fonts:** the mockups use Inter in place of SF Pro, so real spacing will differ slightly. Compare layout, not glyph widths.
- **Contrast on the photo:** the scrim and dense module are tuned on one photo. If the house photo changes, rerun the contrast audit.
- **Liquid Glass fallback:** iOS 17–25 get `.ultraThinMaterial` capsules. Lanes screenshot one older-iOS run of the shell.
- **Overlap with in-flight restyles:** wave-2 threads are changing the same files now, which is why coding waits for them to merge.
