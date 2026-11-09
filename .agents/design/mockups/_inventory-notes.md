# Mockup atlas inventory notes (2026-10-23)

> **What:** how `catalog.json` was built, the author batches, and where docs and code disagree. **Read when:** you pick a batch or a surface to mock up.

209 items from `main` (a28b40be): 32 pages, 71 modals, 93 components, 13 flows. Extra fields beyond the brief: `presentation` (sheet, push inside sheet, alert, confirmationDialog, fullScreenCover, system UI), `deviceNote` (iPad form vs page sheet, always-dark), `status` (shipped, placeholder, designed-not-wired), `weight`, `note`. Appearance may read `dark-page+system-sheet` for components drawn on both surfaces. Counts exceed the brief (components 93, modals 71) because every pushed level inside a sheet and every distinct alert is its own item; one-line alerts weigh 0.5.

## Batches (owner = one author; weight: page 3, flow 2, tabbed sheet 3, sheet 2, pushed level 1, dialog 0.5, component 1 to 2)

| Batch (n, weight) | Scope | Source folders |
|---|---|---|
| login-launch-flows (11, 22) | Login, location permission, launch, arrival, expiry, sign-out, offline flows | Features/Login, Features/Location, App/RootView, App/Shell/Reconnecting* |
| shell-navigation (14, 23) | Tab bar, flyout, header items, Profile button, chips, backdrop, nav flows, placeholder | App/, App/Shell, Common/HouseBackdrop |
| settings-account (15, 23.5) | Settings, HA settings cover and web page, Performance, Your Summary, sign-out, feedback, App Icon | Features/Settings, Diagnostics |
| home-weather (11, 19) | Home, status rail and chip, weather card and sheet, guests, GlassTile, tile finish, colour families | Features/Home, HassDesign/GlassTile* |
| security-climate (12, 19.5) | Security, alarm sheet, Climate, thermostat sheet and pushes, dial, hub pill | Features/Security, Features/Climate, HassDesign/ThermostatDial |
| rooms (11, 21) | Room page (generic, Kitchen, Bedroom 1), room card sheet, Quick Links (3 modals) | Features/Rooms |
| room-overview (8, 18) | Five chip overview sheets, group detail, overview and light tiles | Common/RoomOverview |
| devices-vacuums (14, 23.5) | Fan, purifier, grill, humidifier sheets; Vacuums page, sheet, area editor, report, map | Features/RoomDevices, Features/Vacuums |
| bedroom-motion (18, 24) | Wake light, bed side sheets and pushes; spinner, gate, motion tokens, edge fade, icons, images | Features/Bedroom, HassDesign/{Loading,Motion,Images} |
| media-lights-cameras (13, 23.5) | Media page and remotes, Custom Lights, brightness tile, camera tile, viewer, controls | Features/{Media,MediaRemote,CustomLights,Cameras} |
| chores (14, 22) | Chores root plus five list pages, task, grocery, admin to-do sheets, row, badge | Features/Chores |
| vacation-sprinklers (13, 23) | Vacation chooser, mode, Solo Trip and sheets; Sprinklers page, controller sheet, pushes | Features/{Vacation,Sprinklers} |
| household-forms (15, 22.5) | Four household pages, presence and auto-reset sheets; form controls, buttons, date fields, empty states | Features/Settings/Household, HassDesign forms |
| food (13, 23) | Food hub, Recipes, recipe detail, sort and filter; HassModal, tab bar, edit toolbar, pickers | Features/Food, HassDesign/{HassModal,FilterSheet,SheetEditToolbar}, Common/ModalTabBar |
| inventory (16, 23) | Inventory page, editor, scan, sort, filter, prompt; module list, grid, chips, pill, paged row | Features/Inventory, HassDesign/{ModuleList,DynamicGridLayout,ChipRail} |
| widgets-liveactivity (11, 17) | Live Activity cards, island, small family, widget, camera notification, Watch stub, system UI | FentonActivityViews, Apps/{Widgets,NotificationContent,watchOS,iOS} |

Each id's batch is its `owner`; list a batch with `jq '.items[]|select(.owner=="chores").id' catalog.json`. The brief's ~10 batches of 6 to 8 items became 16 batches of 8 to 18 items (~20 weighted units each) because the item count is twice the estimate.

## Targets

- **Watch:** `Apps/watchOS` is a stub ("S+H", "Coming soon"); one `watch-app` page marked `placeholder`. Planned scope in `watchos.md` is not built.
- **Widgets:** the extension bundle holds only the Home Live Activity (lock screen, banner, StandBy, island, `.small` family for Watch and CarPlay). No Home Screen widgets or Controls exist.
- **Other extensions:** `NotificationContent` (camera expanded view), `NotificationService` (no UI). App Shortcuts and Spotlight are system UI: record titles only.
- Debug-only `ComponentGallery` pages are test fixtures, not product surfaces, and are not catalogued.

## Formerly in flight (all on main, checked 2026-10-28)

- Flyout full-height drawer (#140), camera viewer fitted detent, reconnecting arc and weather header option D (#143) are all **on main**: draw them as shipped. (Checked 2026-10-28; this note listed them as in flight until then.)

## Docs versus code

1. **Zoom:** motion.md section 3 lists room tile, camera and recipe as zoom, `patterns/motion.md` says overview room tiles, owner 2026-10-22 says none inside sheets; `zoomSource`/`zoomDestination` have no call sites. Item `zoom-transition` is `designed-not-wired`.
2. **Camera viewer:** `split-view.md` calls it a full-screen modal and `iphone.md` a `.large` detent; code is `hassSheet(.page, .full, appearance: .dark)` (custom fitted detents, never `.medium`).
3. **Settings and Chores splits:** `split-view.md` still lists Settings as leading pane plus detail and Chores lists splitting to item detail; Settings is a tab with pushes, `OnDemandSplitStack` has no adopter, chore edits are sheets.
4. **Sign out:** Account sheet uses `.alert("Sign Out of Home Assistant?")`; HA settings uses `.confirmationDialog("Sign out of Home Assistant?")`; direction-g says an alert.
5. **Sign-in is not a modal:** `split-view.md` lists it as full-screen modal; it is a root layer under `RootView`. AUTHORING rule 5 lists Login among always-dark sheets for the same reason.
6. `pages/README.md` marks Home "Scaffolded" but Home ships chips, weather, cameras and guests.
7. `direction-g.md` still has a macOS bullet; AGENTS.md says macOS is not a target.
8. AUTHORING's area list lacks `design`, `widgets`, `live-activity`, `watch` (used here).
9. Vacuum tab `zones` and `more` are titled Rooms and Dock in the UI; docs and gallery flags use the raw names.

## In code, not in docs

`PlaceholderScreen` (no-connection fallback) and `KitchenGroceriesSection` appear in no doc under `.agents`; Quick Links tiles that show only while a visibility entity is on are not described in the rooms docs.

## Authoring cautions

- Room pages are one template for 16 rooms, inventory one for six spaces, resident chores one for two residents: mock the template and list instances in states.
- HA settings cover appearance is inherited from the shell (no `hassSheet`), so confirm dark in the simulator before drawing.
- Fixtures: `HomeActivityFixtures` names for Live Activities; gallery fixtures elsewhere. No real camera names, addresses or tokens.
