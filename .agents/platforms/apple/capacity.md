# Simulator and build capacity

> **What:** how lanes share the Mac's simulators, devices and compile capacity. **Read when:** booting a simulator, driving a device, or running a heavy build or test.

Many lanes (this repo's and FestivalNativeApps') run on one Mac. Every simulator, physical device and heavy compile goes through `tools/devcap.py`, which hands out machine-wide slots first come, first served. When the Mac is full a lane waits its turn instead of booting another simulator.

`tools/devcap.py` is vendored byte for byte from `SFenton/FestivalNativeApps` `tools/devcap.py` (canonical copy, with `tools/tests/test_devcap.py`). Change it there first, then copy both files here; `python3 tools/devcap.py --version` must match. Worktrees keep the copy they branched with, so every copy from 1.2.1 on defers to the shared install at `~/.devcap/lib/devcap.py` when it is newer; after a devcap change merges, run `python3 tools/devcap.py install` once from an up-to-date FestivalNativeApps default-branch (`primary`) checkout, and only after both the FestivalNativeApps and the Fenton change have merged. **Deletion goes live at install**, not at merge: every copy on the Mac defers to the installed one. A worktree with a copy older than 1.2.1 (or none) must rebase on `main`.

## Gates

| Gate | Slots | Taken by |
|---|---|---|
| `device-<UDID>` | 1 | `--sim UDID` or `--device UDID`: one lane per simulator or physical device |
| `simulator` | RAM / 16 GB, 1–6 (4 on the MacBook; owner asked for more parallel lanes, 2026-10-15; 1 on the Mac mini) | `--sim UDID`: one per simulator in use |
| `build` | cores / 4, 1–4 (2 on the MacBook; 1 on the Mac mini, set in its `config.json` because two compiles swap on 8 GB) | `--pool build`: `xcodebuild build-for-testing`, `swift build`/`swift test` |

