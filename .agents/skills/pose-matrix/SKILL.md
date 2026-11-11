---
name: pose-matrix
description: Runs a UI change through every device pose and writes the evidence pack at build/evidence/<branch>/manifest.json. Use as the Verifier, before a design verdict or a review of any visible change.
---
# Pose matrix

> **What:** how the Verifier checks a visible change in every pose and records the evidence pack. **Read when:** a change touches layout, sizing, a sheet, a split or navigation chrome. Reference: [devices](../../testing/apple/devices.md), [capacity](../../platforms/apple/capacity.md).

## Poses

Everything that drives a simulator runs inside one `tools/devcap.py` hold.

| Pose | Reached by |
|---|---|
| `iphone` | `tools/ios_uitest.sh --only iphone`; portrait only |
| `ipad-portrait` | `--only ipad` |
| `ipad-landscape` | `TEST_RUNNER_FENTON_UITEST_ORIENTATION=landscape` |
| `duo-folded` | the Duo simulator boots folded |
| `duo-unfolded-landscape` | `tools/duo_pose.py --sim <UDID> --set unfolded` |
| `duo-unfolded-portrait` | `--set rotate-left` from unfolded landscape |
| `duo-partial-fold` | `--set half` |
| `rotate-in`, `rotate-out` | Duo and iPad: open a sheet, rotate, rotate back |

1. Confirm the pose (which panel is lit, its aspect) before and after the run.
2. Run each unfolded pose with `-only-testing` for journeys that apply; a skipped test there invalidates the run.
3. Capture the Duo inner panel with `--display=primary-1`; for iPad landscape use the result bundle's attachment.

## Checks per pose

Tree first, then screenshots; never judge from one alone.

1. **Accessibility tree.** Run the surface's journey (`python3 tools/affected_tests.py` picks it) and dump the tree, pass or fail. Read names, roles, values, reading order, frames and hittability. Run the audit with the largest-text relaunch ([accessibility](../../testing/apple/accessibility.md)).
2. **Frames from the tree,** as numbers:
   - clipping: every frame inside its container and window, clear of the Duo rail and hinge band;
   - wrapping: no label narrower than a word, at default and largest text;
   - row heights: siblings match, and hold between two captures with no input;
   - tile widths ([dynamic-grid](../../patterns/dynamic-grid.md));
   - targets: 44 by 44 pt;
   - split gap and hinge ([split-view](../../design/apple/split-view.md), [hinge-avoidance](../../patterns/hinge-avoidance.md));
   - sheet placement, on the sheet frame ([modal-sheet](../../patterns/modal-sheet.md)).
3. **Screenshots,** for colour, material and motion end states: set `TEST_RUNNER_FENTON_CAPTURE_DIR` and `TEST_RUNNER_FENTON_REDACT_PRIVATE=1`, answer each `<name>.ready` with a `simctl io` screenshot, then write `<name>.done`. Motion needs a short sequence. Keep everything under `build/evidence/`, uncommitted.

## Evidence pack

`build/evidence/<branch>/manifest.json` (`/` in the branch becomes `-`) holds `branch`, `sha`, `task`, `ran_at`, a `summary` of counts, and one `poses` entry per pose in the brief: `device`, `udid`, `pose_confirmed`, `screenshots`, `ax_tree`, `measurements`, `tests`, `result` (`pass`, `fail`, or `not_run` with the reason in `notes`) and `failure_class`. Flip ledger checks with the manifest as `--evidence`.

## Clips for the pull request

1. `python3 tools/pr_visual.py select --branch <branch> --task <task> --round <N>` writes `selection.json`: the clips and pairs each device class shows.
2. For a class marked `needs_evidence: "unknown"`, look at its screenshot pairs and decide.
3. Record only the chosen clips, inside a hold: `xcrun simctl io <udid> recordVideo --codec=h264 <name>.mov`, stopped with SIGINT. One round trip per edge, 8 to 12 seconds.
4. Shrink each under 8 MB with `avconvert --preset PresetMediumQuality`.
5. Put each path in its clip's `path` in `selection.json`; `pr_visual.py render` embeds it.

## Failure classes

- `real`: the app is wrong in that pose. Re-run a journey that died oddly before calling it `real`.
- `infra`: the harness failed (a slot wait, a hang, a wrong pose, no tests executed). Fix the setup and re-run once; a second failure is reported as infra.
- `known-flaky`: a race a doc names, or a failure that passes on an identical rerun of the same sha. Cite the doc line or both run ids.

## Never

Automate a physical device: build Release, install it and tell the owner. Edit `apple/` during a test run. Touch another lane's simulator or process.
