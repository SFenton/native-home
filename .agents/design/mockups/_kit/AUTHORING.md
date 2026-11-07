# Authoring a mockup

> **What:** how to build, update and check a mockup in this atlas, and what the shared kit (`_kit/`) provides. **Read when:** you add or edit any file under `pages/`, `modals/`, `components/`, `flows/` or `proposals/`, or you need to see how a screen looks today.

A mockup is a self-contained-by-export HTML page that shows a surface **as the app is today** on iPhone, iPhone Duo and iPad, in every state, with its motion playable. It links the shared kit by relative path, so it opens offline from `file://` or any static server. Two finished examples to copy from: [pages/home/home/home.html](../pages/home/home/home.html) (a page) and [modals/security/security-system-sheet/security-system-sheet.html](../modals/security/security-system-sheet/security-system-sheet.html) (a sheet). The component index is [README.md](README.md); `_kit/gallery.html` renders every component.

## Layout of this folder

```
mockups/
  README.md          index for agents (start here)
  catalog.json       machine-readable list of every mockup ({items:[{id, kind, area, path, mockup, sources, ...}]})
  _kit/              shared kit: kit.css, kit.js, lib/, components/, gallery.html, this file
  pages/<area>/<page>/<page>.html (+ README.md)
  modals/<area>/<modal>/<modal>.html (+ README.md)
  components/<group>/<component>/<component>.html (+ README.md)
  flows/<flow>/<flow>.html          multi-screen sequences (sign-in, launch, navigation)
  proposals/<topic>/<topic>.html    owner-review proposals (propose-first); frozen after the pick, no README needed
  _reference/        raster screens imported from the owner's 2026-10-14 gallery (see its README)
```

- `<area>` is the product area: `home`, `security`, `climate`, `chores`, `settings`, `rooms`, `room-devices`, `bedroom`, `media`, `custom-lights`, `sprinklers`, `vacuums`, `food`, `inventory`, `vacation`, `cameras`, `location`, `login`, `shell`.
- A folder name is a kebab-case id and equals the file stem. The id is stable: other docs link to it.
- Every mockup folder has a `README.md` of at most 40 lines (template below). When the mockup file exists, set `mockup` in its `catalog.json` entry.

## A mockup file

```html
<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Home · page mockup</title>
<link rel="stylesheet" href="../../../_kit/kit.css">
<script src="../../../_kit/kit.js"></script>
</head><body>
<script>
Mock.mount({
  kind: 'page', id: 'home', title: 'Home', area: 'home',      // kind: page | modal | component | flow | proposal
  status: 'shipped',                   // shipped | proposed | in-flight:<branch> (only until it merges)
  summary: 'One sentence under the title.',
  source: ['apple/Sources/HassUI/Features/Home/HomeScreen.swift'],     // REQUIRED, repo-relative
  spec: ['.agents/pages/home/spec.md', '.agents/pages/home/ios.md'],  // REQUIRED
  patterns: ['status-rail', 'dynamic-grid'],                          // .agents/patterns/<n>.md
  hig: ['Tab bars', 'Toolbars'],  entities: ['weather.demo_weather_1'],  kitComponents: ['ChipRail', 'GlassTile'],
  devices: ['iphone', 'duo-folded', 'duo-unfolded-landscape', 'ipad-portrait', 'ipad-landscape'],
  states: { default: { title: '...', render: function (ctx) { return Mock.page(ctx, {...}); } }, ... },
  motion: [ ... ], transitions: [ ... ],
  a11y: [ {rule, note} | 'string' ], reviews: { date, hig: [...], swiftui: [...] },
  notes: [ ... ], changelog: [ {date, note} ],
});
</script></body></html>
```

`Mock.mount` renders, in this order: header (title, status badge, source and spec paths; they link when the page is opened from a checkout) → **warning banner** if `Mock.lint()` finds anything → controls bar (device, state, sheet appearance, page scroll, text size, Reduce Motion, Reduce Transparency, zoom, Play all) → the device stage → **States** gallery (every state for the selected device; a modal shows dark and light side by side) → **Motion** (each animation with its token, duration, source, Reduce Motion behaviour and a live Play button) → **Transitions** → **Accessibility** → **Reviews** (HIG and SwiftUI Pro, dated) → **Source map** (+ Notes) → **Change log**. The control values live in the URL hash (`#d=ipad-landscape&s=offline&a=light&t=ax5&rm=1&rt=1&z=75&sc=end`) so a view can be linked or screenshotted.

