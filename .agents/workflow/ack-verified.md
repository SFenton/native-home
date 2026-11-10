# Spec: `ack-verified`, an agent-runnable acceptance of a PR-only move of main

Date 2026-11-10. Entry B (owner request). Author: Steward. Implementer: Coder, from this file alone.
Ships as ONE PR that the owner approves (CODEOWNERS) and merges. It is not a lane: the kill switch (`SELF_CHANGE_PAUSED`) is on and the change touches the owner's fixed set.

## Owner request (quotes, 2026-11-10)

- "update rules to allow agents to run these commands and then update"
- "Run it for me? Stop asking me and just do it"
- Coordinator approval of the narrow reading: a new `ack-verified` verb for agent sessions; `ack-base <sha>` and `--owner-ack` unchanged and owner-only.

## Problem

`SELF_CHANGE_PAUSED` fires whenever `origin/main` moves without the runner. PRs #36, #37, #45, #48, #50, #47, #46 landed through GitHub's ruleset `main-checks` (squash only; required checks `pr-checks` app 15368 and `ai-review` app 5618837; code-owner review required; no bypass actors). Only the owner can clear the pause, and `ack-base` needs a typed SHA while main keeps moving ("main moved again").

## Step 0 result (done: root cause found, read-only)

The runner already has an automatic PR-only acceptance (`Runner.pr_moves_ok` / `moves_are_merged_prs`, `tools/triage/hass_triage.py` ~1577-1618). It did NOT accept today's range `970dfdb..45c4cf7` because of ONE commit:

| sha | PR | `gh api commits/<sha>/pulls` |
|---|---|---|
| 4b86f73 | #36 | `[]` (empty). GraphQL `associatedPullRequests` is also `[]` |
| ab3d1db | #37 | ok |
| 456c68e | #45 | ok |
| 42900cb | #48 | ok |
| 3ab928a | #50 | ok |
| e3371de | #47 | ok |
| 45c4cf7 | #46 | ok |

Yet `gh api repos/SFenton/native-home/pulls/36` says: merged_at 2026-11-10T15:03:34Z, base main, `merge_commit_sha` = 4b86f73, head 7fbad2c, and head 7fbad2c has `pr-checks` and `ai-review` both `success`. So GitHub's commit-to-PR index has a gap; the PR record itself is sound. `moves_are_merged_prs` treats "no answer" as "not a PR" and pauses (correct to fail closed, but the lookup is the weak part). Ancestry holds (970dfdb is an ancestor of origin/main), every commit has one parent and committer `GitHub`.

