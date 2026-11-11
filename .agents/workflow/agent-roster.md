# Agent roster

> **What:** who dispatches whom, the contracts between agents, the guards that judge them, and when to ask the owner. **Read when:** spawning an agent, writing a brief or a status block, or answering a hook refusal.

## Roles

Roles: [AGENTS.md](../../AGENTS.md#roles). Each `.claude/agents/<role>.md` states the role's scope, what it writes and what it never does; model and effort live only in its frontmatter ([models](token-economy.md#models)).

- **Entry.** Every session in the repo starts as the orchestrator (`"agent"` in `.claude/settings.json`) unless an explicit `--agent` names another role.
- **One dispatcher.** Only the orchestrator spawns agents that write. Researcher and Designer are advisors: they return `research_requests` and `implementation_specs` in their status block and the orchestrator dispatches them.
- **Read-only helpers.** The Researcher may spawn only read-only helpers, each with a cheap model named on the call.
- **Independent review.** The Reviewer is never the author and never runs on the orchestrator's model.
- **No other roles.** Area, platform and release knowledge lives in skills and scripts.
- **Shared simulator tools** belong to another repository: a change is delegated there and the task ends `blocked` ([capacity](../platforms/apple/capacity.md#changing-the-shared-tools)).

## Contracts

| Contract | Rule |
|---|---|
| Brief | Carries the objective, output format, tools and sources, boundaries (files owned, files not to touch), the done check as ledger check ids, and device families. Advisor briefs carry a ledger check too. |
| Status block | The last thing every subagent prints: a fenced block tagged `status` holding JSON. `tools/hooks/subagent_report.py` sends back a stop without one, or `done` with a `fail`. |
| Task ledger | `build/tasks/<id>.json`, written through `tools/tasks.py`. The orchestrator creates entries and checks; agents only flip a check they proved, with its evidence path. A task is finished when `tasks.py check` exits 0. |
| Evidence pack | `build/evidence/<branch>/manifest.json` lists, per pose, the screenshot, accessibility tree, test results and a failure class: `real`, `infra` or `known-flaky`. Skill: [pose-matrix](../skills/pose-matrix/SKILL.md). |
| Research note | Answer, evidence, fit with our patterns, recommendation (follow, deviate, rearchitect), confidence, open questions. Skill: [research-note](../skills/research-note/SKILL.md). |
| Handoff note | Blocked work leaves `build/handoff/<topic>.md` and reports `blocked` with the reason. |

Status block fields:

| Field | Value |
|---|---|
| `status` | `done`, `blocked`, `needs_research` or `needs_decision` |
| `task`, `summary`, `artifacts` | Ledger id, at most 250 words, paths written |
| `acceptance` | `pass`, `fail` or `not_run` per check id |
| `question` | Required for `needs_research` and `needs_decision` |
| `blocked_reason` | For `blocked`; `waiting_bg: <label>` and `slot_wait: <gate>` are the two waits ([waiting](token-economy.md#waiting)) |
| `decision.owner_only` | Set only when the owner must decide ([levels](autonomy.md#levels)) |
| `research_requests`, `implementation_specs`, `hub_republish` | Advisor requests; the last asks for a mockup hub republish |

The interactive orchestrator writes its block to `build/status/<task>.json` with `tools/agent_status.py` and prints one short line; a headless session writes the runner's status file ([triage-agent](triage-agent.md)).

## Guards

A guard is a tripwire for accident and habit. Answer a refusal by changing the work or finishing `needs_decision`; never reword, rename or switch tools to get past it. Each refusal message states its rule.

| Enforcer (`tools/hooks/` unless a path is given) | Holds |
|---|---|
| `worktree_guard.py`, `commit_guard.py`, `push_guard.py`, `.githooks/pre-push` | [Worktrees](pr-lifecycle.md#worktrees), shipping, [house data](security.md#house-data) |
| `merge_guard.py`, `review_guard.py` | [Landing](pr-lifecycle.md#landing) and who records a verdict |
| `signing_guard.py`, `owner_prompt_log.py`, `owner_prompt_guard.py` | [Credentials](security.md#credentials) and the owner's typed requests |
| `orchestrator_guard.py`, `research_write_guard.py`, `agent_model.py`, `subagent_report.py` | Role scope, spawn models, the status block |
| `no_poll.py`, `bg_timeout_guard.py`, `stop_continue_guard.py`, `tier_guard.py` | [Waiting](token-economy.md#waiting) and test tiers |
| `kill_guard.py` | A process kill is scoped to the agent's own work |
| `mockup_hub_guard.py` | A session with mockup changes ends with a hub publish |
| `triage_session.py`, `triage_deny.py` | A headless session's deny list ([triage-agent](triage-agent.md)) |

A change to a guard hook ships with block and allow rows in `tools/tests/guard_tables/`, and its brief says whether the guard is a tripwire or a wall.

## Questions

- Ask the owner only for an [owner-only](autonomy.md#owner-only) decision. Every other choice is decided by the agents and recorded.
- When work waits on the owner, say so once in one line, post the handoff [PR note](pr-lifecycle.md#pr-notes) and stay silent.