An incomplete config (missing source, spec, reviews, a11y, a state this list expects without a note saying why, a motion item without `reduce`) shows a red banner at the top of the page. `tools/mockups_check.py` repeats the static part for CI.

## The kit (`_kit/`)

- `kit.css`: every token as a CSS custom property, light and dark pairs exactly as in [direction-g](../../direction-g.md): sheet scopes `.g-dark` / `.g-light` (`--sheet-ground`, `--sheet-cell`, `--ink`, `--ink-sheet-2`, `--sep`, `--ink-action`, `--ink-error`...), `--fam-<family>-glyph|glyph-light|fill`, `--room-<room>`, `--ql-*`, `--chip-contact-*`, security modes (`--fam-sec-*`), the tinted-glass finish (`--tg-*`), `--radius-tile: 22px`, `--radius-module: 26px`, the wallpaper (dusk house stand-in, 16.8 pt blur, the documented scrim stops), glass, module and tile materials, Dynamic Type (`.ts-xxxl`, `.ts-ax5` set `--fs-*` and `--sc`), device frames. The atlas page furniture uses `--k-*` and `.k-*` (light and dark by `prefers-color-scheme`, manual Theme button). App components are `.ui-*`.
- `kit.js`: the `Mock` namespace, `Mock.h` (DOM builder), `Mock.register`, `Mock.color`; it loads `lib/` and `components/` (see below) in order, verifies the load and retries a file whose request failed (a busy static server dropping connections; works from `file://` and over http, no timers), so `Mock.components.X` is there when your next inline script runs. Builders return DOM nodes (icons return HTML strings); they never fetch.
- **Page furniture never reaches into a device.** The `.k-wrap h1, h2, h3, p, code, a, ul, li, table` rules are guarded with `:not(:where(.screen, .k-device, .k-swatch, .k-plain, .ui-root, .ui-sheet, .in-sheet, .ui-host) *)`, so a SettingsSection title, a page section header or a form header inside a frame is styled by the kit's `.ui-*` rules alone. Delete local `margin: 0` / `font` workarounds on those headings when you next touch the file.
- `lib/symbols.js`: `Mock.icon(name, {fill, size, weight, label})` and `Mock.iconEl`: about 300 inline SVG stand-ins keyed by **SF Symbol name** (the names `HassDesign/SymbolMap.swift` returns). A name not in the map draws a dashed circle and the lint banner names it: add the drawing to `symbols.js`.
- `lib/anim.js`: `Mock.anim` (below). `lib/devices.js`: `Mock.devices`, `Mock.ctx`. `lib/chrome.js`: `Mock.frame`, `Mock.page`, `Mock.sheet`, `Mock.split`, `Mock.presentDemo`. `lib/mount.js`: `Mock.mount`, `Mock.lint`, `Mock.componentConfig`.
- `components/<Name>.js`: one file per shared component (several names where they are one SwiftUI file: `NavigationGlass.js` registers the header buttons). Each calls `Mock.register(name, fn, {source, variants, states})`, so `Mock.components.<Name>(props)` returns a node and `.variants` / `.states` list `{id, label, props}` for the component mockup of the same name. Props are documented in each file's header comment and in [README.md](README.md).

### Devices and `ctx`

Mock device frames (CSS pixels equal points; the stage scales with `zoom`, never the frame):

