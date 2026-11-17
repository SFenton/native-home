# Composition collections, forms and shell

This is the shared UIKit composition path, not a page-ID-to-controller router. It is the app's only root: the layout
comes from the publication Home Assistant stores (`fenton_home/ui_publication`), followed over the app's one websocket
and cached as the last good one per server ([architecture](../../../../../.agents/platforms/apple/architecture.md#server-driven-root)).
The app holds no reader enrollment, publisher endpoint or reader credential; the Studio is the only writer.
Chores, Inventory and Food use the same closed node types and retain the existing
domain stores. Other lanes should implement providers against these interfaces,
not another forms or collections language.

## Injection boundary

All native interfaces below are `@MainActor`, in `HassUI`. `UKServerUIRecords`
contains the record dictionaries below, plus section, tab-scope and action-state
projections:

```swift
collections: [String: any UKServerUICollectionSource]
forms: [String: UKServerUIFormFactory]
recipes: [String: RecipeBrowsingSource]
```

Pass this registry as `records:` to `UKServerUIRenderer`. IDs are authored provider
identities; they never select a compiled feature controller. Keep registrations
stable between accepted changes. A replacement registry goes through
`validateUpdate(records:)` and `apply(records:)`, including when the document is
unchanged. Open forms and pending commands reject replacement; ordinary value
updates keep their sources. Changing a registry dictionary invalidates its
identity, including changes made to a copied registry. Updating a publication
preflights its entire provider graph before replacing last-good content.

The normal-session runtime builds detached renderers and all window apply plans
before the publication's durable write. It rechecks scene membership, provider
generation, geometry and active interactions after that write, before any window
changes. A new scene or stale plan rejects the transaction and preserves last-good.
Accepted or discarded plans release their detached renderers; later windows
prepare their own renderer against the accepted publication.

The DEBUG publication preview can explicitly opt into the canonical demo
provider graph with `gallery: { viewerUserID, administrator, bedroomScenario? }` alongside its
synthetic `entities`. This installs the demo house, supplies collections,
editors, Settings, account/header projections and scoped fixture forecasts,
and keeps device preferences and feedback in isolated stores. It cannot be
combined with `live`; it never substitutes fixtures for a rejected live
provider. Authenticated web pages are explicitly unavailable in this mode.
An explicit `bedroomScenario` seeds the same `BedroomFixtures` values as the
bedroom gallery; omission preserves the supplied bedroom inputs and an
unknown scenario is rejected before entity mutation.
The `wake-summary` atom reuses canonical modal status text, typography and alerts;
it is read-only and requires `sh.wake-summary@1`. `wake-hold.showsExplanation`
adds the integration-aware canonical footnote through `sh.wake-hold-explanation@1`.
Generic text can opt into Dynamic Type subheadline/footnote with secondary ink
through `sh.supporting-text-styles@1`; original styles are unchanged.
`section-title` text (`sh.section-title@1`) retains the native sheet heading's
bold title3 font and accessibility heading trait, independently of page headers.
`wake-stop.episode` (`sh.wake-episode@1`) uses the bedroom sheet's active-episode
card with authored heading, detail and pending label. Omission keeps the standalone
Stop button; availability and stopping always come from the canonical controller.
Unsupported record and response-bearing fixture services fail rather than
claiming a successful mutation.
Gallery service coverage and matched image inputs still require their own
journey evidence; provider admission alone is not pixel-parity certification.
Paired backdrop fixtures publish `HouseBackdropStore.fixturePhotoData()` unchanged;
the gallery decodes that same PNG rather than drawing from a differently
interpreted in-memory image. The backdrop source test can export it with
`FENTON_SERVERUI_FIXTURE_PHOTO_OUTPUT`; production photos and rendering are unchanged.
Clean bedroom galleries omit their debugging-only indigo tint so it cannot
contaminate a comparison with the production backdrop.

Configured remote calls retain the native `speakerdevice` entity-array argument.
Its use requires `sh.remote-speaker-targets@1`, including inside state-conditioned
commands. Like `sonosdevice`, the array is bounded to 16 entity IDs; other unknown
argument keys remain rejected. Existing `sonosdevice` documents need no new capability.

Pending room commands pin their source and containing root component, including
its position and visibility policy. They do not freeze unrelated page titles or
other unchanged surfaces. The pin lasts through the actual network call, even
when a live state echo has already acknowledged the intent.

`UKServerUICollectionSource` supplies:

```swift
var template: ServerUICompositionDocument.Collection.Template { get }
var records: [UKServerUIRecord] { get }
var sections: [UKServerUIRecordSection] { get }
var emptyState: (title: String, message: String, symbol: String)? { get }
var summary: String? { get }
var navigationTitle: String? { get }
var loading: Bool { get }
var error: String? { get }
var hasPendingIntent: Bool { get }
var isPinned: Bool { get }
var hasMore: Bool { get }
var searchText: String { get set }
var showsSearch: Bool { get }
func actionState(_ role: ServerUICompositionDocument.PinnedActions.Role) -> UKServerUIActionState
func load() async throws
func loadMore() async throws
func select(_ record: UKServerUIRecord) throws
func displayed(_ record: UKServerUIRecord)
```

`UKServerUIRecord` is closed: `.row(ServerUIRowItem)`,
`.bedroom(ServerUIBedroomAlarms.Row, UKServerUIBedroomSource)`,
`.todo(TodoItem, ServerUITodoProvider)`,
`.inventory(InventoryDisplayItem, InventoryCompositionProvider)`, or
`.recipe(RecipeCard)`. Templates are `rows`, `todo`, `inventory`, `recipes`, and
`carousel`. `select` must reject stale or foreign records and capture the exact
target before the authored selection action opens a factory. `displayed` is the
canonical recipe pagination hook, not a per-frame observable write.

`hasPendingIntent` means an active command blocks another interaction.
`isPinned` also includes immutable edit/deletion tickets: it prevents provider
replacement without preventing an unchanged editor from closing. Providers report
failures explicitly and preserve cached records. The registry's aggregate
`hasPendingIntent` includes these publication pins.

## Transactional forms

Bedroom descriptors also register lazy alarm-editor factories and keyed alarm
collections over their canonical `ServerUIBedroomSession`. `<provider>.editor`
opens a fully revalidated selected row; `<provider>.new-editor` opens a new alarm.
Beds also expose `<provider>.day.<weekday>.new-editor` with the weekday locked.
Admission requires a matching real owner and draft kind, but never creates a
draft. Each rendered page owns its opened draft; live updates and publications
cannot replace it. Native Back, modal dismissal and system routes honor its
pending-command/discard guard. Alarm rows keep their native tap target and
trailing switch across live updates, in the canonical spaced card stack rather
than a second list-cell background. `alarm-add` uses the native primary button,
the canonical source's editing eligibility and an explicit authored destination.
Departed pages retire their drafts; completed or retired drafts are released
only after their protected work settles. Completed native modal pops release
removed pages at the navigation boundary, not eventual deallocation; cancelled
pops and sheet-to-column reparenting retain their owners.
Optional `titleSourceId` (`sh.surface-title-source@1`) names a typed alarm draft
used by that same surface. The title uses the opened alarm, not the edited text,
and an explicit reload adopts the latest title. Pushed alarm editors install
the native labeled Back action and route discard/busy decisions through the
existing exit gate.

`alarm-name` and `alarm-kind` may opt into `showsHeading`
(`sh.bedroom-field-headings@1`); weekday options may add `accessibilityLabel`
(`sh.weekday-accessibility-labels@1`) independently of their visible label.
`alarm-feedback` (`sh.alarm-feedback@1`) has an `error` or `problems` parameter.
A top-level error slot owns shared provider feedback for its source; individual
controls still display their own interaction failures. The empty slots retain
the canonical editor's layout. Reload is hidden until a stale draft needs it;
Delete is hidden for new alarms, and bed targets are hidden for existing alarms.
New wake-editor drafts use the native scheduled/workday defaults. Publication
ownership and discard prompts are separate: a pristine new draft pins its source
while open, leaves without a prompt, and is released when its page retires.
An `alarm-delete` confirmation may declare `messageFormat: "wake-alarm"`
(`sh.wake-alarm-confirmation@1`). Its message accepts only `{time}` and
`{schedule}`, resolved from the opened wake alarm. Literal messages remain
unchanged when the format is omitted; other source kinds or placeholders fail
compilation. The original immutable deletion ticket is still checked before send.

Wake collections may declare `props.bedroomLinks`, with a unique configured bed
`side`, button `label` and navigation `action` per entry. These require
`sh.bedroom-collection-links@1` and a real wake collection. Native alarms use the
collection's ordinary selection; mirrored alarms retain link-only toggles and
the canonical separate linked-device button. `present` with `ifPresented:
"replace"` requires `sh.modal-handoff@1`: it honors the existing draft exit gate,
waits for dismissal, and presents from the original owner without pushing onto
the underlying page. The default `reject` policy is unchanged.

Factory metadata is checked against every authored field before opening:

```swift
UKServerUIFormFactory(
    fields: [String: ServerUICompositionDocument.Form.Control],
    selectionOnly: Bool,
    open: @MainActor () async throws -> any ServerUIFormSession
)
```

`ServerUIFormSession` lives in Core. Its exact interface is `identity:
ServerUIDraft.Identity`, `groups: [ServerUIFormGroup]`, `hasChanges`, `isBusy`,
`canSave`, `error: String?`, `canReset`, `resetLabel`, plus:

```swift
func set(_ value: ServerUICompositionDocument.LocalValue, group: String, field: String) throws
func save() async throws
func reset() throws
func discard() throws
```

A group has a stable ID, header/footer and typed `ServerUIFormValue` fields.
Fields carry their current scalar value, rule/options, enabled/visible/required
state and optional option subtitles. Factories declare all possible field keys;
groups may omit conditional fields. Group IDs are unique; field keys are unique
within a group (batch editors may repeat a field key across groups). Each
returned control/rule must match factory metadata. Providers must be observable
through their getters. The host observes snapshots, not a second model transport.

Use `ServerUIValueForm` for ordinary scalar transactions. It pins the submitted
values, rejects edits/reset/discard while saving, retains errors and edits for
retry, and closes once on success. Reset restores provider defaults without
closing. `allowsReset: false` matches task and plain Todo editors. `selectionOnly`
filters discard un-applied choices on exit without the user-content discard
prompt; it does not make changes immediate. An unchanged Apply stays disabled.

Provider-owned deletion uses `ServerUIDeletableFormSession.deletion:
ServerUIFormDeletion?` and `delete() async throws`. The descriptor contains
`title`, `noun` and original `name`, never an authored service command.
`ServerUIValueForm` accepts paired `deletion:` and `delete:` arguments. Confirmation
pins the original target; failure retains the draft and allows retry.

Controls: `text`, `multiline`, `number`, `toggle`, `choice`, `date`, `time`,
`weekdays`, `attachment`, `options`, `percent`, `segmented`, `scan-camera`,
`schedule-date-time`. Date/time strings retain their domain formatting. Schedule
date-time uses bounded epoch seconds with a numeric rule and **step 1**; all values
must be finite whole seconds. A group of these fields shares
`UKScheduleDateFields`; its native responsive layout and disabled picker state
are reused. Fields remain draft-owned until Save. An attachment control requires
`ServerUIAttachmentFormSession`; a camera control requires `UKServerUIScanForm`.
Neither can turn an arbitrary scalar provider into an upload/camera interface.

`ServerUISteppedFormSession` adds `progress: ServerUIFormProgress`, `advance()` and
`retreat()`. The scanner uses this same host with the canonical camera, quantity,
header, footer and processing atoms. A successful add followed by a failed refresh
retries only refresh, not the add. Detaching cancels opening and camera work; a late
factory result is discarded rather than attached to a departed page.

## Production adapters

`UKServerUIRecordProviders` assembles Chores, Inventory/scanner, Recipes and
authenticated Summary registrations. The normal runtime obtains identity only
from the authenticated websocket; remembered
viewer preferences are not authority. Todo controllers share one account store,
with a server/user-partitioned disk cache removed at sign-out. Each window owns
its selections, forms and inventory/recipe models, which live as long as the window. A house-config replacement retains the window's inventory
and recipe sources, while replacing immutable chore descriptors. Restricted
lists and admin collections reject unauthorized reads and editor creation.
Summary tabs retain an allowed selection, or return to Profile when its scope
changes. Guests keep shared expired food, but cannot mount personal chore lists
or open their editors.

Normal-session Preferences and Performance providers are also registered.
Performance rows use the existing telemetry report and keyed row collections.
Preferences use the real icon/version models and the active window's backdrop.
Each staged backdrop owns a distinct blur object and render callback; Preferences
rebinds only when that window commits. A local blur choice persists and updates
all visible windows, without touching staged candidates. A preference change
during persistence invalidates the prepared plan. With no local choice, the
authored blur remains the default.

Household and Away use explicit verified house targets. Vacation and Solo Trip
share one plan controller per window; their sections, automatic route and cancel
states read those same models. Residents pin their person records while retaining
neutral-key equality and wire encoding, so a queued command or snapshot cannot
resolve through a newer house's person mapping. A changed configuration stages
replacement providers, while old command adapters reject further requests and
renderer admission retains protected interactions.

Profile supplies the existing location coordinator, per-person boxes, authenticated
account/house-layout values and full-screen Home Assistant web boundary. Shell
attention and room personalization use the verified user, not remembered viewer
preferences. Feedback keeps separate per-window bug/feature drafts and fences
each HTTP request and response to that account. Diagnostics use the submitting
page's traits. Unchanged presentation registries retain identity across preflight;
provider changes cannot replace an open form. System routes also respect native
Settings exit guards. Complete-catalog adoption and paired device evidence remain
separate gates; constructing these providers alone does not certify parity.

| Domain | Construction and registrations |
|---|---|
| Chores | `UKServerUIChoresCollection(configuration: ChoresConfig.Page, model: ChoresModel, store: EntityStore, people: ServerUITodoPeople)`; register `editFactory` and throwing `addFactory`. Share the session's `ChoresModel`/`TodoStore`, viewer and `EntityStore`. Visibility, vacation copy and completion/Undo remain canonical. |
| Individual Todo | `UKServerUITodoCollection(ServerUITodoProvider)`; `textFactory(editing:)`, `taskFactory(editing:people:viewerUserId:defaultAssignee:)`, `adminFactory(accessToken:)`. Task edit/delete tickets revalidate the captured source and row. |
| Inventory | `InventoryCompositionProvider(sourceID:space:model:)` over the existing `InventoryListModel`, then `UKServerUIInventoryCollection(provider)`. Register `editorFactory` and `preferencesFactory(sort:)`. Batch identities, expiry grouping, quantity/delete prompts and mutation serialization stay with the canonical model. |
| Scanner | `UKServerUIScanForm.factory(sourceID:makeModel:makeCamera:added:)`. Closures return the existing `ScanItemModel`/`ScanCameraController`; `added` refreshes the same inventory model. `makeCamera` has a production default. |
| Food | One `RecipeBrowsingSource(models: FoodModels)` shared by `UKServerUIRecipeCollection(source)` and `UKServerUIRecipeCollection(source, suggested: true)`. Register it under `recipes` for detail parts; use `preferencesFactory(sort:sourceID:)`. Tests may construct `RecipeBrowsingSource(service: any RecipeServing)`. |

Do not expose a session or connection through `UKContext` to satisfy these
providers. Production uses its existing authenticated domain models. Isolated
preview supplies narrow read providers and explicit rejecting mutation providers;
its rejecting service caller must not be replaced. The admin attachment adapter's
only token seam is `@MainActor () async throws -> String`; preview may reject it.
No credential is authored into a document.

## Shell, navigation and layout

`shell-header` must be the sole item in the sole trailing chrome group. It has
authored present-only `quickLinksAction` and `profileAction` destinations and
`always`/`root-only` visibility. Inject:

```swift
UKServerUIShellHeaderSource(
    state: @MainActor () -> UKShellHeaderItems.State,
    avatar: @MainActor () -> AvatarBox?
)
```

The closures read the existing observed name, attention count, avatar and
offline/reconnect projection. The renderer reuses `UKShellHeaderItems`; it owns no
connection lifecycle. `navigation-tile.props.titleProviderId` binds personalized
Chores quick-link labels to a collection's `navigationTitle`.

Pages may declare `navigation-columns` with `placeholder`, `standalone`, and
optional `onDemand`. Modals may declare `presentation.adaptive`. Geometry is
decided only by `SplitPolicy`. The same controllers, form sessions and logical
paths move between columns and sheets; geometry handoff does not reopen a factory.
Inventory keeps its wide placeholder; the Recipes grid stays full-width until a
detail is selected. User-opened columns animate with the canonical motion;
geometry changes do not. Chores has one shared window-spanning action bar.

`local-tabs` supports `pinned`, per-tab `icon`/`centerWhenFits`, and
`resetOnPresentation`. Pinned tabs reuse `UKModalTabBar` (`Design/UKSegmentedControls.swift`), including its AX menu.
They reset for a new presentation, not rotation or compatible publication. Only
one root pinned owner is permitted; a root form/pinned-action bar cannot also own
that space. `info-box`, `status-pill` and recursive `paged-row` use the canonical
atoms; paging retains keyed child views and anchors the visible child on reorder.
At accessibility text sizes it shows one child per page.

The parent resolves a `RouteRequest` through the publication's `target(for:)` and calls
`routeExternal(tabID: String, pageID: String? = nil) throws`. Unknown destinations,
dirty/busy drafts, active prompts or transitions reject the route. The parent
must retain rejected notification/shortcut intents for an explicit retry. This
method does not install or replace the global `AppShortcutRouter` handler.

## Settings lane integration

These are shared presentation hooks, not a second Settings language. The
Settings lane's `settings-control` nodes still own their native controls and
commands. Both compilers use the same closed row/primary-kind allowlists: tiles,
date editors, media, status blocks and nested containers are not module rows.
`settings-link` row eligibility is implemented directly and negotiates
`sh.module-settings-rows@1`.

**Native exits.** The renderer installs `nativeExitGate` before view loading,
using the attached Settings providers' `blocksExit`/`canDiscard` and
`requestSettingsExit(from:completion:)`. Weak captures fail closed if the renderer
is gone. Provider discovery includes the sender, UIKit stack and wide-column
children, with source-ID deduplication. Authored-action/modal-dismissal guards
remain in place.
Root and modal Back, ancestor menus and custom interactive pops now enter
this gate before changing stacks. Wide Back/Close uses `UKColumnExitRequesting`;
dirty/busy pages cannot edge-pop, and clean edge-pop admission uses the same
gate. Deferred/repeated/stale approvals cannot remove a different page.
Canonical discard callbacks run after alert dismissal. Direct `perform` and
external routes reject blocking Settings state rather than silently bypassing it.
Ancestor and wide-Close admission checks every departing generic form, not only
the top controller.

**Pinned forms.** `pinned-actions.props.style = "form"` uses the canonical
keyboard-aware `UKPagePinnedBar`. It takes either one prominent item, or one
existing primary control in `children`; either may have one secondary Cancel
item. The existing-control slot retains the real Settings submit/confirm node,
its closures and its observed busy/disabled state. Do not invent a Settings
domain action to replace it. The form stack and canonical row text stack exclude inherited safe-area margins:
the bar itself creates that inset, so inheriting it would grow its measured height
on every layout pass. Item `stateProviderId` resolves
`records.actionStates: [String: @MainActor () -> UKServerUIActionState]`;
`visible`, `enabled` and `busy` update retained buttons without dismissing the
keyboard. A Cancel state normally enables when `!provider.blocksExit ||
provider.canDiscard`; its authored dismiss action still runs the exit guard.

**Observed sections.** `section.props.presentationProviderId` resolves
`records.sections: [String: @MainActor () -> UKServerUISectionState]`. Optional
`header`/`footer` replace authored text, `detail` carries counts, and `visible`
removes the entire section, including header/footer, from its parent layout and
accessibility tree while retaining its keyed controls. Root columns, grids,
sections, tabs and pagers all honor it. A scope is immutable for a renderer;
closure reads can use existing Observation models and per-entity boxes.

**Scoped summaries.** A single root `local-tabs.props.scopeProviderId` resolves
`records.tabScopes: [String: UKServerUITabScope]`. Initialize it with
`allowedTabIDs: scope.tabs.map(\.id)`, `initialTabID: scope.initialTab.id`,
`title: { scope.title }`, and a badge closure mapping each allowed tab through
`ProfileSummary.counts(viewer:store:).badge(for:)`. Here `scope` is Settings'
session-captured `ServerUISummaryScope`; use its Profile initial tab, not the
older `SummaryTab.initial(viewer:)` helper. Unauthorized panels are neither
preflighted for collection registration nor mounted. Pinned native tabs retain
their content and refresh badge accessibility labels.

For each permitted chore tab, construct
`UKServerUIChoresCollection(summary:lists:model:store:people:)`, passing exactly
`scope.lists(for: tab)`. Register its real `editFactory`: grouped task rows,
completion/Undo, deletion and immutable selected-task editing are unchanged.
For guests, instantiate no personal collection/controller. The global modal
catalog still needs form metadata: register its exact declared fields with an
`open` closure that throws `ServerUIRecordFailure.missingProvider` when that
tab's collection is absent. This is a denied guest entry, not a fake editor;
authorized entries delegate to the collection's `editFactory.open()`.
Use `scope.showsAdminTodo` for a provider-visible section around the Settings
To-Do link.

Expired Food uses the retained `.allFood` model with
`InventoryCompositionProvider(sourceID:space:model:query: .expiredFoodSummary)`
and `UKServerUIInventoryCollection(provider, summaryStore: store)`. Its fixed
expired/expiry-ascending projection does not mutate the shared screen's
sort/filter preferences. Its canonical empty/vacation states, entity-driven
refresh, cart quantity/confirmation and `editorFactory` remain operative.

**Automatic Away.** Content-only root tabs set `showsSelector: false` and
`retainsAutomaticSelection: true`. Supply an `automaticSelection` closure
mapping the existing `Vacation.route(...)` into the authored chooser/vacation/
solo IDs, plus its live title. `ServerUIAutomaticSelection` retains lastEngaged
and keeps a departed chooser for that visit; a new presentation starts fresh.
For Vacation, `away-mode` is visible when `!controller.soloTripEngaged`,
`away-checklist` additionally requires `!controller.showsInlineDates`, and
`away-dates` requires `controller.showsInlineDates`. The checklist detail is
the number of `controller.checklist` entries satisfying `controller.isChecked`
over the total. Traveler visibility follows `UKSoloTripContent`'s existing
projection. `tile-grid.minimum = "section-wide@1"` is a body-scaled 340 pt
minimum with at most two columns, not split navigation.

**HA Settings.** Set `presentation.fullScreen = true`, `height.type = "full"`
and `adaptive = false` on `modal-ha-settings`. The closed
`sh.full-screen-modal@1` option uses canonical `UKHassModalOptions.isFullScreen`;
it does not add another WebView or redirect by page ID.

## Debug preview and provider preparation

The debug-only `--server-ui-preview` launch path reads `Application Support/ServerUIPreview/bootstrap.json` (exactly one of
synthetic `entities` or `live: {server, accountID}`) and `publication.json` beside it, the published envelope; assets come
from `assets/<sha256>`. The envelope reaches the app's store as if the integration had sent a `published` event: there is
no publisher HTTP endpoint. A live preview takes its bearer from the launch environment variable
`FENTON_PREVIEW_HA_TOKEN` (`simctl launch` sets it as `SIMCTL_CHILD_FENTON_PREVIEW_HA_TOKEN`): taken and removed with `unsetenv` in `UKServerUIPreview.init`, before any step that can fail, so a failed bootstrap or fixtures
mode cannot leave it in the environment; a launch without the flag removes it at start (`UKGalleryRouter.requested()`). It is
kept in memory only, used on the live path alone, and never logged or written. There is no file source: a stray `ha-credential`
file is never read. A live preview also needs
`bootstrap.json` with `live: {server, accountID}` and a `publication.json` (plus `assets/<sha256>`) staged in the
simulator container; the app does not fetch the publication from Home Assistant.
Live design uses the existing `HassConnection`, `EntityStore` and `ConnectionLifecycle`. Normal account restoration, push
registration, location and Live Activities stay disabled. Canonical controls remain visible, but their caller rejects
commands without changing live entity state; action-success comparisons run with fixtures. The receipt distinguishes
fixtures, cached or live data, connection rejection and blocked commands, and is reset before each load. The harness does
not replace production sign-in or certify all-app parity.

The live preview constructs its scoped forecast and camera readers from the accepted document's sources. Forecasts use the
same websocket's readiness; camera reads lease the renderer's canonical stream pool. Neither gives the configured controls
a raw connection or session. Both ordinary and response-bearing service commands remain rejected, including commands from
authored bedroom providers. Preview preparation constructs and retains the fully validated renderer before durable
publication acceptance, so a missing scoped provider cannot advance the cache and fail only afterward.

The live preview also builds the production provider set from its read-only connection and the followed `house_config`
(`UKServerUIPreviewLiveProviders`): household, away, profile, preferences, performance and feedback settings providers;
to-do, inventory, recipe and summary records; Data Flow collections; media remotes and bedrooms; the account and shell header.
It calls the production static builders (`UKServerUIHouseholdProviders`, `UKServerUIRecordProviders`,
`UKServerUIProductionProviders.bedroomProviders`, `.flowHost`, `.feedbackProvider`, `.presentations`), so the two cannot drift.
Reads (to-do items, schedules, the current user, the entity feed) pass; every service call, upload, schedule update and flow
call goes through `UKServerUIPreviewReadOnlyServices` and is refused and counted. Sign-out, Home Assistant web pages and feedback
filing are refused at the action. Like production, the preview waits (bounded, 20 s) for the house document and the user, and a
supply asked for earlier throws `inputs_pending`. The wait honours cancellation and holds no reference to the providers; `stop()`
restores `HouseConfigSource.shared` to what it held before the preview started. The app-icon choice stays in memory and the
preferences land in an isolated defaults suite. Known fixture difference: recipe and inventory collections stay empty in live
preview (their reads are response-bearing service calls, which stay refused). Fixtures mode keeps `DemoHouse`.

### Preview state flags (DEBUG)

`UKServerUIPreviewFlags` stages an error or edge state with no live write. They mirror the reference's launch variables, so one
state is staged on both sides. Read from `bootstrap.json` `flags` (keys below), then the launch environment, which wins. A
variable counts only when it is `1` (the delay: a number); with no flag the preview and its receipt are unchanged, and a set flag
is written to the receipt as `flags`. Each acts through an existing seam, never a view branch:

| Flag | Reference variable | Seam |
|---|---|---|
| `connection` `offline` / `reconnecting` | `FENTON_GALLERY_OFFLINE` / `_RECONNECTING` | the shell header state production reads from `HassConnection.isOffline` and `ReconnectingIndicator`; weather `connected` |
| `failCalls` | `FENTON_GALLERY_FAIL` or `_FAIL_COMPLETE` | the fixture caller and records answer every call with `UKServerUIPreviewFault.callFailed` (`UKServerUIPreviewFailingCaller` without a gallery) |
| `empty` | `FENTON_GALLERY_EMPTY` | the fixture todo lists keep their ids and hold no item; no inventory row |
| `gateDelayMs` | `FENTON_GALLERY_GATE_DELAY_MS` | the load waits before it applies the publication (at most 60 s); the status line stays up |
| `animationsPaused` | `FENTON_GALLERY_PAUSE_CONTINUOUS_ANIMATIONS` (the reference's `pauseContinuousAnimations`) | `UKDesign.animationsPaused` |
| `reduceMotion` | `FENTON_GALLERY_REDUCE_MOTION` | `UKMotion.reduceMotionOverride`; every UIKit read goes through `UKMotion.reduceMotion` |

`connection`, `failCalls` and `empty` act on the gallery fixtures (`gallery` in the bootstrap; `failCalls` also on a plain
`entities` bootstrap); a `live` preview ignores them, and faults on live runs belong to the guard proxy's fault layer. The two
process-wide switches are put back when the preview leaves the screen. All of it is `#if os(iOS) && DEBUG`
(`tools/tests/test_preview_flags_debug_only.py`).

Normal-session provider preparation resolves authored device descriptors before checking their references; house-config
providers fill only keys those descriptors do not own. Reconnect permission changes replace idle bedroom providers without a
new document revision, but never discard an owned draft or command. Schedule reads and writes use the same session-fenced
caller as ordinary service commands.


## Bedroom composition atoms

Moved from the bedroom-devices pattern record, which keeps the behaviour rules.

`ServerUIBedroomControl` defines the closed bedroom atom contract; `bedroom-provider@1`
resolves only scene-injected `UKServerUIBedroomProvider` values. It never consults
global house configuration. `BedSideEnvironment` captures the canonical controller's
shared targets at construction; existing callers retain the configured default.
`ServerUIBedroomDraft` owns an editor draft and delegates commands to the existing
controllers (wake saves receive the room's canonical provisioning closure).
`ServerUIBedroomAlarms` supplies full-value keyed rows, day filtering, revalidated
toggle intents and typed domain routes to the shell-owned collection/router seam.
Mirrored wake rows send only link commands and open their originating bed editor.

`bedroom-config@1` supplies both bed descriptors, wake configuration and
`BedSideEnvironment`. `ServerUIBedroomSession` constructs one canonical bundle,
projects stable alarm/day collections and retains editor ownership through
`editor(providerId:route:visitId:now:)`. Existing alarms use their row identity; Add
uses the shell visit identity. `release(_:)` rejects dirty or busy drafts. Script
fields use the canonical bare service name, not a `script.` entity identifier.
The source requires an explicit `HassServiceResponding`; edit permission is injected,
never authored. New weekly wake-alarm provisioning reports bed transport/link
failure instead of dismissing the editor as if the entire operation succeeded.

Editor admission validates a real scene-owned factory and matching draft kind;
it never opens a draft just to pass preflight. `UKServerUIBedroomRegistry` supplies
`<provider>.editor` for a revalidated full-row selection, `<provider>.new-editor`
for Add, and bed `<provider>.day.<weekday>.new-editor` for a locked day. Each page
keeps its opened draft and the native exit gate owns discard/busy protection.
`bed-tile`, `wake-tile` and `alarm-bed-target` reuse the canonical controls.
`alarm-add` reuses `UKPrimaryButton` with the configured label and authored
navigation action, enabled only by the canonical alarm-editing permission.
HIG [Buttons — Content](https://developer.apple.com/design/human-interface-guidelines/buttons):
"Make each button's purpose clear with a symbol, text or both, as the platform allows."
The existing Add Alarm button's plus symbol and label remain the single pattern.
Wake collection `bedroomLinks` maps each configured side to an authored
destination. Mirrored rows use the same separate link button as the compiled
wake sheet, never a native wake-alarm draft. Negotiated `present`/`replace`
waits for dismissal and honors the native dirty/busy gate before handing off.
`UKBedroomRow` exposes its Auto Layout fitting height to manual columns, keeping
the full native alarm card and its independent switch visible. `wake-summary`
reuses `UKWakeStatusView` for the modal subtitle and integration/command alerts
through the injected wake controller; it requires `sh.wake-summary@1` and never
sends a command. `wake-hold.showsExplanation` opts into the canonical, integration-
aware hold footnote through `sh.wake-hold-explanation@1`; omission preserves a
standalone choice grid. Selecting an existing default sends no command.
Bedroom atoms retain their Auto Layout fitting height without rounding up to
whole points, preserving fractional-pixel text placement under pinned materials.
Authored sheet headings use `section-title` text (`sh.section-title@1`), retaining
the canonical bold title3 font and accessibility heading trait rather than the
page header's distinct font descriptor.
`wake-stop.episode` opts into `UKWakeEpisodeView` through `sh.wake-episode@1`.
Its heading, explanation and pending label are authored; the canonical controller
owns occurrences, availability and Stop. Omission retains the standalone button.
Alarm editors reuse `UKBedroomField` for optional name/type headings
(`sh.bedroom-field-headings@1`). Weekday choices may separate visible and spoken
labels (`sh.weekday-accessibility-labels@1`). A surface's `titleSourceId`
(`sh.surface-title-source@1`) must reference its own typed alarm draft: the
opened title remains stable while typing and changes only on explicit reload.
Pushed editors use the existing shell exit gate through a labeled Back button.
Top-level `alarm-feedback` error/problems slots render shared native alerts instead
of duplicating provider feedback under each field. Reload remains reachable when
stale validation blocks Save; bed targets and Delete respect new/existing state.
Both native and authored wake editors create scheduled workday alarms. Untouched
new drafts retain publication ownership while open, but Back asks only about real
edits or pending work; retiring an unchanged draft releases that ownership.
Wake delete questions can opt into `messageFormat: "wake-alarm"`
(`sh.wake-alarm-confirmation@1`). Their authored message substitutes only `{time}`
and `{schedule}`, using the opened alarm rather than unsaved edits. Other braces
and non-wake draft sources are rejected; omitted format preserves literal copy.
The compiled sheet uses the same active-episode card.

Studio's schema inspector authors labels, weekday/duration order, mode icon/family,
and mandatory power/delete/scope questions. UIKit uses the existing dial, stage row,
choice chips and compact date/time fields; no feature controller is embedded. The
required action-sheet semantics cannot be removed by configuration (HIG
[Action sheets — Best practices](https://developer.apple.com/design/human-interface-guidelines/action-sheets));
time/date input stays in context (HIG
[Pickers — iOS and iPadOS](https://developer.apple.com/design/human-interface-guidelines/pickers)).
Inputs preserve the pattern's checkmarks and minimum targets (HIG
[Accessibility — Vision and Mobility](https://developer.apple.com/design/human-interface-guidelines/accessibility)).

Transport, debounce work, optimistic feedback, scope questions and dirty/busy drafts
pin publication. Focused input also blocks document replacement. Delete tickets
capture the complete draft; power tickets capture the whole-bed scope and revalidate
before acting. A failed save keeps the draft; reload/discard are explicit and a
live command cannot be discarded. Ordered local tabs, complete authored entry
routes and linked-device handoffs still need paired device evidence; provider
admission and hosted rendering alone do not certify complete pages.
The first-slice capability manifest and fixtures stay unchanged.

## Evidence

The Studio is the only writer of the publication. Its fixtures and this app share one corpus
(`apple/Tests/HassCoreTests/ContractCorpus`): every accepted and rejected envelope and the capability list.
`ServerUIShellAtomsFixture.json` and the matching Studio fixture are synthetic; actual house entities never appear in a
committed fixture. Core and Studio tests exercise closed parsing, immutable command targets, draft failure/retry and
navigation. Hosted tests cover retained adaptive drafts, rows, pinned tabs, native status/paging, shell header and
schedule controls at family widths/AX. Build-for-testing proves compilation only. Devices, camera permission journeys,
VoiceOver/motion inspection and unfolded Duo evidence remain separate gates; source completion is not certification.

## Authority

This extends existing controls, not their product design: see `UKTodoForms`, `UKScanItemSheet`, `UKScheduleDateFields`,
`UKColumnsViewController` and `UKShellHeaderItems`. Owning patterns are `modal-sheet`, `floating-actions`, `motion` and
`content-gate`, and the split-view design. Platform authority remains Apple HIG
[Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets),
[Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars),
[Pickers](https://developer.apple.com/design/human-interface-guidelines/pickers),
[Segmented controls](https://developer.apple.com/design/human-interface-guidelines/segmented-controls),
[Layout](https://developer.apple.com/design/human-interface-guidelines/layout),
[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
and [Motion](https://developer.apple.com/design/human-interface-guidelines/motion).
