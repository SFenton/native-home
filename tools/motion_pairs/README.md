# motion_pairs: the reference against native, one transition at a time

> **What:** records one named transition on the reference (the production UIKit app, gallery fixtures) and on native (preview mode, fixtures) at the same time, then measures onset, duration, easing and trajectory and writes a paired GIF, a +0/50/100/200/300 ms strip and a JSON row with pass or fail. **Read when:** you compare a push, sheet, modal or control animation across the two apps, or add a transition to the inventory.

## Method

1. **Record.** `agent-device record start --hide-touches` on each simulator (without that flag the clip is re-rendered at 30 fps), the two sides at once, `N` takes each, every take after a relaunch with Reduce Motion set explicitly. A take starts only when the 1-minute load is under 40 and is discarded when the recording ran 4 s past its sequence. No Swift runs on a device; ffprobe is not needed (three small Swift tools in `swift/` read the clips).
2. **Find events.** The mean change of each frame against the one before it gives bursts; an event starts at the first frame over the onset threshold (1.0 of 255 for a full-screen move; a button highlight changes less; a control sets a lower threshold and a `roi`). The first changed frame is the `lead`; the onset comes from pixels, never from the tap clock.
3. **Progress.** Each frame is projected onto the line from the picture before the event to the picture after it: `p` is 0 before, 1 settled. Fades, slides and springs read the same way. Settle is the last time `p` leaves the 2% band (T98).
4. **Fit.** The curve is compared with `linear`, `ease-in`, `ease-out`, `ease-in-out`, CSS `ease`, a spring (`duration`, `bounce`) and a free cubic-bezier, with a start delay and a duration free. The simplest family within 1.25 of the best RMSE wins. The recorder paces irregularly (62 to 85 fps), so fits use real timestamps and no frame is counted as dropped.
5. **Trajectory and type.** For every frame half way through, the best rigid shift of the new (or old) picture along x or y is compared with a plain cross-fade of the same pixels (`slideRatio`, under 1.5 is a slide). `edge` is the shift per frame; `centroid` is the centre of change (a control).
6. **Anchor on the tap.** agent-device writes each tap's time beside the clip (`<clip>.gesture-telemetry.json`). Tap to settled (`tapRestMs`) is the duration compared; tap to first changed frame (`tapOnsetMs`) is the latency, compared separately. A first-frame hitch (the first changed frame already over 30% through) then shows as latency, not as a broken settle time. The tap clock runs about 0.5 to 0.8 s ahead of the clip's, and a single take can wander by up to 150 ms, so only the difference between the two sides is meaningful, over several takes. Takes caught late are left out of the curve, lead and overshoot checks, which need the onset.
7. **Pair.** Medians over takes, the median curve of each side, then the checks below. A limit is never tighter than `noiseK` times the larger side's spread across takes. A change that settles within 25 ms is a `cut`; a row can carry class `fixture-polluted` (`--fixture-polluted EVENT`) when the sides drew different content.

| Check | Default limit | Gates |
|---|---|---|
| `type` | slide against fade must match | yes |
| `duration` | tap to settled: 40 ms or 10 % of the larger, or 2x the take spread | yes |
| `latency` | tap to first changed frame, difference between sides: 100 ms | yes |
| `lead` | 50 ms (needs onset-anchored takes on both sides) | yes |
| `curve` | RMSE 0.04 of the normalised range | yes |
| `overshoot` | 0.02 | yes |
| `frameDiff` | 3 % mean of pixels over 8/255 after onset alignment | reported only: a fixtures run puts different content on each side |

The defaults are the research note's starting values. Override any of them with `--tolerances FILE.json` (a flat object of these names; `gate` lists the checks that decide).

## Use

```
python3 -m tools.motion_pairs inventory                          # rewrite transitions.json
python3 -m tools.motion_pairs analyze [--fixture-polluted EVENT ...] --scenario S --reference a.mp4 b.mp4 --native c.mp4 d.mp4 --out DIR
tools/devcap.py run --sim REF_UDID --sim NATIVE_UDID -- \
  python3 -m tools.motion_pairs record --scenario S --reference-udid REF_UDID --native-udid NATIVE_UDID \
  --publication build/evidence/native-ingest/fullpair --takes 5 --out DIR [--reference-agent CMD --native-agent CMD]
```

`record --dry-run` resolves selectors, publication, tools and simulators without recording. `record` refuses without a devcap simulator hold, waits up to 15 minutes per take for the load to drop under 40, and closes its agent sessions at the end (an open session keeps the device claimed). Pass the bound `agent-device` commands from `device_open`; without them it builds the standalone form (own session and state dir). Output, per event: `<event>.json`, `<event>-pair.gif`, `<event>-strip.png`, plus `motion.json`, `index.md` and the clips under `takes/`. Keep them under a git-ignored folder.

## Files

| File | Job |
|---|---|
| `curves.py` | Pure maths: events in a motion series, progress helpers, curve families and the fit. Unit-tested on synthetic series |
| `progress.py` | Frames to progress, slide analysis and the frame-sequence diff (numpy) |
| `pair.py` | Medians, tolerances, the verdict |
| `record.py`, `scenarios.py`, `calibration.py` | The recorder wrapper, the scenario shape and the calibration scenarios |
| `analyze.py`, `report.py`, `video.py`, `swift/` | Clip decoding, GIFs and strips, the Swift readers |
| `inventory.py`, `transitions.json` | Every transition the atlas and `motion.md` name, with the trigger path on each side |

## Limits

- Simulator timing is the Mac's, not a device's: dropped frames and hitch ratios are not measured here (`.agents/testing/apple/performance.md`).
- A reference and a native clip show different content (fixtures), so a frame-by-frame pixel diff is reported but does not gate.
- Navigation signposts (`FENTON_NAVPERF`) need the signed-in shell and the owner's go; they are not part of this tool.
