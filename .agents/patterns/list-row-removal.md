# List row removal

> **What:** the one way a diffable list applies a snapshot, so a row or form section that leaves slides away the way iOS does, and never on a reopen. **Read when:** a list adds, removes or re-sorts rows, or you are about to write `dataSource.apply(_:animatingDifferences:)`.

Related: [motion](motion.md) (tokens, Reduce Motion), [module-list](module-list.md) (self-drawn cards), [swipe-row](swipe-row.md), [optimistic-actions](optimistic-actions.md), [action-tiles](action-tiles.md) (the same reapply rule).

## Rule

- **Every diffable list applies through `UKListUpdater`** (`UIKitPort/Design/UKListUpdater.swift`). Never call `apply(_:animatingDifferences:)` on a data source; the guard `list-row-removal/direct-snapshot-apply` fails the PR check.
- The animation is the system's: `apply(_, animatingDifferences: true)` on a snapshot without the id. Nothing custom slides, fades or masks a row, except the Reduce Motion fade and the module card's corners below.
- The decision is pure and tested: `ListUpdateTransition.decide` (HassDesign/Motion) with `ListUpdateLedger` (tickets, reapply window).

## Rung 0 (system API first)

| Need | System API | iOS 17 / 18 / 26 | Here |
|---|---|---|---|
| Animated delete of a row or section | `UICollectionViewDiffableDataSource.apply(_:animatingDifferences:)` | same on all three (the framework diffs and animates) | used as is |
| Redraw a neighbour, no cell swap | `NSDiffableDataSourceSnapshot.reconfigureItems` | 15+ | used |
| Redraw a section header | `reloadSections` (cross-fades) | same | used; counts as a change that animates |
| Swipe action | `UIContextualAction` via `UKSwipeAction` | same | `completion(true)` only once the row is really leaving |
| Self-drawn card corners | none: `maskedCorners` is discrete | same | `UKModuleRowBackgroundView.configure(animated:)` animates `cornerRadius` (a dissolve when one radius cannot do it). Escalation, not built: a section background decoration item |
| Reduce Motion | none for diffable deletes (unverified) | same | fade the leaving cells (`quick`), then apply unanimated |

## Causes and tickets

| Cause | Meaning | Motion |
|---|---|---|
| `.reset` | search, sort, filter, page or tab switch | none |
| `.live` (default) | data changed underneath: another device, a push, a refresh | animates when on screen |
| `.person` | a ticketed change: a confirmed delete, a completed or undone chore, a failed action coming back | animates, announced, focused |

- **Never animates:** the first apply, an apply with no window, a change that only reconfigures, and anything inside the reapply window (2 s after `EntityStore.reapplyGeneration` changes: a reconnect, a cold launch from the disk snapshot). "No reload on reopen" wins over a ticket.
- **Reduce Motion:** `fade`; nothing slides.
- **Tickets** (`expectRemoval(of:title:)`, `expectInsertion(of:)`, `cancelExpectation(of:)`) expire after 10 s. Register one when the person commits, never when they merely ask; give only one id of a group the `title`. A ticketed removal says "`<title>` deleted" through `Announcer` and moves VoiceOver focus to the row that took its place (`layoutChanged`), else the list.
- Lists fed by the store pass `{ store.reapplyGeneration }` and apply inside the observation that reads it, so a reconnect applies while its window is open.

## Sequencing with the server

- **Editor (pessimistic):** the Delete row keeps its spinner for the EverShelf round trip; when the call lands the batch's rows leave in one `setSections(…, cause: .person)` and the next header reloads in the same apply. A failure, or a partial delete that leaves the batch, cancels the ticket and shows the inline error with no motion (`UKInventoryEditorViewController.deleting`). The section holds the person's drafts, so it is not removed early.
- **List (optimistic):** after the confirm, `InventoryListModel.pendingRemoval` hides the card at once; a failure restores it with `rowErrors`, as `TodoListController.remove` does. A partial quantity delete only reconfigures the row.
- **Swipe:** the row stays open while the confirmation is up (`UKInventoryRowActionsHost.swipeDelete`): confirm calls `done(true)` as the card leaves, cancel and a partial delete call `done(false)`. Rows also offer Delete as a VoiceOver action (HIG: swipe is not discoverable).

## Adopting on a new list

1. Build `UKListUpdater(surface:collectionView:dataSource:generation:)` after the data source.
2. Replace every `apply` with `updater.apply(snapshot, cause:, cornerNeighbours:)`. Pass `.reset` for a rebuilt question; leave `.live` otherwise.
3. Register a ticket where the person commits a removal; cancel it where the call fails.
4. Module-card lists: give the cell registration `animated: updater.isAnimating` and pass the rows that only became first or last as `cornerNeighbours`.
5. Redraw rows without changing which rows exist (a header's height, a selection) with `updater.redraw(where:)`, never by applying a snapshot built from the list on screen: a redraw queued behind an animation joins the update waiting there (which keeps its removals and their announcement) and applies unanimated. Use `apply` for any change of rows.
6. A form (`UKFormViewController`) is built with `holdsOnlyForRemovals: true`: it applies section changes as they come, as the system does, and only a person's removal (focus moves, a title is announced) or a Reduce Motion fade holds back what follows it. Leave the default (`false`) for a list: any animated apply holds back what follows, so a second apply cannot cut the first short. Use `true` only for a screen whose controls change its own sections while it animates.
7. Add the journeys and the unit tests below.

## Instrumentation and tests

- Each animated apply is a `LayoutChange` signpost, page `ListRowRemoval.<surface>` (`Telemetry`), measured by `tools/ios_motionperf.sh` (`LayoutChangePerformanceTests.testListRowRemovalCost`, `…ReduceMotion`).
- Unit: `ListUpdateTransitionTests`, `ListUpdateLedgerTests`, `InventoryListModelTests` (pending removal), `UKListUpdaterTests` (hosted). Journeys: `InventoryEditorJourneyTests`, `InventoryRowActionsJourneyTests`. Hosted accessibility: announcement, VoiceOver Delete, held swipe.
- Cost: one O(n) id diff per apply on the main thread; nothing runs per frame.

## Guards

- `list-row-removal/direct-snapshot-apply`: no direct `apply(…animatingDifferences:)` under `UIKitPort` except `UKListUpdater`.

## Known debt

Lists that never add or remove rows still apply directly; route one through the updater when it gains a removable row.

- `apple/Sources/HassUI/UIKitPort/Features/Food/UKRecipesViewController.swift`
- `apple/Sources/HassUI/UIKitPort/Features/Climate/UKClimateForm.swift`
- `apple/Sources/HassUI/UIKitPort/Gallery/UKMediaRemoteGalleryPage.swift`
- `apple/Sources/HassUI/UIKitPort/Features/Settings/UKAppIcon.swift`

Known limit: a module card that keeps some rounded corners and gains others (a first row that becomes the only row) cross-dissolves; one radius cannot interpolate both.
