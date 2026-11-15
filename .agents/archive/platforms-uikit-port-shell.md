# UIKit port: the shell and the page contract

> **What:** how the UIKit app's root, sign-in, tab/flyout shell and page chrome work, and how a feature screen plugs into them. **Read when:** you port a screen under `apple/Sources/HassUI/UIKitPort/Features/` or change `UIKitPort/App/`. Port-wide rules are in [uikit-port](uikit-port.md).

## Pieces (all under `UIKitPort/`)

| SwiftUI | UIKit | Notes |
|---|---|---|
| `RootView` | `App/UKRootViewController` | Launch ground, sign-in or tabs, scene phase, probes, Spotlight/URL opens. Owns the `UKShellEnvironment`. |
| `LoginView` + `Login*` | `App/Login/UKLoginViewController`, `UKLoginParts` | Same `LoginModel`; intro, welcome back, failure card, hinge-aware column. |
| `MainTabView` | `App/Shell/UKShellViewController` | One `UITabBarController` (5 sections), flyout overlay, offline chip, route restore, Chores badge, profile name, push opens. |
| `NavigationStack(path:)` per section | `App/Shell/UKSectionNavigationController` | Reconciles its stack to `ShellNavigator` (source of truth); builds pages with `UKScreens`; presents the header sheets. |
| `NavigationFlyout` | `App/Shell/UKNavigationFlyout` | Touch shield, scrim, panel; edge swipe is on the shell. |
| `ShellHeader*`, `ProfileButton` | `App/Shell/UKShellHeaderItems`, `UKProfileButton` | Quick Links, Profile (badges, offline), reconnecting arc. |
| `pageChrome()` / `modalChrome()` | `App/Page/UKPageViewController` | The contract below. |
| `HeaderEdgeFade*`, `ScrollOffsetReader` | `App/Page/UKHeaderEdgeFade` | Gradient mask on `contentView`, KVO on the scroll view, same `HeaderEdgeFade` math and clamp. |
| `LeadingCollapsedTitle` | `App/Page/UKLeadingBarTitle`, `UKBarTitleLabel` | Leading bar title (marquee when long). |
| `HouseBackdrop` | `Common/UKBackdropView` | Reuses `HouseBackdropStore` / `BackdropRenderer`. |
| `ScrollFit` | `App/Page/UKScrollFit` | `alwaysBounceVertical = false`. |
| `HomeArrival` / `arrivalMotion` | `App/Motion/UKArrivalMotion`, `Shell/UKArrivalChrome` | |
| `OnDemandSplitStack`, `HingedPanes`, hinge | `App/Layout/UKOnDemandSplit`, `UKHingedPanes`, `UKDeviceSignals` | |
| Probes | `Diagnostics/UKProbes` | Same elements, notifications and env vars; `ScrollCostDriver` is shared. |

Shared-logic extractions: none of behaviour; `ScrollCostProbe.append(_:to:)` and `.notifications()` and `NavigationPerfProbe.notifications()` lost `private` so the port runs the same code.

## The page contract

Every screen is a `UKPageViewController` (or any `UIViewController`: the shell wraps it in `UKPageHost`, which gives it the same chrome with its view in `contentView`).

```swift
final class UKSecurityViewController: UKPageViewController {
    private let bag = UKObservationBag()     // pages already have `bag`; use it
    init(context: UKContext) { super.init(context: context, title: "Security") }

    override func viewDidLoad() {
        super.viewDidLoad()                  // backdrop, contentView, fade, header buttons, title mode
        let collection = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        install(scrollView: collection)      // pinned edge to edge in contentView; drives title, fade, scroll-to-top
        UKArrivalMotion.apply(to: someCard, shell: context.shell, kind: .rise, index: 0, bag: bag)
    }
}
```

What the base class gives a page, in one place:

