# Modal inventory

> **What:** every modal in the app (UIKit `FentonHome`; the SwiftUI column records the screens the UIKit ones replaced, deleted 2026-11-01), how it is presented, what it holds, how it behaves in each pose, and the bugs found. **Read when:** adding, changing or auditing a modal, or a pose-dependent sheet rule. Written 2026-10-31 for the owner's two reports (content under the folded Duo's rail; sheets that do not open all the way). Rules: [modal-sheet](modal-sheet.md), [hinge-avoidance](hinge-avoidance.md).

## The one path

| | SwiftUI | UIKit |
|---|---|---|
| Presentation | `.sheet(...)` + `.hassSheet(width, height:, appearance:, fitKey:, predictedContentHeight:)` (`HassDesign/HassModal.swift`); 38 `.sheet` and 47 `hassSheet` sites | `UKHassModalController` (`UIKitPort/Design/UKHassModal.swift`), a `UINavigationController` over `UKHassModalOptions`; ~31 feature sites. `UKShellSheet.present` (`App/Page/UKShellSheet.swift`) is now a **thin wrapper over it** (the separate `UKSheetNavigationController` with its own detents, grabber, placement and pose handling is deleted) |
| Dismissal hooks | `onDismiss` of `.sheet` | `UKHassModalOptions.onDismissed` / `onClose`; a presenter hears a swipe close through `UKHassModalController.swipeDismissObserver`, never by setting the sheet's delegate ([modal-sheet](modal-sheet.md)) |
| Chrome | `HassModal` / `HassPathModal` (inline title, circle-X, system ground) | `UKHassModal.applyChrome` (same) |
| Duo rule | `HassSheetPresentation` reads `DuoSheetPolicy.fillsHeight(hinge:)`, `SheetPlacementModifier`, `LeadingHalfSizing` | `UKHassModalController.updateDetents` / `configureSheet`, `UKSheetPlacement.place` / `fillsHeight`, `PoseWatch` for fold, unfold and rotation under an open sheet |
| Safe area | SwiftUI scroll content and `List` respect the side safe areas natively; backgrounds `ignoresSafeArea()` | every sheet page is a `UKPageViewController` (content inset by the side safe areas); a backdrop uses `setSheetBackdrop`; the modal hosts any non-page in `UKPageHost` |

## Rules by pose

| Pose | Height | Width / placement | Close |
|---|---|---|---|
| iPhone (portrait only) | designed: content-fitted or `.full` | window width | trailing circle-X |
| iPad | designed | form sheet 580 x 660 or page sheet, system placement (centred) | trailing circle-X |
| Duo folded (outer screen, portrait or rotated; vertical rail on one side) | **always full height from the bottom** (`DuoSheetPolicy.fillsHeight`, no band) | full width less the rail | **in the rail**, every sheet (see bug 2) |
| Duo unfolded portrait (horizontal hinge) | designed (unchanged) | system sheet | trailing circle-X |
| Duo unfolded landscape (vertical hinge) | **full height** | leading half (`DuoSheetPolicy.leadingHalfWidth`, `preferredPlacement .leading`) | in the sheet bar |
| Duo partly folded | as landscape, the system keeps it off the fold | leading half | in the sheet bar |

"Designed" means `.fitted` (the height follows the content, capped at large), `.fittedToTopPage` (follows the page on top) or `.full`. A row below only says which; the pose columns above apply to all of them.

## Presented sheets

