---
name: pose-matrix
description: Run a UI change through every device pose (iPhone, Duo folded, unfolded portrait, unfolded landscape, partial fold, iPad portrait and landscape, rotate-in and rotate-out) and write the evidence pack at build/evidence/<branch>/manifest.json. Use as the Verifier, before a design verdict or a reviewer pass on any visible change.
---

# Pose matrix

> **What:** how the Verifier checks a visible change in every pose and records it as an evidence pack the Designer and Reviewer grade. **Read when:** you are the Verifier, or any change touches layout, sizing, a sheet, a split or navigation chrome ([agent-roster](../../workflow/agent-roster.md)). Spec: [testing](../../testing/apple/README.md), [devices](../../testing/apple/devices.md), [split-view](../../design/apple/split-view.md).

The owner was the QA in the UIKit port: about 15 on-device rounds, each a defect that one pose would have shown. This skill is the replacement. Check the **accessibility tree first** (cheap, exact, repeatable), then **screenshots** (what a person sees). Never judge from a screenshot alone, and never from a tree alone.

## Poses and how each is reached

Everything that boots or drives a simulator runs inside one `tools/devcap.py` hold ([capacity](../../platforms/apple/capacity.md)). `tools/ios_uitest.sh` already does; a script of yours does `python3 tools/devcap.py run --sim <UDID> -- …`. Never boot a simulator outside a hold. Launch long runs with `tools/bg_run.py LABEL -- CMD` and read the digest.

