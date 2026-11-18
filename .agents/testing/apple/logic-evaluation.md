# Logic evaluation

> **What:** what authored logic (a node's `visibleWhen`, rules, badges and text expressions, a tab's badge and visibility) costs the main thread: the counters, the worst-case scenarios and the budgets. **Read when:** changing how logic is evaluated, observed or cached, or the live-update path. The scroll-cost run: [performance](performance.md).

Every evaluation runs inside an observation of the entity boxes it read, so an update runs only the evaluations that read the changed entity.

- **Counters** (`HassTelemetry.LogicCost`, on the scroll-cost line beside the `entity.*` counters):
  - `logic.runs`: evaluations, the first run of an observation and each re-run.
  - `logic.runUs`: their wall time in microseconds; each also has a `LogicRun` signpost.
  - `logic.skippedEqual`: evaluations whose result equalled the one shown, so no view was written (a node's `visibleWhen`, a node badge, a tab badge and a tab rule).
  - An idle page runs nothing, so the counters cost nothing there. A bag of observations counts only with `UKObservationBag.evaluatesAuthoredLogic` set; set it on any new bag that evaluates authored logic.
  - The counters are process-wide. A renderer also keeps its own `LogicCost.Tally` (`bindings.logicTally`), which only its nodes, tab observations and shared values add to.
  - A hosted test that asserts an exact count reads the tally. A bag that evaluates authored logic gets `logicTally` set; a `DerivedValue` or `SharedLogic` made for a renderer takes its tally.
- **Scenarios** (`LogicWorstCasePerformanceTests`, each on iPhone, iPhone Duo and iPad, fixtures with invented ids):
  - whole-house replay;
  - a 50-box burst;
  - attribute churn on an entity many nodes read for `state`;
  - a large count read in many places, written as `math add` over `choose` and as the one `count` operand;
  - viewer predicates in a large house;
  - every tab loaded;
  - a `choose` that flips on every update;
  - a minute tick inside a burst;
  - one template expanded ten times.
- **Counting many entities (`sh.count@1`):**
  - `ServerUIOperand.count` is one node whatever the number of entities: up to 32 entries, each a condition (`ServerUIPredicate`) and an optional list of `person.*` ids the entry counts for.
  - Entries are read in order, **one tracked read per entry**, with no pattern match. The person filter compares strings and asks for the viewer once. A tree that reads three or more sources is one shared value (`isWorthSharing`).
  - An entry whose answer is unknown (no state, loading, text where a number is wanted) is skipped, and the count goes on.
  - Only when every entry in play is unknown is the count `loading` (any read of any kind was "not yet") or `unavailable`.
  - An entry the viewer is not in is never read. A count with none in play is 0.
  - Never in a flow (`invalid_combination`); evaluated there it is a gap. The Studio's answers are the `count-operand-*` evaluation corpus; the native tests are `ServerUICountTests` and `ServerUICountHostedTests`.
  - Scenarios `LW-d3-count-operand-single` and `LW-d4-count-operand-all` run the real operand beside the expanded `math add` over `choose` of `LW-d1` and `LW-d2`.
- **Budgets:** p95 run-loop turn at most 8 ms and none over 16 ms in every scenario; a standing-still page's update work (logic plus store apply) at most 25 ms in 8 s. A scenario `main` misses is an expected failure naming it (`knownBreaches`); never loosen a budget.
- **Pruning:** a run that finds a listed scenario inside budget prints `UNDER BUDGET on <family>` and writes it to the rows file. Delete the entry only when every family stays inside budget on two runs.
- **Run it:** the suite skips unless `TEST_RUNNER_FENTON_PERF_ON_SIMULATOR=1` and wants a 1-minute load under 40: each row records the load at start, and a run above 40 prints `LOAD OVER 40` and is not a baseline. One hosted run per family with `FENTON_HOSTED_FILTER=LogicWorstCasePerformanceTests`; `TEST_RUNNER_FENTON_LOGICPERF_FILE` collects the rows.
- **Correctness tests** (`ServerUILogicEvaluationTests`, `ServerUILogicCountersHostedTests`) run everywhere: an entity no evaluation reads runs nothing, an equal result writes no view, a `choose` that flips reads the new branch, and a sum runs once per turn.
- **Harness:**
  - The driver lays out the window and lets the run loop idle before it meters, so a hosted window's first frame is not charged to a scenario.
  - Each row prints `turns`, `over8` and `over16`; `LOGICPERF_TURNS` names the step and turn of each turn over 8 ms.
  - p95 is over every turn in the window, idle ones included, so read it with `turns`. The longest turn and `over16` are the stricter check.
  - A step slow only the first time is a cold cost, not noise.
- **Rules:**
  - A change to one entity runs only the evaluations that read it.
  - A page that is away rests: see [resting while away](../../patterns/derived-value.md).
  - A burst is one run per evaluation per turn.
  - No evaluation scans the house; a read costs what it names, not the entity count.
  - A new scenario or counter extends this suite under the same budgets.
- **Shared and cached work:** a `DerivedValue` run counts in `logic.runs` and `logic.runUs`, an equal result in `logic.skippedEqual`. The rules (what is shared, when, and the viewer and id caches) are in [derived-value](../../patterns/derived-value.md).
