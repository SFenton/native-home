# state_space

> **What:** the state space of every tile kind, the golden answers of the frozen old app over it, and the lint that finds authoring gaps. Task `parity-loop`, check `pl-states`. **Read when:** adding a tile kind or a state, refreshing the Home Assistant states, or running the mapping lint on a publication. Design: `build/research/parity-state-sweep.md`.

Python 3 standard library only. Tests: `tools/tests/test_state_space_*.py`, `test_state_golden.py` (`tools/run_tool_tests.sh core`); the Swift side is `StateGoldenTests` in `HassCoreTests`.

| File | Job |
|---|---|
| `kinds.json` | The one hand-kept registry: per tile kind its node types, entity domain, state sets, variants and evaluator. A native node type neither registered nor listed in `node_types_unregistered` fails `test_state_space_registry.py`. |
| `ha-states-<tag>.json` | The closed state sets read from a pinned Home Assistant core tag (`generate.py ha-diff OLD NEW` lists what a newer tag adds, as unreviewed rows). |
| `observed-text.json` | Generic placeholders for the free-text helpers. The real observed values are house data: keep that file under `build/state-space/` (git-ignored), strings only, and pass `--observed` with `--out` elsewhere. |
| `generate.py` | Writes `apple/Tests/HassCoreTests/StateGolden/state-space.json`; `--check` fails when it is stale. |
| `lint.py` | `empty-map`, `partial-map`, `reachable-fallback`, `unread-helper` over a publication passed as a path. Its report holds counts and a table by node type and kind, never ids. |

The golden is built by `tools/state_golden/generate.py` (it exports the pin with `git archive` into a temp directory and builds only the old `HassCore`; nothing of it is committed). `StateGolden/expected-failures.json` lists every difference between the golden and the current code with a class (`native`, `config`, `studio`, `fixture`) and a reason; the suite fails on an unlisted difference and on a stale entry.

Run the lint over a layout: `python3 tools/state_space/lint.py PATH --report build/evidence/parity-loop/state-lint.md`. The layout of a house is house data: run it over a git-ignored copy and never commit the input or `--details` output.
