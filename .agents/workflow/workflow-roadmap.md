# Workflow roadmap

Status as of 2026-11-04. **Update 2026-11-05:** the UIKit port landed on `main` (#308) and `workflow_base` is now `main`; `claude/uikit-port` is retired, so read its name below as `main` and treat P0 (reconcile local and origin `claude/uikit-port`) as done by the landing. This file is the backlog of everything the T-section-sides session (2026-11-03 and 04) left open: one branch that has to be reconciled, the workflow and tooling fixes its post-mortem found, and the product follow-ups its design pass left behind. It is written so whoever picks an item up next can start cold. Each proposal says:

- the issue to work from (full link);
- why it matters, with evidence from our own logs and numbers;
- what to try, step by step, and which files to touch;
- how to measure it, and the guardrails that keep it from weakening a check;
- the gain and effort, and whether it is **owner-only** (a file in the fixed set, so an agent may not land it) and why;
- sources: Apple's guidance first for the product and test items, then other projects and official docs.

Change this file when a proposal lands or is rejected, and move its result into the page that owns the rule ([pr-lifecycle](pr-lifecycle.md), [ci](ci.md), [agent-roster](agent-roster.md), [coverage](../testing/apple/coverage.md)). The test-speed backlog is separate: [test-speed-roadmap](../testing/apple/test-speed-roadmap.md).

**How to use this file.** Read section 1 for the state of things and section 2 for what the session cost, then take the first proposal in section 3 that is not owner-only and not already landed. Check the issue first: several issues were opened before work landed on `origin/claude/uikit-port` that overlaps them, and each proposal says what has changed since. Owner-only items are written up so the owner can decide in one read; an agent does not start them. Files named below are on `origin/claude/uikit-port` unless the text says the local branch has them too (a few tools exist only on origin until proposal P0 lands); read an origin-side file with `git show origin/claude/uikit-port:<path>`.

## Contents

1. [Where we are](#1-where-we-are)
2. [Where the time went](#2-where-the-time-went)
3. Proposals, best first:
   - [P0 Reconcile local and origin `claude/uikit-port` (item zero)](#p0-reconcile-local-and-origin-claudeuikit-port-item-zero)
   - [P1 CI on pushes to the workflow base (#277, owner-only)](#p1-ci-on-pushes-to-the-workflow-base-277-owner-only)
   - [P2 `ShipDraftTests` is broken on the base (#288)](#p2-shipdrafttests-is-broken-on-the-base-288)
   - [P3 Refuse a selector the plan skips (#283)](#p3-refuse-a-selector-the-plan-skips-283)
   - [P4 Coverage classifier follow-ups (#286)](#p4-coverage-classifier-follow-ups-286)
   - [P5 Record the base commit's red test set (#284)](#p5-record-the-base-commits-red-test-set-284)
   - [P6 Keep a pass verdict across a base-only merge (#278, owner-only)](#p6-keep-a-pass-verdict-across-a-base-only-merge-278-owner-only)
   - [P7 `merge_guard` reads commands, and every agent gets the simctl boot guard (#279, owner-only)](#p7-merge_guard-reads-commands-and-every-agent-gets-the-simctl-boot-guard-279-owner-only)
   - [P8 `mockup_hub_guard`: block once per file set (#281)](#p8-mockup_hub_guard-block-once-per-file-set-281)
   - [P9 `tier_guard` ignores quoted and heredoc text (#282)](#p9-tier_guard-ignores-quoted-and-heredoc-text-282)
   - [P10 A gate route for interactive owner requests (#280, owner-only, partly landed)](#p10-a-gate-route-for-interactive-owner-requests-280-owner-only-partly-landed)
   - [P11 Protect `tools/ci_*.py` and the coverage quarantine file (#285, owner-only)](#p11-protect-toolsci_py-and-the-coverage-quarantine-file-285-owner-only)
   - [P12 Jev: one rule for question versions (#276)](#p12-jev-one-rule-for-question-versions-276)
   - [P13 Motion gallery: lower cards move 52 pt (#271)](#p13-motion-gallery-lower-cards-move-52-pt-271)
   - [P14 Vacuums pane: translucent header covers the first switch (#272)](#p14-vacuums-pane-translucent-header-covers-the-first-switch-272)
   - [P15 One status chip (#273)](#p15-one-status-chip-273)
   - [P16 Fix the two capture paths (#274)](#p16-fix-the-two-capture-paths-274)
4. [Tried or rejected](#4-tried-or-rejected)
5. [How to measure](#5-how-to-measure)
6. [Sources](#6-sources)

## 1. Where we are

**CI consolidation (2026-11-08).** `tools/ci_scope.py` is gone: job selection is `dorny/paths-filter` in the `scope` job of `pr-checks.yml`, the private self-hosted job set and `tool-tests.yml` are deleted, one macOS job replaced the five, and the merge gate moved onto GitHub (a ruleset requiring `pr-checks`, auto-merge armed by `ship.sh`). On 2026-11-09 it became review before push: the reviewer passes the exact commit before anything is pushed, git's own pre-push hook (`.githooks/pre-push`) enforces it, with `push_guard` and `ship.sh` only guarding the ways around it, GitHub requires no approval, and the reviewer app is for comments only ([ci](ci.md#the-merge-gate)). Where this section or P1 names `ci_scope.py`, read the `scope` job; see [ci](ci.md#hosted-github-actions-owner-2026-11-07) and [the merge gate](ci.md#the-merge-gate).

**The T-section-sides work shipped** as #269 (the context and turn hand-off removed from settings and the triage runner), #270 (base CI repaired) and #275 (every section stays on one side of the Duo hinge). It cost far more than its size: about 10 device rounds of 36 to 56 minutes and 4 review rounds on #270 and 3 on #275, nearly all of it on failures that did not come from the change ([section 2](#2-where-the-time-went)). The post-mortem (`build/retro/T-section-sides-postmortem.md` in the section-sides worktree, with the digest `T-section-sides.json` beside it) named three tool-layer actions (A1 base CI on push, A2 coverage classification, A3 a disk reaper) and three owner holds (O1 to O3). **A2 and A3 landed to origin; A1 did not**, and the owner holds are open.

**Since the issues were written, more landed on `origin/claude/uikit-port`** (head `d3346f4b` on 2026-11-04). Read this before picking an item, because it changes some of them:

| Landed | Commit | Touches |
|---|---|---|
| Coverage classifier (A2) | `7f74a52a` | P4, P5 |
| Disk reaper, `prune-worktrees` and a preflight chain (A3) | `630d9f20` | P11 |
| `merge_guard` judges code, not text: a narrow exemption for read-only commands, `cat > file <<WORD` heredoc bodies and a short list of repo scripts | `8a3c8e90`, `53a55bca` | P7 |
| Mockup hub guard decides by content hash, with a fallback for a session that began in another checkout | `773f1651`, `23e313a1` | P8 |
| The gate counts the owner's chat requests: a `UserPromptSubmit` hook logs typed prompts, and a PR's `Owner's request: "<quote>"` line counts when the quote is in a prompt from the last 14 days | `7a862403` | P10 |
| Per-change tests diff against the branch the work came from, and `build/baselines/<sha>.json` lists failures the base already has (informational only) | `90a1a645`, `bc49ce5b`, `f1fd2a55` | P5 |
| `lane_land` runs right-sized tests on the merged tree and reaps the lane after the push | `83c587db`, `025a217d` | P0, P11 |
| `ship.sh` split: safety checks moved into the owner-only `tools/ship_guard.sh` | `f8fda7ed` | P2 |

**The local branch has diverged from origin** (P0). That is the first thing to fix, because every other item lands through `origin/claude/uikit-port`.

**Already in place, so don't redo it:** `tools/pr_land.sh` and `tools/lane_land.py` as the only merge paths; the eval gate ([eval-gate](eval-gate.md)); the kill, worktree, merge, tier and orchestrator guards; `tools/devcap.py` holds for every simulator and heavy compile ([capacity](../platforms/apple/capacity.md)); the context-size hand-off is gone (section 4).

## 2. Where the time went

Numbers from the T-section-sides digest and post-mortem (2026-11-04):

| Cost | Count | Time | Cause | Proposal |
|---|---|---|---|---|
| Base CI red before the work began | 636 mockup problems, 76 `pattern_guard` errors, 11 tool-test failures | every PR inherited them until #270 | `pr-checks.yml` triggers `push` only on `main`; the workflow base is `claude/uikit-port` | P1 |
| Long device rounds (coverage, changed-iphone, r1, v1) | 10 rounds over 30 minutes | 36 to 56 min each, four ended exit 124 | the same instrumented-only failures rerun in full (`UKHostedModalTests`, `UKHostedRecipesTests` x3, `UKHostedChoresGapTests`, `UKHostedHomeAssistantTests`, `HomePagesJourneyTests`) | P4, P5 |
| Empty runs | 8 (`duo-sides`, `duo-sides7` to `12`, `r2-ipad-home`) | about 20 min in total (1 to 6 min each) | the plan skips the class, or the selector names nothing in the plan | P3, P16 |
| Review rounds over the cap | #270 four, #275 three (cap 2) | a fresh review per head change | each base merge moved the head | P6 |
| Hub guard blocks | more than 20 in one session | tokens, not minutes | the guard read `cwd` and file mtimes | P8 |
| Guard false positives | `gh issue create` bodies blocked (`merge_guard`, `tier_guard`) | minutes each | the guards read the body text, not the command | P7, P9 |
| Disk preflight failures | 2 (hass-mac) | CI stopped | nothing reaped merged worktrees | landed (A3) |
| `--owner-ack` on #270 and #275 | 2 | owner time | an interactive request had no issue for the gate to read | P10 |
| A Verifier booted a simulator outside a hold | 1 | broke the shared-capacity invariant | `orchestrator_guard` blocks `simctl boot` for the orchestrator only | P7 |

The two biggest lines, the red base and the long rounds, are both **missing early signals**: nothing tested the base, and nothing separated an inherited failure from a new one. Fix those first.

## 3. Proposals

Every proposal follows the same rules:

- Never weaken what a check does to make a number better: no narrower coverage line, no waived test, no skipped assertion.
- A fixed-set file (the list in `tools/lane_land.py` `DEFAULT_PROTECTED` plus `protected_paths` in `tools/triage/config.json`) is **owner-only**: write the change as a proposal, never land it as an agent.
- A change the owner will see or feel goes through [propose-first](propose-first.md).
- Measure with the signal named in the proposal ([section 5](#5-how-to-measure)) before and after.

### P0. Reconcile local and origin `claude/uikit-port` (item zero)

**Issue.** None yet. File one with the label `Workflow` before starting. Do not reconcile in the primary checkout or the uikit-port worktree; use a lane.

**Why.** The local `claude/uikit-port` (the uikit-port worktree, head `10dc14e8`) and `origin/claude/uikit-port` (head `d3346f4b`) have diverged:

```
git rev-list --left-right --count claude/uikit-port...origin/claude/uikit-port
142	63
```

- **142 commits local only:** the journey-speed rollout (class-by-class reuse, snapshot reads, the AX5 audit in place, the test speed roadmap), merged locally and never pushed. 36 of them are merge commits. Against the merge base `80b05337` (2026-11-03) that is 152 files, +7,998 and -4,229 lines.
- **63 commits origin only:** #269, #270, #275, lanes A2 `7f74a52a` and A3 `630d9f20`, and the later lanes of 2026-11-04 (landing-fast, devcap 1.5.0, app identities, ship guard, merge-guard false positives, owner prompt log, quiet orchestrator, visual PRs, the apps setup helper). 319 files, +14,704 and -4,978 lines.

**The overlap is small:** `git diff --name-only 80b05337 <side>` on each side, intersected, gives 7 files:

| File | Local side | Origin side | Merge result |
|---|---|---|---|
| `tools/ios_uitest.sh` | +4 -1 | +13 -5 | conflict |
| `tools/apple_coverage.sh` | +3 | +47 -16 | conflict |
| `.agents/testing/apple/coverage.md` | +2 -1 | +1 | conflict |
| `.agents/testing/apple/README.md` | +1 | +9 -1 | merges cleanly |
| `contracts/components.json` | +818 -3148 | +829 -3151 | conflict (generated) |
| `contracts/patterns.json` | +1 -3 | +210 -98 | conflict (generated) |
| `contracts/test-map.json` | -14 | +128 -54 | conflict (generated) |

`git merge-tree --write-tree --name-only claude/uikit-port origin/claude/uikit-port` reports exactly six conflicts: the two scripts, `coverage.md` and the three generated registries. The journey-speed docs (`journey-speed.md`, `app-reuse.md`, `test-speed-roadmap.md`) and `AppReuse.swift` are touched on the local side only, so they carry over. Nothing is lost by merging; the risk is the two shell scripts, which both sides edited and which every test run goes through.

**What to try.**

1. Make a lane from the local head: `tools/lane_new.sh reconcile-uikit-port --base claude/uikit-port` (check the script's usage for the base flag), so the local speed work is the lane's base.
2. `git fetch origin` and `git merge origin/claude/uikit-port` in the lane. Resolve in this order:
   - `tools/ios_uitest.sh`, `tools/apple_coverage.sh`: keep both sets of edits; read each hunk. Origin's side adds the base-failure subtraction (`tools/lane_base.py`, `build/baselines`) and the phase classification; the local side adds a few lines for reuse. Re-run `bash -n` on both.
   - `coverage.md`: keep origin's classification paragraph and the local lines.
   - `contracts/components.json`, `contracts/patterns.json`, `contracts/test-map.json`: do not hand-merge. Take origin's file, then regenerate with the generators the repo already has (`python3 tools/components_index.py`, `python3 tools/jev_ask.py sync`, and the pattern and test-map changes the local side made, replayed on top), then run `python3 tools/pattern_guard.py`, `python3 tools/components_index.py --check` and `python3 tools/jev_ask.py sync --check`.
3. Run the overlapping tests: `tools/run_tool_tests.sh` (the Python tool tests, including `test_pr_land`, `test_coverage_classify`, `test_ci_hygiene`), `python3 tools/affected_tests.py` on the merged tree, and `tools/ios_uitest.sh --changed` on iPhone, then `--plan Smoke` on Duo and iPad as two commands. These are the journey-speed classes the local side touched, so run one reuse class end to end (for example Food) to prove `AppReuse` still works with the new base-failure subtraction.
4. Land through `python3 tools/lane_land.py` (the gate), not by pushing the local branch. The lander merges the lane onto the current base, runs the eval gate and the right-sized tests, and checks that the lane runs no fewer tests than the base. The lander refuses a diff that touches a protected path, so check `git diff origin/claude/uikit-port...HEAD --name-only` against `DEFAULT_PROTECTED` first. If the speed work touched a protected path (it should not), those files go to the owner as a separate PR.
5. After the lander merges, fast-forward the local `claude/uikit-port` in the uikit-port worktree to `origin/claude/uikit-port` and check `git rev-list --left-right --count` reads `0 0`.

**How to measure.** `git rev-list --left-right --count claude/uikit-port...origin/claude/uikit-port` ends at `0 0`; the tool tests and the affected Swift tests pass on the merged tree; one reuse class runs with the same launched-count as its row in [journey-speed](../testing/apple/journey-speed.md).

**Guardrails.**

- No rebase of the 142 commits and no force push: the local merges stay as history.
- Do not edit a generated registry by hand.
- Do not skip a hook or the lander to make a conflict go away.
- If the lander refuses for a reason the speed work caused (fewer tests than the base, for example because a journey class was retired), fix that in the lane; never fold the lane into an owner PR to get past the check (section 4).

**Gain and effort.** Gain: origin gets the 1.41x iPhone journey speed-up (156 to 111 minutes) and every lane stops branching from a base that lacks half the work. Effort: half a day for the merge and conflict resolution, plus the test runs. **Owner-only:** no, unless a protected path turns up in step 4.

**Sources.** [`git rev-list --left-right`](https://git-scm.com/docs/git-rev-list), [`git merge-tree --write-tree`](https://git-scm.com/docs/git-merge-tree) (a trial merge that reports conflicts without touching the worktree), [`git merge-base`](https://git-scm.com/docs/git-merge-base), [`git diff` (two and three dots)](https://git-scm.com/docs/git-diff), [`git merge`](https://git-scm.com/docs/git-merge). In the repo: [pr-lifecycle](pr-lifecycle.md), [journey-speed](../testing/apple/journey-speed.md).

### P1. CI on pushes to the workflow base (#277, owner-only)

**Issue.** private app repo issue #277

**Why.** `.github/workflows/pr-checks.yml` triggers `push` only on `main` (`branches: [main]`), and the workflow base is `claude/uikit-port` (`tools/triage/config.json` `workflow_base`). Nothing tests the base. On 2026-11-03 it had drifted to 636 mockup problems, 76 `pattern_guard` errors and 11 tool-test failures before anyone noticed, and every PR into it inherited the red until #270 fixed it. That is the largest avoidable cost in section 2: a red base makes every lane merge it, which moves every PR head (P6), and hides which failures a lane caused (P5).

**What to try.**

1. In `.github/workflows/pr-checks.yml` add the base to `on.push.branches` next to `main`. Read the branch name from `tools/triage/config.json` (the job filter was `tools/ci_scope.py`, now the `scope` job's `dorny/paths-filter`) rather than a second literal in the workflow, so a base change touches one place. (`on.push.branches` itself cannot read a file; the workflow lists the name, a repo check compares it with the config.)
2. For a push to a branch other than `main`, make the `scope` job compare against `github.event.before` (the pushed-to sha before the push) the way a pull request compares against its base, and run only `repo-checks` and the Python tool tests: no `swift test`, no Release build. A push to `main` stays as it is. Guard the first push of a new branch, where `before` is all zeros.
3. Leave the aggregate `pr-checks` job unchanged. `pr_land.py` reads the aggregate by name (`REQUIRED_CHECKS`), so the merge path is untouched.
4. On failure the run opens nothing. A red run on the base is the signal; [ci](ci.md) names who looks at it (add that line).
5. Tests in `tools/tests/test_ci_scope.py`: a push event with `before` set returns `scope=tools` for a tools-only diff and `scope=app` for an app diff; a push to the base never sets `release=true`; an all-zeros `before` falls back to the full repo checks.

**How to measure.** Count PRs into the base that arrive with an inherited red check: `gh run list --branch claude/uikit-port --workflow pr-checks --limit 50 --json conclusion` before and after. Target: none. Also the runner minutes it adds (the tools scope compiles nothing).

**Guardrails.** The workflow runs on the owner's machines with the owner's Keychain in reach ([ci](ci.md), security section), so the push trigger must not widen what a branch can do: keep the `permissions: contents: read`, the pinned actions and the `concurrency` group. Do not add a branch glob; name the one base.

**Gain and effort.** Removes the largest inherited-failure cost. Effort: an hour for the workflow and `ci_scope` change, an hour for tests and docs. **Owner-only:** yes. Workflow files are in the fixed set (they run as the owner with the owner's credentials in reach), and the owner decides whether the base may run CI on every push.

**Sources.** GitHub: [workflow syntax, `on.push.branches`](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions), [the `push` webhook payload (`before`, `after`)](https://docs.github.com/en/webhooks/webhook-events-and-payloads), [security hardening for Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions). In the repo: [ci](ci.md), `tools/ci_scope.py`.

### P2. `ShipDraftTests` is broken on the base (#288)

**Issue.** private app repo issue #288

**Why.** `tools/tests/test_pr_land.py` `ShipDraftTests.test_pr_is_always_a_draft_and_needs_no_review_file` fails on `origin/claude/uikit-port` with `tools/ship.sh: line 37: tools/ship_guard.sh: No such file or directory`. `f8fda7ed` split the safety checks into `tools/ship_guard.sh`; `ship.sh` finds it with `"$(dirname "$0")/ship_guard.sh"`, which is fine in the repo, but the test builds a temp repo and copies only `tools/ship.sh` into it (`shutil.copy(TOOLS / "ship.sh", clone / "tools/ship.sh")`). So the issue's "relative path that does not resolve" is the fixture, not `ship.sh`. `lane_land` tolerates the failure because the base fails the same way, but every lane's tool-test run now shows one red test, and a known red test teaches agents to ignore red.

**What to try.**

1. In `ShipDraftTests.make`, copy `tools/ship_guard.sh` into the fixture beside `ship.sh` (and `chmod +x`, as the other fixture scripts are). That is a test-only change.
2. Run the test, then the whole `test_pr_land` module and `test_ship_guard_wiring`.
3. If `test_ship_guard_wiring.py` pins the fixture shape, leave it alone: it is protected.

**How to measure.** `python3 -m unittest tools.tests.test_pr_land.ShipDraftTests` passes; `tools/run_tool_tests.sh` has no failure that the base also has.

**Guardrails.** `tools/ship_guard.sh` is owner-only: copy it, never edit it. Do not change `ship.sh` to hide a missing guard (a missing guard must fail loudly, that is its job).

**Gain and effort.** One red test removed from every lane. Effort: minutes. **Owner-only:** no. The test file is not in the fixed set; only `ship_guard.sh` is, and the fix does not touch it.

**Sources.** In the repo: `tools/ship.sh` line 37, `tools/tests/test_pr_land.py`. The fix is a file copy, so no outside source applies.

### P3. Refuse a selector the plan skips (#283)

**Issue.** private app repo issue #283

**Why.** `apple/TestPlans/Gate.xctestplan` lists `MotionJourneyTests` under `skippedTests`, so `-only-testing:FentonHomeUITests/MotionJourneyTests` under the Gate plan matches nothing. `tools/ios_uitest.sh` already fails EMPTY afterwards (`xc_watch.py --require-tests`), but only after a 1 to 6 minute build and simulator boot. In T-section-sides that happened in seven `duo-sides` runs and in `r2-ipad-home`, about 20 minutes (section 2). The fix is a check that runs before the build.

**What to try.**

1. In `tools/ios_uitest.sh` (or a small Python helper it calls, easier to test), after the plan is resolved (`PLAN_FILE`) and before the build: parse the plan JSON, read the UI test target's `skippedTests` and `selectedTests`, and test every `-only-testing:` / `--tests` selector. A selector is **skipped** when it equals a skipped entry or sits under one (`Class` skips `Class/test()`; `Class/test()` skips only that test), and **absent** when the plan has `selectedTests` and the selector is in none.
2. On a hit, exit 2 before the build with one line that names the plan that does contain the class: scan `apple/TestPlans/*.xctestplan` for the selector and print `MotionJourneyTests is skipped by Gate; it is selected by Capture (use --plan Capture)`.
3. Also check the iPad Home selector in #274: `testHomeSplitsOnTheHingeOnlyWhenUnfoldedInLandscape` is skipped by Gate and selected by Live, which is why the filtered run found nothing (P16).
4. Document in [devices](../testing/apple/devices.md) that **XCUITest sees only the Duo's outer panel**, so a Duo journey cannot read the inner panel's elements. Then a partly folded or unfolded capture goes through the pose tooling or the debug hooks, not a journey selector.
5. Tests: a fixture plan with a skipped class, a selected-only plan and a plain plan; a selector under a skipped class refused; the message names the right plan.

**How to measure.** The EMPTY-run count per task in the retro digest (`empty_runs` trigger), target zero; the time between a wrong selector and the refusal, seconds instead of minutes.

**Guardrails.** Never rewrite a plan to make a selector match. A refusal must not fire for `--changed` runs that legitimately select nothing (they exit with their own message). Read `tools/hooks/tier_guard.py`'s allowed flags first so the check does not duplicate it.

**Gain and effort.** Saves 1 to 6 minutes per wrong selector and a boot slot. Effort: two hours with tests. **Owner-only:** no (`ios_uitest.sh` is not in the fixed set).

**Sources.** Apple: [organizing tests to improve feedback](https://developer.apple.com/documentation/xcode/organizing-tests-to-improve-feedback) (test plans, selected and skipped tests), [`XCTestCase`](https://developer.apple.com/documentation/xctest/xctestcase). In the repo: [devices](../testing/apple/devices.md), `apple/TestPlans/Gate.xctestplan`.

### P4. Coverage classifier follow-ups (#286)

**Issue.** private app repo issue #286

**Why.** Lane A2 (`7f74a52a`) added `tools/coverage_classify.py` and `tools/coverage_phases.sh` so a coverage run that fails tests reruns only the failed ids uninstrumented and prints `coverage-only:`, `real:` and `timeout:`. Its review found four loose ends:

1. **Crash label.** `log_digest`'s shared `test host crash` INFRA label also matches `signal code` and `Restarting after unexpected exit`. A non-zero `swift test` whose only symptom is a host-code crash (a `fatalError` or force-unwrap) used to digest as FAIL and now digests as `INFRA (not a test failure)` with rerun-once advice. Give it a separate `test crash` label that the verdict treats as FAIL. (`coverage_classify.py` already fails a phase on a crash marker, so the phase verdict is safe; the digest wording is not.)
2. **Fail-closed cases.** Two cases fail closed and can never be quarantined; document both in [coverage](../testing/apple/coverage.md): a test that exceeds its allowance under instrumentation, and issue lines from parameterised Swift Testing cases.
3. **First real run.** `tools/apple_coverage.sh --changed` has only been tested statically or with stubs. Do one real run on a small change before any quarantine entry is added to `apple/coverage-quarantine.json`.
4. **`gh` on host-mini.** The nightly coverage step checks a quarantine entry against `gh` (an open `Workflow` issue). Confirm `gh` is authenticated there (`GH_TOKEN`); otherwise quarantine fails closed, which is safe but would block a legitimate entry.

**What to try.** (1) Add the label in the digest writer and the verdict; a unit test with a fixture log that has `signal code` and no failing id. (2) Two short paragraphs in `coverage.md`. (3) A real run, pasted into the PR as the digest line, not the log. (4) On host-mini, `gh auth status` only (never print a token); if it is unauthenticated, that is an owner step (add `GH_TOKEN` to the runner's environment), so write it as a note, not a change.

**How to measure.** A host crash digests as FAIL with the `test crash` label; the real run's digest shows `coverage-only`, `real` and `timeout` lines; no quarantine entry exists before the real run.

**Guardrails.** The 95% line stays. A quarantined test still counts toward coverage. Every quarantine entry needs an open `Workflow` issue.

**Gain and effort.** Prevents a crash being waved through as infrastructure, and makes the first quarantine entry trustworthy. Effort: half a day, mostly the real run. **Owner-only:** the code is not in the fixed set; host-mini's `GH_TOKEN` is the owner's machine.

**Sources.** In the repo: [coverage](../testing/apple/coverage.md), `tools/coverage_classify.py` and `tools/coverage_phases.sh` (origin only until P0), `apple/coverage-quarantine.json` (origin only).

### P5. Record the base commit's red test set (#284)

**Issue.** private app repo issue #284

**Why.** The classifier needs to know whether a failing test is inherited. Eight coverage digests over six SHAs in T-section-sides showed nearly the same failing set, and nobody could say whether the base had it too (post-mortem, "Not verified"). Since the issue was written, `90a1a645`, `bc49ce5b` and `f1fd2a55` landed `tools/lane_base.py` (origin only until P0): it resolves the branch the work came from, `build/baselines/<sha>.json` stores failures keyed by family, and a run prints `inherited / new / unaccounted`. That covers the **local** store. What is missing is the **shared** record: a run on the base itself, on a schedule or on a push, writing the failing ids per base sha somewhere every lane can read.

**What to try.**

1. After P1 lands, have the base push run (or the nightly) call the baseline recorder and upload `<base-sha>.json` as a workflow artifact, or keep it in a cache folder on the runner that `lane_base.py` reads when its own `build/baselines/<sha>.json` is missing (a design choice for whoever builds it).
2. Keep the rule from `f1fd2a55`: base-failure reporting is **informational**; it never turns a failing run green. The classifier may print "inherited" next to an id; the exit status still comes from the real rerun.
3. Do this after P1 (the push run) and P4 (the classifier is real). Without them there is nothing to schedule.

**How to measure.** The count of coverage rounds over 30 minutes per task (retro digest trigger `repeated_long_device_rounds`), target at most one full run plus cheap reruns. The share of failing ids in a lane's digest that are labelled inherited.

**Guardrails.** A baseline is recorded only from a clean checkout of the base commit (`f1fd2a55` already enforces it). Never subtract an id the base failed in a different family. An unparsable log records nothing.

**Gain and effort.** Turns a 40-minute full rerun into one cheap rerun of the ids that are new. Effort: half a day after P1 and P4. **Owner-only:** no, but it reads the CI workflow from P1.

**Sources.** In the repo: `tools/lane_base.py`, `tools/coverage_classify.py`, [coverage](../testing/apple/coverage.md). Apple: [XCTest test plans and results](https://developer.apple.com/documentation/xcode/organizing-tests-to-improve-feedback).

### P6. Keep a pass verdict across a base-only merge (#278, owner-only)

**Issue.** private app repo issue #278

**Why.** (Superseded 2026-11-09: `pr_land` no longer reads a review file or the check rollup; it asks `review_verdict.has_pass` for the exact head and GitHub judges the checks.) `pr_land.py` `review_state` requires the recorded review to be for exactly the PR head (`recorded != head` gives "review again"). Every merge of the base into a reviewed PR moves the head and forces a new review round: #270 needed four and #275 needed three, against a cap of two. The upstream cause was the red base (P1), which forced base merges into each PR, but even with a green base a PR that waits for a runner will meet a moving base.

**Proposal.** Accept the earlier pass when the only change since the verdict's head is a merge whose second parent is `origin/<base>` and the merge tree equals what an automatic merge would give. In code:

1. Read the verdict's `head` (H0) and the PR head (H1).
2. Require `git rev-parse H1^2` to be an ancestor of (or equal to) `origin/<base>`, and `H1^1` to equal H0 (or H0 to be an ancestor reached only through first parents).
3. Compute `git merge-tree --write-tree H0 <H1^2>` and require its tree to equal `H1^{tree}`. If the merge needed a conflict resolution, the trees differ and the pass does not carry over.
4. Require the PR's own diff (`git diff <base>...H0` against `<base'>...H1`) to be identical, so only the base moved.
5. When all hold, print `review carried over from <H0> (base-only merge)` and treat the pass as current. Any other change, including an evil merge, needs a fresh review.

**How to measure.** Review rounds per PR (retro digest `review_rounds_over_cap`), target at most two; count of "review is for X but the PR head is Y" blocks per week.

**Guardrails.** Conflict resolutions never carry over. Only the lander computes this, not the agent. The reviewer's checklist still applies on the first round. A weakened check here is a merge-path bug, so test with fixtures: a clean base merge, a merge with a resolved conflict (must not carry), a merge plus an extra commit (must not carry), a merge from a non-base branch (must not carry).

**Gain and effort.** Removes one review round per base move. Effort: half a day with fixtures. **Owner-only:** yes. `tools/pr_land.*` is the merge path and in the fixed set; the owner decides what a verdict vouches for.

**Sources.** GitHub: [protected branches, "dismiss stale pull request approvals when new commits are pushed"](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) (the platform default is the same strictness, with an off switch). Gerrit: [`copyAllScoresOnTrivialRebase`](https://gerrit-review.googlesource.com/Documentation/config-labels.html) (a precedent: keep a vote across a rebase that changes no content). Git: [`git merge-tree --write-tree`](https://git-scm.com/docs/git-merge-tree). In the repo: [pr-lifecycle](pr-lifecycle.md), `tools/pr_land.py` `review_state`.

### P7. `merge_guard` reads commands, and every agent gets the simctl boot guard (#279, owner-only)

**Issue.** private app repo issue #279

**Why.** Two separate gaps:

1. **Text matching.** `merge_guard.reason()` runs its regexes on the raw command string, so `gh issue create` was blocked because its body named the landing scripts. Commits `8a3c8e90` and `53a55bca` added a narrow exemption: a block is dropped only when every simple command is on an allow-list (`grep`, `rg`, `cat`, `head`, `tail`, `less`, `ls`, `wc`, `echo`, `mkdir`, read-only `git log|show|diff|status|commit`, a `cat > file <<WORD` heredoc, and a short list of repo scripts). **`gh issue create` and a `git show ... | grep` pipeline are still outside it**: while writing this file, a `git show` piped to `grep` with a quoted pattern naming an owner-only flag was blocked (2026-11-04). The raw scan still decides; the exemption only subtracts.
2. **Boot guard.** `orchestrator_guard.py` blocks `xcrun simctl boot|install|launch` only when the payload's `agent_type` is `orchestrator`. A Verifier booted a simulator outside a `tools/devcap.py` hold, which breaks the "Shared capacity" invariant in `AGENTS.md`; devcap reaps it after 5 minutes unmanaged ([capacity](../platforms/apple/capacity.md)), so the cost is a flaky run, not a leak.

**Proposal.**

1. Decide on the parsed command, not the text: run the regexes on the output of `shell_parse.scan_shell(command)[0]` (which drops heredoc bodies and comments, and is already used by `request_repo_reason`) joined with quote-aware words from `shell_parse.tokenize`. Keep the raw scan as a second line of defence for constructs the parser cannot read (an unbalanced quote), and fail closed there.
2. Add `gh issue create|comment|edit` and `gh pr create|comment` with a `--body`/`--body-file`/heredoc to the exemption only when the body is data: the program is `gh`, the subcommand is on a fixed list, and no `$(...)`, backtick or `eval` appears outside quotes.
3. Move the `simctl boot|install|launch` rule into a guard that runs for every `agent_type` (a Verifier and a Coder included, a missing `agent_type` too), with the existing comment override (`# orch-ok: reason`) kept only for the orchestrator's other rules. A `tools/devcap.py run` hold is allowed because `simctl` runs inside it. Test with payloads for `orchestrator`, `verifier`, `coder`, `menial` and null.
4. Tests: every false positive on record (issue bodies, quoted greps, heredoc bodies) passes; every real bypass on record (`bash -c`, `xargs`, `$(...)`, a script that runs its argument) still blocks.

**How to measure.** False-positive blocks per session, counted from the session's hook messages; simctl boot outside a hold per week, from the unmanaged-simulator lines of `python3 tools/devcap.py status`; both target zero.

**Guardrails.** A guard that loosens is a security change: loosen only what the tests prove is data. Never read the decision from the model's own comment on a merge guard (the override stays orchestrator-only and for the non-merge rule).

**Gain and effort.** Removes a recurring false positive and closes the simctl gap. Effort: a day with fixtures. **Owner-only:** yes. `merge_guard.py`, `orchestrator_guard.py` and `shell_parse.py` are in the fixed set (an agent loosening its own guard is exactly what the set exists to stop).

**Sources.** Claude Code: [hooks reference](https://docs.claude.com/en/docs/claude-code/hooks) (PreToolUse input has `tool_input.command`, `agent_type`, exit 2 blocks). Python: [`shlex`](https://docs.python.org/3/library/shlex.html) (and its warning that it is not a security boundary: keep the raw scan as the fail-closed line). Bash: [shell syntax, quoting](https://www.gnu.org/software/bash/manual/html_node/Shell-Syntax.html). In the repo: [capacity](../platforms/apple/capacity.md), [agent-roster](agent-roster.md).

### P8. `mockup_hub_guard`: block once per file set (#281)

**Issue.** private app repo issue #281

**Why.** The Stop hook blocks ending a session that changed mockups without republishing the hub. It fired more than 20 times in T-section-sides while a publish was correctly deferred (no Artifact tool in the lane), because it read `cwd`, which drifts into subagent worktrees, and decided by file mtimes, so a fresh checkout or a base merge looked new. **Part of this has landed:** `773f1651` and `23e313a1` decide by SHA-256 content against a SessionStart snapshot stored outside the worktree, fall back to dirty files and commits since the transcript began when the session started in another checkout, and `stop_hook_active` lets a second stop through. What is still open from the issue:

- The root still comes from the event `cwd` first (`mockup_hub_guard.py` around line 148), so a session whose `cwd` has drifted can check the wrong tree.
- There is no per-signature memory: the guard blocks every first stop, even when the same file set was already reported and deferred.
- The snapshot is by content but there is no record of "this signature was reported", so a long session pays one block per Stop.

**What to try.**

1. At SessionStart store the root and the `HEAD` sha beside the snapshot. At Stop, diff `<sha>...HEAD` and the dirty files, and use the stored root, not the event `cwd`, unless the stored root is gone.
2. Compute a signature (sorted list of changed publishable files plus their hashes), store it on the first block, and let the next Stop with the same signature through with a one-line reminder. A new or changed file changes the signature and blocks again.
3. Keep `stop_hook_active` and the "say in the PR that the hub republish is pending" rule.
4. Fixtures in `tools/tests`: drifted `cwd`, a base merge that brings in mockups (must not block), the same file set twice (blocks once), a changed file after a deferral (blocks again).

**How to measure.** Hub-guard blocks per session, target at most one per distinct file set; zero blocks for a session that changed no mockup.

**Guardrails.** A publish must still happen when the Artifact tool exists. A session that changes a mockup and never mentions the pending publish must still block once. Do not weaken the content test.

**Gain and effort.** Tokens, not minutes: removes a loop of 20 blocks. Effort: half a day. **Owner-only:** no. `mockup_hub_guard.py` is not in the fixed set (the `.claude/settings.json` registration is, so any new hook event is an owner step).

**Sources.** Claude Code: [hooks reference](https://docs.claude.com/en/docs/claude-code/hooks) (SessionStart, Stop, `stop_hook_active`). Git: [`git diff` three-dot](https://git-scm.com/docs/git-diff). In the repo: the `mockup-hub` skill (`.agents/skills/mockup-hub/SKILL.md`), AGENTS.md "Mockup atlas".

### P9. `tier_guard` ignores quoted and heredoc text (#282)

**Issue.** private app repo issue #282

**Why.** A quoted or heredoc `gh issue create` body that named the UI test runner was blocked, because `tier_guard.reason()` splits the raw command on newlines and `;` (`SPLIT`) and a body line that starts with `ios_uitest.sh` looks like a command.

**What to try.**

1. Run `shell_parse.scan_shell(command)` first, as `kill_guard` does: it drops heredoc bodies and comments. Then split with the quote-aware `shell_parse.tokenize`, not a regex on the raw string, so a quoted body stays one word.
2. Keep the nested-command handling (`bash -c`, `xargs`), which already calls `reason(nested)`.
3. Tests for both body forms (a `--body "..."` argument and a heredoc `--body-file -`) plus the existing true positives (a bare `tools/ios_uitest.sh`, one inside `bash -c`, one after `&&`).

**How to measure.** False-positive tier blocks per session; the existing `tier_guard` test suite passes unchanged.

**Guardrails.** Do not exempt by command name (`gh`); exempt by structure (the text is a quoted argument or a heredoc body). A command the parser cannot read (unbalanced quote) stays blocked.

**Gain and effort.** Removes a recurring false positive. Effort: two hours. **Owner-only:** no (`tier_guard.py` is not in the fixed set; `tools/hooks/shell_parse.py` is, so only call it, never edit it).

**Sources.** Python: [`shlex`](https://docs.python.org/3/library/shlex.html). Claude Code: [hooks reference](https://docs.claude.com/en/docs/claude-code/hooks). In the repo: the owner's tier rule in AGENTS.md ("`tools/hooks/tier_guard.py` refuses unfiltered runs") and [testing README](../testing/apple/README.md#test-tiers).

### P10. A gate route for interactive owner requests (#280, owner-only, partly landed)

**Issue.** private app repo issue #280

**Why.** The app-UI gate (`design.matches_request`) vouched for a request only through a request-repo issue (`Owner-Request:`). An owner request made in an interactive session has none, so Jev answered `unsure` and #270 and #275 needed `--owner-ack`, which only the owner can type at a terminal. **`7a862403` landed most of the proposal:** a `UserPromptSubmit` hook (`tools/hooks/owner_prompt_log.py`, with `owner_prompt_guard.py`) logs the owner's typed prompts outside every worktree, and a PR's `Owner's request: "<quote>"` line counts when the quote appears in a prompt from the last 14 days and is at least 20 characters. The hook, the log folder and the matcher are protected paths. The owner's own words come from the harness, not from the agent, which was the requirement.

**What is left to decide (owner).**

1. Close #280 as done, or keep it open for what the hook does not cover: a request typed in a session the hook did not run in (a resumed session, another machine in the mesh), a request given as a voice note or in the Claude app, and a request whose quote was edited by the harness (line wrapping).
2. Check the gate on the next interactive owner request: the PR carries the quote line, `pr_land.sh N --dry-run` shows the gate passing without `--owner-ack`.
3. Decide whether the 14-day window and the 20-character floor are right.

**How to measure.** How often the owner has to use `--owner-ack`, target zero for requests typed in an attended session; the count of gate answers `unsure` on `design.matches_request` for PRs that carry a quote.

**Guardrails.** An agent message never vouches for a request. The quote is checked against the log, not trusted. The log lives outside every worktree and agents cannot write it.

**Gain and effort.** Removes the owner's terminal step for requests they typed. Effort: an owner decision plus one dry run. **Owner-only:** yes, it touches the gate, `lane_land.py` and `pr_land.*`.

**Sources.** Claude Code: [hooks reference](https://docs.claude.com/en/docs/claude-code/hooks) (`UserPromptSubmit`). In the repo: [pr-lifecycle](pr-lifecycle.md), [agent-roster](agent-roster.md) ("What code enforces today"), [propose-first](propose-first.md).

### P11. Protect `tools/ci_*.py` and the coverage quarantine file (#285, owner-only)

**Issue.** private app repo issue #285

**Why.** Every CI workflow runs `tools/ci_hygiene.py`, and the workflows are protected. The script now deletes worktrees and simulators on the owner's machines (A3, `630d9f20`). [ci](ci.md)'s security section says a change to `tools/ci_*` needs the owner's eye. **Part of this changed since the issue:** `83c587db` put `tools/ci_hygiene.py` in `protected_paths` in `tools/triage/config.json`, so the lander treats it as protected. What remains outside the fixed set:

- the `scope` job filter in `.github/workflows/pr-checks.yml` (it decides which CI jobs run, so a change that routes an app change to "not app" would skip the tests);
- any future `tools/ci_*.py`, because the config lists files, not a glob;
- `tools/coverage_classify.py` and `tools/coverage_phases.sh` (they decide whether a failed test is real or coverage-only);
- `apple/coverage-quarantine.json`, which is data that can turn a failing test into a pass. It already requires an open `Workflow` issue per entry, but the lander does not check that the file is edited by the owner.

**Proposal.** Add `tools/ci_*.py` (a glob), `tools/coverage_classify.py`, `tools/coverage_phases.sh` and `apple/coverage-quarantine.json` to `protected_paths`. A quarantine entry then lands only in an owner PR, with the issue number the classifier already requires. Because the lander itself is protected, only the owner can make this change.

**How to measure.** `python3 tools/lane_land.py` refuses a test diff that touches one of the new paths (add a fixture in `tools/tests`); the number of quarantine entries equals the number of open `Workflow` + quarantine issues.

**Guardrails.** Do not make the glob so wide that a doc under `tools/` becomes protected. Keep the quarantine rule: every entry needs an open issue and the threshold stays at 95%.

**Gain and effort.** Closes the way a lane could weaken CI or the coverage gate without the owner seeing it. Effort: minutes for the list, an hour for the fixture. **Owner-only:** yes (the lander and the config are in the fixed set).

**Sources.** GitHub: [about code owners](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners) (the platform way to require a named reviewer for given paths; ours is the lander's `protected_paths`), [security hardening for Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions). In the repo: [ci](ci.md) (security section), `tools/triage/config.json`.

### P12. Jev: one rule for question versions (#276)

**Issue.** private app repo issue #276

**Why.** Two rules disagree.

- `tools/jev_ask.py` and [decision-models](decision-models.md) say to **bump `version` whenever wording, criteria or state change**, because Jev reads literally and answers and measurements are attributed to `id@version`.
- `tools/tests/test_jev.py` `GeneratedQuestionTests.test_every_proposal_question_is_a_versioned_unmeasured_shadow_with_an_output` (around line 660) pins every proposal and shadow question to `(version, mode) == (1, "shadow")`.

Both #270 and #269 synced the criteria of shadow questions (`learning.home`, `research.release_impact`) and kept them at version 1 so the test would pass. That follows the test and breaks the tool's rule: a shadow answer logged under `learning.home@1` can come from two different wordings.

**Options.**

1. **Shadow questions stay at version 1 until measured.** Simple, matches the test. Cost: answers from before and after a criteria change share an id, so a shadow measurement mixes wordings. Mitigate by recording a content hash of the criteria in the shadow record.
2. **The version counts every criteria change**, and the test accepts version 1 or higher for unmeasured questions (`mode == "shadow"` and `evidence == "unmeasured"` remain the pins). Cost: a version bump on every `sync`. Benefit: measurements are attributable, which is the point of versioning.

Option 2 keeps the tool's rule true and weakens only the version number in the test, not the mode, evidence or output pins. The agent-side change is small; the thresholds and graders are owner-only and are not part of this.

**What to try.** Pick one (record it in decision-models.md). Then make the three agree: the sentence in `jev_ask.py`, the assertion in `test_jev.py`, and the paragraph in decision-models.md. If option 2: have `jev_ask.py sync` bump the version of any question whose generated criteria changed, and run `jev_ask.py sync --check` in CI (it already runs in `repo-checks`).

**How to measure.** `python3 tools/jev_ask.py sync --check` is clean; `test_jev.py` passes; a criteria change in a fixture bumps the version.

**Guardrails.** `jev_ask.py`, `jev_measure.py`, `jev_gate.py`, thresholds and graders are in the fixed set: an agent writes the decision, the owner lands the tool change. Questions under `contracts/jev/questions/` may be edited by an agent, but never a threshold.

**Gain and effort.** Correct attribution of shadow answers. Effort: an hour once decided. **Owner-only:** the tool and test edits are (`tools/jev_ask.py` is protected); the decision record is not.

**Sources.** In the repo: `tools/jev_ask.py`, `tools/tests/test_jev.py`, [decision-models](decision-models.md), [jev-corpus](jev-corpus.md). No outside source applies: the version rule is ours.

### P13. Motion gallery: lower cards move 52 pt (#271)

**Issue.** private app repo issue #271

**Why.** `MotionJourneyTests` runs only under the Capture plan (Gate skips the class). On iPhone with Capture it executed 37 tests: 26 passed and 11 failed, all with one pattern. On the lower gallery cards (`controllerToggle`, `pagedRow`, `pageIndicator`, `percentSlider`, `scheduleFields`, each in the normal and the Reduce Motion variant) the card's y differs by 52 pt after the toggle tap. The journey requires the card not to move (`assertSameFrame` in `toggle(_:in:)`). Before #270 every journey failed on SwiftUI ids, so these 11 are the first real signal; #270 landed with the class as is (decision note `T-catalog-uikit-sources`). The issue names ten (five cards, two variants); take the eleventh from the first Capture run's log.

**Three candidates, in order of cost to rule out.**

1. **The scroll is still settling.** `reveal(_:in:)` swipes with `velocity: .slow` until `isHittable`, then the test reads `before = component.frame`. A swipe's deceleration can finish after `isHittable` turns true, so `before` is read mid-scroll and `after` at rest. A 52 pt jump is a short coast. Fix in the test: wait for rest before reading `before` (poll the frame until two reads 200 ms apart agree).
2. **The large title collapsing.** The gallery uses a large title; scrolling collapses it by a fixed amount, and 52 pt is near a collapsed large title's height difference. If the tap scrolls the content (the lower cards are near the bottom, and tapping a button can scroll it into view), the title collapses and every frame moves. Check `UINavigationBar.prefersLargeTitles` and the gallery's `contentInsetAdjustmentBehavior`.
3. **A real layout jump.** The toggle changes the card's content (a state line, a colour fade) and the card or its section re-lays out. Only the lower cards are affected, which fits a section whose height depends on the cards above it. This one is a product bug and needs the component fixed.

**What to try.**

1. Reproduce one card on a simulator in a devcap hold with the Capture plan (`tools/ios_uitest.sh --only iphone --plan Capture --tests MotionJourneyTests/testEveryComponentControllerToggleTogglesItsState`), and record a short video (`xcrun simctl io <udid> recordVideo`, inside the hold).
2. Add temporary logging of `scrollView.contentOffset` and `isDecelerating` at `before` and `after` (UIKit), or read `frame` twice in the test. If the offset moved between the reads, it is cause 1; if only the title bar's height changed, cause 2; if neither, cause 3.
3. Fix the cause. For 1, add a shared "wait for rest" helper next to `reveal` (used by every journey that reads a frame after a reveal; the reveal helpers in `JourneyTestCase.swift` are the canonical place). For 2, make the gallery's title behaviour deterministic (no collapse during the test, or measure relative to the title). For 3, fix the component and add a unit test.

**How to measure.** `MotionJourneyTests` passes 37 of 37 on iPhone, Duo and iPad (Capture plan, one family at a time); then decide whether the class belongs back in Gate. The layout case (3) also needs a frame-stability unit test on the component.

**Guardrails.** Do not widen `assertSameFrame`'s tolerance, skip the lower cards or move the check before the tap: the journey exists to prove a toggle does not move its card. Motion tests stay at real animation speed. A product change goes through [propose-first](propose-first.md).

**Gain and effort.** Gets the motion gallery's only automated check back; if cause 3, fixes a visible jump. Effort: half a day to diagnose, longer if a component changes. **Owner-only:** no.

**Sources.** Apple HIG: [Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles) (a toggle changes state in place), [Scroll views](https://developer.apple.com/design/human-interface-guidelines/scroll-views). UIKit: [`UIScrollView.isDecelerating`](https://developer.apple.com/documentation/uikit/uiscrollview/isdecelerating), [`contentOffset`](https://developer.apple.com/documentation/uikit/uiscrollview/contentoffset), [`contentInsetAdjustmentBehavior`](https://developer.apple.com/documentation/uikit/uiscrollview/contentinsetadjustmentbehavior-swift.property), [`UINavigationBar.prefersLargeTitles`](https://developer.apple.com/documentation/uikit/uinavigationbar/preferslargetitles). XCUITest: [`XCUIElementAttributes.frame`](https://developer.apple.com/documentation/xcuiautomation/xcuielementattributes/frame), [`isHittable`](https://developer.apple.com/documentation/xcuiautomation/xcuielement/ishittable). In the repo: `apple/Apps/iOSUITests/MotionJourneyTests.swift`, `build/decisions/T-catalog-uikit-sources.md` in the section-sides worktree.

### P14. Vacuums pane: translucent header covers the first switch (#272)

**Issue.** private app repo issue #272

**Why.** Found by the section-sides Verifier and confirmed by the Designer (verdict V3, 2026-11-04); already broken before that change. On a partly folded iPhone Duo the Vacuums trailing pane shows a translucent header bar. Its "Auto-Clean" title is blurred and unreadable, and the bar covers the switch in Main Floor's first row. Evidence in the section-sides worktree: `build/evidence/claude-section-sides/before/` and `build/evidence/claude-section-sides/after/duo-partial-fold/vacuums--uikit-inner.png` (and `vacuums--scrolled--uikit-inner.png`).

**What to try.**

1. Reproduce on the partly folded Duo with the pose tooling (`pose-matrix` skill) and the Vacuums page: `apple/Sources/HassUI/UIKitPort/Features/Vacuums/` (`UKVacuumsEntry.swift`, `UKVacuumTabs.swift`, `UKVacuumSheet.swift`).
2. Find who owns the translucent bar: a navigation or section header drawn as a `UIVisualEffectView` over the scrolling content in the trailing pane. In the split, the pane's content inset must start below the bar, or the bar must sit above the pane instead of floating over its first row. Check the scroll view's `contentInsetAdjustmentBehavior` and `adjustedContentInset.top` in the pane against the bar's height.
3. Fix it in the canonical component the other panes use (section headers and the sticky-header pattern, [status-rail](../patterns/status-rail.md) and the page-base pattern), not in the Vacuums page alone, then sweep the other panes that use the same bar for the same inset error.
4. Add a UX test and an accessibility test on Duo (partly folded) and iPad landscape: the first row's switch is hittable and not covered (frame test), the header title has name and role, targets at least 44 pt, AX5 text does not clip.

**How to measure.** `pose-matrix` evidence pack on the Duo partial fold, iPad landscape and iPhone: the first row's switch is fully visible at rest and when scrolled to the top; `isHittable` is true; AX5 screenshot.

**Guardrails.** A visible change goes through [propose-first](propose-first.md) if there are options (blur over content, or solid header, or no header). The text must stay readable: HIG says a material needs enough contrast behind content. Keep the one canonical header; do not add a Vacuums-only one.

**Gain and effort.** Fixes a readable-text and covered-control bug on the Duo. Effort: half a day. **Owner-only:** no.

**Sources.** Apple HIG: [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) (use materials so text stays legible), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) (safe areas and not covering content), [Split views](https://developer.apple.com/design/human-interface-guidelines/split-views), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility). UIKit: [`UIVisualEffectView`](https://developer.apple.com/documentation/uikit/uivisualeffectview), [`adjustedContentInset`](https://developer.apple.com/documentation/uikit/uiscrollview/adjustedcontentinset). In the repo: [split-view](../design/apple/split-view.md).

### P15. One status chip (#273)

**Issue.** private app repo issue #273

**Why.** Two implementations of the status chip exist: `UKStatusChipView` (`apple/Sources/HassUI/UIKitPort/Design/UKStatusChipView.swift`, a `UIControl`) and `UKRoomChipView` (`apple/Sources/HassUI/UIKitPort/Features/Rooms/UKRoomsParts.swift`, also a `UIControl`). The pattern-first rule calls for one canonical component per pattern ([status-rail](../patterns/status-rail.md)). The T-section-sides design verdict V1 gave both the same wrap and corner rules, so they now match by copy, which is the drift risk: the next rule change lands in one and not the other.

**What to try.**

1. Diff the two: properties, states (selected, pressed, disabled), accessibility traits and labels, the icon and count slots, how each sizes to Dynamic Type.
2. Extend `UKStatusChipView` with whatever the room chip has that it lacks (a configuration struct or style, not a subclass), keeping its public API stable, and port `UKRoomChipView`'s callers to it. Use a `UIButton.Configuration`-style value type if the chip is button-like, rather than more subviews.
3. Delete `UKRoomChipView`, update `contracts/components.json` (regenerate with `python3 tools/components_index.py`) and `contracts/patterns.json` so `pattern_guard.py` shows one canonical owner.
4. Sweep: `grep -rn "UKRoomChipView" apple` for callers and tests; update the Rooms mockups only if what is drawn changes (it should not), and the atlas rule in AGENTS.md if it does.
5. Tests: the existing chip tests for both, merged; one accessibility test for the combined chip (name, role, state, 44 pt, AX5 wrap) on iPhone, Duo and iPad.

**How to measure.** `grep` finds one chip class; `python3 tools/pattern_guard.py` passes with the chip owned once; `swift test --filter` for the chip and Rooms suites and the Rooms and Home journeys pass on iPhone, with Smoke on Duo and iPad; screenshots before and after are pixel-identical in the Rooms and Home chip rows (`pose-matrix`).

**Guardrails.** Behaviour-neutral: no visible change. If the merge needs a visible choice, stop and use propose-first. Do not leave a typealias or wrapper that keeps the second class alive.

**Gain and effort.** One component, one place for the next chip rule. Effort: a day with the sweep and tests. **Owner-only:** no.

**Sources.** Apple HIG: [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Collections](https://developer.apple.com/design/human-interface-guidelines/collections) (consistent items), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility). UIKit: [`UIControl`](https://developer.apple.com/documentation/uikit/uicontrol), [`UIContentSizeCategory`](https://developer.apple.com/documentation/uikit/uicontentsizecategory). In the repo: [status-rail](../patterns/status-rail.md), [patterns README](../patterns/README.md).

### P16. Fix the two capture paths (#274)

**Issue.** private app repo issue #274

**Why.** The T-section-sides Verifier found two capture paths that do not work (2026-11-04):

1. **`FENTON_DEBUG_SETTINGS_PANE` opens only the placeholder** on a partly folded Duo (three attempts, one with a 20 s wait), so the Vacation topics in the Settings pane could not be captured. The hook is in `UKSettingsViewController.viewDidAppear`: it waits a fixed 3 seconds, then calls `show(.route(.vacation))` (or `.adminTodo`, `.performance`, or a household page). If the split has not formed yet at the time the 3 seconds end, or the controller's `viewDidAppear` ran before the window split, `show` falls into the single-column path or the placeholder. A longer fixed wait did not help, which points at a state the pane never reaches rather than a late split.
2. **The iPad landscape Home journey selector matches nothing.** A run filtered to `testHomeSplitsOnTheHingeOnlyWhenUnfoldedInLandscape` with `--env shell` reported `EMPTY: no tests ran`. `Gate.xctestplan` lists the test under `skippedTests`; `Live.xctestplan` selects it. So the run used Gate, and Gate skips it (P3 would have refused it before the build).

**What to try.**

1. For the pane: instead of `asyncAfter(3)`, act when the split exists. Observe the split controller's `isCollapsed` / `displayMode` (or the fold-columns policy's geometry) and call `show` when the pane exists; add a fallback `viewDidLayoutSubviews` retry. Print one `os_log` line when the hook runs and what `show` did, so a failed capture says why. Keep it DEBUG-only ("a probe, never in a release build").
2. Check that the Vacation route is reachable in the pane at all on a partial fold: a route that returns the placeholder when the pane is not the topmost detail would explain the three failures.
3. For the selector: run it with `--plan Live` (or add `--plan` to the capture instructions in [devices](../testing/apple/devices.md)), and note that on an iPad it passes by checking the one-column layout (the test says "Not a skip when it does not apply"), so a capture of the Duo unfolded landscape layout must run on the Duo family, not iPad; the issue's title asks for an iPad landscape capture, which the test's else-branch will not draw as split. Decide with the Designer which layout "iPad landscape Home" is meant to show (iPad landscape may split, per `SplitPolicy`) and write a capture-only test (Capture plan) that does not assert, only screenshots, if the journey is not the right tool.
4. Then capture the Vacation topics in the pane and iPad landscape Home, and attach them to the section-sides evidence for the Designer.

**How to measure.** The debug hook opens `vacation` in the pane on a partly folded Duo within the hold on the first attempt; the capture run reports a non-zero executed count; screenshots land in `build/evidence/<branch>/`.

**Guardrails.** Debug hooks stay out of release builds. Do not add a fixed longer wait as the fix. Do not weaken the journey's assertions to make it capture.

**Gain and effort.** Two capture paths the design process needs. Effort: half a day. **Owner-only:** no.

**Sources.** Apple HIG: [Split views](https://developer.apple.com/design/human-interface-guidelines/split-views), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout). UIKit: [`UITraitCollection.horizontalSizeClass`](https://developer.apple.com/documentation/uikit/uitraitcollection/horizontalsizeclass). XCUITest: [`XCUIApplication.launchEnvironment`](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/launchenvironment) (how a debug switch reaches the app). Apple: [organizing tests to improve feedback](https://developer.apple.com/documentation/xcode/organizing-tests-to-improve-feedback). In the repo: [devices](../testing/apple/devices.md), [split-view](../design/apple/split-view.md), `apple/TestPlans/Gate.xctestplan`, `apple/TestPlans/Live.xctestplan`.

## 4. Tried or rejected

| Idea | Why not | Date |
|---|---|---|
| A hand-off note and a session stop at a share of the context window or a turn cap (`contracts/session-caps.json`, `context_guard`) | Removed in #269: the owner struck it. A session continues; `build/handoff/<topic>.md` is only for genuinely blocked work (infra, an owner-only item, a slot wait over 20 minutes) and is never written because of context size or turn count ([token-economy](token-economy.md)) | 2026-11-03 |
| Folding a lane that deletes tests into an owner PR to get past `lane_land` | `lane_land` refuses a lane that runs fewer tests or suites than the base, or loses a test id that is not a rename or a retired tool's (`tools/lane_land.py`, "a lane cannot run fewer tests than the base"). Moving the deletion into an owner PR dodges a check that exists on purpose. Retire a test with its tool in the lane, or get the owner to approve the deletion explicitly | 2026-11-04 |
| Bumping Jev `learning.home` to version 2 on a criteria sync | `test_jev.py` pins proposal and shadow questions to version 1, so #269 and #270 kept version 1. Kept until P12 decides | 2026-11-04 |
| Relaxing the mockup checker for the port window, or remapping only the catalog | Hides drift (a guard weakened to hide drift) or leaves the lander blocked for every lane; the catalog and the HTML source lists were remapped instead (`T-catalog-uikit-sources`, option a) | 2026-11-03 |
| Making the aggregate `pr-checks` wait on a base push run | Touches the merge path (`REQUIRED_CHECKS` in `pr_land.py`); P1 leaves the aggregate alone | 2026-11-04 |
| Waiting longer for `FENTON_DEBUG_SETTINGS_PANE` | A 20 s wait still showed the placeholder; the wait is not the cause (P16) | 2026-11-04 |
| Rerunning the 40-minute instrumented suite after each fix | The same set failed over six SHAs; rerun only the failed ids and compare with the base (P4, P5; the "rerun changed only" rule) | 2026-11-04 |
| Agent self-vouching for an owner request | An agent message is never consent; the harness-written prompt log is the route (P10) | 2026-11-04 |

## 5. How to measure

**Retro digest.** `python3 tools/retro_digest.py` builds `build/retro/<task>.json` from the ledger, the gate, shadow and review records. Triggers to watch, with the target for each:

| Trigger | Target |
|---|---|
| `review_rounds_over_cap` | none |
| `routing_override` | none for requests typed in an attended session |
| `repeated_long_device_rounds` | at most one full run plus cheap reruns per task |
| `empty_runs` | none |
| Hub-guard blocks per session | at most one per distinct file set |
| False-positive guard blocks per session | none |
| `Disk pre-flight` failures per week | none |
| Inherited red checks per PR into the base | none |

**Before and after.** For a tooling item take the metric over the last ten tasks before the change and the next ten after, from the retro digests. A single task proves nothing.

**CI health.** `gh run list --branch claude/uikit-port --workflow pr-checks --limit 50 --json conclusion,headSha,createdAt` for the base's red share once P1 lands; `gh run list --workflow pr-checks --json conclusion` for failures that name `Disk pre-flight`.

**Divergence.** `git rev-list --left-right --count claude/uikit-port...origin/claude/uikit-port` (P0, target `0 0`), and `git merge-tree --write-tree --name-only A B` for a trial merge.

**Guards.** Run a guard's tests (`python3 -m unittest tools.tests.test_<guard>`), then replay the false positives from this file as fixtures; a guard change is proven by a fixture that failed before, not by a clean run.

**Device items.** Test and journey timing follows the A/B method in [test-speed-roadmap](../testing/apple/test-speed-roadmap.md#5-how-to-measure); every simulator step runs inside a `tools/devcap.py` hold.

**Owner-only items.** Write the evidence (logs, the false positive, the digest line) into the issue so the owner decides from one page, and leave the issue open and labelled `On Hold`.

## 6. Sources

**In the repo**

- Post-mortem: `build/retro/T-section-sides-postmortem.md` and `T-section-sides.json` in the section-sides worktree (`.claude/worktrees/section-sides`); decision `build/decisions/T-catalog-uikit-sources.md`; design record `.agents/design/section-sides.md` (on `origin/claude/uikit-port`).
- Workflow: [agent-roster](agent-roster.md), [pr-lifecycle](pr-lifecycle.md), [token-economy](token-economy.md), [eval-gate](eval-gate.md), [ci](ci.md), [decision-models](decision-models.md), [capacity](../platforms/apple/capacity.md).
- Testing: [coverage](../testing/apple/coverage.md), [devices](../testing/apple/devices.md), [journey-speed](../testing/apple/journey-speed.md), [test-speed-roadmap](../testing/apple/test-speed-roadmap.md).
- Code: `tools/pr_land.sh`, `tools/pr_land.py`, `tools/lane_land.py`, `tools/ci_hygiene.py`, `tools/hooks/merge_guard.py`, `tools/hooks/tier_guard.py`, `tools/hooks/mockup_hub_guard.py`, `tools/hooks/orchestrator_guard.py`, `tools/hooks/shell_parse.py`, `tools/jev_ask.py`, `tools/apple_coverage.sh`, `tools/ios_uitest.sh`, `.github/workflows/pr-checks.yml`, `tools/triage/config.json`; origin only: `tools/coverage_classify.py`, `tools/coverage_phases.sh`, `tools/lane_base.py`, `tools/ship_guard.sh`, `apple/coverage-quarantine.json`.

**GitHub**

- [Workflow syntax (`on.push.branches`)](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions)
- [Webhook events and payloads (`push`: `before`, `after`)](https://docs.github.com/en/webhooks/webhook-events-and-payloads)
- [Security hardening for GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions)
- [About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [About code owners](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)

**Git**

- [`git rev-list`](https://git-scm.com/docs/git-rev-list), [`git merge-tree`](https://git-scm.com/docs/git-merge-tree), [`git merge-base`](https://git-scm.com/docs/git-merge-base), [`git diff`](https://git-scm.com/docs/git-diff), [`git merge`](https://git-scm.com/docs/git-merge), [`git cherry`](https://git-scm.com/docs/git-cherry)

**Claude Code, Python, shells, Gerrit**

- [Claude Code hooks](https://docs.claude.com/en/docs/claude-code/hooks) (PreToolUse, SessionStart, Stop, UserPromptSubmit, exit code 2)
- [Python `shlex`](https://docs.python.org/3/library/shlex.html)
- [Bash shell syntax](https://www.gnu.org/software/bash/manual/html_node/Shell-Syntax.html)
- [Gerrit label configuration (`copyAllScoresOnTrivialRebase`)](https://gerrit-review.googlesource.com/Documentation/config-labels.html)

**Apple: Human Interface Guidelines**

- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Split views](https://developer.apple.com/design/human-interface-guidelines/split-views), [Scroll views](https://developer.apple.com/design/human-interface-guidelines/scroll-views), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Toggles](https://developer.apple.com/design/human-interface-guidelines/toggles), [Collections](https://developer.apple.com/design/human-interface-guidelines/collections), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)

**Apple: documentation**

- [Organizing tests to improve feedback](https://developer.apple.com/documentation/xcode/organizing-tests-to-improve-feedback), [`XCTestCase`](https://developer.apple.com/documentation/xctest/xctestcase)
- [`XCUIElementAttributes.frame`](https://developer.apple.com/documentation/xcuiautomation/xcuielementattributes/frame), [`isHittable`](https://developer.apple.com/documentation/xcuiautomation/xcuielement/ishittable), [`XCUIApplication.launchEnvironment`](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/launchenvironment)
- [`UIScrollView.isDecelerating`](https://developer.apple.com/documentation/uikit/uiscrollview/isdecelerating), [`contentOffset`](https://developer.apple.com/documentation/uikit/uiscrollview/contentoffset), [`adjustedContentInset`](https://developer.apple.com/documentation/uikit/uiscrollview/adjustedcontentinset), [`contentInsetAdjustmentBehavior`](https://developer.apple.com/documentation/uikit/uiscrollview/contentinsetadjustmentbehavior-swift.property)
- [`UINavigationBar.prefersLargeTitles`](https://developer.apple.com/documentation/uikit/uinavigationbar/preferslargetitles), [`UIVisualEffectView`](https://developer.apple.com/documentation/uikit/uivisualeffectview), [`UIControl`](https://developer.apple.com/documentation/uikit/uicontrol), [`UIContentSizeCategory`](https://developer.apple.com/documentation/uikit/uicontentsizecategory), [`UITraitCollection.horizontalSizeClass`](https://developer.apple.com/documentation/uikit/uitraitcollection/horizontalsizeclass)
