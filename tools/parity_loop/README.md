# parity_loop

> **What:** the permanent harness behind task `parity-loop`: it captures a reference and a candidate surface back to back and gates the pair. **Read when:** capturing, re-capturing or judging a parity pair. Design: `build/research/parity-loop.md` (Q3).

Python 3 standard library only. Tests: `tools/tests/test_parity_loop_*.py` (run with `tools/run_tool_tests.sh core`).

| File | Job |
|---|---|
| `surfaces.json` | Generic surface list (kinds, routes, deep links, reach steps, state tags, mask rules, `writes_on_reach`). No house data. Regenerate: `build_surfaces.py build/research/parity-loop-surfaces.json`. |
| `sidecar.py` | One sidecar per capture: simulator model, runtime build, size, scale, appearance, status-bar override, bundle hash, app build. `compare` refuses a pair on any mismatch. |
| `capture.py` | `Agent` (a bound `agent-device`), reach planning, AX normalisation and mask resolution, `capture_shot`. |
| `run.py` | Per surface: reference, candidate, reference again; then judges with `tools/expo_pair_compare.py`. Output `build/evidence/parity-loop/<run>/<surface>/`. |
| `launch.py` | `gallery` (fixture) and `live` (token launch) launches; `proxy` starts the guard proxy. |
| `guard_proxy.py` | Write-guard proxy for the live reference: WebSocket and HTTP allow-lists, rejection log. |

## Running a pair

Take a `tools/devcap.py` hold on both simulators first. The agent-device commands come from `device_open`; the harness never boots a simulator.

```
python3 tools/parity_loop/run.py --mode gallery --device duo --run NAME --surfaces chores \
  --reference-udid U1 --reference-agent "<agent-device bound to U1>" \
  --candidate-udid U2 --candidate-agent "<agent-device bound to U2>"
```

`--device` picks the family table in `run.py` (`duo`, `iphone`, `ipad`: scale, pose, expected screenshot size). Verdicts: `pass`, `fail`, `drift` (the two reference shots differ over the gate), `statusbar`, `refused` (sidecars missing or unequal; exit 2), `skipped` (a write-on-reach surface with no deep link). Every row has `class: unclassified` for the judge.

## Live mode (read-only)

- Needs `PARITY_LIVE_GO=1` and an output folder git ignores (checked with `git check-ignore`).
- The reference is launched only through the guard proxy: `launch.py proxy --log RUN/proxy-rejections.jsonl` (upstream from the credentials file, loaded in a bash child), then `launch.py live --side reference --udid U --proxy-url URL`. The token never enters Python, an argument, a log or a file.
- The proxy allows WebSocket `auth`, `auth/sign_path`, `camera/stream`, `ping`, `get_states`, `get_config`, `get_services`, `subscribe_events`, `subscribe_entities`, `render_template`, registry and list reads, and `fenton_home/*` `/subscribe`, `/get`, `/list`; HTTP `GET` on a short read allow-list (including `/api/image/serve/*` and `/api/camera_proxy*`). `call_service`, `mobile_app` registration, webhooks and every non-GET are refused and logged (kind, type, path without query; for `call_service` also domain and service; never a body, service data or target). Allowed traffic is counted by type in `allowed-summary.json` beside the log.
- The candidate's read-only live preview needs a one-time credential file, which would write the token to disk. `launch_live` refuses it until the owner allows that.

## Not done yet

- Scroll stops (top plus each page height) are not captured; list cells outside the viewport are missing from the AX tree.
- Whether `agent-device open <url>` opens a deep link, and whether `agent-device open` attaches after a `simctl launch` with env, are unverified on a device.
