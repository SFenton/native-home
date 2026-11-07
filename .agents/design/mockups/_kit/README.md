# Mockup kit

> **What:** the shared kit behind every mockup in the atlas: tokens, device chrome, motion helpers and one builder per shared SwiftUI component. **Read when:** you need a component, a token or a helper before you write a mockup. The contract is [AUTHORING.md](AUTHORING.md); `gallery.html` renders everything below.

Call a component as `Mock.components.<Name>(props)` (returns a DOM node) or `var K = Mock.components`. Screens: `Mock.page(ctx, opts)` (`collapsed: true` = the large title scrolled into the bar), `Mock.sheet(ctx, opts)`, `Mock.split(ctx, {leading, trailing})`, `Mock.frame(ctx, node)`. Component mockups: `Mock.componentConfig('GlassTile')`. What changed in each kit version: [CHANGELOG.md](CHANGELOG.md). Paths are under `apple/Sources/`. Variants are in each file's `.variants` and `.states`.

| Component (`Mock.components.`) | SwiftUI source | Props (see the file header) | Variants and states |
|---|---|---|---|
| `GlassTile` (= `GlassTileFace`) | HassDesign/GlassTile.swift | `title subtitle symbol family fill room quickLink tint isActive isUnavailable isError kind wash progress layout titleLines accessory pending` | every family on, rooms, Quick Link, stacked; off lit error pending unavailable progress tinted navigate |
| `TileGrid` (= `DynamicGrid`) | HassDesign/DynamicGridLayout.swift | `items (props or nodes) min max gap equal span` | min 150 / max 2 / wide; even columns on a hinge |
| `ChipRail` | HassDesign/ChipRail.swift | `chips ctx frame mode` | scroll, wrap, hinge gap |
| `StatusChip` + `Mock.chips.*` | HassUI/Features/Home/StatusRail.swift | `title summary symbol family isActive tint dim pending` | lights, 5 security modes, climate gradient 50..85, AQI, occupancy, 4 contact states |
| `ModuleList`, `ModuleRow`, `ToggleRow` | HassDesign/ModuleList.swift | `rows density hasGlyphs` / `title subtitle symbol glyph chevron accessory` | thin, dense, no glyphs |
| `SettingsSection`, `InlineAlert`, `SelectableOptionRow` | HassDesign/SettingsSection.swift | `title paragraphs content` / `message severity` / `icon label description selected` | warning, error |
| `PageSectionHeader` (= `RoomSectionHeader`) | HassDesign/PageSectionHeader.swift | `title detail` | plain, detail |
| `HassModal` | HassDesign/HassModal.swift | `title subtitle leading trailing confirm content tabs fitted` | viewing, edit, pushed (use `Mock.sheet` for the detent panel) |
| `SheetCloseItem`, `SheetCancelItem`, `SheetConfirmItem` | HassDesign/HassModal.swift, SheetEditToolbar.swift | `title enabled busy` | enabled, disabled, busy |
| `FloatingActionBar` | HassDesign/FloatingActionBar.swift | `actions search ctx` | primary, secondary, search+sort+filter; reflows at AX |
| `FilterSheet`, `FilterSection`, `FilterOptionRow` | HassDesign/FilterSheet.swift | `sections canReset` | default, changed |
| `OptionPickerSheet` | HassDesign/OptionPickerSheet.swift | `options selected` | labels, swatches |
| `StatusPill`, `InfoBox` | HassDesign/StatusPill.swift, InfoBox.swift | `label value detail symbol tone` / `title message tone` | six tones; success, neutral |
| `PrimaryButton`, `SegmentedChoice`, `Toggle`, `Slider`, `SliderRow` | HassDesign/PrimaryButton.swift, HassUI/Common/SegmentedChoice.swift | `title symbol family` / `options selected style` | default, family hue, disabled; menu at AX |
| `BrightnessTile` | HassDesign/BrightnessTile.swift | `title percent dragging tint unavailable chevron` | 70, 30, coloured bulb; off, drag (60 x 32 bubble 24 pt above), unavailable, chevron |
| `ThermostatDial` | HassDesign/ThermostatDial/ThermostatDial.swift | `value target heat cool mode off unavailable dragging caption size` | single target, heat+cool range, dragging, off, unavailable |
| `ArcSpinner`, `ArcProgress` | HassDesign/ArcSpinner.swift | `size label color` / `label fraction` | page 44, compact 20, inline 16 |
| `ContentGate`, `Skeleton`, `PendingValueBar` | HassDesign/Loading/ContentGate.swift | `content phase label` | loading, spinner, ready (`Mock.anim.gate` plays it) |
| `CameraTile`, `ImageCard` | HassUI/Features/Home/CameraGrid.swift, HassDesign/ImageCard.swift | `title state scene viewer since delayed` / `title subtitle scene` | live (dot), snapshot, connecting (no pill on the tile); `viewer: true` draws the viewer badge; recipe |
| `ModalTabBar` | HassUI/Common/ModalTabBar.swift | `tabs selected ctx` | icons, titles, badges, menu at AX |
| `QuickLinksButton`, `ProfileButton`, `HamburgerButton`, `BackButton`, `CloseButton`, `RailGroup`, `NavigationGlass` | HassUI/App/Shell/ShellHeader.swift | `name badge offline` | monogram, badge 3, 9+, no name, offline cloud |
| `TabBar`, `NavigationFlyout` | HassUI/App/MainTabView.swift, Shell/NavigationFlyout.swift | `selected badges orientation` | five tabs, Chores badge (the number, never 9+), vertical rail |
| `ReconnectingArc`, `OfflineChip` | HassUI/App/Shell/ReconnectingArc.swift, OfflineChip.swift | `on` / `text` | visible, hidden; offline |
| `ScheduleDateFields`, `FormField`, `FormSection` | HassDesign/ScheduleDateFields.swift, FormSectionText.swift | `fields` / `label value kind on` / `header footer fields` | text, value, toggle, stepper |
| `Alert`, `AlertField` | HassUI/Features/Security/SecuritySystemSheet.swift | `title message buttons stacked field ctx` | destructive + cancel, one button, three stack (and every alert at AX5); with a text field |
| `AlarmPanel`, `AlarmModeButton` | HassUI/Features/Security/SecuritySystemSheet.swift | `state since surface` | five modes, arming, unavailable, hidden (privacy redaction) |
| `WeatherCard`, `WeatherCardHeader`, `WeatherGlyph` | HassUI/Features/Home/Weather/ | `condition temp hi lo glyph pending hours page narrow ctx` | short, long (ticker), unavailable, pending (`--`, static hours), 7 glyphs; 24 hours in pages with page dots and, on regular width, Previous and Next |
| `ConfirmationDialog` (= `ActionSheet`) | SwiftUI `.confirmationDialog` | `title message buttons variant anchor dark ctx` | action sheet + Cancel card (compact), popover without Cancel (regular) |
| `ContentUnavailableView` | SwiftUI `ContentUnavailableView` | `symbol title description action stack` | plain, prominent or plain action, page-level |
| `SettingsLinkRow` | HassUI/Features/Settings/SettingsScreen.swift | `title subtitle symbol appIcon chevron ctx` | glyph, long subtitle, no chevron; icon above text at AX |
| `TextToolbarButtons`, `TextToolbarButton` | HassUI/Features/Settings/Feedback/FeedbackFormSheet.swift | `cancel submit canSubmit` / `title prominent disabled` | Cancel and prominent Submit, disabled; `.leading` / `.trailing` feed `Mock.sheet` |
| `FullScreenCover` (`Mock.cover(ctx, o)`) | SwiftUI `.fullScreenCover` | `title leading trailing content presenter ground cell overlay scrollEnd bleed` | dark base-elevation page, no grabber, nothing scales back |