Everything else I suspected (the runner's `gh` login after #45, the 200 cap, the land clone) is ruled out: the `sfenton-agent` login reads all of this fine, `~/hass-agents/land/native-home` exists, and the range is 7 commits.

**Fix for the lookup (part of the verifier below):** when `commits/<sha>/pulls` returns no PR that matches, fall back to the number in the squash subject `(#N)` (a hint only) and fetch `repos/<repo>/pulls/N`. Accept the commit only if that record itself says `merged_at` set, `base.ref == base`, and `merge_commit_sha == sha`. A forged subject cannot pass, because GitHub's own PR record must name this exact commit as its merge commit. No `(#N)` or no match: fail.

## Behaviour to build

### 1. Shared verifier `Runner.verify_pr_range(base, expected, head) -> Tuple[bool, List[dict], str]`

Returns (ok, per-commit evidence list `{sha, pr, head_sha, contexts}`, reason of the first failure). Replaces the body of `moves_are_merged_prs`; `pr_moves_ok` calls it. It runs against the `land_clone()` after fetching `+refs/heads/<base>`.

Range: `expected` must be an ancestor of `head` (else "force push?"). `git rev-list --first-parent --max-count=BASE_WALK_CAP+1 expected..head`; empty or over `BASE_WALK_CAP` (200) fails.

Each commit passes only if ALL of these hold:

1. **One parent.** `git rev-list --parents -n1 <sha>` shows exactly one parent.
2. **GitHub made it.** `gh api repos/<repo>/commits/<sha>`: `commit.verification.verified` is true and `commit.committer.name` / `committer.login` is GitHub (`web-flow`). A direct push by an agent or the owner's git fails this.
3. **A merged PR owns it.** From `commits/<sha>/pulls`, or the `(#N)` fallback above: `merged_at` set, `base.ref == base`, `merge_commit_sha == sha`. If more than one PR claims the sha, pick the one that matches; none matching fails.
4. **Required checks passed on the PR head.** `pr.head.sha` is the sha the checks ran on (not the squash commit). The required contexts and integration ids come from the LIVE rules (`ruleset_gate.fetch_rules`), never hardcoded (today `pr-checks`/15368 and `ai-review`/5618837). For each context, read `commits/<head_sha>/check-runs` (paginate; `app.id` must equal the integration id; take the newest run of that name; `conclusion == "success"`) and, if no check run exists, `commits/<head_sha>/status` (`context` and `state == "success"`). Missing, failed, skipped, neutral, or a wrong app id fails.
5. **Ruleset is live and unbypassable** (once per range, not per commit): `ruleset_gate.check` passes, the rules include `pull_request` and `required_status_checks`, and the active ruleset has no bypass actors. `main-merge-actor` (disabled) is ignored.
6. **Rules did not change mid-range** (once per range): the active ruleset `updated_at` is not later than the oldest `merged_at` in the range. If it is, fail with "ruleset changed inside the range: owner reviews". (May over-refuse after a ruleset edit. Intended.)

Lookups: retry once on exception; a second failure fails the range. No answer is never taken as a PR. All-or-nothing: no partial acceptance. The first failure's sha and reason are printed.

CODEOWNERS approval is not re-verified: the ruleset enforces `require_code_owner_review` for merged PRs and there are no bypass actors (item 5). Leave a comment in the code saying so.

Extend `tools/ruleset_gate.py` with a function `live_requirements(repo, branch) -> dict` returning `{contexts: [(name, integration_id)], bypass_actors: [...], updated_at, problems: [...]}`; keep `check()` and its CLI exit codes unchanged.

### 2. `check_base` uses the verifier

`pr_moves_ok` keeps its guard (`base == product_base`) and calls `verify_pr_range`. So ordinary PR merges (including the (#36) lookup gap) stop pausing, and a failing or missing check now pauses where before only "merged" was needed. Print the reason on failure.

### 3. New CLI verb `ack-verified` (no SHA argument)

`python3 tools/triage/hass_triage.py ack-verified`

- Refuses (exit 2, message) when `FENTON_HEADLESS=1` or `HASS_TRIAGE_ISSUE` is set. No TTY needed. So the runner's lanes and workers can never clear their own pause; interactive orchestrator sessions and the owner can.
- Needs a pending `SELF_CHANGE_PAUSED` (else "nothing to acknowledge", exit 1).
- `Runner.ack_verified()`:
  1. `expected` = `workflow-base.json[base]` (the last accepted SHA), NOT the pause's first-trip SHA.
  2. `head = remote_base_sha(base)`; run `verify_pr_range(base, expected, head)`. Failure: exit 1, print the reason, leave the pause untouched, tell the caller "owner: `ack-base <sha>`".
  3. Moving target: take the base lock, re-read `remote_base_sha`. If it moved, verify only `verified_head..new_head` and repeat, at most 3 rounds; if it still moves after round 3, record the last verified head anyway (the next tick verifies the rest through `check_base`).
  4. Write `workflow-base.json` = the LAST VERIFIED head, unlink `SELF_CHANGE_PAUSED` and `SELF_CHANGE_PAUSED.json`, append one line to `~/hass-agents`-independent state file `~/.local/state/hass-triage/ack-log.jsonl`: `{at, mode:"verified", from, to, prs:[numbers], contexts, session:"agent"|"owner"}` (`agent` when `agent_type`-style markers or `CLAUDE_CODE`-set env say so; simplest: `"owner"` iff stdin is a TTY and not headless, else `"agent"`).
  5. Print the PR list ("Accepted 7 PR merges: #36 #37 ... head 45c4cf7").
- `ack-base <sha>` and `ack_base()` are unchanged. `--owner-ack` (`tools/pr_land.py`) is unchanged and stays owner-only: it skips the app-UI gate, which is a different safety question.
- Update the pause texts (`pause_text`, `base_moved` reason) to say: "accept with `python3 tools/triage/hass_triage.py ack-verified` when every move is a checked PR merge; for anything else the owner runs `ack-base <sha>` from a terminal." Keep `status` (`pause_info`, ~2849) working: `ack_base` stays the pending SHA; add `ack_verified_hint` only if the tests need it.

### 4. Hooks and deny lists

- `tools/hooks/merge_guard.py`: the `ack[-_]?base` patterns (module docstring ~25, ~251, ~1204) STAY; `ack-verified` does not match them. Add an explicit allow for the exact form `python3 tools/triage/hass_triage.py ack-verified` (or an absolute path to `hass_triage.py`) in non-headless sessions. Headless sessions block it (`headless()` true: new reason string "ack-verified in a headless session"). The pty rule at ~249 (`script|expect|unbuffer`) must also name `ack-verified`, and a chained or piped command around it is refused. Do not touch the `--owner-ack` refusal.
- `tools/triage/config.json`: `Bash(*ack-base*)` (line 26) and `Bash(*owner-ack*)` (line 76) stay. Add `Bash(*ack-verified*)` to the headless worker `disallowed_tools` next to line 26. The reviewer deny list (`hass_triage.py` ~2223) already denies `*hass_triage*`; add `Bash(*ack-verified*)` beside `*ack-base*` for clarity.
- No other hook mentions `ack-base`.

### 5. Docs and agent prose (all under CODEOWNERS)

- `.agents/workflow/agent-roster.md` fixed set (line 76): replace "and `ack-base` / `--owner-ack`, which stay owner terminal actions in code" with "and `ack-base <sha>` / `--owner-ack`, which stay owner terminal actions in code (`ack-verified`, owner 2026-11-10, accepts only a range of squash-merged PRs that passed the live ruleset's required checks, and agent sessions may run it)". Add one bullet under "What code enforces today" describing the verifier, with the owner quote "update rules to allow agents to run these commands and then update". Keep the words `credential`, `signing`, `physical`, `ack-base` so `tools/tests/test_bloat.py` keyword checks still match; do not add a new L3 item.
- `.agents/workflow/triage-agent.md` line 81 (base-integrity monitor): replace "(agents never run this)" language with the two verbs, the verifier rules above, the `(#N)` fallback, `ack-log.jsonl`, and "moving target: record the last verified head, `check_base` verifies the rest".
- `.claude/agents/steward.md` line 39 and `tools/triage/prompts/{retro,nightly,steward}.md` (lines 36, 95, 39): say "`ack-base <sha>` and `--owner-ack`" where they list the fixed set.
- Check size budgets in `tools/tests/test_bloat.py` after the edit; keep additions short.

## Tests that pin it (Coder writes; do NOT touch `evals/` in this PR)

Add to `tools/triage/tests/test_retro_p3.py` (it already has the `FakeGitHub` table helper at ~816, extend with `pull(n)`, `commit(sha)`, `check_runs(sha)`, `status(sha)`, `rules()`) and `test_retro_p4.py`:

Negative (each: `ack_verified` returns failure, pause files remain, `workflow-base.json` and `ack-log.jsonl` unchanged):
- direct push (committer not GitHub, or `verified` false); two-parent commit; force push (expected not an ancestor); unmerged PR; `merge_commit_sha` mismatch; commit with no PR and no `(#N)`; `(#N)` fallback whose `pulls/N` names a different merge commit; `pr-checks` failing, missing, skipped, or wrong `app.id`; `ai-review` missing; required context added to the live ruleset that the PR did not run; ruleset not live; bypass actor present; ruleset `updated_at` inside the range; range over the cap; lookup fails twice; empty range.

Positive:
- Today's real shape: 7 commits, one of them (4b86f73) empty from `commits/<sha>/pulls` but matched through `pulls/36` from the subject `(#36)`: accepted, pause cleared, `workflow-base.json` = head, log line has prs `[36,37,45,48,50,47,46]`.
- Moving target: head advances during verification; the increment is verified; the recorded sha is the last verified head; a later non-PR move re-pauses via `check_base`.
- `check_base` (no CLI) accepts the same range silently and updates the record; with a failing check it pauses and files the `Workflow` + `On Hold` issue.
- `ack_base` tests at p3 448-474 and p4 437-461 stay green unchanged.

CLI: `ack-verified` exits 2 with `FENTON_HEADLESS=1` and with `HASS_TRIAGE_ISSUE` set; runs with no TTY otherwise; `ack-base <sha>` still refuses non-TTY and headless (`test_ack_base_cli_refuses_headless_and_non_tty`).

Hook tests: `tools/tests/test_lane_land.py` ~1175 (`test_ack_base_is_blocked_headless_only`): keep; add `ack-verified` blocked headless and allowed interactive; ~1554: `script -q /dev/null ... hass_triage.py ack-verified` refused; `tools/tests/test_pr_land.py` ~780: `--owner-ack` still refused. `tools/tests/test_bloat.py`: a doc that lists `ack-verified` under the L3 fixed set is a contradiction (add the keyword check); the roster passes.

Evals (separate, later lane; action spec for a Coder, never in this PR): keep `evals/agents/routing-replay/cases/merge-guard-ack-base-headless.json`; add `merge-guard-ack-verified-headless` (blocked) and `merge-guard-ack-verified-interactive` (allowed), `merge-guard-ack-verified-pty` (blocked).

## Landing and the CODEOWNERS note

Every changed path is owned by `@SFenton` (`/.agents/workflow/`, `/.claude/`, `/tools/hooks/`, `/tools/triage/`, `/tools/ruleset_gate.py`), and the ruleset requires code-owner review. This PR needs the owner's CODEOWNERS approval and the owner merges it. It changes the owner's fixed set at the owner's explicit request (quotes above, 2026-11-10), so cite them in the PR description. An independent Reviewer reads it; the Coder or orchestrator does not self-merge. Because the pause is on, nothing here may be delivered as a self-change lane. After merge, the first `ack-verified` run clears today's pause.

## Metrics

- `SELF_CHANGE_PAUSED` trips per week caused by PR-only moves: target 0 (first week: expect 0 after this lands; the `(#N)` fallback removes the #36-style gap).
- Owner `ack-base <sha>` runs: only for non-PR moves.
- `ack-log.jsonl` has one line per accepted range, with the PR numbers.

## Risks noted

- GitHub's commit-to-PR index can be empty or lag; the fallback reads the PR record directly, which is the authority.
- A ruleset edit mid-range makes the verifier refuse; that sends the owner back to `ack-base`, by design.
- `verified: true` for web-flow commits depends on GitHub's signature; if GitHub ever changes this, the verifier fails closed.
