# PR lifecycle

> **What:** how work travels from a worktree to `main`: lanes, shipping, the independent review, the merge and the notes on the pull request. **Read when:** starting a lane, opening a pull request, reviewing one, or waking on a CI or review event.

## Worktrees

- Every session works in its own linked worktree, never in the shared primary checkout. `tools/hooks/worktree_guard.py` refuses edits, commits and branch changes there; reading and fetching stay allowed.
- A lane is cut with `tools/lane_new.sh` and started with `tools/lane_check.py start`, which refuses a lane that overlaps an open pull request or a recent commit. Join the existing work; never open a parallel pull request.
- Nothing is merged, cherry-picked or committed onto a local copy of the base branch; `tools/base_drift.py` lists local-only commits.
- A base merge into a pull-request branch runs in that branch's own worktree.
- Before dispatching into an existing worktree, confirm it is idle: no running job, no recent edit. A live agent gets a message, not a second agent.

## Shipping

- A session ends with `tools/ship.sh`, the review and a merge. `ship.sh` commits with the release-note trailer ([versioning](versioning.md#release-notes)) and the co-author trailer, pushes the branch and opens a draft pull request.
- Commits are small and cohesive. `tools/hooks/commit_guard.py` refuses `--no-verify` and runs `tools/ship_guard.sh` on every commit and push.
- `tools/lane_check.py check` passes before the push; a squash uses `tools/lane_check.py squash`, never a reset onto the remote base.
- An amended or rebased lane branch is pushed with `tools/ship.sh --update`, never a hand-typed force push.

## Review

- Push first, then review: the Reviewer reads the exact pushed head while CI runs.
- A verdict is `pass` (minor findings only), `changes` (a major, no blocker) or `blocker`. `tools/review/record.py` rejects a verdict that does not follow from its severities.
- The Reviewer records with `tools/review/record.py --lane BRANCH`; only the Reviewer records (`tools/hooks/review_guard.py`).
- The Reviewer edits nothing, runs no lane code, and runs the whole checklist in its agent file every round.
- A missing test is a major finding. Rung-0 severities are in [change-loop](change-loop.md#rung-0).
- On `changes` or a failing check, fix with small commits and push to the same branch; the new head gets its own review.
- Review runs at most 2 rounds. At the cap a `changes` verdict with no blocker merges; `record.py` refuses a further round without a stated reason, and a blocker that remains stops the pull request for a decision.

## Landing

- Nothing reaches `main` without an independent `pass` recorded for the exact head. A later commit voids the pass.
- No agent lands its own work: the author of a change never reviews it or records its verdict.
- `tools/pr_land.sh N` is the only merge route. It runs the gates GitHub cannot, then arms a squash merge pinned to the reviewed head; GitHub enforces the required checks ([ci](ci.md)). `tools/hooks/merge_guard.py` refuses every other merge, a push to `main`, and edits to the repository's merge rules.
- A kill-switch file stops landing; `pr_land.sh` names it when set.
- A pull request that touches a path in `.github/CODEOWNERS` waits for the owner's approval. `pr_land.sh` prints the owner's commands; the agent reports them and does not run them.
- A change in the [owner-only](autonomy.md#owner-only) set is never merged by an agent.
- The session reports one line, exactly as `pr_land.sh` printed it: `merged`, `armed`, `blocked` or `failed`, with the pull-request number and reason.
- An `armed` pull request waits on CI as in [ci](ci.md#waiting-on-ci).
- A headless session's self-change lanes are merged by the runner ([eval-gate](eval-gate.md#self-change)).

## PR notes

- A change is followed from its pull request alone: the description is the living view, comments are point-in-time events.
- `tools/pr_note.py` is the only writer of both. Notes written before the pull request exists queue and post when it opens.
- Each role posts as its own identity with `--as <role>`: the Verifier posts evidence, the Designer the pick and verdict, the orchestrator handoff, owner and shipped notes and the status line.
- The review summary in the description belongs to `tools/review/record.py`.