## Helpers worth knowing

- `Mock.icon(name, {fill, size, label})`: SF Symbol look-alike as an SVG string; `Mock.iconEl` returns a node. About 300 names (`Mock.iconNames()`); the author helpers' runtime patches were promoted in v2.
- `Mock.chips.home(opts)`, `.lights`, `.security`, `.climate`, `.contacts`, `.airQuality`, `.occupancy`, `.unavailable`: StatusChip props with the app's colour rules; `Mock.chips.fromWeb(rgb)` is ChipTint.fromWeb.
- `Mock.anim.*`: `fade rise stateColor toggleState roll ticker stagger arrival arc sheet push slide zoom cut flyout gate spinner series` (each cites motion.md).
- `Mock.scene(name)`: stand-in photo backgrounds (`front-door driveway upper-deck lower-deck recipe`). `Mock.tabs`: the five sections. `Mock.securityModes`.
- `Mock.lint(cfg)`: the problems the red banner lists. `Mock.devices`, `Mock.ctx(key, {appearance, ts, reduceMotion, reduceTransparency})`, `Mock.current`.
- CSS: tokens only through `var(--...)`: `--fam-<family>-glyph|fill`, `--room-*`, `--ql-*`, `--sheet-ground|cell`, `--ink`, `--ink-sheet-2`, `--sep`, `--ink-action`, `--g-module-thin|dense`, `--fs-*` (Dynamic Type), `--sc` (metric scale).