| Key | Window (pt) | Chrome |
|---|---|---|
| `iphone` | 402 × 874 | Dynamic Island, status bar, glass floating tab bar (5 tabs, Settings last), hamburger leading, Quick Links and Profile trailing 12 pt apart, large title below the bar |
| `duo-folded` | 466 × 678 (the outer display; FestivalNativeApps measured it, S+H shares the hardware) | trailing vertical rail 83 pt: tabs, and Quick Links with the person symbol as one glass group; no hamburger; the title shares the header row |
| `duo-unfolded-portrait` | 669 × 951, hinge band horizontal at y 455.3 to 495.7 (not measured; "unfolded portrait was not run") | the iPhone chrome at regular width (horizontal bars, no vertical bar, no rail): hamburger leading, Quick Links and Profile trailing, system large title that collapses into the inline title, floating tab bar; always single page (ShellNavigationStyle.resolve with a hinge = tab bar; ShellChrome.resolve(inVerticalBar: false) = menu button) |
| `duo-unfolded-landscape` | 951 × 669, hinge band x 455.3 to 495.7 | tab bar in the trailing vertical bar 83 pt with the group, no hamburger, 24 pt title in the bar; may split on the hinge, even grid columns, chips stop 24 pt short of the fold |
| `ipad-portrait` | 834 × 1194 | flyout style, hamburger leading, QL and Profile trailing, always single page |
| `ipad-landscape` | 1194 × 834 | same; may split at the midpoint |

`render(ctx)` receives `ctx` from `Mock.ctx`: `w`, `h`, `contentW` (window minus the rail), `regular` / `compact` (size class), `rail`, `hinge` ({x, w}, vertical only), `hingeAny`, `canSplit`, `splitGeometry` ({leading, band, trailing} or null), `isPhone` / `isDuo` / `isIPad` / `folded`, `appearance` (`'dark'|'light'`: what sheets use), `ts` (`default|xxxl|ax5`), `scale`, `axSize`, `reduceMotion`, `reduceTransparency`, `stateKey`. `Mock.current` is the ctx of the render in progress (components read it for size class and AX; pass `ctx` explicitly in tests). Never branch on a device name: branch on `ctx.regular`, `ctx.hinge`, `ctx.splitGeometry`, `ctx.axSize` (AGENTS.md: the rule is geometric).

**Hinge posture (owner, 2026-10-24).** On the unfolded Duo `ctx.posture` is `'open'` (fully open, split at the midpoint of the free space) or `'part'` (slightly closed, split on the hinge); `ctx.splitAtHinge` says which. Never compute a split yourself: use `ctx.splitGeometry`, `Mock.split` (panes inside the scroll body) or `Mock.detailPane` (a full-height pane beside the page), so the Reflow and hinge section can animate it. A surface with its own split can set `reflow: { state: 'detail', open, close, posture }` in its config to pick the state the moves play on and to add a note.

State keys every **page** mockup considers (omit one only with a one-line reason in `notes` that contains the key): `default`, `loading` (first run, nothing saved), `refreshing` (saved snapshot, fresh data swapping in), `empty`, `error`, `offline`, `reconnecting`, `long-text`, `ax5` (accessibility text size). A **modal** also needs `loading`, `error`, `offline`, `ax5` and each detent (`medium`, `large`, `fitted`) and its dismiss (a Transition). Light and dark come from the Sheet appearance control and the gallery pair. `reduce-motion` is the control, not a state. Extra states are welcome (`guests`, `triggered`, `closed`).

### Building a screen

```js
Mock.page(ctx, { title, subtitle?, section: 'home', back?: 'Rooms' | true, body: [nodes], connection?: 'live'|'offline'|'reconnecting',
                 badge?: 3 (Profile), choresBadge?: 2, flyoutOpen?, floating?: FloatingActionBar node, noTabs?, scrollTop?, collapsed?: true (large title scrolled into the bar's inline title), bottomPad? })
Mock.sheet(ctx, { title, subtitle?, detent: 'fitted'|'medium'|'large', size: 'page'|'form', leading?: 'none'|'back'|'cancel'|Node, trailing?: 'close'|'confirm'|'none'|Node,
                  confirm?: {title, enabled, busy}, content: Node|Node[], tabs?: ModalTabBar node, appearance?: 'dark' (dark by design), presenter?: Mock.page node, alert?: Alert / AlertField / ConfirmationDialog node })
Mock.split(ctx, { leading: [nodes], trailing: [nodes] })     // two columns on the hinge or midpoint when allowed, else one stacked column
Mock.foldColumns(ctx, { top: [rail], leading: [sections], trailing: [sections] })  // partly folded Duo only: each section wholly on one side (section-sides.md); null elsewhere, so draw the page's own layout; at an accessibility size `top` heads the leading column (rule 11)
Mock.cover(ctx, {title, leading?, trailing?, content, presenter?, ground?, cell?, bleed?})   // FullScreenCover: no grabber, no detents, nothing scales back
Mock.presentDemo(stage, sheetOpts, {hold})                    // for a transition's play(): the page presents the sheet and it dismisses
```

