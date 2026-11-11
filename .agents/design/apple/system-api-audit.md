# System API audit (2026-10-28)

> **What:** one-time audit of the custom UI machinery against what the system and OSS already offer ([rung 0](../../workflow/change-loop.md#rung-0)). **Read when:** touching any component below, or before adding a similar one. Deployment target is iOS 17; "26" means Liquid Glass era APIs. Reasons are taken from each file's header comments; where a number is quoted it was measured by the author of that file and has not been re-measured here.

Verdicts: **keep** (the reason holds), **replace** (a follow-up, filed as a request, not done here), **keep, shrink** (keep for iOS 17, retire the part newer OSes cover). No Swift changed by this audit.

| Component | System alternative (17 / 18 / 26) | Precedent | Verdict |
|---|---|---|---|
| `TintedGlass*` (`TileFinish`, `TintedGlassGround`, `Sheen`, `Rim`, `Edge`) | 17: `Material` (`.ultraThinMaterial`) per tile. 18: same. 26: `glassEffect(_:in:)`, `GlassEffectContainer` | Apple: Applying Liquid Glass to custom views | **Keep** |
| `ScrollOffsetReader` + `UIKitScrollOffset` | 17: `GeometryReader`/preference in the content. 18: `onScrollGeometryChange`. 26: same | Apple: `onScrollGeometryChange` (WWDC24 "What's new in SwiftUI") | **Keep, shrink** |
| `HostedHorizontalScroll` | 17: `ScrollView(.horizontal)` + `scrollTargetBehavior(.viewAligned)`. 18/26: same | Apple: `scrollTargetBehavior` and `ScrollView` docs | **Keep** (measured) |
| `PagedRow` | 17: `ScrollView(.horizontal)` + `.scrollTargetBehavior(.paging)` + `scrollPosition(id:)`. 18/26: same | Apple: `scrollTargetBehavior(.paging)` | **Keep** for the long Weather page; the Recipes carousel already uses the system `ScrollView` |
| `NativePaging` (`pagesScrollViewByViewport`) | 17/18/26: `scrollTargetBehavior(.paging)` | Same | **Keep** (system API leaks on iOS 27.0), re-test when fixed |
| `SheetFit` / `SheetChrome` / `hassSheet` fitting | 17: `presentationDetents([.height(_)])` with a measured height. 18: same, plus `presentationSizing(.fitted)` for regular-width form and page sheets only. 26: same; an iPhone sheet still opens at `.large` unless a detent says otherwise | Apple: `presentationSizing`, `presentationDetents`; OSS: `SwiftUI-Introspect`-free "fit to content sheet" patterns | **Keep, shrink** |
| `ScrollFit` (`scrollsOnlyWhenNeeded`, `pullToRefresh`) | 17: `scrollBounceBehavior(.basedOnSize)`. | It is that API | **Keep** (a 2-line wrapper) |
| `PageIndicator` | 17: `TabView(.page)` page control (`indexViewStyle`), UIKit `UIPageControl`. 18/26: same | Apple: `UIPageControl`; HIG Page controls | **Keep, review** |
| `FlowLayout` | 17: `Layout` protocol (this is a `Layout`). 26: none for wrapping | Apple sample "Composing custom layouts"; OSS: `WrappingHStack`, `Flow` | **Keep** |
| `HeaderEdgeFade` (+ `HeaderBackgroundHidden`, modifier) | 17: `toolbarBackground(.hidden)` + a mask. 18: `onScrollGeometryChange`. 26: `scrollEdgeEffectStyle(.soft, for: .top)` | Apple: iOS 26 scroll edge effects | **Replace on 26** (follow-up); keep the mask for iOS 17 and 18 |
| `UKFoldColumns` + `FoldColumns` (`UIKitPort/Design`, `App/Layout`) | 17/18/26: none lays out variable-height live sections around a reserved region (`UIView.reservedRegions` and `UIHingeInteraction` are 27.1 queries). `UICollectionViewCompositionalLayout` needs reused cells; `UISplitViewController` owns navigation; two `UIStackView`s need the same hinge geometry and observer. `shouldGroupAccessibilityChildren` is used for the reading order | Home's hand-laid columns, `UKHingedPanes`, Apple HIG Designing for iPhone Duo | **Keep** (rung 0 in [section-sides](../section-sides.md#rung-0)) |

## Why each verdict

### TintedGlass family: keep
- **Reason on file** (`TileFinish.swift`): tiles are content-layer elements, and HIG Materials says not to use Liquid Glass in the content layer. A per-tile `Material` or `.blur` costs GPU time and crashed the render server (direction-g.md, performance.md). The finish is a translucent fill, one gradient and a hairline.
- **Alternative considered:** `glassEffect` is the right API for the navigation layer and the app already uses it there (`NavigationGlass`, `FloatingActionBar`, `ModalTabBar`). Not for tiles, by HIG.
- **Check on the follow-up list:** none. Re-open only if the owner changes the tile finish.

### ScrollOffsetReader: keep, shrink
- **Reason on file:** `onScrollGeometryChange` observes through the view graph; a KVO read of `contentOffset` that writes only when the rounded value changes took graph updates from 23% to 10% of main-thread samples and cut main-thread time 27% on Settings and Chores (Time Profiler, simulator).
- **Alternative:** `onScrollGeometryChange` (iOS 18) is the system answer and is still used on the non-iOS path. Below 18 there is no system scroll-offset API.
- **Shrink:** on iOS 26 `scrollEdgeEffectStyle` removes the need for the offset in the header fade (see below); the reader then serves only what still needs a number.

### HostedHorizontalScroll, PagedRow, NativePaging: keep
- **Reasons on file:** a nested SwiftUI `ScrollView` commits its offset through the page's view graph every frame (about 0.5 ms main-thread per frame on a 120-tile page, measured 2026-10-16); the hosted `UIScrollView` removes that. `PagedRow` cut the hourly weather from 1.1 s to 0.4 to 0.55 s of main-thread time over an 8 s sweep. `scrollTargetBehavior` on iOS 27.0 leaks a `ScrollEnvironmentStorage` per environment change (about 14 objects per carousel per background/foreground, heap census 2026-10-16).
- **Conditions to revisit:** each one is a measured, version-specific bug or cost. Re-measure on each new iOS release; replace with `ScrollView` + `scrollTargetBehavior(.viewAligned)` once the nested-scroll graph cost and the leak are gone. The Suggested Recipes carousel already shows the rule: where the hosted row costs the same, use the system `ScrollView`.

### SheetFit: keep, shrink
- **Reason on file:** owner decision 2026-10-16, a sheet is only as tall as its content (HIG Sheets); and 2026-10-26, it must open at its final height, so heights are measured and remembered per call site, in memory and on disk.
- **Alternative in use:** on iOS 18+ `HassModal` applies `presentationSizing(.form/.page .fitted)` with the measured ideal height, but that governs regular-width (iPad) form and page sheets only. The iPhone height stays on `presentationDetents([.height(_)])` from the measured content, because iOS 17, 18 and 26 all open an iPhone sheet at `.large` unless a detent says otherwise. There is no system "fit to content" detent for an iPhone sheet.
- **`SheetChrome`** (#185) is the learned header and bottom inset that turns measured content into a detent height (`SheetFit.wantedHeight`), and lets a precomputable sheet such as the camera viewer open at its final height on first presentation. It is bookkeeping around the detent, not a UI replacement, and stays with `SheetFit`.
- **Shrink:** raising the target to 18 retires only the iOS 17 branches around `presentationSizing`; the measured detent stays until the system offers a content-fitted detent on iPhone. Keep "open at final height" (owner, 2026-10-26).

### ScrollFit: keep
It is `scrollBounceBehavior(.basedOnSize)` plus a named `pullToRefresh` exception, so one call site stays searchable. Nothing to replace.

### PageIndicator: keep, review
- **Reason on file:** follows the card's ink and the `quickTransition` capsule motion, a full-width 44 pt strip of two tap zones, one adjustable accessibility element with "Page 2 of 5", and a "4 of 12" label past ten pages (HIG Page controls).
- **Alternative:** `UIPageControl` / `TabView(.page)` indicator. Neither follows a card's ink or the app's motion, and `TabView(.page)` is the paging container, not just the control.
- **Review:** `UIPageControl` hosted with `currentPageIndicatorTintColor` would give the system's tap, VoiceOver and Switch Control behavior for free. Spike it against the page-indicator accessibility test before deciding; do not file a replacement until the spike shows the motion can be matched.

### FlowLayout: keep
A `Layout` implementation, the system extension point. No system wrapping layout exists on 17, 18 or 26. OSS precedents (`WrappingHStack`, `Flow`) do the same job; adopting one adds a dependency for 74 lines. Keep.

### HeaderEdgeFade: replace on iOS 26 (follow-up)
- **Reason on file:** owner, 2026-10-13: headers have no translucent band; content fades as it scrolls up to the header. Ported from FestivalNativeApps' `ModalTopEdgeFade`, a mask with a 40 pt ramp driven by the scroll offset.
- **Alternative:** iOS 26's `scrollEdgeEffectStyle(.soft, for: .top)` is exactly this effect, maintained by the system, and the code already uses `scrollEdgeEffectHidden(true, for: .top)` in `HeaderBackgroundHidden` and `scrollEdgeEffectStyle(.soft, for: .bottom)` in `FloatingActionBar`. On 17 and 18 there is no system equivalent of the edge effect, but the mask itself could be built from iOS 17 `visualEffect` / `scrollTransition` (both already used, in `BrightnessTile` and `HouseBackdrop`) instead of a hand-driven mask and offset readers; check that against the scroll-offset cost in `ScrollOffsetReader` before proposing it.
- **Follow-up (propose first, it changes how the header looks):** a proposal comparing the system soft edge effect with today's 40 pt mask on iPhone, Duo and iPad. If the owner accepts, the iOS 26 branch drops the mask, `UIKitScrollOffset` and the geometry readers; 17 and 18 keep the current fallback. The R7 to R10 rules in `header-edge-fade.md` shrink with it.

## Follow-ups (filed, label `follow-up`)

1. **Header fade on iOS 26**: proposal for `scrollEdgeEffectStyle(.soft, for: .top)` (above). #192 (private app repo)
2. **Target bump to iOS 18**: retire the `#available(iOS 18)` branches in `ScrollOffsetReader`, `HeaderEdgeFadeModifier` and `HassModal`'s sizing. `SheetFit`'s measured detent stays. #193 (private app repo)
3. **Page indicator spike**: `UIPageControl` against the existing accessibility test. #194 (private app repo)
4. **Re-measure** `HostedHorizontalScroll`, `PagedRow` and `NativePaging` on each iOS release; replace when the system path matches. #195 (private app repo)
