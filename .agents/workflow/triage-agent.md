# Triage agent

> **What:** the rules for unattended sessions: how the runner turns requests and nightly failures into reviewed changes, what a headless session may do, and what stops it. **Read when:** changing `tools/triage/`, writing a headless prompt, or working out why a request did or did not move.

The runner is `tools/triage/hass_triage.py`; `status` shows the queue, the switches and why anything is paused. Labels, authors, schedules and limits live in `tools/triage/config.json`.

## Intake

- The runner works only issues and replies written by the configured authors. Issue text is wrapped as [untrusted input](security.md#untrusted-input).
- Requests live in the private request repository ([house data](security.md#house-data)); nightly failures are issues on this one ([ci](ci.md#nightly-failures)).
- The owner's requests come first, then nightly failures; one issue at a time, priority first, then oldest; an issue naming an `agents/` branch waits while that lane's `Workflow: lane ... not landed` issue is open.
- Each issue gets its own worktree and branch from the base, a ledger entry, and a headless orchestrator session with the job's prompt from `tools/triage/prompts/`.
- A request's level starts from its kind and may only be raised ([levels](autonomy.md#levels)).

## The session

- A headless session is the orchestrator and follows every rule an interactive one does ([agent-roster](agent-roster.md)).
- It runs with the per-job tool deny list in the config, enforced for registered sessions by `tools/hooks/triage_session.py` and `tools/hooks/triage_deny.py`.
- It ends by writing the runner's status file. A session that ends without one is retried once, then blocked.
- It never answers or asks the owner; it finishes `needs_decision` with `decision.owner_only` and the runner posts the question.
- Against the request repository it may read and may create an issue with the workflow label; every other write is refused by `tools/hooks/merge_guard.py`.
- It reaches simulators and builds only through capacity holds ([capacity](token-economy.md#capacity)).
- Product work merges through `tools/pr_land.sh` after the independent review ([landing](pr-lifecycle.md#landing)).

## Outcomes

| Status | The runner |
|---|---|
| `done` with tests passed and a pull request | Marks it for merge; closes the request with a summary once it merges |
| `needs_decision` with `decision.owner_only` | Parks the pull request and the issue for the owner; `pr_land.sh` refuses a parked pull request |
| `needs_decision` without it | Sends the pick back to be judged and merged |
| `blocked` | Labels the issue blocked with the reason |
| `no_changes`, `split` | Closes as not planned; files child issues and closes the parent |

- The owner steers by replying on the issue, merging or closing the parked pull request, or setting a label; a reply re-queues the issue.
- A parked pull request waits however long the owner takes.
- An agent never closes a nightly issue; the next passing nightly run does.
- A workflow issue is never closed as not planned for lack of code.

## Self-change and post-mortems

- Every ending of a flow archives its evidence, redacted. Only the runner queues a post-mortem ([eval-gate](eval-gate.md#post-mortems)).
- Post-mortems and the scheduled Steward and Researcher jobs run only on an idle tick, one at a time.
- A session pushes its self-change lanes and never merges them. The runner merges a lane only when it is new or moved in that session, the independent Reviewer passed its exact head from a trusted checkout, and the checks in [eval-gate](eval-gate.md#self-change) hold.
- A refused lane comes back as a workflow issue; one in the [owner-only](autonomy.md#owner-only) set is put on hold for the owner. Nothing is dropped.

## Stops

- Kill-switch files pause intake, self-change merges or product merges; `hass_triage.py pause` sets the runner's.
- The base-integrity monitor pauses self-change when the base moves by anything other than a checked, merged pull request, and files an issue. It never resets or force-pushes.
- `hass_triage.py ack-verified` accepts a base that moved only by checked merges; agent sessions may run it. `ack-base` accepts anything else and is the owner's, from a terminal.
- The runner is the trusted actor: it ends a session's processes before any merge step and trusts no file the session could write.
- A logged-out CLI or an unconfigured request repository stops the tick before any issue is touched.
