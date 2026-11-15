# Modal inventory

> **What:** how every modal the renderer opens is presented and how it behaves in each pose. **Read when:** adding, changing or auditing a modal, or a pose-dependent sheet rule.

Modals are authored in the publication and presented by the server-driven renderer ([architecture](../platforms/apple/architecture.md#server-driven-root)); no compiled sheet remains. Rules: [modal-sheet](modal-sheet.md), [hinge-avoidance](hinge-avoidance.md).

## The one path

| | UIKit |
|---|---|
| Presentation | `UKHassModalController` (`UIKitPort/Design/UKHassModal.swift`), a `UINavigationController` over `UKHassModalOptions`. `UKShellSheet.present` (`App/Page/UKShellSheet.swift`) is a thin wrapper over it |
| Chrome | `UKHassModal.applyChrome`: inline title, circle-X, system ground |
| Duo rule | `UKHassModalController.updateDetents` and `configureSheet`, `UKSheetPlacement.place` and `fillsHeight`, `PoseWatch` for fold, unfold and rotation under an open sheet |
| Safe area | every sheet page is a `UKPageViewController` (content inset by the side safe areas); a backdrop uses `setSheetBackdrop`; the modal hosts any non-page in `UKPageHost` |

## Rules by pose

| Pose | Height | Width / placement | Close |
|---|---|---|---|
| iPhone (portrait only) | designed: content-fitted or `.full` | window width | trailing circle-X |
| iPad | designed | form sheet 580 x 660 or page sheet, system placement (centred) | trailing circle-X |
| Duo folded (outer screen, portrait or rotated; vertical rail on one side) | **always full height from the bottom** (`DuoSheetPolicy.fillsHeight`, no band) | full width less the rail | **in the rail**, every sheet |
| Duo unfolded portrait (horizontal hinge) | designed | system sheet | trailing circle-X |
| Duo unfolded landscape (vertical hinge) | **full height** | leading half (`DuoSheetPolicy.leadingHalfWidth`, `preferredPlacement .leading`) | in the sheet bar |
| Duo partly folded | as landscape, the system keeps it off the fold | leading half | in the sheet bar |

"Designed" means `.fitted` (the height follows the content, capped at large), `.fittedToTopPage` (follows the page on top) or `.full`; the pose rows apply to all of them.

## System controllers (the sheet rules do not apply)

Alerts and confirmation dialogs (`UIAlertController` in `.alert` and `.actionSheet`), context menus (`UIMenu`), `PHPickerViewController`, `UIDocumentPickerViewController` and `UIActivityViewController`. The system places and sizes these: they ignore `DuoSheetPolicy` and keep the system's own safe-area handling. Alerts and dialogs present from the topmost controller (`(presented ?? self).present`), so they sit over a sheet, never under it.
