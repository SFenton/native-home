# Derived value

> **What:** logic that reads several entities and is used in more than one place is evaluated once for the session and wakes its readers only when its result changes. **Read when:** adding a count, sum or status over many entities, an authored expression that Studio expands into copies, or anything a header, tab and page all show.

- **Component:** `DerivedValue` (`HassCore/Derived/DerivedValue.swift`), `DerivedValues` (the keyed set, `DerivedValues.swift`) and `DerivedReaders` (what holds a value alive, `DerivedReaders.swift`). Observation only, no UI: it sits below `HassUI` and over values. Web source: none (the web re-selects per consumer, `useDailyReportContext`; native has Observation).
- **Behavior:**
  - `DerivedValue(read)` runs `read` now, follows exactly the boxes it reads (re-recorded on every run, so a branch that flips follows the new inputs) and keeps the result in `current`.
  - Readers read `current` inside their own observation. A change to an input runs `read` once per turn, however many inputs moved or readers there are, and writes `current` only when the result differs; an input that leaves the sum equal wakes no one (`logic.skippedEqual`).
  - A change marks the value dirty at once and `current` runs a dirty value before it answers, so a reader awake in the same turn never sees the old result.
- **Key and scope:**
  - Native logic is keyed by what it is: the Profile attention count is one value in `UKServerUIProductionProviders`; a status source's projection and a todo-counts source's words are keyed by source, the publication's sources (a changed source is a new key) and whether screenshots redact.
  - Authored logic is keyed by its operand tree, which is `Hashable`: ten copies of one count are one value. `ServerUIOperand.isWorthSharing` says which.
    - A worthwhile tree reads three or more sources (below that the extra run costs more than it saves) and nothing of where it sits.
    - A repeat cell's `item` and `index`, a flow's `param`, an action's `control` and the clock are evaluated where they are used (the clock's tick starts and stops with the node and its page).
- **Lifetime:** `DerivedValues` holds its entries weakly. `UKObservationBag` runs each observation inside a `DerivedReaders`, which holds what that run read until the observation's next run, so a value ends with its last reader and a closed page's expression stops running. A value an owner stores (the attention count) lives as long as the owner.
- **Reading, never scanning:** an input is a box (`store.entity(id).state`), the people revision or another derived value, never `store.allValues`. The viewer's person is found once per user and people revision (`PersonLookup`); the entity id grammar is matched once per string (`EntityIDCache`).
- **Rules:** a new shared count or sum is a `DerivedValue`, not a copy in each view. Do not read the clock or `.now` inside one unless the clock is tracked. Counters: a derived run counts in `logic.runs` and `logic.runUs`, an equal result in `logic.skippedEqual` ([logic evaluation](../testing/apple/logic-evaluation.md)).
- **Tests:** `Tests/HassCoreTests/DerivedValueTests.swift`, `PersonLookupTests.swift`, `EntityIDCacheTests.swift`; hosted `ServerUILogicCountersHostedTests` and `LogicWorstCasePerformanceTests` (apple/Apps/iOSTests).
