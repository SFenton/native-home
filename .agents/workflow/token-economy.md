# Token economy

> **What:** the rules and tools that keep Claude usage proportional to the work: no polling, the right model, a short test loop. **Read when:** starting a lane or session, launching a build or test, or when the plan runs dry early. Evidence: [token-burn audit](../archive/audit/token-burn-2026-10-22.md).

Cost is turns × context, and a turn that only waits costs as much as one that works. A session carries its task to the end; the host compacts context.

## Rules

1. **Never wait by polling.** No `until … sleep`, `for … seq … sleep`, `sleep` over 29 s or `tail -f`. Run long commands as `tools/bg_run.py LABEL -- COMMAND` with `run_in_background: true` and **end the turn**; the harness notifies you when it exits, and the notification is a digest of 30 lines, not a log. A `PreToolUse` hook (`tools/hooks/no_poll.py`, wired in `.claude/settings.json`) refuses the loops; `# poll-ok: reason` overrides it. **A job over 25 minutes needs the Bash `timeout` too:** the harness kills a background call after 30 minutes unless it passes `timeout` (ms, at most 7200000), and a full coverage run (about 50 minutes) or full UI run dies mid-way. Pass `timeout: 4200000`; `bg_run.py --expect-minutes N` prints the value to use when N is over 25, and `tools/hooks/bg_timeout_guard.py` denies a background `apple_coverage.sh` or `ios_uitest.sh --full` without it, with the retry text (it fails open on its own errors). `bg_run` also kills the command's whole process group on SIGTERM or SIGHUP (exit 128+signal), so a killed wrapper leaves no child holding the build lock. Past five minutes a subagent's prompt cache has expired too, so each poll also rewrites its whole context.
2. **Read digests, not logs.** Open `build/runs/LABEL.log` only for a failure the digest cannot explain, and then `grep -n 'error:'` it. `INFRA` in a digest (Device Hub pose, hold timeout, unavailable simulator) is the machine, not the test: rerun once, then report it instead of diagnosing it again.
3. **The right model.** Every main-thread session in this repo starts as the orchestrator (Fable 5.2, medium; `"agent"` in `.claude/settings.json`, [agent-roster](agent-roster.md)); the settings' Sonnet (medium) is the model of a plain session (`claude --agent ""`). Fable 5.2 orchestrates, writes specs and design decisions (the Designer is Fable 5.2 too); Opus stays the final reviewer. Coder and Researcher escalate only with Agent parameters `model: "fable"` and an explicit `effort` per the roster; the brief alone does not configure them. The orchestrator does not poll, run builds, read logs or do git chores. Routine compile-fix, test-fix, screenshot and PR lanes run on `coder` (Sonnet). Test re-runs, log reading, status checks and git chores run on `menial` (Haiku). A `PreToolUse` hook on `Agent` (`tools/hooks/agent_model.py`) refuses accidental Fable inheritance: use `subagent_type: coder` or `menial`, or pass `model: sonnet|haiku`; the built-ins `Explore`, `Plan` and `general-purpose` do not default to a cheap model (docs read 2026-11-10: Plan and general-purpose inherit the parent's, Explore runs on Opus on a subscription) and are refused without `model: "sonnet"` or `"haiku"`. The final reviewer says `opus-ok: reason` in its prompt; outside the pinned `reviewer` type, that approval also requires explicit `model: "opus"`. No `reviewer` spawn may use Fable. `tools/token_report.py` counts Fable at 2× Opus (cache reads equal), in relative units, not dollars.
4. **Climb the test ladder.** Run the cheapest check that can fail: `swift test --filter` (seconds) → the journeys you added or changed (`tools/ios_uitest.sh --changed`, one `--quick` family first) on the families they affect. After a family has a baseline run, a fix round reruns only the failed tests (`--tests 'Class/test'`) plus `--changed`; the one full three-family run comes once, before the PR. A full coverage run that fails tests already does the cheap rerun for you: it reruns only the failed ids without instrumentation and digests `coverage-only` / `real` / `timeout`, so read that digest instead of rerunning the 36-56 minute run ([classification](../testing/apple/README.md#test-tiers)). That is the whole per-change tier: `swift test --filter` on the touched suite, `tools/lint_motion.sh` and one journey class on the primary family (the full affected set and `--plan Smoke` on all three families run in CI; run them yourself only when the change is layout-sensitive). `tools/apple_coverage.sh --changed` now runs in CI as the `coverage-changed` job, so locally it is optional. The full three-device suite and full `tools/apple_coverage.sh` are the **nightly and release** tiers, never a per-PR or per-edit step, and `tools/hooks/tier_guard.py` refuses them unless the command carries `FENTON_TIER=nightly|release` (or `--full` with a `# full-ok: reason` comment); an identical rerun (same tree, filter and device) is skipped, `--force` overrides ([test tiers](../testing/apple/README.md#test-tiers)).
5. **Do not rebuild a tool.** Lane setup, commit and PR, and log digests have scripts below; extend them.

6. **Wait silently (owner, 2026-11-04).** Woken by a background job or agent notification with nothing new for the owner, end the turn with no text, or one short line only when something changed. A waiting stop is said once, then silence. The interactive orchestrator also keeps status JSON out of chat: it writes `build/status/<task>.json` with `tools/agent_status.py` and prints one line of at most 30 words.

## Blocked-work note

`build/handoff/<topic>.md` (git-ignored, 40 lines at most) records work that is genuinely blocked: infra, an owner-only item, a slot wait over 20 minutes. Branch and worktree, what is done, what is blocked and why, the next step. Never written because of context size or turn count.

## Tools

| Tool | Does |
|---|---|
| `tools/bg_run.py LABEL [--timeout S] -- CMD` | Runs CMD, log to `build/runs/LABEL.log`, prints the digest and exits with CMD's status (124 after `--timeout`) |
| `tools/log_digest.py LOG` | Result, failing tests with the first assertion, compile errors, infra causes; XCTest, Swift Testing and build logs |
| `tools/ios_uitest.sh --quick` | Skips `xcodegen` when `project.yml` is unchanged (the compile is skipped for every run on already-built code by the products cache, `products: hit KEY` in the log and digest); a filtered run holds its devcap slots 25 minutes, not 60 |
| `tools/affected_tests.py` | The `swift test --filter` suites, journeys and device families a diff against `origin/main` needs (`contracts/test-map.json`); files no rule, convention or module places ask for a pick, never the full suite. Also prints the smoke families; `tree-hash`, `seen`, `record` for the passing-run ledger |
| `tools/lane_new.sh NAME` | Worktree `.claude/worktrees/NAME` on `claude/NAME` from `origin/main`, and the commands to run in it |
| `tools/ship.sh "Subject" [--pr]` | `git add -A`, commit with the trailer, push, optionally `gh pr create --draft` with the assignee and footer; refuses on `main` and for env files, keys and profiles (checks in the owner-only `tools/ship_guard.sh`) |
| `tools/pr_land.sh N` | The only merge route: checks green or none, review recorded; squash, delete branch and worktree, one result line ([pr-lifecycle](pr-lifecycle.md)) |
| `tools/token_report.py [--since D]` | Tokens and relative cost by day and model, long sessions, poll turns, cache rewrites. Run it weekly; healthy is zero of each |

Landing a lane runs a right-sized tool-test set, not the 38-minute full suite twice: the eval gate, a core set, and the tests the diff reaches by import; the full suite only for a shared module or a deleted test, and after every push to the workflow base (the `tool-tests-core` and `linux-checks` jobs of `pr-checks.yml`) ([agent-roster](agent-roster.md), "What code enforces today").

Hooks (`no_poll.py`, `bg_timeout_guard.py`, `agent_model.py`, `merge_guard.py`, `tier_guard.py`, `mockup_hub_guard.py`) live in `tools/hooks/` and are wired in `.claude/settings.json`; each is a no-op when its script is missing, so older worktrees are not blocked. Tests: `python3 -m unittest tools.tests.test_digest tools.tests.test_affected_tests tools.tests.test_hooks tools.tests.test_bg_timeout_guard tools.tests.test_tier_guard tools.tests.test_test_plans tools.tests.test_pr_land tools.tests.test_lane_ship tools.tests.test_token_report tools.tests.test_mockup_lifecycle tools.tests.test_agent_roster tools.tests.test_design_defects_run`.

## Cost by phase

The floor is unchanged after Fable adoption. At equal usage, its non-cache-read cost doubles, so some phases may now cross the floor; that reflects cost, not evidence of worse routing.

`python3 tools/phase_cost.py --session FILE` (or `--task T`) cuts one transcript into phases at an Agent spawn (its `subagent_type`), `tasks.py flip`, `ship.sh`, `review/record.py`, `jev_gate.py` and `pr_land`, weights each phase with `token_report.weighted`, and writes `build/retro/<task>.phases.json` (phase, kind, fresh tokens, weighted cost, minutes, share). A phase is flagged when its weighted cost is above the absolute floor `COST_FLOOR` (10M weighted tokens; owner "Yep", 2026-11-05, approving the reviewer's calibration); its share of the session is reported but is no longer a condition. Markers wrapped in `tools/bg_run.py LABEL ... --` or `tools/devcap.py run ... --` count (the wrapper is stripped before matching). For a flagged phase the tool lists the Jev questions that could have routed it differently (a table keyed by phase kind: a Coder rework after a Reviewer finding maps to `review.finding_family`, `code.custom_machinery`, `context.patterns`; a design loop to `design.target_decided`, `decision.needs_owner`). With `--replay`, and only with a key and archived input (the spawn prompt), it asks them in shadow and prints "would have routed differently: yes/no/unsure"; without a key it prints "not run". A spawn phase includes its subagent's own cost; a one-phase session is never flagged, and an over-threshold kind with no table row is reported as `no_candidates`, not a flag. `--task` never picks the calling session and prefers the transcript whose first user turn names the task; `--replay` appends shadow rows. The Steward reads the flagged phases weekly and proposes a gate only when the same phase kind is flagged in two or more sessions.

Calibration, 2026-11-05 (shadow only, no gate; real sessions, no `--replay`, 174 transcripts):

| | flags | coder | reviewer | coder_rework | design_loop | sessions with a flag, by kind |
|---|---|---|---|---|---|---|
| before (35% share and 25M floor, bare markers) | 1 | 1 | 0 | 0 | 0 | coder 1 |
| after (10M floor, wrapped markers) | 86 | 65 | 12 | 5 | 4 | coder 11, reviewer 4, coder_rework 4, design_loop 3 |

The Steward's two-session rule now fires for four kinds. `general-purpose` (74 phases) and `work` (8) are over the floor with no `CANDIDATES` row and stay `no_candidates`.

## Background jobs and the Stop hook

`tools/hooks/stop_continue_guard.py` refuses to end a session that still has a background job (`LABEL.running` next to the `bg_run` log, with a live pid) or a background agent running, or that says it is waiting. It is active only in headless sessions (`FENTON_HEADLESS=1`, set by the triage runner on every `claude -p`): an interactive session is re-invoked by the completion notification, a headless one is not. `bg_run` removes the marker in a `finally`, so a failed or killed command never leaves one, and it redacts the log and digest it writes ([triage-agent](triage-agent.md)). A coder runs devcap holds with `--max-wait 1200` (`--max-wait` is an alias of `--wait`, in seconds); a slot wait over 20 minutes makes it yield with status `blocked` and `blocked_reason: "slot_wait: ..."` instead of retrying. A coder that ends a turn while its own `bg_run` job is still running reports `blocked` with `blocked_reason: "waiting_bg: <label>"` after a WIP commit; the orchestrator reads that as a live handback and messages the agent instead of dispatching another into its worktree.

## Liveness before reuse

Before dispatching any agent into an existing worktree `<wt>`, check that nobody owns it. Three steps:

1. Dirty files: `git -C <wt> status --short`.
2. Running jobs: `cat <wt>/build/runs/*.running` lists a JSON marker per bg_run job (pid, label, cwd); a job is live when `kill -0 <pid>` succeeds (the check `tools/hooks/stop_continue_guard.py` uses). A `.digest` beside an old log proves nothing: bg_run keeps the previous digest when a rerun starts.
3. Newest edit: `find <wt> -type f -mmin -10 -not -path '*/.build/*' -not -path '*/.git/*' | head -1`; any output means an edit under 10 minutes old.

A live job or a recent edit means the owner is alive (a `blocked` with `waiting_bg: <label>` is a live handback): message that agent instead of dispatching a new one.