| Pose | Simulator | How it is reached |
|---|---|---|
| `iphone` | `iPhone 17 Pro` (`FENTON_SIM_IPHONE`) | `tools/ios_uitest.sh --only iphone …`. Portrait only; nothing to set |
| `ipad-portrait` | `iPad Pro 11-inch (M5)` (`FENTON_SIM_IPAD`) | `--only ipad`; portrait is the launch orientation |
| `ipad-landscape` | same | `TEST_RUNNER_FENTON_UITEST_ORIENTATION=landscape` (`JourneyTestCase` rotates with `XCUIDevice.shared.orientation = .landscapeLeft`) |
| `duo-folded` | `iPhone Duo (HASS)` (`FENTON_SIM_DUO`) | The simulator boots folded. Outer panel: `simctl io <udid> screenshot --display=primary` |
| `duo-unfolded-landscape` | same | Device Hub unfold from a fresh boot lands here. `tools/duo_pose.py --sim <UDID> --set unfolded` inside `python3 tools/devcap.py run --sim <UDID> --hold 600 --` ([devices](../../testing/apple/devices.md)). Needs the Accessibility permission, about a minute. Inner panel: `--display=primary-1` |
| `duo-unfolded-portrait` | same | From unfolded landscape: `tools/duo_pose.py --set rotate-left` (Device Hub rotate) |
| `duo-partial-fold` | same | `tools/duo_pose.py --set half` (Device Hub's Book button; `HingeState.partiallyOpen`). Inner panel lit |
| `rotate-in`, `rotate-out` | Duo and iPad | In-run: `XCUIDevice.shared.orientation`. Duo from the host: `duo_pose.py --set rotate-left\|rotate-right`. Duo folded: portrait, landscape (in), portrait (out). Open a sheet first, then rotate; the sheet must re-fit |

Rules that bite:
- **Confirm the pose** after setting it (which panel is lit and its aspect), before and after the run. `set_duo_pose` often reads "unknown" under load. Panel lit: inner on, outer dark means unfolded.
- A test that throws `XCTSkip` on the unfolded Duo hangs tear-down and the restart comes back **folded**. Run each unfolded pose with `-only-testing` for journeys that apply (no skips) and re-check the pose afterwards. Results after a `Restarting after unexpected exit` are invalid for an unfolded pose.
- Duo unfolded host captures: `--display=primary-1`; XCUIScreen returns the dark outer panel. iPad landscape host captures can come back rotated: use the `XCTAttachment` from the result bundle (`xcrun xcresulttool export attachments`).
- Slim every simulator you boot (`tools/sim_slim.sh`; the test scripts do). Never touch another lane's device or run `simctl shutdown all`.
- `tools/duo_pose.py` wraps FestivalNativeApps' `ios_sim.py pose` (path from `FENTON_FST_REPO`, default `~/repos/FestivalNativeApps`) and refuses to run outside a devcap simulator hold.

## Order of checks (per pose)

1. **Accessibility tree.** Run the journey that exercises the surface (`tools/ios_uitest.sh --quick --only <family> -only-testing:FentonHomeUITests/<Class>`; pick with `python3 tools/affected_tests.py`). Dump `app.debugDescription` or `app.snapshot()` (`JourneyTestCase` attaches it on failure; attach it on pass too). Read: names, roles, values, reading order, frames, hittability. `performAccessibilityAudit()` via `FentonHomeApp.audit` with the AX5 relaunch ([accessibility](../../testing/apple/accessibility.md)).
2. **Frame checks from the tree** (numbers, not impressions), all in the pose's window:
   - **Clipping:** every element's frame inside its container and the window; none under the Duo's vertical rail or the hinge band.
   - **Wrapping:** no label narrower than a word (one letter a line was a real defect); line count at default and AX5.
   - **Row heights:** siblings of one kind within a line of each other; unchanged between two captures with no input (rows that "fix themselves" are a layout loop).
   - **Min widths:** tiles at least 150 pt, at most four per row, leading-aligned, equal tracks.
   - **Targets:** 44 x 44 pt minimum for every control.
   - **Split-view midpoint gap:** partial fold, divider on the hinge (455.3 / 40.4 / 372.3 pt of 868 pt content); fully open, a 1 pt band at the midpoint of the window minus the trailing rail (433 / 1 / 434). No gap inside a row of one element at the midpoint.
   - **Hinge avoidance:** content clear of the band only while partly folded ([hinge-avoidance](../../patterns/hinge-avoidance.md)).
   - **Modal placement:** folded and beside a vertical hinge, full height from the bottom; unfolded landscape and partial fold, leading half (ends at hinge minus 8 pt); iPhone and portrait, content-height ([modal-sheet](../../patterns/modal-sheet.md)). Measure the sheet frame, not the window.
   - **AX5:** relaunch with `FentonHomeApp.ax5`; text grows more than 1.35x, actions stay reachable.
3. **Screenshots**, second, to catch what frames cannot (colour, material, motion end states): host capture with `TEST_RUNNER_FENTON_CAPTURE_DIR=<dir>` and `TEST_RUNNER_FENTON_REDACT_PRIVATE=1`; answer each `<name>.ready` with `xcrun simctl io <udid> screenshot [--display=…] <dir>/<name>.png`, then write `<name>.done`. For motion, capture a short sequence, not one still. Screenshots are never committed; keep them under `build/evidence/` (git-ignored).

## Evidence pack

`build/evidence/<branch>/manifest.json` (branch with `/` replaced by `-`). One entry per pose in the brief; a pose not run is `"result": "not_run"` with a reason, never absent.

```json
{
  "branch": "claude/x", "sha": "<head>", "task": "T-0142", "ran_at": "2026-11-01T18:00:00Z",
  "poses": {
    "duo-partial-fold": {
      "device": "iPhone Duo (HASS)", "udid": "<UDID>", "pose_confirmed": true,
      "screenshots": ["build/evidence/x/duo-partial-fold/home.png"],
      "ax_tree": "build/evidence/x/duo-partial-fold/home.ax.txt",
      "measurements": {"sheet_frame": [0, 0, 455, 874], "min_target_pt": 44},
      "tests": {"FentonHomeUITests/HomeJourneyTests/testX": "pass"},
      "result": "pass|fail|not_run",
      "failure_class": null,
      "notes": ""
    }
  },
  "summary": {"pass": 6, "fail": 1, "not_run": 2}
}
```

Flip ledger checks only with `python3 tools/tasks.py flip T aN --evidence build/evidence/<branch>/manifest.json`.

## Clips for the PR

The tree checks above run on **every** pose; clips are only for what a PR shows. After the after-pack is written, run `python3 tools/pr_visual.py select --branch <branch> --task <T> --round <N>`. It reads `before/` and `after/` of `build/evidence/<branch>/`, the request file and the diff, and writes `selection.json` beside them. Per device class it lists at most 3 clips and 4 before/after pairs; `needs_evidence: false` means no comment and nothing to record for that class.

**Known gap, and routing.** The Duo inner panel has no accessibility tree today (XCUITest drives only the outer panel), so its poses are `unknown` ("not compared"), never "same". A class with an uncompared pose that the diff could affect gets `needs_evidence: "unknown"` and `route: "verifier"`: `select` still lists the before and after screenshot pairs, and the Verifier looks at them and decides. Nothing is silently "no comment".

**Departure from K.2 rule 3.** Transition code widens the candidates to every edge of a class only when no changed pose and no named motion already gives an edge; otherwise the changed-pose edges stand for the transition code. Why: it reproduces K.4 (PR 275: one flat → half open → flat clip, the rest listed as checked) instead of filling the budget with unrelated edges; `pr.motion_is_point` is shadow, so nothing better can rank them yet.

Record **only the chosen clips**, inside a `devcap.py` hold, with the pose set as in the table above:

1. `xcrun simctl io <udid> recordVideo --codec=h264 <name>.mov` (background process; stop it with SIGINT). Duo inner panel: add `--display=primary-1`.
2. Round trip, one clip per edge, 8 to 12 seconds: start in the first pose, move to the second, come back, hold one second. Split the directions only when `selection.json` lists a `forward` and a `reverse` clip.
3. Shrink under 8 MB with `avconvert --preset PresetMediumQuality --source <name>.mov --output <name>.mp4` (no ffmpeg on this host); check the size with `ls -l` and use `PresetLowQuality` if it is over.
4. Put the path in the clip's `path` in `selection.json`; `pr_visual.py render` embeds it. Clips and screenshots stay under `build/evidence/` (ignored by version control).

## Failure classes

- **`real`:** the app is wrong in that pose (a frame, wrap, target, placement or tree defect, or a crash in the app's own code). Report it; the Coder fixes it.
- **`infra`:** the harness failed, not the app: devcap wait (exit 75) or hold timeout (124), `backboardd` crash, `INFRA hung` (125/126), a simulator that came back in the wrong pose, a pose the tool could not set, `no tests executed`. Fix the setup, **re-run once**, and mark `infra` if it fails again; two infra failures stop the loop (report as infra, [agent-roster](../../workflow/agent-roster.md)).
- **`known-flaky`:** a failure that a doc already names as a known race ([journey health rules](../../testing/apple/README.md), [devices](../../testing/apple/devices.md)), or one that failed and then passed on a source-identical rerun of the same sha. Cite the doc line or the two run ids. There is no flaky registry yet; do not invent one. A flaky audit passing once is not certification; the identical rerun must pass too.

Re-run a journey that died or failed oddly before calling it `real`.

## Hard limits

- **Physical Duo: Release installs only, no automation, ever.** Build Release, install, tell the owner. No XCUITest, no capture driving, no taps.
- **iPhone 18 Pro: only with the owner's approval for this run.** Ask in the thread; an earlier approval does not carry over.
- Credentials come from `--env shell` ([devices](../../testing/apple/devices.md)); never print, log or commit them.
- Do not edit `apple/` while an `xcodebuild test-without-building` run is going. Kill only PIDs you started.
