# Scroll fit

> **What:** a vertical scroll view scrolls and bounces only when its content is taller than its viewport. **Read when:** adding a page, sheet, list or any vertical `ScrollView`, `List` or `Form`, or adding pull-to-refresh.

Owner decision, 2026-10-24: a short page, sheet or list that rubber-banded and snapped back read as "resetting to its default position". Content that fits is static; content that overflows scrolls.

## The rule

- **Geometry decides, never a device.** The check is content height against viewport height (SwiftUI `.scrollBounceBehavior(.basedOnSize, axes: .vertical)`), so one screen is static on an iPad and scrolls on an iPhone or the folded Duo, and flips at an accessibility text size or when a sheet outgrows its detent. No `idiom`, `sizeClass` or device-name branch.
- **Static means static:** no bounce, no drag response, no scroll indicator. A scroll view that overflows by even a point scrolls and bounces as normal.
- **One call per layer, never per feature** (`scrollsOnlyWhenNeeded()`, `HassDesign/ScrollFit.swift`; it is an environment value, so every scroll view below inherits it, `List` and `Form` included):

  | Layer | Where |
  |---|---|
  | Pages | `PageChrome` (`pageChrome()`, `HassUI/App/MainTabView.swift`): every tab root and pushed page |
  | Sheets | `hassSheet()` and `modalChrome()` (`HassDesign/HassModal.swift`): every presented sheet and every page pushed inside one. The root's value does **not** cross into a presented sheet (measured on iOS 26.5: a sheet under the root rule alone still bounced), so a sheet without `hassSheet()` or `HassModal` bounces |
  | Backstop | `RootView`: sign-in, the flyout, anything that skips the page chrome |

  A feature never writes `.scrollBounceBehavior`. A new scroll view needs nothing.
- **Fitted sheets.** A content-fitted sheet ([modal-sheet](modal-sheet.md), `SheetFit`) is sized to its content, so it is static until the content outgrows the large-detent cap, then scrolls.
- **Pull-to-refresh is the one exception.** `.refreshable` cannot start on a scroll view that does not bounce, so a refreshable list uses `pullToRefresh { … }` (same file): it always bounces, however short. Never a bare `.refreshable`. Today: Inventory (list and empty state), the Expired food list, Performance.
- **Horizontal scrollers are out of scope** (`axes: .vertical`): the chip rail and paged rows keep their own behavior ([status-rail](status-rail.md)).
- **Tap-the-status-bar-to-top** (`ScrollToTop.mainScrollView`) skips a scroll view that cannot scroll, which is correct: there is nothing to scroll back from.

## Tests

`Apps/iOSTests/ScrollFitTests.swift` hosts real views in a window and reads the `UIScrollView` SwiftUI builds: each case has an unmodified control that does bounce, then asserts a short `ScrollView`, `List`, `Form`, page and presented sheet do not, a tall one still scrolls, the same content flips between a roomy and a cramped window, `pullToRefresh` keeps a short list pullable and horizontal scrollers are unchanged. Run with `tools/ios_uitest.sh --quick --only iphone -only-testing:FentonHomeTests/ScrollFitTests`.

Mockup: [components/shell/scroll-fit](../design/mockups/components/shell/scroll-fit/README.md), the same content static or scrolling on all six windows and at an accessibility text size.

## Guards

Checked by `python3 tools/pattern_guard.py` against `contracts/patterns.json` (comment lines are ignored).

- `scroll-fit/no-raw-bounce-behavior`: Use scrollsOnlyWhenNeeded() / pullToRefresh from HassDesign, not a per-view scrollBounceBehavior (scroll-fit). Scans `HassUI/**/*.swift`.
