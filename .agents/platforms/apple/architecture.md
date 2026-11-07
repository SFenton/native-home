# Apple architecture

> **What:** how the Swift code is structured. **Read when:** adding Apple code or a shared component.

| Path | Contents |
|---|---|
| `apple/Sources/HassCore` | No UI. `Auth/` (login flow, Keychain, token manager), `Connection/` (HAKit wrapper, lifecycle), `Entities/` (`EntityState`, `EntityStore`, `EntitySnapshotCache`), `Config/` (entity IDs ported from the web; `HouseConfig`, the same house data as one document, and `HouseConfigStore`, which follows the server's copy: [connection-lifecycle](connection-lifecycle.md#house-config)) |
| `apple/Sources/HassDesign` | Tokens (`HassTokens`), `DynamicGridLayout`, `GlassTile`, MDI → SF Symbol mapping |
| `apple/Sources/HassUI` | `App/` (root, session, tabs), `Features/<Feature>/` |
| `apple/Apps/iOS`, `apple/Apps/watchOS` | App entry points |
| `apple/Tests` | SwiftPM tests for Core and Design |

Deployment: iOS/iPadOS 17, watchOS 10. Swift 6 language mode.

## Invariants

- Views never talk to HAKit. They read `EntityStore.entity(_:)` (an `@Observable` box per entity) and act through `HassConnection.callService`.
- Entity IDs live in `HassCore/Config`, ported with a citation to the web constant they came from.
- A view that shows one entity observes only that entity's box, so unrelated updates do not redraw it.

## House config facades

The app compiles in no house data (plan `build/research/house-config-runtime.md`, step 7b-2, 2026-11-06). Every house value (entity ids, rooms, people, titles, icons, colours, order) is read from the server's document through a facade on a `*Config` enum; the facades are the only place the document is read.

A facade is a computed `static var` returning `HouseConfigSource.active.read { $0.<section>.<value> } ?? <empty>`:

1. With a document it answers the document's value. `read` projects inside the lock, so it never copies the whole document.
2. With **no document** it answers an empty value: an empty string, list or map, a zero, or a placeholder with no entities (`MasterBedroom.bed(_:)` answers `BedSideConfig.unconfigured(_:)`, `MediaRemotes.sourceSelectRemote` answers `MediaRemoteConfig.unconfigured`, an unknown chores page answers an empty `Page`). Never house data. A page that depends on the layout then draws the skeleton or message of `HouseLayoutState` (there is no built-in fallback, so a device with neither a cached nor a server document sees the missing-layout states, [house-config-states](../../design/house-config-states.md)); a device with a cached or server document sees no change.
3. Call sites do not change. A list is read with `.first` or a lookup, never an index; a set of parallel values the code reads by name (garage doors, source roles) is a role-keyed map (`garageDoors["left"]`) that `HouseConfig.validateRoles()` checks at decode.

Rules:

- **No house literal in `apple/Sources`.** A new entity id, name or address in code is a `house_scan` hit (`tools/house_scan.py`; the allowlist holds only generic ids such as service names, SF Symbol names and accessibility identifiers). A fallback is empty, never a default house.
- **No `static let` that reads a facade.** It freezes the first value until relaunch. Make it a computed `static var` (`WeatherEntities.weather`, `QuickLinks.securityEntityId`, `UKSecurityChips.chips`, the vehicle tiles). The `weather/static-let-reads-house-facade` guard in `contracts/patterns.json` checks every `static let` against its `facades` map (type to names); add each new facade's names to the map.
- **No `Dictionary(uniqueKeysWithValues:)` on server data** (a repeated key traps): use `uniquingKeysWith: { first, _ in first }` (`HomeConfig.guestToggleRules`, `VacuumController.roomOrders(for:)`, `SpotlightCatalog`). The `weather/unique-keys-in-facade-files` guard flags it in files that name a facade.
- **No index subscript on a server-provided array** (`[0]`, `.first!`): the document may carry an empty list, or none. Use `.first`, a lookup or a count guard, and add a test with an empty array (`HouseholdSettingsTests.relayWarningSurvivesADocumentWithNoGuestRooms`).
- **Read through `active`**, never `shared`.

`HouseConfigSource` (HassCore) is the single accessor: `public func read<T>(_ project: (HouseConfig) -> T) -> T?`. `HouseConfigStore` pushes every accepted document into `HouseConfigSource.shared` (the app passes it; the cache copy first, `nil` at sign-out). Nothing else writes. A widget or Live Activity extension that first reads a facade calls `HouseConfigSource.shared.seed(from:for:)` with the app-group cache (future work, no caller yet); the Watch cannot read the iPhone's app-group container, so it has no house layout until it has its own source (a WatchConnectivity transfer or its own subscription). `read` is Observation-tracked, so a UIKit `updateProperties()` or `withObservationTracking` that reads a facade re-runs when the document changes.

**The document is owned by the server.** There is no compiled copy to export or to compare with: a change to the house is an edit of the document on the server (`fenton_home/house_config`), and the DEBUG `DemoHouse` (`apple/Sources/HassDemoHouse`, exported to `build/ha/demo-house.json` for the test instance) is the only document the repo carries. The shadow comparison against compiled values, the exporter and the schema 1 reader were deleted with the compiled values.

**Schema 2.** The document is `schema: 2`: residents are keyed by neutral ids (`resident_1`; one `Resident` struct, its record in `chores.people`), garage doors are role-keyed, and brand names are out of keys (`lightSync`, `consoleState`, `hasTaskForm`, `assignedTask`, `taskAssignee`, `pause`). The Music Room scripts and action graphs are `media.sourceSelect.commands` / `.actions`. Optional fields (absent means empty): each climate room's `occupiedOnlyEntityId` and each air purifier's `aqiEntityId`, `autoModeEntityId`, `fanEntityId` and `modeEntityId` (a missing occupied-only or fan id is empty: the control is not configured and the app never guesses an id from a name; the AQI, auto-mode and fan-mode ids fall back to the generic suffix names; the server document carries them all, filled once from Home Assistant's registries by `tools/house_config_patch.py`), `home.airQualityEntityId`, `home.sunEntityId`, `media.scriptPowerDevices[]` (`activeEntityId`, `onScript`, `offScript`, `symbol`) and `media.sourceSelect.remoteId` (the id of the remote the source-select roles belong to). `HouseholdAway.statusEntityId`/`commandService` read `bedroom.householdAwayEntityId`/`householdAwayScript`; `HouseholdSettingsConfig.MachE.tiles` reads `household.vehicleTiles`. `HouseConfig.decode` reads schema 2 only (`minimumSchema` is 2): every server has been re-uploaded, and the schema 1 reader that filled missing fields from compiled values went with them. The ha-fenton-home server stores any document with an integer `schema` and mapping or list sections, so it needs no change for new keys. A server value the app cannot use (a launcher that is not a plain command) leaves its tile unavailable with a telemetry line; document data never reaches a `precondition`. Gallery launch settings and the Solo Trip identifiers (`soloTrip.traveler.<resident key>`) key on the resident key, never on a server-provided id.

**Tests.** A suite that reads a facade carries `@Suite(.demoHouse)` (`HassTestSupport`), which scopes each test to `DemoHouse.source`; a test of the empty case scopes `HouseConfigSource()`. A synchronous test scopes its own source with `HouseConfigSource.$scoped.withValue(source) { … }` (task-local, parallel-safe, never touches `shared`). The scope does **not** survive a main-queue hop, a UIKit observation re-run or an `onChange` re-read, so a hosted test of a live update on a built screen must inject a source (`DemoHouseTestCase` installs the demo document in `shared` for the test).

Limit: a screen that reads a facade once while it is built (the camera tile grid, the guest tiles) shows a changed value the next time it is built; one that reads it inside an observed block updates in place; a frozen `static let` never updates until relaunch, which is why rule one exists.
