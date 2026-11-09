# Your Summary (the Profile button)

> **What:** the sheet behind the header Profile button: the web's Daily Report modal as a full-height sheet with four bottom tabs. **Read when:** changing `HassUI/Features/Settings/Profile`, `HassCore/Profile`, the Profile badge or the summary's chore and food rows.

Owner-approved design, 2026-10-17. Replaces the single-scroll Account sheet (2026-10-16), whose pieces are now the Profile tab.

## Web source

`ha-sfenton-react-dash@f5a7bf9`: `src/components/hass/DailyReportModal.tsx` (the modal: title, tab request, edit forms inside it), `DailyReportModalContent.tsx:26-148` (nav with badges, the three tabs, empty states, the "Whose Summary?" picker), `dailyReportModal.ts:25-100` (`dailyReportExpiredFoodControls` locks the Food page's controls to the expired filter and expiry sort; the context and badge), `src/constants/dailyReport.ts:22-86` (tabs, icons, per-resident lists, titles), `src/components/core/ModalTabNav.tsx` (the icon tab bar with count badges), `src/i18n/locales/en/core.json:22-26` (`tabItemCount`).

## Sheet

- `YourSummarySheet` (`.hassSheet(.form, height: .full)`; a tabbed sheet's height must not change with a tab, [modal-sheet](../../patterns/modal-sheet.md)). Title **Your Summary** for a household resident, **Summary** for anyone else (`ProfileSummary.title(viewer:)`). Circle-X close (`account.close`).
- Four tabs in this order (`SummaryTab`): **Profile** (person), **Overdue Chores** (`mdi:alert-circle`), **Upcoming Chores** (`mdi:clipboard-list`), **Expired Food** (`mdi:food-off-outline`, drawn as the plain fork and knife: SF Symbols has no slashed one). The sheet **opens on Profile** for everyone (owner, 2026-11-01), with its selected capsule drawn from first display.
- Tab bar: the shared `.modalTabBar(...)` (`HassUI/Common/ModalTabBar.swift`, [modal-sheet](../../patterns/modal-sheet.md)), spoken name **Summary sections**, identifier `summary.tabs`, each tab `summary.tabs.<id>` (`profile`, `overdue`, `upcoming`, `expired-food`). Compact width (iPhone, folded Duo): icons. Regular width (iPad, unfolded Duo): an icon over its title. Accessibility text sizes: a menu naming the selected tab, items "Overdue Chores, 3 items".
- **Badges** (`SummaryCounts`): Overdue Chores = the viewer's open overdue count; Expired Food = expired items on the local calendar, **0 in Vacation Mode**; Profile and Upcoming never badge (upcoming is informational). Drawn "9+" past nine. VoiceOver: "Overdue Chores, 3 items" ("1 item" for one). The header Profile button's own badge is `SummaryCounts.attention` (overdue + expired), unchanged.
- A non-resident (the web asks "Whose Summary?" and shows no tabs until someone is picked) sees **Profile and Expired Food** only: the chore tabs are personal and the app is signed in as one person, who cannot be picked; the kitchen is the household's. Recorded choice, 2026-10-17.

## Tabs

- **Profile** (`ProfileTab`): the centred `AccountHeader` (84 pt monogram, name, the server they are signed in to), **People at Home** (one row per `person.*`: a monogram in the person's colour, name, Home / Away / zone; residents take their chore colours, `ColorFamily.choreResident1` blue and `.choreResident2` magenta, a guest a neutral grey), `LocationAccountSection` on phones, Sign Out behind the existing confirmation alert ("Sign Out of Home Assistant?"). Identifiers `account.list`, `account.header`, `profile.person.<entity id>`, `account.signOut`.
- **Overdue Chores** (`SummaryChoresTab`): `todo.demo_todo_<n>` (the viewer's past-due-with-unassigned list), one `TodoListSection` ("Overdue Chores") of the Chores page's canonical `TodoItemRow` on the same module list, **with the edit button** (Choreapp task form, `DonetickTaskSheet`, the same flow) and the same swipe actions (Complete leading; Delete and Edit trailing), the same completion animation and the same delete confirmation. Empty: **No Chores Due** / "You are all caught up on chores that slipped past their due date."
- **Upcoming Chores**: `…_due_today_with_unassigned` ("Upcoming Chores") then `…_no_due_date_with_unassigned` ("No Due Date"), the same rows, each section hidden when empty. Empty (both): **No Chores Upcoming** / "There is nothing else on your schedule for the rest of today."
- **Expired Food** (`SummaryExpiredFoodTab`): the Food page's canonical `InventoryRow` for each expired card of the All Food model, soonest expiry first (the web locks the Food page's controls to the expired filter and expiry sort the same way): name, the red "Expired <date>" line with the warning glyph, the stock count above one, the add-to-Groceries cart (quantity prompt) and a chevron into the same item editor, with the same swipe actions (Add to Groceries leading, Delete trailing). `sensor.demo_ext_12` decides whether there is anything: a confirmed zero shows **No Expired Food** / "Everything in the kitchen is still within date." The models are the session's (`InventoryModels.shared(for:)`), so the tab keeps its rows between visits.
- **Vacation Mode** (`input_boolean.demo_mode_3` on): empty chore tabs read "Enjoy vacation!" under their usual title; Expired Food hides its list: **Expired Food Hidden** / "Enjoy vacation!", or **No Expired Food** / "Enjoy vacation!" when the count is a confirmed zero (an unavailable sensor stays "Hidden"). Exact web copy (`ProfileSummary.expiredFoodEmpty`, `choresEmpty`).

## Native rules

- **One component per pattern.** The summary draws no row of its own: `TodoListSection`/`TodoItemRow` ([module-list](../../patterns/module-list.md)), `InventoryRow` and `.inventoryRowActions(...)` (editor sheet, quantity prompt, delete confirmation, shared with the inventory pages), `todoDeletionDialog`, `DonetickEditTarget(item:listEntityId:)`, `TodoPageLayout.section(for:...)`. In a sheet (`tileSurface == .sheet`) the module card is the sheet's cell colour and the secondary ink follows the sheet (`TileSurface.secondaryInk`, `ModuleRowBackground`), so the same rows read in a light sheet.
- Home Assistant stays the source of truth: a check-off, edit or delete goes through the Chores page's `TodoListController` and form; food edits through the item editor. The summary holds no state of its own beyond the selected tab.
- The sheet hosts a `ChoresModel` (`.live`) when the environment has none, because the task form reads it.

## Tests

- Unit: `SummaryTabTests` (order, membership, opening tab, badges, spoken names, counts, empty and vacation copy, resident colours), `ModalTabBarTests` (badged forms, badge text, targets), `ProfileSummaryTests`.
- Hosted (macOS): `YourSummaryFlowTests` (AX-driven: tabs and badges, edit button opens the form, check-off records the fixture call, expired rows and cart prompt, empty and vacation states, guest), `GalleryLaunchMatrixTests.yourSummaryOpensOnEveryTabViewerAndState`, `NavigationHostedTests.summarySheetRendersEveryTab`.
- Journeys (iPhone, iPhone Duo, iPad): `SummaryJourneyTests` on `FENTON_GALLERY=profile` (fixtures, no house): tab switching and badges, rows with edit and swipe actions, empty and vacation states, guest, AX5 menu, reading order, 44 pt targets, accessibility audits, light sheet; `ShellJourneyTests.testSummarySheet{OpensOnSummary,ProfileTab}` reads the live house without changing it.
- Gallery: `FENTON_GALLERY=profile` with `FENTON_GALLERY_TAB`, `_VIEWER=<resident>|guest`, `_VACATION=1`, `_EMPTY=1`, `_CHORES=<n>`, `_CLEAN=1`.