`Mock.page` supplies the wallpaper, the header (hamburger or Back, the reconnecting arc, Quick Links, Profile), the large title, the scrolling body with the header edge fade, and the tab bar, rail or flyout for the device. Body children get a 16 pt margin; a node with class `ui-bleed` (ChipRail) is full width. A modal puts a **trimmed copy of the page it opens from** behind it as `presenter`. A state can override the controls: `{ override: { ts: 'ax5', appearance: 'light', device: 'iphone', reduceMotion: true } }`.

Never copy the kit's CSS into a mockup: if the kit lacks a component, add a local helper in the mockup and list it in `notes` as "promote to kit". Before you write a helper check the v2 additions: `ConfirmationDialog` / `ActionSheet`, `ContentUnavailableView`, `AlertField`, `SettingsLinkRow`, `TextToolbarButtons`, `FullScreenCover`, and about 300 symbols (do not patch `Mock.symbols` at run time any more; add the drawing to `lib/symbols.js`). Text uses `var(--fs-*)` (Dynamic Type) inside kit components; a local helper must too.

### Scroll fit

The app scrolls only when there is something to scroll ([scroll-fit](../../../patterns/scroll-fit.md), owner 2026-10-24): a page, sheet or list whose content fits its viewport is static, one that overflows scrolls, a pull-to-refresh list always bounces. A mockup does not draw that by hand: `Mock.mount({ scrollFit: true })` (or `{ indicator: true, lock: true }`) measures every vertical scroller the kit rendered (`Mock.scrollFit(el)`: `scrollHeight` against `clientHeight`) and prints `Static · fits (content 612 pt ≤ viewport 780 pt)` or `Scrolls · overflows by 148 pt` under each device and States figure; the indicator is drawn only on a scroller that scrolls. A state of a refreshable list sets `scrollFit: { always: true }`. `Mock.scrollFit.bounce(stage)` plays the drag demo for a motion item (it needs a `reduce` note). `sections: [{id, title, build()}]` adds a section (the scroll-fit mockup's device by text size matrix). Do not branch on a device to decide whether something scrolls: read the measurement.

### Motion

```js
motion: [
  { id: 'chip-colour', what: 'A status chip fills when a door opens', token: 'state 0.6 s ease-in-out (0.2 s reduced)',
    source: 'HassUI/Features/Home/StatusRail.swift', reduce: 'still cross-fades at 0.2 s', state: 'default' /* optional: stage this state first */,
    play: function (stage) { ... return Promise } },
]
```

`play(stage, stageInner)` receives the device's `.screen` element after the stage was restaged from the selected state (every Play starts from rest). Use `Mock.anim`:
`ms.{quick,state,standard,emphasized,stagger,moment}()`, `fade`, `rise` (content gate, 4 pt in 170 ms), `stateColor`, `toggleState`, `roll` (numbers, 0.2 s), `ticker` (weather label), `stagger`, `arrival` (sign-in, 0.9 s), `arc` (reconnecting arc), `sheet(host,'in'|'out')`, `push` (the system push), `slide` (the UIKit port's single-page push and pop), `zoom`, `cut`, `flyout`, `gate` (loading gate), `spinner`, `series`. Each cites its [motion.md](../../motion.md) section in `lib/anim.js` and honours Reduce Motion. Colour changes of tiles, chips and mode buttons need no JS: flip a class or a custom property and the registered colour slots cross-fade for `state`. Durations and curves come from motion.md (cite its section); never invent one.

### Transitions

`{ from: 'Home', to: 'Security System sheet', kind: 'zoom|push|sheet|cut|fade|overlay', note, state?, play }`.

### Reviews

Every mockup carries a dated review from the `apple-hig` skill and one from `swiftui-pro` (design lens: Dynamic Type, 44 pt targets, state in colour plus shape, motion with Reduce Motion, materials). A finding is `{ rule, verdict: 'pass|fix|departure', note }`; a departure cites the owner decision or direction-g paragraph that overrides the HIG. `reviews.date` is `YYYY-MM-DD`.

### Component mockups

`Mock.mount(Object.assign(Mock.componentConfig('GlassTile', { surfaces: ['page', 'sheet'] }), { id, title, spec, a11y, reviews, notes, ... }))` renders the component's `variants` and `states` as swatches on the page surface (always dark, over a gradient) and the sheet surface (follows the appearance control), with no device frame (the Device control picks the size class). Add `states` of your own for anything the lists miss.

## Rules

1. **Map the app as it is.** Read the SwiftUI source for the surface and its tests (`apple/Sources/HassUI/Features/<Area>`, `HassDesign`) and the page docs (`.agents/pages/<id>/spec.md`, `ios.md`). The mockup shows what the code draws today: real copy, real section order, real entity-driven states. Do not redesign. Where code and docs disagree, show the code and write the disagreement in `notes`.
2. **In-flight changes are marked, and unmarked on merge.** A change decided but not yet on `main` is shown as the target with `status: 'in-flight:<branch>'` and a one-line "was" note; the catalog's `inFlight` entry names the branch. The PR that merges it removes the "was", sets `shipped` and clears `inFlight` before it merges: a marker naming the PR's own branch is cleared, with status `shipped`, in that same PR, and `mockups_check.py` fails it in CI otherwise (it also fails a merged or deleted branch). A marker for another branch stays until that branch merges. Shipped behaviour is drawn once, as it is; old versions live in git.
3. **Sample data is fixture data** (names and values from the gallery fixtures, `HomeActivityFixtures`, `Gallery/`). No real addresses, camera names or tokens. The wallpaper, camera pictures, weather glyphs and SF Symbols are kit stand-ins, never the app's assets.
4. **Offline and no network.** No external fonts, scripts or images. Use the system font stack (`-apple-system`), the kit's symbol map, and the wallpaper gradient.
5. **Appearance.** Pages are always dark (on the dimmed house photo); sheets follow the system appearance except the always-dark ones (Weather, camera viewer, Login, Location permission: pass `appearance: 'dark'` to `Mock.sheet` and `alwaysDark: true` to the config). Show both for sheets.
6. **Reuse before you write.** Check `_kit/components/` ([README.md](README.md)) and [patterns](../../../patterns/README.md); one component, one implementation.
7. **Accessible HTML.** Real `<button>`, labels, `aria-label` on icon buttons, 44 pt targets, 4.5:1 text. The mockup is for people and agents to read.
8. **Check before you commit.** Serve the folder (`python3 -m http.server 8077 --directory .agents/design/mockups`), open the page in the browser pane, flip every control (device, state, appearance, text size, Reduce Motion, Reduce Transparency), press Play all, and confirm no console errors, no banner, and no clipped text at `ax5`. `python3 tools/mockups_check.py` must pass.
9. **Update the catalog and the folder README** in the same change as the mockup (`mockup` path in `catalog.json`).

## Folder README template

```
# <Title> (<kind>)
> **What:** one line. **Read when:** one line.
- Mockup: [<id>.html](<id>.html) · status · reviewed <date>
- Source: `path` ...  · Spec: `path`  · Patterns: ...
- States covered: ...   · Motion: ...   · Devices: ...
- Open notes: ...
```

## Exporting a single file

`python3 tools/mockups_inline.py <mockup.html> > out.html` inlines `kit.css`, `kit.js`, `lib/` and `components/` so the page can be shared as one artifact (the [propose-first](../../../workflow/propose-first.md) format). Proposals are exported before sharing; the atlas files stay linked.
