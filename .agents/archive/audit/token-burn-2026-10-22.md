# Token burn audit

> **What:** where the Claude usage went between 2026-10-10 and 2026-10-22 (desktop and CLI sessions for this repo), what was wasted, and the fixes. **Read when:** you need the evidence behind a rule, not to learn the rule.

> **Archived 2026-10-28.** Evidence from a point-in-time audit; the rules it produced live in [patterns/README.md](../../patterns/README.md#reuse-rules), [token-economy](../../workflow/token-economy.md) and the pattern docs.

Source: every transcript under `~/.claude/projects` for this repo (53 main sessions, 67 subagent transcripts, the CLI orchestrator `ede97274` and its 22 subagents), 25.4k assistant turns. Per-turn `usage` was de-duplicated by message id. Totals: **9.0 B cache-read tokens, 0.6 B cache-write tokens, 8.4 M output tokens**.

"Weighted cost" below is my own relative unit, not the plan's: input 1, cache read 0.1, cache write 1.25 (5 min tier) or 2 (1 h tier), output 5, with Opus at 5× Sonnet and Haiku at 0.33×. The multipliers are assumptions; the ranking does not change if they are off by 2×. Shares are of the 4.9 B weighted total.

## What happened

Cost is **turns × context size**, not thinking and not output. Output tokens are about 6% of weighted cost. Every turn re-reads the whole conversation, and the conversations were enormous.

| Fact | Number |
|---|---|
| Busiest days (weighted) | Oct 12 (894 M), Oct 18 (643 M), Oct 17 (727 M), Oct 13 (699 M), Oct 11 (626 M) |
| Median context per turn in the 30 longest sessions | 300 k to 580 k tokens, up to 958 k |
| Context at the first turn of any session | 70 k to 92 k (system prompt, tool schemas, skill list, CLAUDE.md) |
| Compactions in all those sessions | 3. Sessions simply grew to 500 to 900 turns |
| Growth per turn | about 1.1 k tokens, so cost per session is quadratic in its length |
| Oct 20 to 21 CLI orchestrator and 22 Sonnet/Haiku lanes | 435 M total, median context 90 k, no lane over 320 turns. The same work shape cost 4 to 5× less per turn |

By origin:

| Origin | Sessions | Weighted share |
|---|---|---|
| Coordinator-spawned "Mac build / worker" sessions, **all Opus** | 49 | 63% |
| Sonnet/Haiku subagent lanes (Oct 11 to 18) | 67 | 31% |
| Interactive main session `b2164581` and others | 5 | 7% |

## Findings

### 1. Agents sit in 10-minute polling loops (22% of weighted cost)

3,763 turns exist only to run `until grep -q … ; do sleep 10; done` (or `for i in $(seq 1 58)`), each with a 590 to 600 s timeout, then read a log. 1,980 of them were Opus turns on a 400 to 800 k context. The harness already sends a completion notification for every background command (1,458 completed and 133 failed notifications are in the transcripts), so the poll adds nothing but a turn.

Example (`90d3f9f9`, turns 314 to 357): launch a one-test UI run in the background, then poll twice, ten minutes each, for a 15-minute run. One test iteration cost about 3 turns at 550 k context.

On Sonnet lanes polling is **40.6% of their cost**. It is also worse there: subagent contexts are written to the **5-minute** cache tier, so a 10-minute poll expires the cache. 1,219 Sonnet turns re-wrote a whole 300 to 500 k context (523 M cache-write tokens, 87% of all cache writes). One such turn costs roughly 12× a cache hit. Opus main sessions use the 1-hour tier and mostly avoid this.

### 2. Sessions never end (the biggest multiplier)

`90d3f9f9` (782 turns, avg ctx 567 k), `aa9cfa41`, `e89ed1c7`, `189f4eda`, `b2164581` (921 turns) and the Sonnet lanes "Scroll performance audit" (940 turns), "Journey health" (709), "Chores" (403) each carried an ever-larger context through hours of build, test, screenshot and PR-hygiene work. A simulation of resetting every 150 turns (25 k handoff, same growth rate) cuts cache-read volume to **about 50%**; every 100 turns, 43%. This is an upper bound: relearning has a cost.

### 3. Mechanical work runs on Opus

- `~/.claude/settings.json` sets the default model to `gh/claude-opus-5.5`, effort high. Anything that does not pick a model, including the 49 coordinator-spawned sessions and the SwiftUI Pro review sessions (Oct 14 to 15), ran on Opus (effort medium or high).
- Those sessions' briefs are "the code was written in the cloud and never compiled: build, fix compile errors, run tests, fix, push". That is a compile/test fix loop and fits Sonnet.
- On Opus turns: 28% were `sed`/`grep`/`cat` reading, 13.7% were git and `gh` chores (1,559 turns), 13.7% were polling. The role table in `AGENTS.md` says Opus is "sparingly" the planner and final reviewer; in practice it did the typing and the waiting.
- Haiku was used for 24 turns in total. The `menial` agent (Haiku) exists since Oct 20 and was spawned once. Test re-runs, log reading, git chores and polling are all menial work.
- Reasoning effort is not the problem: Opus output was 8 M tokens.
- Good example to copy: Oct 20 to 21. The CLI Opus session orchestrated `coder` (Sonnet medium) lanes, each short and in its own worktree.

### 4. Test process: slow single iterations, over-frequent gates, no digest

Counts are command invocations found in the transcripts (some sessions overlap):

| Run | Invocations | Typical duration |
|---|---|---|
| `tools/ios_uitest.sh` **filtered to one test** | 521 | median **14.6 min** (233 background runs), 23% failed |
| `tools/ios_uitest.sh` full suite, 3 devices | 268, plus 64 with `--only` | median 16 min |
| `tools/apple_coverage.sh` (the 95/95 gate) | 182 | median **34 min** (hold is up to 1 h) |
| `swift test`, full | 338 | median 3.4 min |
| `swift test --filter` | 615 | |

- The strategy doc says gates "are not run on every slice", yet single sessions ran them over and over: `90d3f9f9` ran the coverage gate 12 times for a navigation change, `573f76ad` the full three-device suite 14 times, `189f4eda` a full `swift test` 20 times.
- A one-test iteration takes 15 minutes because every call runs `xcodegen generate`, `build-for-testing` under a build slot, boots a simulator through a device slot, then runs. There is no "I only changed a test file" fast path, and each iteration is watched by an Opus or Sonnet agent.
- **Agents watch tests, not just results.** Nothing prints a summary, so every lane hand-writes greps over xcodebuild logs (`jh-fstatus.sh`, `jh-err.sh`, `grep -E "Test Case .*(passed|failed)|error:"`, 11+ copies) and tails logs while waiting.
- Flaky infrastructure is paid for repeatedly: the Duo "Pressed the unfolded control but the Duo reads…" DeviceHub error appears in 131 tool results across 24 transcripts; 54 hung runs hit the one-hour `hold timeout`; 76 results report a `GAP:` (unavailable simulator). Each is diagnosed from scratch by the model.
- Screenshot capture for PRs (resize with `sips`, view PNGs, re-run `testCapture…`) is about 5% of cost. Lower priority.

### 5. Work redone every session (tool candidates)

| What agents re-did | Evidence | Tool |
|---|---|---|
| Wait for a background job and read its result | 3,763 poll turns, 11+ ad-hoc status scripts | `tools/bg_run.sh` + `tools/test_digest.py` (below) |
| Reduce a test log to pass/fail + failing test names + first error | each lane, each run | `tools/test_digest.py` |
| Create a lane: fetch, `git worktree add`, branch, sim pool names, `temp.env` path, devcap env | `git fetch` 323×, `git worktree add` 44×, `xcrun simctl list` 87× | `tools/lane_new.sh <name>` |
| Commit with the trailer template, push, open PR, assign owner, label | the Co-Authored-By block hand-built 15×, `gh api …/assignees` 24×, `git add -A` 239× | `tools/ship.sh` |
| Edit files with `python3 - <<EOF` rewriting the old text in full | about 2,100 heredocs, 331 `sed -i` | use `Edit`; or a small `tools/replace.py` |
| Screenshot, downscale, contact-sheet, copy into `docs/screenshots/pr-N` | `sips`/`ffmpeg`/frames scripts rewritten per session | `tools/shots.py` |
| Read the same orientation docs at the start of every session | briefs say "read AGENTS.md, .agents/README.md, testing README first" | one `tools/lane_brief.sh` that prints a 60-line digest |

### 6. Fixed context overhead

First-turn context is 70 to 92 k in every session and subagent, re-read every turn. Contributors visible in the transcripts: tool schemas for many MCP servers (Chrome, Browser, iOS Simulator, hearthbot, ccd_*), a 7.6 k-token skill listing (the 12-skill `design-skills` plugin plus `design:`, `anthropic-skills:` and Apple HIG skills with long descriptions), a 6 k-token desktop prompt, `CLAUDE.md`. For a 150-turn lane this baseline is 40% or more of what it reads.

### 7. Things that are not a problem

- The triage runner (`com.sfenton.hass-triage`, every 60 s) calls no model on an idle tick. One real run is on record (request #3, 5 turns).
- Screenshots in context: 33 to 72 images per long session, a few thousand tokens each.
- Extended thinking: small next to context re-reads.

## Proposals, in order of payoff

Estimates are rough and not additive.

1. **No polling, ever.** Rule in `AGENTS.md` plus a `PreToolUse` hook on Bash that rejects commands matching `until|while .*sleep|for .* in \$\(seq` with a message: "launch with run_in_background and end your turn; the harness notifies you". Expected: −20% weighted, and removes the 5-minute-cache rewrite tax on Sonnet lanes.
2. **`tools/bg_run.sh <label> -- <cmd>`** runs the command detached with output to `build/runs/<label>.log`, then runs `test_digest.py` on exit and writes `<label>.digest` (≤ 30 lines: status, device, duration, failing tests with first assertion, `GAP`/hold-timeout/DeviceHub classified as infra, not test failure). `ios_uitest.sh` and `apple_coverage.sh` print the digest as their last output. Agents read the digest, never the log.
3. **Session hygiene.** Rule: a lane or main session ends at about 150 turns or 200 k context. Write `build/handoff/<name>.md` (≤ 40 lines: branch, state, next step, open failures) and start a new session from it. A `PostToolUse`/`UserPromptSubmit` hook can read the transcript's last `usage` and inject a "context is 200 k, hand off now" reminder. Expected: up to −50% of cache reads in long sessions.
4. **Model routing.** Set the global default to Sonnet medium; keep Opus for orchestration, spec/design decisions and the final review. Compile-fix, test-fix, screenshot and PR-hygiene lanes use `coder`; test re-runs, log reading, git chores and CI checks use `menial` (Haiku). In briefs and in `AGENTS.md` say so explicitly, and make the coordinator's spawn note state the model. Expected: most of the 63% Opus share moves to a 5× cheaper model.
5. **Fast test loop.** `ios_uitest.sh --quick` (skip `xcodegen` when `project.yml` is unchanged, skip `build-for-testing` when sources are unchanged, keep the simulator warm). One device first (iPhone), then the three-device run once per PR. The coverage gate runs once per PR, by CI or a `menial` agent, not by every lane after every edit; use `swift test --filter` while iterating (3 min against 34 min).
6. **Fix the flaky Duo pose path** (`DeviceHubError`) and make hung runs fail at 15 min rather than 60, so models stop diagnosing the same infrastructure error.
7. **`lane_new.sh` and `ship.sh`** (lane setup and commit/PR hygiene), `shots.py`, then trim the base context: disable MCP servers a build lane does not need, shorten skill descriptions, and keep the plugin lists of `design-skills` out of Sonnet lanes.
8. **Keep this report honest.** `tools/token_report.py` (the scripts behind these numbers) run weekly: tokens by day, by model, turns per session, poll turns, cache-rewrite turns. A week with any session over 200 turns or any poll turn is a regression.

## Method and limits

- Transcripts hold per-message `usage` but not the plan's own weighting, so the unit is relative. I could not see the plan meter, and the reset timestamp is not in the data. Festival work on the same account (Sep 28 to Oct 7: roughly 1.0 to 1.2 B weighted on each of the four peak days) shares the plan and is not counted here.
- Transcripts for Oct 19 are missing; the CLI session covers Oct 20 to 22.
- "Poll turn" = a Bash call containing a sleep loop; "read/search" etc. classify by the first tool in the turn. The reset simulation reuses each session's own context growth.
