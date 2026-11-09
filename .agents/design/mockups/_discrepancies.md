# Docs versus code

> **What:** where the docs, catalog hints or the app disagreed while the atlas was mapped (2026-10-23, `main` at a28b40be plus the in-flight branches). Each mockup draws the **code**. **Read when:** you edit a doc listed here, or a mockup's README says "see discrepancies". Fixing a doc is a docs change; changing the app is not part of the atlas.

## Navigation and presentation

| Topic | Docs say | Code does | Where |
|---|---|---|---|
| Camera viewer | `split-view.md`: full-screen modal; `iphone.md`: `.large` detents | `hassSheet(.page, .full, appearance: .dark)`; fitted detent is uncommitted in the primary checkout | `components/cameras`, `proposals/camera-viewer-fit` |
| Sign-in | `split-view.md`: full-screen modal | A root layer under `RootView`, not a modal | `pages/login` |
| Settings and Chores splits | `split-view.md`: Settings leading pane + detail; Chores lists split to detail | Settings is a tab with pushes; `OnDemandSplitStack` has no adopter; chore edits are sheets, sub-pages push full width | `pages/settings`, `pages/chores` |
| Zoom transitions | `motion.md` s3: room, camera, recipe tiles zoom; `patterns/motion.md`: overview room tiles; owner 2026-10-22: none inside sheets | `zoomSource` and `zoomDestination` have no call sites; plain push or sheet | `flows/zoom-transition` (`designed-not-wired`) |
| Flyout edge swipe | `direction-g.md`: off on iPhone | Enabled on every window that shows the menu button, iPhone included | `components/navigation` |
| Quick Links entry | docs mention a floating circle at regular width | Header button everywhere; the shell owns it. Pushed levels in Quick Links have no Close item, only Back | `pages/rooms` |
| Sheet sizes | `media-remote.md`: `.hassSheet(.page)`; `option-picker.md`: medium and large | `.full`; `.form`, fitted | `modals/media`, `components/design` |
| Chores task form | `ios.md`: large detent; one-field sheets medium | All content-fit | `modals/chores` |
| Household pages | `household.md`: push inside the Account sheet, sheets say "Done" | Push on the Settings tab path; circle-X Close; page title "Admin" | `pages/settings` |
| Vacation | `AwaySection` comment: opens in sheets | Settings is a tab | `pages/vacation` |
| Hinge awareness | `split-view.md`: divider on the hinge | Food hub, Recipes, Inventory split into equal halves without reading the hinge; sign-in, Security, Climate, Rooms second column and centred sheets are not hinge-aware (not run on a device) | `pages/food`, `pages/inventory` |

## Alerts and copy

| Topic | Docs say | Code does |
|---|---|---|
| Sign out | `direction-g.md`: an alert | Alert in the Account sheet and Your Summary, `confirmationDialog` in the HA settings cover, with different spelling |
| Chore delete | `direction-g.md`: alert | `confirmationDialog` |
| Food tile | "Food & Recipes" | "Food" in Quick Links |
| Chores title | catalog: "Your Tasks" | "Alex's Chores" for everyone |
| Photos denied | S+H | "Allow Home" |
| Recipe detail | `ios.md`: "8/9" | "8 of 9 Ingredients"; search prompt "Search recipes" (pattern record: "Search Recipes") |
| Switch dialog | one title | "Switch to Rooms" and "Switch to Area?" |
| Overview cards | `direction-g.md`: "not navigation" | Chevron, pushes the room; Air Quality cards are read-only, detail branch is dead code; a one-sensor room reads "1 sensors" |

## Motion and states

| Topic | Docs say | Code does |
|---|---|---|
| Intro mark rise | spring in first | Hidden by the header's opacity, never seen |
| Arrival | `arrivalRise` 8, `arrivalStaggerCap` 8 | Unused; call sites 16 pt and index cap 5; `MotionTokens` has two stagger caps (8, 5) and two rises (8, 16) |
| Expired session | quiet | Goes through `signOut()`: replays intro and arrival |
| Offline chip (the reconnecting chip it grew from is gone, replaced by the header arc) | moves 10 pt | `.move(edge: .top)` (`OfflineOverlay.swift`), its own height |
| Vacuum tab switch | cut | Fades 0.13, 0.17, 0.28 s (not in `motion.md`) |
| Summary sheet tabs | `motion.md` 4.4: cut | 0.15 s fade |
| Thermostat dial | numerals roll | Only the handles glide; arcs step |
| Tile press | scale | Opacity 0.8 only |
| Bed tile | idle keeps dark face | Idle is filled; a ringing alarm does not change the tile; wake-light alarms card never fills |
| Weather sheet | detents | None: large only; hourly carousel is a UIKit paging row |
| Feedback form | arc on Submit | Linear bar while sending; text Cancel and Submit |
| Inventory scan | step pages cross-fade | Plain cut; no low-stock state; two camera pills unreachable |
| Pending values | `valuesPending` honoured | Alarm panel and chips ignore it |

## Components and docs

- `entity-tile.md` contradicts itself on `.accessibilityElement(.ignore)`.
- `floating-actions.md` mentions `FilterSheet(detents:)`; the code takes `height:`.
- Only the App Icon picker uses `HassModal`.
- Humidifier editor does not use `ScheduleDateFields`.
- Live Activity per-job spec s8 (64 pt ring, 34 pt island ring, "Needs help", 28 pt value) is superseded by s8a; ring sizes are 32 and 24 pt, corner marks 24 pt (job card, island) and 40 pt (problem card).
- `PlaceholderScreen` and `KitchenGroceriesSection` are in no doc. `SecurityConfig.Tone` colours are only read by tests.
- `pages/README.md` marks Home "Scaffolded"; `direction-g.md` keeps a macOS bullet; `split-view.md` lists surfaces the code does not have.
- `AUTHORING.md` area list lacked `design`, `widgets`, `live-activity`, `watch`; they are now in use.

## Not confirmed on a device (all authors)

Duo unfolded placement of centred sheets and alerts across the hinge; the Save button look on iOS 26; iPad popover anchors for confirmation dialogs; the HA settings cover and Performance rows' exact grounds (drawn dark by inference); camera notification live video; Watch, CarPlay and StandBy scale (stand-ins); the camera viewer's fitted detent height; the arc position on the Duo rail.
