# List row removal

> **What:** the one way a diffable list applies a snapshot, so a row or form section that leaves slides away the way iOS does, and never on a reopen. **Read when:** a list adds, removes or re-sorts rows, or you are about to write `dataSource.apply(_:animatingDifferences:)`.

Related: [motion](motion.md) (tokens, Reduce Motion), [module-list](module-list.md) (self-drawn cards), [swipe-row](swipe-row.md), [optimistic-actions](optimistic-actions.md), [action-tiles](action-tiles.md) (the same reapply rule).

## Rule

- **Every diffable list applies through `UKListUpdater`** (`UIKitPort/Design/UKListUpdater.swift`). Never call `apply(_:animatingDifferences:)` on a data source; the guard `list-row-removal/direct-snapshot-apply` fails the PR check.
- The animation is the system's: `apply(_, animatingDifferences: true)` on a snapshot without the id. Nothing custom slides, fades or masks a row, except the Reduce Motion fade and the module card's corners below.
- The decision is pure and tested: `ListUpdateTransition.decide` (HassDesign/Motion) with `ListUpdateLedger` (tickets, reapply window).
- Motion goes through `UKMotion` (the corner radius, the Reduce Motion fade), so Reduce Motion is honoured in one place and `tools/lint_motion.sh` stays clean.

## Consumers

| List | Owner | Cause it passes |
|---|---|---|
| A server-drawn record collection that is its page's scroller (Chores, Food inventory, recipes) | `UKRecordCollectionController` (`apply(_:changed:signatures:surface:cause:)`) | `.reset` when the definition, the surface, the search text, the sort or the filter changed; else `.live` |
| A record collection inside a page's column (a Summary tab) | `UKServerUIRecordList` (`apply(keys:rows:changed:surface:density:cause:)`) | the same, from `UKServerUICollectionView.listCause` |
| Forms and settings | `UKFormViewController.setSections(_:animated:cause:)` (built with `holdsOnlyForRemovals: true`), `UKSettingsListDriver`, `UKSprinklerListController` | `.live` when `animated`, else `.reset` |

`UKServerUICollectionSource.listQuestion` carries what a source is asked beyond its search text (Inventory: sort, direction, filter, phase). A source with no sort or filter keeps the default.

## Rung 0 (system API first)

| Need | System API | iOS 17 / 18 / 26 | Here |
|---|---|---|---|
| Animated delete of a row or section | `UICollectionViewDiffableDataSource.apply(_:animatingDifferences:)` | same on all three (the framework diffs and animates) | used as is |
| Redraw a neighbour, no cell swap | `NSDiffableDataSourceSnapshot.reconfigureItems` | 15+ | used |
| Redraw a section header | `reloadSections` (cross-fades) | same | used; counts as a change that animates |
| Swipe action | `UIContextualAction` via `UKSwipeAction` | same | `completion(true)` only once the row is really leaving; the row stays open until the answer |
| Self-drawn card corners | none: `maskedCorners` is discrete | same | `UKModuleRowBackgroundView.configure(animated:)` animates `cornerRadius` (a dissolve when one radius cannot do it). Escalation, not built: a section background decoration item |
| Reduce Motion | none for diffable deletes (unverified) | same | fade the leaving cells (`quick`), then apply unanimated |

## Causes and tickets

| Cause | Meaning | Motion |
|---|---|---|
| `.reset` | search, sort, filter, page or tab switch, a rebuilt definition | none |
| `.live` (default) | data changed underneath: another device, a push, a refresh | animates when on screen |
| `.person` | a ticketed change: a confirmed delete, a completed or undone chore, a failed action coming back | animates, announced, focused |

- **Never animates:** the first apply, an apply with no window, a change that only reconfigures, and anything inside the reapply window (2 s after `EntityStore.reapplyGeneration` changes: a reconnect, a cold launch from the disk snapshot). "No reload on reopen" wins over a ticket.
- **Reduce Motion:** `fade`; nothing slides.
- **Tickets** (`expectRemoval(of:title:)`, `expectInsertion(of:)`, `cancelExpectation(of:)`) expire after 10 s. Register one when the person commits, never when they merely ask; give only one id of a group the `title`.
- A ticketed removal says "`<title>` deleted" through `Announcer` and moves VoiceOver focus to the row that took its place (`layoutChanged`), else the list.
- Lists fed by the store pass `{ store.reapplyGeneration }` (the record views read `page.context.store`) and apply inside the observation that reads it, so a reconnect applies while its window is open.

## Sequencing with the server

- **Inventory (optimistic):** after the confirm, `InventoryListModel.pendingRemoval` hides the card at once; a failure restores it with `rowErrors`, as `TodoListController.remove` does for chores. A partial quantity delete only changes the row when the call succeeds (`delete(_:quantity:accepted:)` reports `false` for it).
- **Chores:** the confirmed delete is already optimistic in `TodoListController`; the view registers the ticket first and withdraws it when the call throws.
- **Swipe (held):** the row stays open under the confirmation and the neighbours' corners re-round in the same update (`UKServerUICollectionView.deleteInventory`, `todoAction`).
- Confirm calls `done(true)` as the card leaves; cancel, a failure and a partial delete call `done(false)`.
- Rows also offer Delete as a VoiceOver action (UIKit exposes the swipe actions of a list cell; HIG: swipe is not discoverable). Anchoring the iPad popover on the open Delete action is not part of this pattern.

## Adopting on a new list

1. Build `UKListUpdater(surface:collectionView:dataSource:generation:)` after the data source.
2. Replace every `apply` with `updater.apply(snapshot, cause:, cornerNeighbours:)`. Pass `.reset` for a rebuilt question; leave `.live` otherwise.
3. Register a ticket where the person commits a removal; cancel it where the call fails.
4. Module-card lists: give the cell registration `animatedCorners: updater.isAnimating` and pass the rows that only became first or last as `cornerNeighbours`.
5. Redraw rows without changing which rows exist (a header's height, a selection) with `updater.redraw(where:)`, never by applying a snapshot built from the list on screen. A redraw queued behind an animation joins the update waiting there, which keeps its removals and their announcement.
6. A form is built with `holdsOnlyForRemovals: true`: it applies section changes as they come, as the system does, and only a person's removal or a Reduce Motion fade holds back what follows it.
7. A list keeps the default (`false`): any animated apply holds back what follows, so a second apply cannot cut the first short.
8. Add the unit tests and the hosted tests below.

## Instrumentation and tests

- Each animated apply is a `LayoutChange` signpost, page `ListRowRemoval.<surface>` (`Telemetry`), measured hosted by `UKHostedListRemovalPerformanceTests` (`XCTCPUMetric` and `XCTOSSignpostMetric`; name the class in `FENTON_HOSTED_FILTER`).
- Unit: `ListUpdateTransitionTests`, `ListUpdateLedgerTests`, `InventoryListModelTests` (pending removal).
- Hosted, on iPhone, iPhone Duo and iPad: `UKListUpdaterTests` (the applier: queue, redraw, reset, the fade, the announcement) and `ServerUIListRemovalHostedTests` (Food) and `ServerUIChoreRemovalHostedTests` (chores): held swipe, cancel, confirm, a refused delete, a remote removal, no motion on a first apply, the VoiceOver action.
- Cost: one O(n) id diff per apply on the main thread; nothing runs per frame.

## Guards

- `list-row-removal/direct-snapshot-apply`: no direct `apply(…animatingDifferences:)` under `UIKitPort` except `UKListUpdater`.

Known limit: a module card that keeps some rounded corners and gains others (a first row that becomes the only row) cross-dissolves; one radius cannot interpolate both.
