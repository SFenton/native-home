# Apple architecture

> **What:** how the Swift code is structured. **Read when:** adding Apple code or a shared component.

| Path | Contents |
|---|---|
| `apple/Sources/HassCore` | No UI. `Auth/` (login flow, Keychain, token manager), `Connection/` (HAKit wrapper, lifecycle), `Entities/` (`EntityState`, `EntityStore`, `EntitySnapshotCache`), `Config/` (entity IDs ported from the web; `HouseConfig`, the same house data as one document, and `HouseConfigStore`, which follows the server's copy: [connection-lifecycle](connection-lifecycle.md#house-config)) |
| `apple/Sources/HassDesign` | Tokens (`HassTokens`), `DynamicGridLayout`, `GlassTile`, MDI → SF Symbol mapping |
| `apple/Sources/HassUI` | `App/` (root, session, coordinators), `UIKitPort/` (canonical components, `ServerUI/` renderer), `Features/<Feature>/` (models and shared pieces) |
| `apple/Apps/iOS`, `apple/Apps/watchOS` | App entry points |
| `apple/Tests` | SwiftPM tests for Core and Design |

Deployment: iOS/iPadOS 17, watchOS 10. Swift 6 language mode.

## Server-driven root

The server-driven renderer is the only root: the app has no compiled tab catalog or compiled page. Every screen is composed from the publication stored in Home Assistant (`fenton_home/ui_publication`, integration 1.4.1 or later). The Studio (`ha-native-home-app`) is the only writer; the app only reads.

- **Transport.** `ServerUIPublicationSubscription` follows `fenton_home/ui_publication/subscribe` over `HassConnection`'s one websocket, like the house config. The integration answers at once and after every publish or rollback; HAKit resubscribes after a reconnect. There is no poll, no HTTP fetch of the document and no reader secret. `ServerUIPublicationEvent.judge` compiles each reply off the main thread.
- **Capability negotiation.** The subscription sends `ServerUICompositionPublication.supportedCapabilities`; the server chooses the newest entry whose capabilities are a subset, else reports `incompatible` with the missing names. A document naming a capability the compiler does not know is refused whole. The Studio's capability list and the app's are one corpus (`apple/Tests/HassCoreTests/ContractCorpus`).
- **Last-good cache.** `ServerUIPublicationStore` keeps one record per server origin (`ServerUIPublicationPartition`) holding the layout, the integration's epoch and revision and the Home Assistant user it was delivered to. A cold launch restores it synchronously before the first frame; `bind(userID:)` discards a record written for another user. An older revision within one epoch is ignored; a new epoch restarts ordering.
- **Acceptance.** A candidate is prepared (assets fetched from `/api/fenton_home/ui_assets/<sha256>` with the current token, verified by hash, staged; renderer built), saved, then committed in that order. Any failure leaves the visible last-good untouched. A candidate refused only because an interaction is open is held and committed when it ends.
- **Boundary states.** With no last-good, `ServerUIPublicationRemoteState` selects the ground: waiting ("Getting Your Layout…"), `unpublished` ("No Layout Published"), `incompatible` ("Update Required"), or a failure ("Layout Unavailable", with retry and clear). With a last-good every one of them keeps it on screen.
- **Generic actions and visibility.** A document may author any call-service action (domain, service or script; target, data operands, optimistic state, optional confirmation), bound controls (toggle, stepper, slider, choice, button), `visibleWhen` on nodes and tabs and `selectedWhen` on choices and local tabs. Operands and predicates are a closed grammar with no client-side templates. Home Assistant still owns state and automation.
- **Navigation.** `ServerUINavigationState` keeps independent paths for published tab ids and modal instances. A compatible publication preserves paths and instance ids; removed ancestors prune their paths. Apply only after the renderer's safe-handoff gate has protected drafts and in-flight work.
- **Rejection classes.** Only an invalid document rejects (an unknown capability, a grammar error, a broken reference); the last good layout stays.
  - A device or runtime gap (a symbol or feature this OS lacks, a missing entity or copy entry) degrades one node and logs a diagnostic.
  - A launch fact (window geometry, the viewer, an open interaction) defers the candidate and retries.
- **Renderer.** `HassUI/UIKitPort/ServerUI` ([README](../../../apple/Sources/HassUI/UIKitPort/ServerUI/README.md)) renders the compiled document with the canonical components and the providers over the existing domain models; Core compiles it in `HassCore/ServerUIComposition`.

## Invariants

- Views never talk to HAKit. They read `EntityStore.entity(_:)` (an `@Observable` box per entity) and act through `HassConnection.callService`.
- Entity IDs live in `HassCore/Config`, ported with a citation to the web constant they came from.
- A view that shows one entity observes only that entity's box, so unrelated updates do not redraw it.

## House config facades

The app compiles in no house data. Every house value (entity ids, rooms, people, titles, icons, colours, order) is read from the server's document through a facade on a `*Config` enum; the facades are the only place the document is read.

A facade is a computed `static var` returning `HouseConfigSource.active.read { $0.<section>.<value> } ?? <empty>`:

1. With a document it answers the document's value. `read` projects inside the lock, so it never copies the whole document.
2. With **no document** it answers an empty value: an empty string, list or map, a zero, or a placeholder with no entities (`MediaRemotes.sourceSelectRemote` answers `MediaRemoteConfig.unconfigured`, an unknown chores page an empty `Page`). Never house data. A page that depends on the layout then draws the `HouseLayoutState` skeleton or message ([house-config-states](../../design/house-config-states.md)); there is no built-in fallback.
3. Call sites do not change. A list is read with `.first` or a lookup, never an index; a set of parallel values the code reads by name (garage doors, source roles) is a role-keyed map (`garageDoors["left"]`) that `HouseConfig.validateRoles()` checks at decode.

Rules:

- **No house literal in `apple/Sources`.** A new entity id, name or address in code is a `house_scan` hit (`tools/house_scan.py`; the allowlist holds only generic ids such as service names, SF Symbol names and accessibility identifiers). A fallback is empty, never a default house.
- **No `static let` that reads a facade.** It freezes the first value until relaunch. Make it a computed `static var` (`WeatherEntities.weather`, `QuickLinks.securityEntityId`, the vehicle tiles). The `weather/static-let-reads-house-facade` guard in `contracts/patterns.json` checks every `static let` against its `facades` map (type to names); add each new facade's names to the map.
- **No `Dictionary(uniqueKeysWithValues:)` on server data** (a repeated key traps): use `uniquingKeysWith: { first, _ in first }` (`HomeConfig.guestToggleRules`, `VacuumController.roomOrders(for:)`, `SpotlightCatalog`). The `weather/unique-keys-in-facade-files` guard flags it in files that name a facade.
- **No index subscript on a server-provided array** (`[0]`, `.first!`): the document may carry an empty list, or none. Use `.first`, a lookup or a count guard, and add a test with an empty array (`HouseholdSettingsTests.relayWarningSurvivesADocumentWithNoGuestRooms`).
- **Read through `active`**, never `shared`.

`HouseConfigSource` (HassCore) is the single accessor: `public func read<T>(_ project: (HouseConfig) -> T) -> T?`.

- `HouseConfigStore` pushes every accepted document into `HouseConfigSource.shared` (the cache copy first, `nil` at sign-out). Nothing else writes.
- A widget or Live Activity extension that first reads a facade calls `HouseConfigSource.shared.seed(from:for:)` with the app-group cache (no caller yet). The Watch cannot read the iPhone's app-group container, so it has no house layout until it has its own source.
- `read` is Observation-tracked, so a UIKit `updateProperties()` or `withObservationTracking` that reads a facade re-runs when the document changes.

**The document is owned by the server.** There is no compiled copy to export or compare with: a change to the house is an edit of the document on the server (`fenton_home/house_config`). The DEBUG `DemoHouse` (`apple/Sources/HassDemoHouse`, exported to `build/ha/demo-house.json` for the test instance) is the only document the repo carries.

**Schema 2.** `HouseConfig.decode` reads `schema: 2` only. The ha-fenton-home server stores any document with an integer `schema` and mapping or list sections, so new keys need no server change.

- Residents are keyed by neutral ids (`resident_1`; one `Resident` struct, its record in `chores.people`), garage doors are role-keyed, and brand names stay out of keys.
- The Music Room scripts and action graphs are `media.sourceSelect.commands` and `.actions`; `media.sourceSelect.remoteId` names the remote the source roles belong to.
- Optional fields (absent means empty): each climate room's `occupiedOnlyEntityId`; each air purifier's `aqiEntityId`, `autoModeEntityId`, `fanEntityId`, `modeEntityId`; `home.airQualityEntityId`, `home.sunEntityId`; `media.scriptPowerDevices[]`. A missing occupied-only or fan id means the control is not configured; the app never guesses an id from a name. `tools/house_config_patch.py` fills the rest once from Home Assistant's registries.
- `HouseholdAway.statusEntityId` and `commandService` read `bedroom.householdAwayEntityId` and `householdAwayScript`; `HouseholdSettingsConfig.Vehicle.tiles` reads `household.vehicleTiles`.
- A server value the app cannot use (a launcher that is not a plain command) leaves its tile unavailable with a telemetry line; document data never reaches a `precondition`. Gallery launch settings and Solo Trip identifiers key on the resident key, never on a server-provided id.

**Tests.**

- A suite that reads a facade carries `@Suite(.demoHouse)` (`HassTestSupport`), which scopes each test to `DemoHouse.source`; a test of the empty case scopes `HouseConfigSource()`.
- A synchronous test scopes its own source with `HouseConfigSource.$scoped.withValue(source) { … }` (task-local, parallel-safe).
- The scope does **not** survive a main-queue hop, a UIKit observation re-run or an `onChange` re-read, so a hosted test of a live update uses `DemoHouseTestCase`, which installs the demo document in `shared`. A hosted test never scopes or injects a source itself; the bundle linking is in the [testing README](../../testing/apple/README.md).

Limit: a screen that reads a facade once while it is built (the camera tile grid, the guest tiles) shows a changed value the next time it is built; one that reads it inside an observed block updates in place; a frozen `static let` never updates until relaunch, which is why rule one exists.