| Surface | Presented through (UIKit / replaced SwiftUI) | Options | Root content, safe area | Notes and bugs found | Meets standard (2026-10-31 audit) |
|---|---|---|---|---|---|
| Weather | `UKWeatherSheet.controller` / `WeatherCardContent` `.hassSheet(.page, .full, .dark)` | dark, full, page | `UKPageViewController` (sheet): gradient via `setSheetBackdrop`, scroller via `install(scrollView:)`. SwiftUI: `ScrollView`, backdrop `ignoresSafeArea` | **Bug 1**: UIKit content ran under the folded rail. Fixed structurally: the page inset (was `UKSheetSafeArea`, now removed). SwiftUI clear | Yes. Exempt from `modalChrome` by design (own photo backdrop and header fade); rules 8 and 9 hold through `setSheetBackdrop` and the page scroller. SwiftUI the same. |
| Camera viewer | `UKCameraViewer.present` / `CameraViewer` `.hassSheet(.page, .dark, predictedContentHeight:)` | dark, fitted, page, `closeStaysInBar` | `UKPageViewController` (insets itself) / SwiftUI scroll | **Bug 2**: `closeStaysInBar` disabled the vertical bar, so the folded Duo put the status bar back across the top and seated the sheet 90 pt low, in both apps. Fixed: not applied where the full-height rule holds | Yes. |
| Quick Links (header) | `UKSectionNavigationController.presentHeaderSheet` / `QuickLinksSheet` | fittedToTopPage, page | collection page; pushed Rooms / Security System | clear; full height folded and landscape | Yes. |
| Your Summary (header) | same / `YourSummarySheet` `.hassSheet(.form, .full)` | full, form | page with tab bar | clear | Yes. Tab children are plain controllers inside a page whose scroller follows the tab (not hosted); the chores fallback is a plain controller inside a tab (left). |
| Room overview, contacts, lights, media remotes, climate, humidifier, wake light, bed side, sprinklers, vacuum, custom light, room card sheets | `UKRoomOverviewSheet`, `UKMediaRemoteSheet`, `UKClimateSheet`, `UKHumidifierSheet`, `UKWakeLightSheet`, `UKBedSideSheet`, `UKSprinklerSheet`, `UKVacuumSheet`, `UKCustomLightsViewController`, `UKRoomsSheets` / their SwiftUI sheets | mostly `.full`, `.page` | frame or constraint pages, many with a bottom `modalTabBar` | `.full` already filled; `UKSheetColumnViewController` and `UKRoomsSheetPage` are page subclasses; the others are hosted by the modal. `UKVacuumSheet` scroller was `.never` inside a safe-area-pinned page: clipped at the bar, fixed | Fixed 2026-10-31 (UIKit): **vacuum** (scroller `.never` at the safe area clipped at the bar; hand-made bar inset), **bed side and humidifier** (the hero and tabs columns were not the page scroller), **wake light** (page in a page, scroller not named), **climate** (shown tab's scroller not named; `UIViewController()` fallback now `UKStatePageViewController`). SwiftUI: yes. |
| Room device sheets (fan, purifier, grill) | `UKRoomDeviceSheets.modal` / `RoomDeviceRouting` `.hassSheet(.form)` | fitted, form | list / form | fitted; filled folded; verified | Yes (the accessory wrapper is the debug gallery's last-call line). |
| Task, grocery, admin to-do forms | `UKTodoPageViewController.presentSheet` / `TodoPageView` | `TodoPageLayout.sheetHeight`, no Close (Cancel and Save) | form | form sheet on iPad; split pane where `SplitPolicy` allows | Yes. |
| Inventory editor, scan item, filters, option pickers | `UKInventoryEditor`, `UKScanItemSheet`, `UKForm` (`UKFilterSheet`, `UKOptionPickerSheet`) / SwiftUI | fitted or full, form | form | clear | Fixed 2026-10-31 (UIKit): editor and scan item were `UIViewController`s embedding a form page and hosted in `UKPageHost` (no page scroller, no fade, scan footer a stacked non-scrolling box). Now `UKFormViewController` subclasses; scan footer is `UKPagePinnedBar`; the split pane wraps the editor page (`UKInventoryEditorPaneViewController`). Filters and pickers: yes. |
| Recipe detail | `UKRecipeDetailPresenter` / `RecipeDetailView` | full, page | page | clear | Fixed 2026-10-31 (UIKit): `UKRecipeDetailViewController` is now a `UKPageViewController` (scroller installed, tab bar `UKPagePinnedBar`) used by the sheet and, as a child, by `UKRecipeDetailPaneViewController`. |
| Vacation confirm, solo trip editor | `UKVacation` / `VacationConfirmationSheet`, `SoloTripScreen` | fitted, form | form | clear | Yes. |
| Household settings sheets (Auto-Reset, presence) | `UKHouseholdSettings` / `AdminSettingsContent` | page, `.full` | form (`clearsHinge`) | clear | Yes. |
| Security system, contacts | `UKSecurityViewController` / `SecurityScreen` | fitted page; `closeStaysInBar` | alarm card page | **Bug 2** (same cause as the camera) | Yes. |
| App icon picker | `UKAppIconPickerViewController` / `AppIconPickerSheet` | fitted, form, `closeStaysInBar` | list | **Bug 2** (same cause) | Yes. |
| Feedback form | `UKFeedbackFormViewController` / `FeedbackFormSheet` | fitted, form | form | clear; pickers below | Yes. |
| Setup (notifications, time sensitive) | `UKSetupSheet` / `SetupSheet` | `SetupSheet.height` (`.full`), dark, page | custom page | clear | Yes. |
| Home Assistant settings | `UKHomeAssistantSettings` / `HomeAssistantSettingsView` | **full screen**, no detents | `WKWebView` pinned to the page edges | a `UKPageViewController` subclass: the web view sits in `contentView`, clear of the rail; full screen has no Duo placement or fill rule | Yes for rules 6 to 9 and 14; full screen, so rules 2 to 5 do not apply (the web page's own header is the title). |
| Location permission | `UKLocation` / `LocationPermissionView` | fitted page; pushed inside Your Summary | page | clear | Yes. |
| Gallery-only sheets (direction G, design lists, media remote gallery) | `UKHassModalController` | fixtures | | debug builds only | n/a (debug). |

## System controllers (the sheet rules do not apply)

Alerts and `confirmationDialog` / `UIAlertController(.alert, .actionSheet)` (sign out, discard changes, delete confirmations, bed power, photo access, icon failure), context menus (`UIMenu`, `UIContextMenuInteraction`), `PHPickerViewController` / `PhotosPicker`, `UIDocumentPickerViewController` / `fileImporter`, `UIActivityViewController` / `ShareLink` (performance export). The system places and sizes these: they ignore `DuoSheetPolicy` and keep the system's own safe-area handling. Alerts and dialogs present from the topmost controller (`(presented ?? self).present`), so they sit over a sheet, never under it.

## Page base (owner, 2026-10-31)

Every page a `UKHassModalController` shows is a `UKPageViewController` with the sheet surface. Migrated to subclass it: `UKWeatherSheetViewController`, `UKHomeAssistantSettingsViewController` and `UKHomeAssistantWebPageViewController`, `UKSheetColumnViewController` (every room device, bed, wake light, humidifier editor, climate rooms page), `UKRoomsSheetPage` (room overview, Quick Links root, room card pages), `UKFormViewController`, `UKGroupedFormController`, `UKAppIconPickerViewController`, `UKFeedbackFormViewController`; `UKCameraViewerViewController` already was. Lane A (2026-10-31) also ported the Setup steps (`UKSetupStepPageViewController`), the media remote (`UKMediaRemoteViewController`), Your Summary (`UKYourSummaryViewController`; its tabs are children of the page, whose scroller follows the tab), `UKLocationPermissionViewController`, `UKHouseholdSheetContentController` and the to-do forms (`UKTodoFormController`). A page with a bottom bar uses `UKPagePinnedBar` (Design/UKPagePinnedBar.swift) instead of `UKPinnedBarViewController`. Every other controller (Your Summary, Setup steps, vacuum, media remote, summary tabs and the rest) is hosted automatically by `UKPageHost.sheetWrapped` in the modal until it is ported; porting one is mechanical (subclass, content into `contentView`, `install(scrollView:)`).

## Modal standard audit (owner, 2026-10-31)

Checked against [the checklist](modal-sheet.md). SwiftUI: every `.sheet` site builds on `hassSheet` / `HassModal` / `HassPathModal` / `FilterSheet` (grep audit); no deviation found. UIKit deviations fixed: vacuum (header and bar), inventory editor, scan item, recipe detail (were hosted, now pages), climate fallback and tab scroller, bed, humidifier and wake light scrollers (now named to the page), VoiceOver Escape on every modal. Shared layer: `UKPagePinnedBar.follow(_:)` and hidden-bar handling, `UKSheetPinnedBarPage.setScrollers(_:)`, `UKStatePageViewController`, `UKFormViewController` subclassable, `UKHassModalController.accessibilityPerformEscape`, DEBUG `FENTON_DEBUG_SCROLL` on sheet pages.

## Open

- `UKShellSheet` has one live caller: `UKSectionNavigationController` presents any page that is not a header sheet through it (the header sheets present `UKHassModalController` directly and `UKPageViewController.presentSheet` is unused).
- Sprinklers gallery (`FENTON_GALLERY=sprinklers FENTON_GALLERY_SPRINKLER=frontYard`) aborts in `UICollectionViewListCell` self-sizing on the Duo simulator, with or without the safe-area pass: pre-existing, not investigated here.
- SwiftUI galleries do not install the hinge probe, so their sheets read as hinge-less (centred, fitted) on the Duo; the signed-in app does. Verify Duo sheet rules in the live app.
