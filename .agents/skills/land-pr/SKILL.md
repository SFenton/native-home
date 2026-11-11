---
name: land-pr
description: Ships a finished branch as a pull request, gets it reviewed, records the verdict, arms the merge and waits on CI. Use when product work is ready to land, and as the Reviewer when recording a verdict.
---
# Land a pull request

> **What:** the steps from a finished branch to a merged pull request. **Read when:** work is ready to land, or you are the Reviewer recording a verdict. Rules: [pr-lifecycle](../../workflow/pr-lifecycle.md#landing).

1. **Ship.** `tools/ship.sh "Subject" --pr --note TEXT` commits with the trailers, pushes the branch and opens a draft pull request. Set `SHIP_TASK=<task>` so the PR notes start with it. `--note none` marks a change users will not notice ([versioning](../../workflow/versioning.md)).
2. **Wait on CI.** In the same turn start `tools/bg_run.py ci-N --timeout 7200 -- python3 tools/ci_wait.py N` in the background and end the turn ([ci](../../workflow/ci.md#waiting-on-ci)). Its digest ends with one `RESULT:` line.
3. **Review.** While CI runs, spawn the `reviewer` on the pushed head with a prompt that starts `opus-ok: final review` and names the pull request, the branch and the round.
4. **Record** (Reviewer only).
   1. Confirm `git rev-parse HEAD` in the branch's worktree is the pushed head; if it moved, review again.
   2. Write the verdict to a file: `{"verdict": "pass|changes|blocker", "findings": [{"severity": "blocker|major|minor", "rule": "...", "file": "...", "detail": "...", "fix": "..."}]}`. Leave `round` out; the recorder adds it.
   3. Run `python3 tools/review/record.py verdict.json --lane BRANCH` from that worktree, or add `--root WORKTREE` from elsewhere.
   4. After a `pass`, post the check: `python3 tools/review/record.py --post-check <head sha> --repo <product_repo>`, with `product_repo` from `tools/triage/config.json`.
   5. Post no review or comment with `gh pr review`.
5. **Fix.** On a failing check or a `changes` verdict, fix in small commits and push to the same branch. CI restarts and the new head needs its own review. `python3 tools/jev_hints.py findings build/review/<branch>.json` groups the findings into a checklist.
6. **Arm.** After a `pass`, run `tools/pr_land.sh N` (`--dry-run` prints the decision without acting). It arms auto-merge pinned to the reviewed head; GitHub merges when the required checks pass on that head.
7. **Report** the last line `pr_land.sh` printed, as it is: `merged`, `armed`, `blocked` with a reason, or `failed` with a reason. When it also prints commands for the owner, report them and do not run them.
   - "carries #A, #B": those pull requests close as included once this one merges.
   - "do not merge; included in #M": merge #M instead; run no commands for this one.

## When a step refuses

| Message | Do |
|---|---|
| `blocked: no independent pass` | Run step 3 on the current head, then step 6 |
| `blocked: merge conflicts` | Merge the base branch, test the touched area, push, review again |
| `blocked` with blockers | Fix them, or finish `needs_decision` when only the owner can decide |
| `failed` | Report the `gh` or git message as it is |
| A hook refusal | Follow its message ([agent-roster](../../workflow/agent-roster.md#guards)) |
