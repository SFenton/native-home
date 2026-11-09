# Routing replay (tier 0 of the eval gate)

Recorded incidents of the workflow's own deterministic code paths, replayed against the current code by
`python3 tools/agent_eval.py` on every lane (`tools/lane_land.py` runs the trusted base's harness against the lane's clone, each
case in its own process, and compares with a plain run in the base; see `.agents/workflow/eval-gate.md`). No network, no key, no LLM: Jev answers are **recorded probabilities** that the real question files fold through
a fake transport, so the banding and routing logic runs for real.

Each case is `cases/<id>.json` (the `id` equals the file name):

```json
{"id": "...", "source": "what happened, with the date", "recorded": "2026-11-02", "kind": "...", "input": {}, "expect": {}}
```

`expect` maps a dotted path of the handler's observed result to a value (equality) or to `{"has": [...], "lacks": [...], "eq": v}`
(`has` is substring, membership or key; `lacks` is the opposite).

| kind | runs | input | observed |
|---|---|---|---|
| `route` | `route_rule`, `ledger_level`, `jev_level_raise` | `labels`, `title`, `body`, `nightly`, `cfg`, `jev` (id to P(yes)) | `route`, `level`, `raise`, `raise_p`, `final` |
| `gate_route` | `jev_gate.route_hint` | `visible`, `chosen`, `pick` | `route` |
| `gate_hints` | `jev_gate.hints` | `plan`, `jev` | `lines`, `text` |
| `gate_cli` | `jev_gate.py --plan-file` | `plan` (absent = missing file) | `exit`, `stdout`, `stderr` |
| `brief` | `brief.complete` lint | `brief`, `jev` (option to P(yes)) | `present`, `unsure`, `missing` |
| `digest` | `retro_digest.py` | `files` (fixture tree), `args` (`{dir}` is the tree) | `triggers`, `evidence`, `counts`, `durations` |
| `stop_hook` | `stop_continue_guard.py` | `items` (transcript), `headless`, `event` | `blocked`, `reason` |
| `merge_guard` | `merge_guard.reason` | `command`, `headless` | `blocked`, `reason` |
| `record_round` | `review/record.py` round cap | `round`, `reason`, `verdict` | `refused`, `message` |
| `lane_check` | `lane_land` `check_paths` / `check_separation` / `check_jev_thresholds` / `check_retired` | `check`, `rows` (`git diff --raw` as `[status, path, old, new]`), `blobs`, `exists` | `refused`, `kind`, `message` |

`files` values: a string is written as is, a list becomes lines (dicts as JSON), a dict becomes JSON, and
`{"$repeat": {"line": s, "n": N}}` repeats a line (a long log).

## Adding a case

1. After an incident, add `cases/<short-id>.json` with the `source` (what happened, the date) and the expected outcome of the
   code path *as it should now behave*. Prefer an existing `kind`; a new kind is a handler in `tools/agent_eval_case.py` (the shim that runs one case in its own process).
2. Run `python3 tools/agent_eval.py`: it must pass on the fix and (check by reverting the fix) fail without it.
3. Cases are append-only: a lane may add them, never edit or delete one (`lane_land` refuses it).

## Retiring a case

Only through `docs`/`.agents/workflow` rules (see the loop plan, section 8): `git mv` the case to `retired/` and add
`retired/<id>.json.reason.json` with `kind` `target_removed`, `owner_rule`, `duplicate` or `mislabel` and its evidence.
`lane_land` checks the reason; a retiring lane may not change the eval runner. Retired cases keep running as a report-only
suite (a failure is printed, never blocks) and still count in the case total, so retiring never lowers the count.
