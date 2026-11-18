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
- **Pruning:** a run that finds a listed scenario inside budget prints `UNDER BUDGET: prune knownBreaches[<scenario>]` and writes it to the rows file; delete the entry.
- **Run it:** the suite skips unless `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1` and wants a 1-minute load under 40: each row records the load at start, and a run above 40 prints `LOAD OVER 40` and is not a baseline. One hosted run per family with `FENTON_HOSTED_FILTER=LogicWorstCasePerformanceTests`; `TEST_RUNNER_FENTON_LOGICPERF_FILE` collects the rows.
- **Correctness tests** (`ServerUILogicEvaluationTests`, `ServerUILogicCountersHostedTests`) run everywhere: an entity no evaluation reads runs nothing, an equal result writes no view, a `choose` that flips reads the new branch, and a sum runs once per turn.
- **Rules:**
  - A change to one entity runs only the evaluations that read it.
  - A burst is one run per evaluation per turn.
  - No evaluation scans the house; a read costs what it names, not the entity count.
  - A new scenario or counter extends this suite under the same budgets.
