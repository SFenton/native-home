# UI duplication audit

> **What:** duplicated views, tokens and gallery fakes in `HassUI` and `HassDesign`, 2026-10-13 at `d9548ba`. **Read when:** you need the evidence behind a rule, not to learn the rule.

> **Archived 2026-10-28.** Evidence from a point-in-time audit; the rules it produced live in [patterns/README.md](../../patterns/README.md#reuse-rules), [token-economy](../../workflow/token-economy.md) and the pattern docs.

Repo audited: `apple/Sources` (HassUI ~18.7k lines in Features, HassDesign ~2.7k). Read-only. Paths below are relative to `apple/Sources/`. "Identical" means the bodies match apart from argument names, data types or copy; "different" lists exactly what differs.

Tag legend: **[chrome-owned]** = page headers, modal close button, sheet heights/detents, page chips, modal tab bar, background image. Reported, not for refactor by this thread.

## Doc-level findings (no code risk)

- D1. `.agents/patterns/README.md` lists `floating-actions.md` twice (rows at lines 12 and 24, byte-identical). Delete the second.
- D2. `.agents/patterns/README.md:10`, `.agents/workflow/swiftui-pro.md:29` and `.agents/pages/vacation/spec.md:32` name a **`HassSheet`** chrome. **No such type exists** (`grep HassSheet` over `apple/` returns nothing). The "canonical sheet chrome" is aspirational, which is why every feature re-implements it (finding 12, chrome-owned). Either create it (chrome owner) or rewrite the docs to name what exists (`FilterSheet`, `OptionPickerSheet`, `RoomDeviceSheetChrome`, `HouseholdSheet`, `SheetTabPicker`).
- D3. `.agents/patterns/entity-tile.md` says `GlassStateTile` is superseded by `GlassTile(kind: .state)`, but `GlassStateTile` is still used (finding 6).
- D4. Several patterns have no entry in the README table although a canonical component exists: `SheetTabPicker` (only in modal-sheet.md), `StatusChipButton` (status-rail.md covers it), `RemoteImage`. And there are no pattern records for the things duplicated most (notice/alert, section header, empty/error state, day picker, 0-255 colour init). Add records when consolidating.

## Ranked summary (value / risk)

| # | Finding | Lines saved | Risk | Chrome-owned |
|---|---|---|---|---|
| 1 | Notice / alert / inline-error views (9 variants, ~55 call sites) | 150-200 | Medium (contrast audits) | no |
| 2 | Section headers and section blocks (14+ variants) | 120-160 | Low-Med | no |
| 3 | Gallery fakes: last-call line, recorder shell, `set`/`update` helpers | 120-180 | Low (Debug only) | no |
| 4 | Tab pickers: `BedroomTabPicker` is `SheetTabPicker`; two raw segmented tab pickers skip the AX menu | 40-50 | Low | modal tab bar is chrome-owned, see note |
| 5 | Colour tokens: 7 copies of green (67,160,71), 4 "action blues", 6 reds, 5 light/dark `dynamic` helpers, 8 0-255 inits | 90-130 | Low | no |
| 6 | `GlassStateTile` and `RemoteGlassTile.state` duplicate `GlassTile(kind: .state)` | 25-35 | Low-Med | no |
| 7 | Empty / error / loading states re-built 4 ways | 60-90 | Low-Med | no |
| 8 | `@ScaledMetric minTileWidth` + `DynamicGridLayout` repeated 35 times | 70-100 | Low | no |
| 9 | Row-style toggle buttons (Vacuum rooms/auto-clean, checklist, todo, fan accessory) | 60-90 | Medium | no |
| 10 | Day-of-week pickers (`WeekdayPicker`, `DayPicker`) | 30-40 | Medium | no |
| 11 | Form error rows (5 copies) | 30 | Low | no |
| 12 | Sheet chrome: NavigationStack + title + Done (20+ copies) | 150-250 | Medium | **yes** |
| 13 | Sheet presentation modifiers (4 aliases + 17 inline detent/drag pairs) | 60-80 | Low | **yes** |
| 14 | Rail scroll container (`StatusRail` vs `RoomStatusRail`) | 10 | Low | **yes** (page chips) |
| 15 | Option picker: `ClimateOptionPicker` vs `OptionPickerSheet` | 0-40 | Medium | no |
| 16 | Pills: `VacuumInfoPill`, `DeviceStatusPill`, `FactTile` vs `StatusPill` | 80-100 | Medium | no |
| 17 | Time string <-> Date helpers (3 copies) and `String(format:"%02d:%02d")` | 25 | Low | no |
| 18 | `titleCase` x5 in HassCore plus 2 ad-hoc `capitalized` in HassUI | 20 | Low | no |
| 19 | Smaller: bottom CTA bar x3, `AppTile` image, `FilterSection` header re-implemented, "Hidden" redaction strings, `ClimateDescription`=`VacuumDescription`, readable-width frames | 60-100 | Low | partial |

---

## 1. Notice / alert / inline-error views

Canonical (documented): `HassDesign/InfoBox.swift:1-55` (tones success, neutral; green wash 16%) and `HassDesign/SettingsSection.swift:41-63` `InlineAlert` (orange triangle, 14% orange wash, `Warning:` label). Consumers of the canonical ones: 1 each (`Settings/Household/AdminSettingsContent.swift:48`; `Vacation/VacationComponents.swift:100`).

Re-implementations:

| View | Where | Call sites | Look |
|---|---|---|---|
| `DeviceAlert` | `RoomDevices/RoomDeviceSheetChrome.swift:100-118` | 7 | orange triangle, orange 14% wash, `Radius.chip`, `.combine` |
| `SprinklerAlert` | `Sprinklers/SprinklersScreen.swift:94-110` | 4 | same |
| `BedroomNotice` | `Bedroom/BedroomComponents.swift:59-104` | 10 | 4 tones (info/warning/error/success), title + message, wash 14%, **radius literal 12** |
| `VacuumNotice` | `Vacuums/VacuumComponents.swift:189-227` (+ `Text` convenience init :223) | 16 | tone icon, neutral `rowFill` (primary 7%) background, secondary-ink body, accent icon on neutral |
| `ClimateNotice` | `Climate/ClimateComponents.swift:107-130` | 5 | `regularMaterial` + tint stroke 0.4, tint is a parameter |
| `AwayInlineAlert` | `Vacation/VacationComponents.swift:82-98` | 7 (VacationModeScreen:45,46,163; SoloTripScreen:53,74,130,173) | **no box**, red text `AwayTint.alert`, `Error:` label |
| `Notice` | `Food/RecipeDetailView.swift:256-267` | 3 | footnote secondary line with info icon, no box |
| `TodoSheetErrorSection` and 4 ad-hoc `Label(error, systemImage: "exclamationmark.triangle.fill")` | see finding 11 | 5 | Form row |

**Identical vs different:** `DeviceAlert` and `SprinklerAlert` are the same view (the only difference is `Text(...).foregroundStyle(Ink.primary)` placed on the text vs on the Label). Both equal `InlineAlert` except for accepting a custom symbol (default same) and the `Warning:` accessibility label that `InlineAlert` adds (a behaviour difference: VoiceOver reads "Warning: ..." only for `InlineAlert`). `BedroomNotice` (warning tone) is `DeviceAlert` plus title and 3 more tones, with a different radius (12 vs 16) and spacing (icon-HStack `Spacing.m`). `VacuumNotice`, `ClimateNotice`, `AwayInlineAlert` and `Notice` are behaviourally different (different surface, different ink).

**Canonical home:** `HassDesign/InfoBox.swift` + `SettingsSection.swift`. Fold into one `NoticeBox(tone:title:message:symbol:)` (tones: info, success, warning, error) in `HassDesign/InfoBox.swift`; make `InlineAlert` a thin alias with the "Warning:" label; add `surface: .tint/.material/.row` only if the differing surfaces are really required (suggest dropping `ClimateNotice`'s stroke and `VacuumNotice`'s row fill after a contrast pass).
**Lines saved:** ~150-200 (deleting 7 views, ~190 lines, adding ~40).
**Risk:** Medium. The notices were each tuned against the AX/contrast audit on specific surfaces (`.agents` notes); keep primary ink on a tone wash (the InfoBox rule) and re-run the device journeys on iPhone, Duo and iPad. Do the `DeviceAlert`/`SprinklerAlert` -> `InlineAlert` merge first (near-zero risk, ~35 lines).
**Chrome-owned:** no.

## 2. Section headers and section blocks

Documented canonical: `HassDesign/SettingsSection.swift:22-40` (`.title3.weight(.semibold)`, Ink.primary, heading trait, paragraphs in `.subheadline` secondary, `Spacing.s`).

Page-level `title3.semibold` headings, identical type spec, each re-implemented:
- `Vacation/VacationComponents.swift:45-69` `AwaySection` (title optional, description; spacing `m`). Same as `SettingsSection` except spacing `m` vs `s`, optional title, single description string.
- `Food/FoodHubScreen.swift:114-134` `FoodSection` (title + content, spacing `m`).
- `Rooms/RoomSupport.swift:71-81` `RoomSectionHeader`.
- `Media/MediaScreen.swift:74-76` inline, `Home/GuestPresenceSection.swift:17-20` (+ footnote description at :21-24, `.foregroundStyle(.secondary)` not Ink), `Home/CameraGrid.swift:11-14`, `Chores/TodoListSection.swift:19-23`, `Chores/ChoresScreen.swift:53-57`, `Security/SecurityScreen.swift:103-106`, `Security/SecuritySystemSheet.swift:44-47`, `Sprinklers/SprinklersScreen.swift:30-34`, `Settings/Household/HouseholdSettingsPage.swift:196-200`, `CustomLights/CustomLightsScreen.swift:36-40`.
  **Different:** `GuestPresenceSection`, `CameraGrid`, `SecurityScreen`, `SecuritySystemSheet` omit `.foregroundStyle(HassTokens.Ink.primary)`. `HassTokens.Ink` documents that the default hierarchical style picks up vibrancy and fails the contrast audit on materials, so these four are latent inconsistency, not just duplication.

Sheet/tab-level `headline` headings:
- `MediaRemote/MediaRemoteControls.swift:23-33` `RemoteSectionHeader` (re-used by `ClimateSection` at `Climate/ClimateComponents.swift:63-77` and `DeviceSection` at `RoomDevices/RoomDeviceSheetChrome.swift:67-86`, so cross-feature coupling: Climate and RoomDevices depend on a MediaRemote view).
- `Vacuums/VacuumComponents.swift:52-73` `VacuumSection` (same heading + `.contain`).
- `Bedroom/BedroomComponents.swift:37-56` `BedroomSectionHeader` (headline + optional detail).
- `Food/RecipeDetailView.swift:229-243` `FactList` heading (inline).

Form-section headers (grouped List/Form, `.subheadline.semibold`, `.textCase(nil)`, primary or secondary ink):
- `HassDesign/FilterSheet.swift:98-112` `FilterSection` (canonical).
- `Food/RecipesScreen.swift:280-290` and `312-322`: **byte-identical copy of `FilterSection`'s header** inside `Section { } header:` (twice), commented "Styled like FilterSection's header". Should just be `FilterSection("Ingredient Coverage") { ... }` plus a footer (extend `FilterSection` with `footer:`).
- `Sprinklers/SprinklerControllerSheet.swift:189-201` `SprinklerHeader` (footnote semibold secondary, different).
- `Settings/HomeAssistantSettingsView.swift:146-149` `sectionHeader` (secondary ink).

Supporting copy:
- `VacuumDescription` (`VacuumComponents.swift:75-88`) and `ClimateDescription` (`ClimateComponents.swift:79-90`) have **identical** bodies (subheadline, Ink.secondary, fixedSize, leading frame).
- `DeviceSection` footnote (`RoomDeviceSheetChrome.swift:75-80`) is the footnote variant.

**Canonical home:** `HassDesign/SettingsSection.swift`. Add to it: `SectionHeading(_ title, level: .page/.group)` (title3.semibold vs headline) and `SectionDescription(_:)`. Make `SettingsSection` build on them; give it an optional `spacing` and optional `title` so `AwaySection`, `FoodSection`, `RoomSectionHeader`, `ClimateSection`, `VacuumSection`, `DeviceSection`, `BedroomSectionHeader` become one-liners or are deleted. Extend `FilterSection` with `footer`.
**Lines saved:** ~120-160. **Risk:** Low-Medium (identifier/`.contain` differences: `VacuumSection` and `DeviceSection` add `.accessibilityElement(children: .contain)`, `AwaySection`/`FoodSection` do not; preserve per call site). **Chrome-owned:** no (page headers means the navigation title/bar, not section headings).

## 3. Gallery fakes and last-call plumbing (Debug)

All under `HassUI/Features/Gallery`.

3a. **The "Last call:" text line** is written out 14 times: `BedroomGallery.swift:89` (primary ink), `InventoryGallery.swift:45`, `SecurityGallery.swift:29`, `ChoresGallery.swift:39`, `ClimateGallery.swift:38`, `MediaRemoteGallery.swift:51`, `FoodGallery.swift:80`, `HomePagesGallery.swift:150` (already a ViewModifier `galleryLastCallBanner`, `:141-160`), `RoomDevicesGallery.swift:62`, `VacationGallery.swift:27`, `RoomsGallery.swift:31,59`, `VacuumGallery.swift:46`, `HouseholdSettingsGallery.swift:57` (own struct `HouseholdGalleryLastCall`, `:53-65`). Identical text spec: `.caption.monospaced()`, `lineLimit(3)`, leading frame, id `gallery.lastCall`. **Different:** foreground is `Ink.secondary` everywhere except Bedroom (`Ink.primary`, comment "secondary rendered 2.2:1 on the iPad sheet's bar"). That is a real contrast defect everywhere else the line sits on `.bar`.
   The surrounding container is also copied: `.padding(.horizontal).padding(.vertical, 4).background(.bar)` in `BedroomGallery:81`, `VacuumGallery:36,40`, `RoomDevicesGallery:38`, `HouseholdSettingsGallery:42`, `MediaRemoteGallery:41`, `SecurityGallery:30-36`. The `FENTON_GALLERY_CLEAN` check is spelled three ways: `MediaRemoteGallery.isClean` (`MediaRemoteGallery.swift:47`, used from 9 other galleries, an odd owner), and raw `ProcessInfo...["FENTON_GALLERY_CLEAN"] != "1"` in `InventoryGallery:44`, `SecurityGallery:28`, `FoodGallery:66`.
   **Home:** one `GalleryLastCall` view + `.galleryLastCallBar(text:)` modifier + `GalleryEnvironment.isClean` in a new `Gallery/GalleryChrome.swift`. Extend the existing `galleryLastCallBanner` (`HomePagesGallery.swift:141-160`, which uses an Environment recorder) to take any `lastCall` string. ~80-100 lines.

3b. **Recorder shell.** Eight types do `lastCall = GalleryServiceRecorder.describe(...)`; `Task.sleep`; mutate `EntityStore`: `GalleryServiceRecorder` (`MediaRemoteGallery.swift:63-...`), `BedroomGalleryRecorder` (`BedroomGallery.swift:104`, conforms `HassServiceResponding`), `SecurityGalleryRecorder` (`SecurityGallery.swift:47`), `HouseholdGalleryRecorder` (`HouseholdSettingsGallery.swift:69`), `PageGalleryRecorder` (`HomePagesGallery.swift:67`, wraps GalleryServiceRecorder), `RoomDeviceGalleryRecorder`+private `Caller` (`RoomDevicesGallery.swift:174-195`), `VacationGalleryHouse` (`VacationGallery.swift:44`), `RoomsGalleryCaller` (`RoomsGallery.swift:81`, wraps two others), `ChoresFixtureService`, `FixtureRecipeService`, `EverShelfFixtureServer`.
   **Fakes defining `callServiceWithResponse` / `callServiceForResponse`:** `BedroomGallery.swift:116` (returns `accepted`+revision for wake_light, else `accepted`), `VacationGallery.swift:67` (household-away revision/state machine), `RoomsGallery.swift:94` (forwards to the Bedroom fake after recording; `try?` swallows the recorder's error), `ChoresGallery.swift:123` (donetick `get_task`). The response bodies are **different**; the shell (record call, sleep delay, optional failure) is **identical**.
   **Identical store-mutation helpers:** `set(id, state)` is written 7 times with the same body (`var entity = store.value(id) ?? EntityState(entityId: id, state: state); entity.state = state; store.apply([entity])`): `MediaRemoteGallery.swift:88` (nested), `RoomDevicesGallery.swift:203` (nested, + attributes merge), `VacationGallery.swift:102`, `BedroomGallery.swift:133` (via `update` :127), `VacuumGallery.swift:142`, `SecurityGallery.swift:85`, `HomePagesGallery.swift:85` (`update`). `ECHO delay` literal `400`/`300` ms in 7 places; `Failure` error structs in `FoodGallery.swift:103` and `SecurityGallery.swift:52`.
   **Home:** `Gallery/GalleryRecorder.swift`: `@MainActor @Observable open class GalleryRecorder { lastCall; store; delay; func record(...) async; func set(_:_:attrs:); func update(_:_:) }`; the per-gallery classes subclass or compose and keep only their `echo` switch. Add `EntityStore.setState(_:_:attributes:)` as a DEBUG extension. ~60-80 lines.
**Risk:** Low (Debug-only), but journeys read `gallery.lastCall`, so keep identifier and text format. **Chrome-owned:** no.

## 4. Tab pickers

- `Common/SheetTabPicker.swift:6-26` is canonical.
- `Bedroom/BedroomComponents.swift:236-257` `BedroomTabPicker`: **identical body** to `SheetTabPicker` (same segmented/menu switch, `minHeight: minTarget`, `labelsHidden`); only the stored-property order differs. Used at `BedSideSheet.swift:158` and `WakeLightSheet.swift:51`. Delete and call `SheetTabPicker`. 22 lines.
- `Vacuums/VacuumTabs.swift:7-25` `VacuumTabPicker`: **different** menu rule (`isAccessibilitySize || tabs.count > 4 && typeSize >= .xLarge`) and hard-coded identifier/label. Fold the rule into `SheetTabPicker` as `menuThreshold: Int?`; keep a thin wrapper if desired. ~12 lines.
- `MediaRemote/MediaRemoteControls.swift:235-243` `RemoteTabPicker` is already a thin wrapper (good model).
- Raw segmented tab pickers that **skip the accessibility menu fallback** (so they fail the pattern doc's "menu at accessibility sizes"): `RoomDevices/HumidifierSheet.swift:101-105` (id `humidifier.tabs`) and `Food/RecipeDetailView.swift:94-100` (id `recipe.tabs`). Behavioural fix as well as dedup: use `SheetTabPicker`. (Verify on AX5 before landing; the Recipe detail pane also sits in a split pane.)
- Note `WakeLightSheet.swift:318-323` "Alarm Type" is a segmented *form* picker, not a tab picker: leave.
**Risk:** Low. **Chrome-owned:** the modal tab bar is chrome-owned, so only touch pickers via `SheetTabPicker`'s API and coordinate before changing `SheetTabPicker` itself. `BedroomTabPicker` and the two raw pickers are feature code.

## 5. Colour, ink and tint tokens

`HassTokens` (`HassDesign/HassTokens.swift`) is thin. Features re-declare near-equal values:

- **Switch-green rgb(67,160,71) = (0.26,0.63,0.28)**, 8 declarations: `HassDesign/InfoBox.swift:51`, `Settings/Household/HouseholdSettingsPage.swift:110` (`Tint.settingsSwitch`), `Bedroom/BedroomComponents.swift:10`, `Vacuums/VacuumComponents.swift:10`, `Security/SecurityTiles.swift:11`, `Vacation/VacationComponents.swift:15`, `Rooms/RoomSupport.swift:50` (`.air`), `RoomDevices/RoomDeviceSheetChrome.swift:17` (as `DialTint`). Identical value. Add `HassTokens.Tint.switchOn`.
- **Action blue**: `HassTokens.Ink.action` (0,0.40,0.80 dynamic) already exists. Re-declared: `BedroomStyle.action` (`BedroomComponents.swift:14`, same value, non-dynamic), `AwayTint.action` (`VacationComponents.swift:21`, same value), `FoodStyle.action` (`Food/FoodHubScreen.swift:142`, 0.04,0.39,0.78; its comment says "Fold into a shared HassTokens action tint once other pages need one"), `VacuumStyle.primaryFill` (`VacuumComponents.swift:39`, 0,0.38,0.76 deliberately darker for badges). First three should use `Ink.action`; `primaryFill` stays but gets a token name.
- **Reds** (5-6 values for "text/fill red with 4.5:1"): `Ink.danger` (HassTokens:56), `BedroomStyle.danger` (BedroomComponents:12, filled-button red), `AwayTint.alert` (VacationComponents:25), `InventoryTone.expired` (`Inventory/InventoryRow.swift:165`), `RoomDeviceStyle.powerOff` (RoomDeviceSheetChrome:16), `HomeAssistantSettingsView.destructiveInk` (`Settings/HomeAssistantSettingsView.swift:152-163`, derived from `systemRed` with high contrast trait). Values differ by a few hundredths; consolidate into `Ink.danger` (text) and `Tint.dangerFill` (white-on-fill).
- **Light/dark `dynamic(light:dark:)` helper written 5 times**: `HassTokens.swift:62-77` (private), `Vacation/VacationComponents.swift:26-39`, `Climate/ClimateComponents.swift:21-34` (`adaptive`), `Inventory/InventoryRow.swift:172-182` (**different**: no macOS dark branch; uses light value on macOS), `Settings/HomeAssistantSettingsView.swift:155`. Make `Color.dynamic(light:dark:)` public in HassDesign and delete four copies (~45 lines).
- **0-255 / hex colour inits** (8): `Chores/ChoresScreen.swift:64`, `Settings/Household/HouseholdSettingsPage.swift:117` (`PresenceOverrideState.tint`), `Security/SecurityTiles.swift:23`, `Food/FoodHubScreen.swift:107`, `CustomLights/CustomLightsScreen.swift:182` (`Color.init(rgb:)`), `Climate/ClimateComponents.swift:56` (`Color(hex:)`), `Rooms/RoomSupport.swift:62` (`RoomColor.color`), `HassDesign/ThermostatDial/ThermostatDial.swift:260`. Add `Color(rgb255:)` / `Color(hex:)` once in HassDesign. Pure duplication, identical math.
- **Translucent fills**: `Color.primary.opacity` 0.07 (`VacuumStyle.rowFill`), 0.08 (`BedroomComponents:161,197`, `BedSideSheet:345`), 0.09 (`RemoteStyle.buttonFill`); `Color.secondary.opacity` 0.12 (`SuggestedRecipesCarousel:93`), 0.15 (`SprinklerControllerSheet:444`), 0.16 (`RecipeDetailView:365`). Visually the same role ("control fill on a sheet"); pick one `HassTokens.Fill.control`.
- **Radius literals** outside tokens: 14 (`VacuumComponents:46`, `BedroomComponents:136`, `MediaRemoteTabs:39`), 12 (`BedroomComponents:101,162`, `ScanItemSheet:386`), 8 (`TodoItemSheets:185`, `WakeLightSheet:336`). `Radius` has only 20/16/16. Add `Radius.row = 14` and `Radius.control = 12/8` or snap to `chip`.
- **`.regularMaterial` card pattern**, 19 copies of `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: HassTokens.Radius.X, style: .continuous))`: `NavigationFlyout:87`, `TodoListSection:114`, `StatusRail:90`, `VacationModeScreen:132`, `WeatherSummaryCard:33`, `BedroomComponents:32,136`, `RecipeDetailView:221,344`, `ClimateComponents:125,228`, `HumidifierSchedulesTab:27,91`, `ClimateSheet:354,376`, `HumidifierSheet:304`, `CustomLightsScreen:138`, plus HassDesign `ScheduleDateFields:85`, `ImageCard:101`. Add `View.glassCard(radius:)` in HassDesign (~3 lines saved each, ~40-50 total, and one place to adapt for iOS 26 Liquid Glass).
- Estimated savings for the colour/token family: 90-130 lines. **Risk:** Low per item; the audited contrast comments say values were tuned, so only merge values that are literally identical (green, action blue, the helper, rgb init) first. **Chrome-owned:** no.

## 6. `GlassStateTile` and `RemoteGlassTile.state` duplicate `GlassTile(kind: .state)`

- `Settings/Household/HouseholdSettingsPage.swift:224-238` `GlassStateTile` (one consumer: `HouseholdSettingsPage.swift:204`, Car). Comment says "Feature-local until the shared read-only tile lands" and `entity-tile.md` says it has landed.
- `MediaRemote/MediaRemoteTabs.swift:125-158` `RemoteGlassTile`: `ControlSemantics` -> `GlassTileKind` mapping (`TODO(orchestrator): fold .selection and .state into GlassTile.Kind` at :123). `GlassTileKind` already has `.selection` and `.state`. 17 call sites across Climate, RoomDevices, MediaRemote.
- **Different:** `GlassStateTile` passes `isUnavailable` to the face so unavailable Car tiles dim, while `GlassTile(.state)` suppresses dimming (`GlassTile.swift:82`). `GlassStateTile` sets the id with `.accessibilityIdentifier` (works because it has no accessory). `RemoteGlassTile` re-applies `.disabled(isDisabled)` outside and, for `.state`, uses `allowsHitTesting(false)` plus `accessibilityRemoveTraits(.isButton)` (the pattern doc warns `allowsHitTesting(false)` inside a Button label breaks taps; here it is on a tile with no outer Button, so safe, but the `.state` kind is the intended path).
- Also `Home/GuestPresenceSection.swift:47-52` `ControlTileGrid`, `Settings/Household/HouseholdSettingsPage.swift:121-131` `HouseholdTileGrid`, `RoomDevices/RoomDeviceSheetChrome.swift:89-96` `DeviceTileGrid`: three wrappers around `DynamicGridLayout` with a scaled min width (see finding 8).
- **Home:** `HassDesign/GlassTile.swift`. Map `ControlSemantics` to `GlassTileKind` (move `ControlSemantics`-aware init into HassUI/Common or HassCore adapter), delete `RemoteGlassTile` body logic and `GlassStateTile`.
- **Lines saved:** ~25-35. **Risk:** Low-Med: `.state` loses the dimmed look for unavailable Car tiles, so decide whether to add `dimsWhenUnavailable` or accept; re-run the `RoomDevices`/`Climate` a11y journeys (disabled-state exposure was a past bug). **Chrome-owned:** no.

## 7. Empty / error / loading states

Four hand-built "icon + title + text + retry" views that exist because `ContentUnavailableView` clips at AX sizes (each carries the same explanatory comment):
- `Inventory/InventoryScreen.swift:128-165` `emptyView` (largeTitle symbol, `title3.bold`, body secondary, "Try Again" prominent button, `FloatingActionBar.tint`).
- `Food/RecipesScreen.swift:96-120` empty block (largeTitle symbol, `title2.bold`, body secondary; **different:** `title2` vs `title3`, `Spacing.xl*2` top padding, wrapped in a `ScrollView`).
- `Food/RecipesScreen.swift:82-95` error: **still `ContentUnavailableView`** with a Retry (the very component the sibling empty-state avoided as clipping), and `Food/RecipeDetailView.swift:76-83` and `Chores/DonetickTaskSheet.swift:48` also use `ContentUnavailableView` (known AX clip in this repo).
- Loading: `ProgressView("...")....frame(maxWidth:.infinity,maxHeight:.infinity)` at `RecipesScreen:80-83`, `RecipeDetailView:73-75`, `DonetickTaskSheet:50`, plus inline `ProgressView()` at `TodoListSection:33-35`.
**Home:** `HassDesign/StateMessage.swift`: `StateMessage(symbol:title:message:actionTitle:action:)` scrollable, wrapping, AX-safe; `LoadingState(title)`. **Saved:** 60-90 lines; **fixes** three clipped `ContentUnavailableView`s at AX5. **Risk:** Low-Med (identifiers `recipes.empty`, `recipes.error`, `inventory.empty`, `recipe.error`, `recipes.retry` must be kept; Retry button's own id is currently preserved by `.contain` container, replicate). **Chrome-owned:** no.

## 8. Scaled minimum cell width on every grid

35 declarations of `@ScaledMetric(relativeTo: .subheadline|.body|.footnote) private var minTileWidth/minPillWidth/minCellWidth: CGFloat = N` immediately feeding `DynamicGridLayout(minCellWidth:maxColumns:)`. Examples: `Vacuums/VacuumsScreen:24`, `VacuumTabs:181,245,315`, `VacuumMapPanel:172,269`, `Rooms/RoomScreen:222,279`, `RoomSheets:82,125`, `QuickLinksSheet:113,198`, `RoomTiles:126`, `Security/SecurityScreen:57`, `SecuritySystemSheet:28`, `Home/ChipSheet:14`, `Media/MediaScreen:19,69`, `MediaRemote/MediaRemoteTabs:12,96,163`, `Climate/ClimateScreen:28,29`, `ClimateSheet:177,204,316,317,444`, `ClimateComponents:296`, `Sprinklers/SprinklersScreen:13,60`, `SprinklerControllerSheet:21`, `CustomLights/CustomLightsScreen:14`, `CustomLightSheet:21`, `Bedroom/BedroomComponents:148,182`, `BedSideSheet:602`, `RoomDevices/RoomDeviceSheetChrome:92`. `HouseholdTileGrid` (HouseholdSettingsPage:121-131) does the same thing with a `scale` multiplier.
Identical mechanism; only the number and the `relativeTo:` style vary. **Home:** `HassDesign/DynamicGridLayout.swift`: `ScaledGrid(minCellWidth:maxColumns:spacing:relativeTo:)` (wrapper reading `@ScaledMetric` from its init value via a small `ScaledMetric`-in-View trick), or a `scaleWithTextSize: Bool` on `DynamicGridLayout` that multiplies by the Dynamic Type scale. ~2 lines saved per site, ~70-100 total, and removes the three wrapper structs (`ControlTileGrid`, `HouseholdTileGrid`, `DeviceTileGrid`). **Risk:** Low (mechanical; `@ScaledMetric` base varies, keep per-site base). **Chrome-owned:** no.

## 9. Row-style toggle buttons with hand-rolled accessibility

Near-identical "tappable row that is a toggle" builds, each repeating row fill/min height/disabled opacity/`.isToggle`/value strings:
- `Vacuums/VacuumTabs.swift:205-239` room button and `:262-278` auto-clean room button: same `HStack`, `minHeight: minTarget + 8`, `VacuumStyle.rowFill`, `.opacity(x ? 1 : 0.45)`, `.isToggle`, value "On/Off" vs "Included/Skipped". (Same file, ~35 duplicated lines.)
- `Vacation/VacationModeScreen.swift:111-145` `VacationChecklistRow` (material fill, 0.5 opacity, "Checked/Not checked").
- `Chores/TodoListSection.swift:60-100` `TodoItemRow` toggle half.
- `Rooms/RoomDeviceRouting.swift:121-143` fan accessory (circle toggle button, On/Off/Unavailable value).
- `Settings/Household/HouseholdSettingsPage.swift:134-153` `HouseholdToggleTile` and `Climate/ClimateComponents.swift:137-156` `ClimateToggleTile` both just configure `GlassTile(kind:.toggle)`, and are fine; the list above is the hand-rolled set.
- `Security/SecurityTiles.swift:52-` `AlarmTile`/`LockTile`/`GarageDoorTile` are `GlassTile` wrappers: fine.
**Different:** surface (material vs primary 7% fill), opacity (0.45 vs 0.5), value strings. **Home:** `HassDesign/ToggleRow.swift` (`ToggleRow(title:isOn:isUnavailable:values:)`) or `.toggleRowSurface()`; or use `GlassTile(kind: .toggle)` for the vacuum rooms. **Saved:** 60-90. **Risk:** Medium (journeys depend on exact accessibility values: "Included"/"Skipped", "Checked"). **Chrome-owned:** no.

## 10. Day-of-week pickers

- `Bedroom/BedroomComponents.swift:176-208` `WeekdayPicker` (`[Weekday]` binding, `DynamicGridLayout(minWidth 52, 7 cols)`, `Capsule`, `BedroomStyle.action` selected fill, `Color.primary.opacity(0.08)` unselected, full-day accessibility label, id `<id>.<rawValue>`). Used by `WakeLightSheet:340`, `BedSideSheet:527`.
- `Sprinklers/SprinklerControllerSheet:415-452` `DayPicker` (`Set<Int>` binding, `ViewThatFits` 7-in-a-row or 4+3 grid, `Circle`, `SprinklerStyle.water`, `Color.secondary.opacity(0.15)`, `SprinklerFormat.dayNames`).
**Different:** value type, layout strategy (grid vs ViewThatFits), shape, tint. Same semantics. **Home:** `HassUI/Common/DayChips.swift` generic over `Hashable` day with `tint`, `shape`, labels. `SprinklerFormat.dayLetters` is HassCore, `Weekday.shortLabel` is HassCore; make a tiny `DayChipModel` in HassCore. **Saved:** 30-40. **Risk:** Medium (ids and the 4+3 wrap logic was tuned for folded Duo). **Chrome-owned:** no.
Also `BedroomComponents.swift:140-173` `ChoiceGrid` is a third single-choice chip grid; `SelectableOptionRow`/`FilterOptionRow`/`GlassTile(.selection)`/`ChoiceGrid` are four single-choice idioms (FilterOptionRow list row, SelectableOptionRow card, GlassTile selection tile, ChoiceGrid chip). Not a pure duplicate, but `ChoiceGrid` could be `GlassTile(kind:.selection)` or a shared chip.

## 11. Form error rows

Same `Label(error, systemImage: "exclamationmark.triangle.fill")` in a `Section` in 5 places, with 3 different styles: `Chores/TodoItemSheets.swift:297-309` `TodoSheetErrorSection` (`.multicolor`, primary ink, id `todoSheet.error`), `Chores/DonetickTaskSheet.swift:158-166` (**identical** to it with id `task.error`; could reuse the struct), `Inventory/InventoryItemEditor.swift:70-78` (red-brown `InventoryTone.expired` ink, no multicolor), `Inventory/ScanItemSheet.swift:286-292` (same as the editor), `Login/LoginView.swift:63-67` (`.red`, symbol without `.fill`), `Chores/TodoListSection.swift:24-30` (footnote, not in a Form). **Home:** `HassDesign` `FormErrorRow(_ message:, identifier:)` (or reuse `NoticeBox` from finding 1). **Saved:** ~30. **Risk:** Low. **Chrome-owned:** no.

## 12. Sheet chrome (NavigationStack + inline title + Done) [chrome-owned]

Pattern `NavigationStack { content.navigationTitle(t).inlineNavigationTitle().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } } }` appears in **identical** form at: `Home/ChipSheet.swift:17-24`, `Home/CameraGrid.swift:61-72`, `Security/SecuritySystemSheet.swift:13-18` (title supplied by `SecurityControls`), `Rooms/RoomSheets.swift:15-35`, `CustomLights/CustomLightSheet.swift:27-54`, `MediaRemote/MediaRemoteSheet.swift:47-85`, `Sprinklers/SprinklerControllerSheet.swift:29-47` (twice, :34 and :45), `Vacuums/VacuumSheet.swift:58-93`, `Bedroom/BedSideSheet.swift:60-90`, `Bedroom/WakeLightSheet.swift:43-65`, `Climate/ClimateSheet.swift:64-89` (+ `doneButton` helper, and `ClimateComponents.swift:301-327` `ClimateOptionPicker`), `Rooms/QuickLinksSheet.swift:60-72`, `RoomDevices/RoomDeviceSheetChrome.swift:36-62` (**this is the closest thing to a shared chrome**, adds subtitle and ids `device.sheet.title/done`), `Settings/Household/AdminSettingsContent.swift:95-123` (`HouseholdSheet` + `householdSheetDone`, id `household.sheet.done`), `HassDesign/OptionPickerSheet.swift:53-85`. Variants with Cancel/Apply: `FilterSheet`, `TodoItemSheets.swift` (3 sheets), `DonetickTaskSheet`, `ScanItemSheet`, `VacationModeScreen:187`, `SoloTripScreen:151`.
**Identical vs different:** the Done button + inline title is identical in ~14 places; identifiers differ (`device.sheet.done`, `household.sheet.done`, none elsewhere); `ClimateSheet` replaces the nav title with an in-content `ClimateSheetHeading` (`ClimateSheet.swift:100-156`) to avoid truncation (a documented HIG departure that other sheets would also benefit from; `RoomDeviceSheetChrome` shrinks instead with `minimumScaleFactor(0.7)`).
**Home:** create the `HassSheet` the docs already name, in `HassDesign` (`HassSheet(title:subtitle:doneIdentifier:content)`), absorbing `RoomDeviceSheetChrome`, `HouseholdSheet`, `ClimateSheetHeading` behaviour (wrapping title). **Saved:** ~150-250. **Risk:** Medium (identifiers and a11y journeys; sheet owner coordination). **Chrome-owned: yes, do not refactor here.**

## 13. Sheet presentation modifiers [chrome-owned]

- `MediaRemote/MediaRemoteSheet.swift:113-137` `mediaRemotePresentation()` = `[.large]` + drag indicator + `.page` sizing.
- `RoomDevices/RoomDeviceSheetChrome.swift:127-153` `roomDevicePresentation(.page)` = **identical body**; `.form` variant differs only in sizing.
- `Bedroom/BedroomComponents.swift:259-263` `bedroomSheetPresentation()` = alias for `mediaRemotePresentation()`.
- `Climate/ClimateSheet.swift:125-136` `climateSheetSizing()` = `.page` only; callers then add detents/indicator inline (`ClimateScreen:84-85`, `ClimateComponents:331-332`).
- Inline `.presentationDetents([.large]).presentationDragIndicator(.visible)` pairs: `Settings/Household/AdminSettingsContent.swift:165-166,238-239`, `Sprinklers/SprinklersScreen.swift:49-50`, `Bedroom/BedSideSheet.swift:238-239` (`[.medium,.large]`), `Chores/TodoPageView.swift:60`, `Security/SecurityScreen.swift:90-95` (x2, `[.medium,.large]`), `Food/RecipeDetailView.swift:22-23`, `Rooms/RoomScreen.swift:136-137`, `CustomLights/CustomLightsScreen.swift:88-95` (x2), `Rooms/QuickLinksSheet.swift:74-75`, `Home/HomeScreen.swift:36-37`, plus detents-only at `CameraGrid:73`, `TodoItemSheets:48,275`, `SoloTripScreen:192`, `InventoryItemEditor:32-33`, `ScanItemSheet:58-59`, `VacationModeScreen:210`, `RecipesScreen:329`.
- `presentationBackground` opaque grouped: `FilterSheet.swift:84`, `OptionPickerSheet.swift:88`, `ScanItemSheet.swift:75-77` (different mac fallback).
**Home:** one `.hassSheet(size: .page/.form, detents:)` modifier in `HassDesign`. **Saved:** ~60-80. **Risk:** Low. **Chrome-owned: yes.**

## 14. Rail scroll container [chrome-owned: page chips]

`Home/StatusRail.swift:6-26` `StatusRail` and `Rooms/RoomTiles.swift:8-26` `RoomStatusRail` have the same `ScrollView(.horizontal) { HStack(spacing: s) {...}.padding(.horizontal, l) }.clipped()` shell with the same Duo-clipping comment; both then draw `StatusChipButton`. Fold into `ChipRail { ... }`. ~10 lines. Chrome-owned.

## 15. Option pickers

`HassDesign/OptionPickerSheet.swift:11-109` (list rows, swatch, Done, opaque grouped bg) and `Climate/ClimateComponents.swift:285-334` `ClimateOptionPicker` (grid of `RemoteGlassTile(.selection)`, `keepsOpen`, per-option tint, heading-in-content). Both document themselves as `OptionPickerDialog presentation="sheet"`. **Different:** list vs tiles, `keepsOpen`, descriptions/icons. The pattern doc (`option-picker.md`) says "use this sheet when options need swatches or more room" and mentions neither the tile variant nor `keepsOpen`. `Vacuums/VacuumComponents.swift:232-279` `VacuumSettingRow` is a third option picker (inline `Menu` row). Recommend adding `style: .list/.tiles` and `keepsOpen` to `OptionPickerSheet` and documenting; low line savings, high consistency value. Risk Medium. Not chrome-owned.

## 16. Pills

Canonical `HassDesign/StatusPill.swift` (label/value/detail, icon, tone, `surface`). Parallel copies:
- `Vacuums/VacuumComponents.swift:91-125` `VacuumInfoPill`: same layout and a11y (label then value), `.caption` label (vs `.footnote`), `rowFill` surface, `minHeight minTarget + 8` (vs `minTarget`), tone enum `VacuumTone` (7 cases) vs `StatusPill.Tone` (6) with `.returning` blue and `.active` teal. Used from `VacuumMapPanel:180`, `VacuumTabs:327`.
- `RoomDevices/HumidifierSheet.swift:282-320` `DeviceStatusPill`: **adds** AX-size vertical layout (icon above text) and a dynamic id; different tone map (`active` = humidifier tint). Used at :253.
- `Food/RecipeDetailView.swift:197-227` `FactTile`: comment says "(web StatusPill)"; same AX-size layout switch as `DeviceStatusPill` (`AnyLayout` vstack/hstack, also `MediaRemoteControls.swift:420`, `ClimateComponents.swift:195`).
- `Climate/ClimateSheet.swift` metric tiles (`minMetricWidth` at :317) and `Sprinklers/SprinklersScreen.swift:56-84` controller cards use `StatusPill` correctly.
**Home:** extend `StatusPill` with `Surface.row`, a caption/footnote knob, `minHeight`, and an `adaptsLayoutAtAccessibilitySizes` (the AX icon-above-text behaviour is the better one and should be default), plus a `Tone` init from `VacuumTone`/`InfoItem.Tone`. **Saved:** 80-100. **Risk:** Medium (three audited layouts). Not chrome-owned.

## 17. Time/date string helpers

- `Bedroom/BedroomComponents.swift:211-235` `ClockTimeField.date/string` (`"HH:MM"` <-> `Date`, default hour 7).
- `RoomDevices/HumidifierSchedulesTab.swift:247-262` `ActivityTime.date(from:)/string(from:)` (same, but normalises via `HumidifierSchedule.normalizedTime`, fallback `00:00`, injectable calendar/now).
- `Chores/DonetickTaskSheet.swift:257-` `DonetickDueBinding.formatter` (POSIX `DateFormatter` for `yyyy-MM-dd`/`HH:mm`).
- `String(format: "%02d:%02d", ...)` at `BedroomComponents:233` and `HumidifierSchedulesTab:260`; `Vacation/VacationComponents.swift:128-` `ScheduleDateField` convenience init is a fourth approach (`WallClock`).
**Different:** fallbacks differ (07:00 vs 00:00). **Home:** `HassCore` (`ClockTime` already exists at `HassCore/Bedroom/SleepypodSchedule.swift:130`): add `ClockTime.date(from:)` / `string(from:)`; one `Binding<Date>.clockString($String)` helper. ~25 lines. Risk Low.

## 18. `titleCase` helpers

HassCore (out of the scoped folders, but consumed by HassUI): `Bedroom/BedSideController.swift:750` (no empty handling), `Vacuums/VacuumStatus.swift:389`, `Climate/ClimateLogic.swift:12`, `MediaRemote/MediaRemoteLogic.swift:15` (the last two **identical**, `nil`->"Unknown"), `RoomDevices/RoomDeviceCommands.swift:106` (also splits on space). In HassUI: `Home/ChipSheet.swift:44` (`replacingOccurrences("_"," ").capitalized`, **different** result: lowercases the rest), `Home/WeatherSummaryCard.swift:70` (`.capitalized`). Put one `String.titleCasedState` in HassCore; delete five bodies. ~20 lines.

## 19. Smaller items

- **Bottom primary-action bar**: `Sprinklers/SprinklerControllerSheet.swift:236-253` and `:351-369` (identical shell: `safeAreaInset(.bottom)` prominent large button, `Spacing.l` padding, `.background(.bar)`, only label/id/action differ), and the footer in `Inventory/ScanItemSheet.swift:141-176` (`footerButton`). The page-level floating bar is canonical (`HassDesign/FloatingActionBar.swift`), but sheet-bottom CTAs are a separate unrecorded pattern. Add `View.bottomActionBar(...)` to HassDesign. ~25 lines.
- **`AppTile` image** (`MediaRemote/MediaRemoteTabs.swift:33-92`) uses raw `AsyncImage(...).scaledToFill()` inside a Button, with the placeholder/fallback logic hand-rolled. `RemoteImage` (`HassDesign/ImageCard.swift:111-175`) exists and `image-card.md` says to apply `allowsHitTesting(false)` to any fill-scaled image; `AppTile` does not. Candidate for `RemoteImage` (behaviour: AppTile has no failure fallback, a bad URL shows nothing but the fallback view; check `.clipShape` already contains it). `CameraSnapshotView` (`Home/CameraGrid.swift:79-109`) is a second fill-scaled image (it is bounded by `Color.clear.aspectRatio` + overlay + clip) without the hit-testing rule. Also `SuggestedRecipesCarousel.swift:91-95` and `OtherLightSwatch`: placeholder squares.
- **`ScreenshotPrivacy` "Hidden"** inline ternaries x6: `Security/SecuritySystemSheet.swift:37,43`, `Rooms/QuickLinksSheet.swift:148,184`, `Rooms/RoomTiles.swift:36`, `Home/StatusRail.swift:36`, `Rooms/RoomSheets.swift:133`. Add `ScreenshotPrivacy.redact(_ text: String, when: Bool = true)`.
- **Readable-width frames**: `.frame(maxWidth: N).frame(maxWidth: .infinity)` with N in {560, 640, 720, 760, 840, 960} at 21 sites (`MediaRemoteSheet:71`, `WakeLightSheet:58,302`, `BedSideSheet:78,490,556`, `VacuumSheet:79`, `ClimateSheet:147,164`, `QuickLinksSheet:64`, `HouseholdSettingsPage:98`, `AirPurifierSheet:28,97`, `HumidifierSheet:80`, `VacuumAreaEditor:45`, `CustomLightsScreen:71`, `HumidifierSchedulesTab:183`, `ClimateScreen:112`, `BathroomFanSheet:28`, `RoomSheets:27`, `CustomLightSheet:45`). Add `.readableColumn(_ width: ReadableWidth)` to HassDesign. ~20 lines; mixed values are probably intentional per sheet, so name 2-3 widths. (Sheet widths are arguably chrome-adjacent: tag partially chrome-owned.)
- **Stepper / wrapping label**: `Sprinklers/SprinklerControllerSheet.swift:379-413` `WrappingRowLabel`, `StepperRow` are generally useful but feature-local; `Inventory/InventoryItemEditor.swift:205`, `RoomDevices/HumidifierSheet.swift:221` use bare `Stepper` with their own labels. Candidate for HassDesign if reused. Low value.
- **`PercentSliderRow`** (`Food/RecipesScreen.swift:334-377`) and `RemoteControlsTab`'s volume/brightness sliders (`MediaRemoteControls.swift:371`, `MediaRemoteTabs.swift:284`) each build a labelled adjustable slider with VoiceOver step logic; `SliderDraft` (`MediaRemoteControls.swift:249`) is the shared commit-on-release piece. Different semantics (step 5 vs 1). Leave unless a third need appears.
- **Round icon button**: `MediaRemote/MediaRemoteControls.swift:36-100` (`RoundButtonStyle`, `RemoteIconButton`), `Climate/ClimateComponents.swift:257-283` `HubPickerButton`, `Rooms/RoomDeviceRouting.swift:121-143` accessory, `Inventory/InventoryRow.swift` `iconButton`: all 44 pt material/fill circles/capsules with label+value. Not identical; candidate for a `HassIconButton`. Low priority.
- **Status chip** inert/active face (`Home/StatusRail.swift:56-92`) is correctly shared by Home and Rooms: good model.

## What is already well-factored (do not touch)

`GlassTile`/`GlassTileFace`/`BrightnessTile`, `DynamicGridLayout`, `FilterSheet`/`FilterOptionRow`, `OptionPickerSheet`, `ImageCard` (3 consumers), `StatusChipButton`, `SheetTabPicker` (Climate + Remote), `StatusPill` (Sprinklers), `InfoBox` (Solo Trip), `SettingsSection` (Household), `SelectableOptionRow`, `ScheduleDateField`.
