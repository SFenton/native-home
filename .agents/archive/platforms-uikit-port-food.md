# UIKit port: Food and Inventory

> **What:** the UIKit counterparts of the Food & Recipes hub, Recipes, the recipe detail, the inventory pages, the item editor and Add Item, and the pieces other lanes reuse. **Read when:** you change `apple/Sources/HassUI/UIKitPort/Features/Food/` or `Features/Inventory/`, or show an inventory row elsewhere (the Summary sheet's Expired Food tab). Port rules: [uikit-port](uikit-port.md).

## Screens

| SwiftUI | UIKit | Notes |
|---|---|---|
| `FoodEntryScreen` / `FoodHubScreen` | `UKScreens.food(_:)` → `UKFoodHubViewController` | Tiles are `UKGlassTileView`s in two `UKDynamicGridView`s; Suggested Recipes is `UKSuggestedRecipesView` (lazy pages, `UKPageIndicator`); the two columns meet at the hinge (`SplitPolicy.columnWidths`). |
| `RecipesScreen` | `UKRecipesViewController` | Compositional grid, reused `UKRecipeCardCell`s on `UKImageCardView`, `UICollectionViewDataSourcePrefetching` through `ImagePipeline`, the content gate, `UKFloatingActionBar` pinned by `UKPinnedBarViewController`, the recipe in a `UKHingedPanes` pane or a sheet. |
| `RecipeDetailSheet` / `RecipeDetailPane` | `UKRecipeDetailPresenter.presentSheet`, `UKRecipeDetailPaneViewController` | One content controller (`UKRecipeDetailViewController`) for both. |
| `InventoryScreen` | `UKInventoryViewController` | A list-layout collection of dense module cards, swipe actions, status headers. |
| `InventoryItemEditor` | `UKInventoryEditorViewController` (`.sheet` or `.pane`) | Rows are kept views (`UKFormRows.swift`), not rebuilt per change. |
| `ScanItemSheet` | `UKScanItemSheet` → `UKScanItemViewController` | `ScanCameraController` is reused as it is (AVFoundation); the feed is `CameraPreview.PreviewView`. |

Food pages push on the section stack itself (`UKFoodNavigation.push`), not through the navigator: they are not `ShellRoute`s. `UKFoodLaunch.pushRequested(on:context:)` is `FENTON_OPEN_FOOD` / `FENTON_OPEN_INVENTORY` (debug builds); the Home screen calls it once its stack is on screen.

## Reusing the inventory row

```swift
let row = UKInventoryRowView(surface: .sheet)            // `UKInventoryRow` is the same type
row.configure(item: item, model: models.model(for: .allFood), actions: UKInventoryRowActions(onEdit: { … }, onShop: { … }))
// a reused cell: row.reset() in prepareForReuse
```

- `UKInventoryRowCell` is the list cell (dense module share, hairline, selected wash) the inventory page uses.
- `UKInventoryRowActionsHost(presentation:model:context:)` with `presenter = self`, `start()` in `viewDidLoad` and `sync()` in `viewDidAppear` is `inventoryRowActions(_:model:)`: the editor sheet, the quantity prompt and the delete confirmation, driven by an `InventoryPresentation`.
- Models: `UKFoodNavigation.inventoryModels(context:injected:)` (session models, else the shared registry).

## Shared-component changes

`UKForm`: header styles `.subheadline` / `.subheadlineQuiet` (`RecipeSectionHeader`), a `.clear` row kind (no cell background, no margins), sections reload when their header or footer words change; `UKFilterSheet(onDismissed:)`; `UKSegmentedChoice.isEnabled`; `UKImageCardView.isSelectionShown`.

## Not identical

- Alert actions have no accessibility identifiers in UIKit; `UKInventoryAlerts.tag` sets `inventory.delete.confirm` on the confirm button's view after the dialog is up, best effort.
- Footers of the editor's batch groups carry no identifier (`inventory.editor.hint` / `note`): a form section footer is plain text.
- The grid and list are collection views, so XCUITest sees `collectionViews` where the SwiftUI app shows `scrollViews`.
