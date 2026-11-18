# Logic evaluation

> **What:** what authored logic (a node's `visibleWhen`, rules, badges and text expressions, a tab's badge and visibility) costs the main thread: the counters, the worst-case scenarios and the budgets. **Read when:** changing how logic is evaluated, observed or cached, or the live-update path. The scroll-cost run: [performance](performance.md).

Every evaluation runs inside an observation of the entity boxes it read, so an update runs only the evaluations that read the changed entity.

- **Counters** (`HassTelemetry.LogicCost`, on the scroll-cost line beside the `entity.*` counters):
  - `logic.runs`: evaluations, the first run of an observation and each re-run.
  - `logic.runUs`: their wall time in microseconds; each also has a `LogicRun` signpost.
  - `logic.skippedEqual`: evaluations whose result equalled the one shown, so no view was written (a node's `visibleWhen`, a node badge, a tab badge and a tab rule).
  - An idle page runs nothing, so the counters cost nothing there. A bag of observations counts only with `UKObservationBag.evaluatesAuthoredLogic` set; set it on any new bag that evaluates authored logic.
- **Scenarios** (`LogicWorstCasePerformanceTests`, each on iPhone, iPhone Duo and iPad, fixtures with invented ids):
  - whole-house replay;
  - a 50-box burst;
  - attribute churn on an entity many nodes read for `state`;
  - a large count read in many places;
  - viewer predicates in a large house;
  - every tab loaded;
  - a `choose` that flips on every update;
  - a minute tick inside a burst;
  - one template expanded ten times.
- **Budgets:** p95 run-loop turn at most 8 ms and none over 16 ms in every scenario; a standing-still page's update work (logic plus store apply) at most 25 ms in 8 s. A scenario `main` misses is an expected failure naming it (`knownBreaches`); never loosen a budget.
- **Pruning:** a run that finds a listed scenario inside budget prints `UNDER BUDGET on <family>` and writes it to the rows file. Delete the entry only when every family stays inside budget on two runs.
- **Run it:** the suite skips unless `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1` and wants a 1-minute load under 40: each row records the load at start, and a run above 40 prints `LOAD OVER 40` and is not a baseline. One hosted run per family with `FENTON_HOSTED_FILTER=LogicWorstCasePerformanceTests`; `TEST_RUNNER_FENTON_LOGICPERF_FILE` collects the rows.
- **Correctness tests** (`ServerUILogicEvaluationTests`, `ServerUILogicCountersHostedTests`) run everywhere: an entity no evaluation reads runs nothing, an equal result writes no view, a `choose` that flips reads the new branch, and a sum runs once per turn.
- **Rules:**
  - A change to one entity runs only the evaluations that read it.
  - A burst is one run per evaluation per turn.
  - No evaluation scans the house; a read costs what it names, not the entity count.
  - A new scenario or counter extends this suite under the same budgets.
- **Shared and cached work** (pattern: [derived-value](../../patterns/derived-value.md)):
  - A `DerivedValue` evaluates cross-entity logic once for the session and wakes its readers only when the result differs. Shared: the Profile attention count (every page that draws the header), a status source's projection, a todo-counts source's words, and every identical authored text or badge expression that reads no cell, flow or clock (ten copies of one count are one value).
  - A derived run counts in `logic.runs` and `logic.runUs`; one that finds the same result counts in `logic.skippedEqual` and wakes no node.
  - The viewer's person is found once per user and people revision (`PersonLookup`, `EntityStore.peopleRevision`, which moves when a person is added, removed or points at another user); a viewer read does not scan the house.
  - The entity id grammar is matched once per string (`EntityIDCache`): a literal id costs a dictionary hit.