Override a count with `DEVCAP_SLOTS_SIMULATOR=2` or `~/.devcap/config.json` (`{"simulator": 2}`); lowering it only affects new holders. Slots are per machine: the Mac mini (`<ci-host>`, the `host` CI runner) has its own `~/.devcap` and does not share holds with the MacBook ([ci](../../workflow/ci.md#rules-for-workflows)).

## Commands

```bash
# Run anything that boots or drives a simulator (device gate + simulator slot):
python3 tools/devcap.py run --sim "$UDID" --shutdown-on-timeout --purpose "rooms captures iphone" -- <command> [args...]

# Heavy compile:
python3 tools/devcap.py run --pool build --purpose "rooms build" -- xcodebuild build-for-testing ...

# Who holds what, and who is waiting:
python3 tools/devcap.py status
```

- `tools/ios_uitest.sh` already compiles once under `build` and runs each family under `--sim`; `tools/apple_coverage.sh` is host-only: it takes the `build` and `swift-test` holds and no simulator. Do not wrap them again (it is harmless: nested calls reuse the parent's gates through `DEVCAP_HELD`).
- Put the whole simulator sequence in one hold: boot, pose (Device Hub), install, run, capture. Leave the simulator warm between consecutive runs on the same device instead of shutting it down each time: a warm simulator counts against the slots, and devcap shuts it down after 60 s idle when another lane is waiting (5 min otherwise). `tools/ios_uitest.sh` does this with `--shutdown-on-timeout` for filtered runs (a hung run still shuts down) and shuts down after a full-suite run; pass `--shutdown`, or `FENTON_SHUTDOWN_SIM=1` for the script, on your last filtered run with a device.
- Simulators booted outside a hold are **unmanaged**: they count against the `simulator` slots, and after 5 minutes unmanaged the next waiter or finished hold shuts them down and closes Device Hub windows of devices nobody is using, including stale "Devices – No Selection" windows (owner decision, 2026-10-13). Simulators under Xcode's debugger are never shut down. So never boot or drive a simulator outside a hold; a direct `simctl boot` or `xcodebuild test` is shut down after 5 minutes. `python3 tools/devcap.py status` lists unmanaged simulators, and `python3 tools/devcap.py reap [--dry-run]` sweeps on demand. `DEVCAP_REAP_GRACE=off` or `DEVCAP_HUB=off` turn the sweeps off.
- Hold limits: `run` holds for 1800 s by default (`--hold`, `0` = no limit, max 7200; `tools/ios_uitest.sh` uses `FENTON_DEVCAP_HOLD`, default 3600). On overrun devcap kills the command's process group and exits 124. A wait gives up after `--wait` seconds (3600) with exit 75.
- Never hold `build` while waiting for a simulator (or the reverse) in separate calls; one `run` with every gate takes them in a fixed order and cannot deadlock.
- A dead holder's slot frees itself (the OS drops the lock). `~/.devcap/devcap.log` records every wait, acquire and release with the purpose and worktree.
- `tools/ios_uitest.sh` draws each family from a pool of identical simulators (`"iPad Pro 11-inch (M5)"`, `"… (pool 2)"`, …, one per simulator slot; `FENTON_SIM_POOL` overrides) through `python3 tools/devcap.py pick-sim`, so two lanes testing the iPad run on two iPads. A lane keeps its last pool member (warm, Duo pose intact) while it is free. Set `FENTON_SIM_IPHONE` / `FENTON_SIM_DUO` / `FENTON_SIM_IPAD` only to pin one specific device. Never `simctl shutdown all`, erase or reset another lane's device. **Bad members:** a simulator that fails `sim_healthy` twice (bootstatus or screenshot) is recorded in `apple/.build/sim-bad/<udid>` for 6 h and is never written as the lane's warm `uitest-FAMILY.udid`; the pick goes through `tools/sim_bad.py pick` (this repo's wrapper over devcap `pick-sim`, which is vendored and unchanged), skips recorded members, and when every member is bad prints `INFRA: pool exhausted (<n> bad, disk <pct>% used)` and exits 126. A record clears when the simulator next passes `sim_healthy`, after 6 h, or with `python3 tools/sim_bad.py clear [UDID]` (no UDID clears all); freeing disk does not clear it, so run `clear` after the fix. `sim_bad.py list` shows the live records. The list is per worktree (`apple/.build`), so a new lane re-learns a dead member; each pick still refreshes a bad member's idle timer (devcap's own), so the idle reaper may not delete it until the record expires. Upstream ask for FestivalNativeApps: `devcap pick-sim --skip UDID` and the same exhausted line.
- **Slim every simulator you drive** ([below](#slim-simulators)): `tools/ios_uitest.sh`, `ios_navperf.sh`, `ios_scrollcost.sh` and `ios_launchperf.sh` already call `tools/sim_slim.sh` inside the hold. A script of your own that boots a simulator does the same, right after the boot and before the app launches.
- **Never `pkill` or `killall` by pattern** (`ios_uitest.sh`, `xcodebuild test-without-building`, `bash -c`): every lane's journeys run the same commands, so a pattern kills their runs too (2026-10-17: the motion lane's pattern kills ended other lanes' runs mid-test, which read as odd failures and `BUILD INTERRUPTED`). Stop only the PIDs you started yourself (`$!` of the background command, or the `pid` `python3 tools/devcap.py status` shows for your own worktree), and re-run a journey that died or failed oddly before counting it as a failure.
- A run that gives up on a slot (`devcap: gave up waiting 1h00m`) executes nothing and still exits: read each shard's log for `Test Suite 'Selected tests' passed|failed` before trusting its pass count, and retry a shard that never ran (the journey-health runner retries up to six times).

## Simulator lifecycle (devcap 1.5.0)

devcap itself creates, resets and deletes pool simulators (owner-approved 2026-11-04; canonical docs in FestivalNativeApps `capacity.md`). It creates members with the base device's type (an iPhone Duo stays a Duo) and tags them with the project in `~/.devcap/sims.json`; the first hold slims a new member with simslim 0.14 or later (`simslim on` boots the simulator, so never outside a hold); `run --sim … --shutdown` (or `--shutdown-on-timeout` after a hold timeout) deletes a poster store over 4 GB and runs `simslim disk-clean --categories caches,logs,temporary` while the device gate is held; `devcap reap` (the nightly runs it) deletes this project's pool simulators idle more than 24 h, after re-checking under the gate; `run --ephemeral-sim "<base name>"` makes a job-scoped simulator and deletes it at the end, on a signal, or on a wait timeout; `devcap status` shows pool size (`--disk` for the whole Mac). `tools/tests/test_devcap_vendored.py` pins the canonical hash, so a hand edit of the vendored copy fails.

**Deleting shut-down, unheld simulators and their data is autonomous (owner decision, 2026-11-04): agents do it without asking the owner.** A booted or held simulator, any device devcap did not make for this project (base devices, the other repository's members, untagged legacy `(pool N)` simulators) is never deleted. `~/.devcap` is shared, so each repository's `reap` sees only its own project's records. `ci_hygiene.py preflight` follows the same rule: it deletes only idle `(pool N)` simulators that `sims.json` tags with this project (untagged legacy members and the other repository's are left alone).

## Disk reaper

Pool simulators and worktrees fill the disk, so the CI pre-flight (`python3 tools/ci_hygiene.py preflight`) reaps when free space is under 30 GB: merged worktrees (`prune-worktrees`), then idle pool simulators, old results and orphaned DerivedData ([ci](../../workflow/ci.md#rules-for-workflows)). For capacity this means:

- A simulator is reaped only when it is a `(pool N)` member that devcap's `sims.json` registry names as created by devcap (kind pool or ephemeral), is shut down, and its `device-<udid>` gate has no holder and no waiter. Hold a device (`devcap.py run --sim`) for as long as you rely on its state; a warm but unheld, shut-down pool member can be deleted between runs and `pick-sim` recreates it stock (and un-slimmed, so `sim_slim.sh` runs again in your hold). Nothing is ever erased automatically.
- A worktree is reaped only when a devcap holder's `cwd` is not inside it, so run long jobs through `devcap.py run` from the worktree they belong to. Merged (including squash-merged), clean, idle (3 days), unlocked and without a `build/handoff/*.md` are also required; `git worktree lock` a lane you want kept. Removal deletes ignored files in it.
- It prunes the primary clone configured in `FENTON_PRIMARY_REPO` or `~/.config/fenton-hass/primary_repo` (owner-created, once per Mac), not the runner's own clone. `python3 tools/ci_hygiene.py prune-worktrees --dry-run` lists what would go. Do not run it for real by hand on a shared Mac without the owner.

## Slim simulators

> **Why:** simslim's README measures a stock iOS simulator at ~258 processes and ~4.0 GB (phys_footprint, iOS 26 on an M1 Pro); slimmed with `ui.json` an iPhone 17 Pro on iOS 27.0 here settles at 85 processes and ~0.66 GB (`ui-lean.json`: 82 and ~0.60 GB). Slim simulators are what lets more lanes share the `simulator` slots (owner, 2026-10-25).

[simslim](https://github.com/MobAI-App/simslim) (`brew install mobai-app/tap/simslim`, 0.12.2 installed on the Mac) disables launchd daemons per simulator with overrides that are stored on the device, so a pool member stays slim across shutdowns. `tools/sim_slim.sh [--lean] UDID` applies a committed profile and is idempotent: a simulator already in the profile costs one `simslim verify` (about 3 s), a stock one about 90 s the first time.

| Profile | Keeps on | Use |
|---|---|---|
| `tools/simslim/ui.json` (default) | push (`apsd`), Photos (feedback attachments), App Intents (`linkd`), widgets and Live Activities | every journey, including a full suite |
| `tools/simslim/ui-lean.json` (`--lean`, `FENTON_SIM_LEAN=1`) | the same minus widgets / Live Activities | filtered runs that touch no `LiveActivity`, `Widget` or `Push` journey |

Rules:

- **Slim inside the hold, after the boot.** `sim_slim.sh` needs a booted simulator (it boots it) and a device gate. Never run `simslim` on a UDID you do not hold, and never on another lane's device.
- **Never `simslim off`, `erase` or `delete` a pool member** another lane may use. A new pool member (`devcap.py pick-sim` creates them stock) is slimmed by the first `sim_slim.sh` run in its hold; overrides do not survive `simctl clone` either.
- **Going lean is live, going back costs a reboot.** simslim 0.12.2 can only move toward more-disabled without a reboot, so `ui-lean.json` → `ui.json` runs `simslim on` (reboot). That drops an unfolded iPhone Duo pose: set the Duo pose after the switch, and keep a Duo on one profile.
- **Need a feature that is off?** Add its category to `except` (or a daemon to `keep`) in `tools/simslim/ui.json`, run `simslim doctor <UDID> --requires <feature>` to prove it, and say why in the commit. `simslim doctor --list` names the features; `simslim profiles <category>` lists the daemons. Do not edit the profile to make one failing test pass: find which daemon the app really needs.
- **Opt out for one run:** `FENTON_SIM_SLIM=0` skips slimming. It does not un-slim a device that was slimmed before (the overrides are stored); `simslim off <UDID>` inside a hold does, and costs a reboot.
- **Perf baselines.** Slim simulators have less background noise and more headroom than the stock ones the baselines in [performance](../../testing/apple/performance.md) were taken on; compare a run against a baseline taken the same way, and retake a baseline when you change the profile.
- `simslim list --booted` shows the slim count per booted simulator (`158/168 slim`); `simslim measure <UDID>` its memory. A booted simulator at `0/168 slim` in `tools/devcap.py status` is stock: some lane booted it outside `sim_slim.sh`.
- A missing `simslim` degrades to a stock simulator with a warning (`sim_slim.sh` exit 3, "left stock"; 0 is slimmed, 1 a hard failure); it never fails a run, and every simslim and boot step runs under an `xc_watch` wall. On a GitHub-hosted runner (`FENTON_CI_HOSTED=1`) the macOS job installs the pinned simslim and slims each device, a measured trial ([ci](../../workflow/ci.md)).

Never kill shared processes: no `killall`, no unscoped `pkill -f` (it also hits other sessions and the Actions runner, which cost a swift-test job on 2026-10-30), no `simctl shutdown all`. Kill by PID you started or `pkill -f` a path under your worktree; the `kill_guard` hook enforces it ([pr-lifecycle](../../workflow/pr-lifecycle.md)).

## Changing the shared tools

devcap, slim, duo-pose and the pose code are owned by the private shared simulator-tools repo, which S+H and Festival Native Apps share. The copy of `tools/devcap.py` in this repo is vendored (until it is replaced by the pinned install) and is not edited for a shared-tool change here.

- To change them, write a spec file (objective, the CLI the app needs, acceptance, call sites here) and run the shared simulator-tools repo's `tools/delegate.sh --from fenton --title "<title>" --spec spec.md`. It opens an issue in the shared simulator-tools repo and starts its orchestrator; it prints `delegated shared-tools#N`. `--dry-run` shows what it would do.
- The app task then ends `blocked` with `blocked_reason: "waiting on shared-tools#N"`. It does not poll the issue or the status file.
- The result comes back as a release and a pin-bump PR in this repo; until releases are enabled the issue is closed with `merged, release pending (owner)` and the owner releases. The follow-up (switching a script to a new flag) is a new task from that PR. Details: the shared simulator-tools repo's `.agents/workflow/delegation.md`.