- **Wallpaper**: `UKBackdropView` behind `contentView` (page surface only). Content draws on `contentView`, edge to edge; it is masked by the header fade, so scroll content reaches under the bar and fades out before it.
- **Scroll view**: `install(scrollView:)` (adds, pins, registers) or `setPageScrollView(_:)`. It becomes transparent, scroll-fit (`alwaysBounceVertical = false`; a pull-to-refresh page sets `UKScrollFit.allowsPullToRefresh`), has the iOS 26 top edge effect hidden, and drives the large title collapse, the fade and the second-tap scroll-to-top. Use `contentInsetAdjustmentBehavior = .automatic`.
- **Header**: Quick Links and Profile trailing (shown when `context.navigator != nil`), the menu button leading on a section root when `shell.chrome.showsMenuButton`, the title as large title (compact) or leading bar title (flyout/Duo rail). Set `title`; do not touch `navigationItem` bar items yourself except to add your own (they are `rightBarButtonItems` owned by the shell: add yours through `navigationItem.rightBarButtonItems` only before `viewDidLoad` ends, or put page actions in the page).
- **Tab bar / flyout / VoiceOver**: the shell hides the tab bar in flyout style and hides the whole tab content from assistive technologies while the flyout is open. A page does nothing.
- **Arrival**: wallpaper and bars arrive by themselves; call `UKArrivalMotion.apply(to:shell:kind:index:bag:)` once per element that should rise (`.rise`, staggered by `index`) or slide in (`.slideIn`). It does nothing when no arrival is under way.
- **Scroll to top**: `scrollToTop()`; the shell calls it on the second tap of the selected tab.
- **The Duo's vertical bar title (owner, 2026-10-29 and 2026-10-30; header-edge-fade R7 (6))**: wherever the system draws a vertical bar (`shell.inVerticalBar`: folded outer display, unfolded inner display in landscape, partial Book landscape) `UKPageViewController` hands the page's navigation item to `App/Page/UKFixedBarTitle`, the UIKit counterpart of `FixedMediumTitleProbe`: it mirrors `navigationItem.title` into `attributedTitle` at 24 pt semibold (`UIFontMetrics(.title2)`, capped at 30 pt, rescaled with the text size) and sets `navigationBarMinimization.minimizationBehavior = .never` (iOS 27), so the title is not taken away when the page scrolls. It gives the plain title back when the bar goes horizontal (unfolded portrait keeps the large title) and never clears an attributed title it did not write. Sheets are untouched.
- **Sheet variant**: a page whose `context.surface == .sheet` takes sheet chrome: the system grouped ground, no wallpaper, no header buttons, inline title, uncapped fade, same scroll rules. Present sheets with `presentSheet(_:width:height:)` (a stand-in for `hassSheet` until the Design lane's `UKSheet` lands); it sets the user's appearance on the sheet.

## Context

`UKContext` gains two fields for the shell: `shell: UKShellEnvironment?` (style, chrome, `inVerticalBar`, `headerEdgeCap`, `windowHinge`, `canvas`, `arrival`, `reduceMotion`, `attentionCount`, `isOffline`; all `@Observable`, read them inside a `UKObservation`) and `reconnecting: ReconnectingIndicator?`. The section stack hands each page a copy with `section` set and `surface = .page`; for a sheet use `context.with { $0.surface = .sheet }`.

## Pushing

Pushes go through the navigator, never `navigationController.pushViewController`, so route restore, Spotlight/notification opens and Quick Links work:

```swift
context.push(HomeRoute.room("kitchen"))          // ShellNavigator.push(_:in:) for the page's section
context.push(SettingsRoute.location)             // ShellNavigator.append(.settings(_), in:)
context.push(HouseholdSettingsPage.guests)
```

`UKSectionNavigationController` builds the page with `UKScreens.destination(for:context:)`, tags it with its `ShellRoute`, and writes a back swipe into the navigator. A page that is not a route (a detail inside a page) pushes on its own `UINavigationController` (see `UKOnDemandSplitViewController`, which owns its leading/trailing navigation controllers).

## Header sheets

Quick Links and Your Summary are presented by the section stack from `UKScreens.quickLinks(_:choose:)` / `yourSummary(_:)`; return a page (or a `UINavigationController`) built on a `.sheet` context. `choose` is called with the chosen route; the stack pushes it after the sheet has gone.

## Galleries

`UKGalleryChrome.context(store:caller:)` gives a gallery a context with the fixture wallpaper (`FENTON_BACKDROP_FIXTURE=1`); `UKGalleryChrome.wrap(page, context:)` hosts it under the shell's navigation bar (measures the window for the wallpaper; `FENTON_GALLERY_FLYOUT=1` adds the flyout, a port-only switch). `UKGalleryLastCallView` is the `gallery.lastCall` line. `shell-header` accepts every `FENTON_GALLERY_*` switch `ShellHeaderGallery` does.

## Stand-ins left for Design components

`UKShellPrimaryButton` (sign-in button) → `UKPrimaryButton`; `UKShellArcSpinner` → the arc spinner; `UKBarTitleLabel` → `UKTickerLabel`; `UKShellSheet` → `UKSheet`; the module fill of the sign-in fields and the notification banner → `UKModule`. Each is marked `TODO(uikit-port)`.

## Hooks for other lanes

- `UKShellHooks.locationPermission` (Settings lane): the screen the shell presents when `LocationCoordinator.isPresentingPermission` turns on; replace the closure at launch.
- `UKNotificationPermissionBannerView(push:)` (Home lane): the banner; it hides itself.
- `UKOnDemandSplitViewController`, `UKHingedPanes` (Chores, Inventory, Food, Vacuums): the on-demand split and the hinged columns.
