# parity_loop

> **What:** the permanent harness behind task `parity-loop`: it captures a reference and a candidate surface back to back and gates the pair. **Read when:** capturing, re-capturing or judging a parity pair. Design: `build/research/parity-loop.md` (Q3).

Python 3 standard library only. Tests: `tools/tests/test_parity_loop_*.py` (run with `tools/run_tool_tests.sh core`).

| File | Job |
|---|---|
| `surfaces.json` | Generic surface list (kinds, routes, deep links, reach steps, state tags, mask rules, `writes_on_reach`). No house data. Regenerate: `build_surfaces.py build/research/parity-loop-surfaces.json`. |
| `sidecar.py` | One sidecar per capture: simulator model, runtime build, size, scale, appearance, status-bar override, bundle hash, app build. `compare` refuses a pair on any mismatch. |
| `capture.py` | `Agent` (a bound `agent-device`), reach planning, AX normalisation and mask resolution, `capture_shot`. |
| `run.py` | Per surface: reference, candidate, reference again; then judges with `tools/expo_pair_compare.py`. Output `build/evidence/parity-loop/<run>/<surface>/`. |
| `launch.py` | `gallery` (fixture) and `live` (token launch) launches; `proxy` starts the guard proxy over TLS; `identity` resolves the session's user hash. |
| `tls.py`, `identity.py` | A throwaway self-signed certificate made at run time; `auth/current_user` through the proxy, as a hash. |
| `guard_proxy.py` | Write-guard proxy for the live reference: WebSocket and HTTP allow-lists, rejection log. |

## Running a pair

Take a `tools/devcap.py` hold on both simulators first. The agent-device commands come from `device_open`; the harness never boots a simulator.

```
python3 tools/parity_loop/run.py --mode gallery --device duo --run NAME --surfaces chores \
  --reference-udid U1 --reference-agent "<agent-device bound to U1>" \
  --candidate-udid U2 --candidate-agent "<agent-device bound to U2>"
```

`--device` picks the family table in `run.py` (`duo`, `iphone`, `ipad`: scale, pose, expected screenshot size). Verdicts: `pass`, `fail`, `drift` (the two reference shots differ by more than 0.15%, the noise floor, or in their AX tree), `statusbar`, `refused` (sidecars missing or unequal, or masks covering more than 15% of the image; exit 2), `skipped` (a write-on-reach surface with no deep link). Every row has `class: unclassified` for the judge.

## Live mode (read-only)

- Needs `PARITY_LIVE_GO=1`, a `tools/devcap.py` simulator hold (`DEVCAP_HELD`; every launch and every `run.py` run refuses without it) and an output folder git ignores (checked with `git check-ignore`; `launch.py proxy` also refuses a `--log` that git does not ignore).
- **Both** halves go through the guard proxy, served over TLS: `launch.py proxy --log RUN/proxy-rejections.jsonl` (upstream from the credentials file, loaded in a bash child) makes a throwaway name-constrained CA (critical constraint: `127.0.0.1` and `localhost` only; its key is deleted as soon as it signs the leaf) and a leaf beside the log (the same git-ignored folder, never committed), prints the CA path, and deletes the leaf key when it exits; then `launch.py live --side reference|candidate --udid U --proxy-url https://127.0.0.1:PORT --proxy-cert RUN/proxy-ca.crt`. Each live launch first runs `simctl keychain UDID add-root-cert` for that simulator (needs the simulator hold; if the app still refuses the certificate, reboot that simulator once). `run.py --mode live` takes the same `--proxy-url` and `--proxy-cert`, resolves the HA user the token belongs to (`auth/current_user` through the proxy) and records, per half (each asked as its own session), only the sha256 of its user id as `userIdHash` in that half's sidecars; two halves with different hashes are refused. `stage.py` and `identity.py` pin the proxy's leaf (`--chain`, the `proxy-chain.crt` beside the CA) because some system TLS libraries cannot evaluate the IP name constraint.
- The token is never printed, passed as an argument, logged or written to a file. It does sit in the environment of two short-lived children that `launch.py` starts through `hass_creds.sh`: the bash that runs `simctl launch`, and `stage.py` (it must authenticate to read the publication). It never enters the harness process, and the long-lived proxy is started with the token, password and username removed from its environment (it needs only the server address).
- The proxy allows only the reads the apps were observed to need, plus what the brief names. WebSocket: `auth`, `auth/current_user`, `auth/sign_path`, `camera/stream`, `ping`, `get_states`, `get_config`, `get_services`, `subscribe_events`, `subscribe_entities`, `unsubscribe_events`, and `fenton_home/house_config/subscribe`, `fenton_home/ui_publication/subscribe` and `/get`. One `call_service`: `weather.get_forecasts`, only with `return_response` exactly `true` (it returns data and changes nothing); the same service without it, any other service and `evershelf.recipe_query` (no reachable source shows it read-only) are refused. HTTP `GET`: `/api/websocket`, `/api/fenton_home/ui_assets/*` and `config`, `/api/image/serve/*`, `/api/camera_proxy*`, `/api/hls/*`, `/api/webrtc/*`, `/local/*`. `--allow-type` accepts only a fixed, vetted set of read types in code (the defaults plus `render_template`); any other name, however harmless it looks, is refused at start-up, and every other `call_service` is refused. `--allow-path` widens the HTTP reads but never to a never-allowed path (`/api/webhook`, `/api/mobile_app`, ...). Widening either set takes a reviewed code change.
- Input is judged strictly: client frames are reassembled and decoded as strict UTF-8, forwarded messages are re-serialised from what was judged, a frame that breaks the protocol closes the connection, a request path containing `%`, `//`, dot segments or odd characters is refused, only an exact `GET` passes, and override headers are dropped. Server frames are relayed whole, and refusal replies are written only between whole server messages.
- Logs record the kind, message type or method, a path template (`/api/hls/*`: the first fixed words, never an id, token or query string), the reason and, for a refused `call_service`, its domain and service; rows also pass through `tools/redact.py`. Allowed traffic is counted by type and template in `allowed-summary.json` beside the log. To bring an older log to this form: `guard_proxy.py scrub FILE...` rewrites it in place.
- The candidate is staged first (`stage.py`): the publication (`fenton_home/ui_publication/subscribe`, first event, then unsubscribe) and each asset (`GET /api/fenton_home/ui_assets/{sha256}`) are read through the proxy and written straight into the simulator container (`bootstrap.json` with the **proxy's** origin and the account only, never the real server's address, `publication.json`, `assets/<sha256>`); nothing lands in the repo. It then launches with `--server-ui-preview` and the token in `SIMCTL_CHILD_FENTON_PREVIEW_HA_TOKEN` only (`launch.py live --side candidate ... --proxy-url URL`).
- Sidecars record what was measured: the simulator's own appearance (`simctl ui appearance`), whether the screenshot was taken with the status bar normalised, and the launch arguments and environment variable *names* (never values) each half is launched with in its mode.

## Not done yet

- Scroll stops (top plus each page height) are not captured; list cells outside the viewport are missing from the AX tree.
- Whether `agent-device open <url>` opens a deep link, and whether `agent-device open` attaches after a `simctl launch` with env, are unverified on a device.
- Drift has no retry and no `unstable` verdict: a pair whose reference shots differ is reported as `drift` at once. The research plan retries up to twice first.
