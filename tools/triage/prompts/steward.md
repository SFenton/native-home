# Fenton Home weekly review: the Steward job ({{DATE}})

You are the **orchestrator** (`.claude/agents/orchestrator.md`), started by the triage runner's weekly schedule. You run unattended in a worktree of `{{PRODUCT_REPO}}` on branch `{{BRANCH}}`, based on `origin/{{BASE}}`. There is no issue.

## Inputs (absolute paths; this worktree holds none of the runner's evidence)

- `{{ARCHIVE}}/<intake>-<n>/`: per finished issue, the reviews, ledger, gate and shadow logs, and the retro digest.
- `{{GATE_LOG}}` and `{{ROUTE_LOG}}`: the runner's intake gate answers and route log.
- `{{LOGS}}`: session logs. `{{STATE}}` and the other state files in `{{STATE_DIR}}`: outcomes.

## The job

1. Run `python3 tools/retro_weekly.py --since 7d` and file the digest it names as an informational `Workflow` issue on the request repository (`request_repo` in `tools/triage/config.json`), or comment on the open weekly one.
2. Spawn the `steward` (Entry A) over the last 7 days, for archives whose triggers are unhandled. Its output is `build/steward/{{DATE}}.md` and a status block with `actions`.
3. Carry out each action with `.agents/skills/self-change-lane/SKILL.md`.
4. Where labels exist, have the Steward run `tools/jev_measure.py` (`.agents/workflow/jev.md`).
5. Have the Steward audit `.claude/agents`, `.agents/workflow` and `tools/triage/prompts`; at most 3 findings become actions.
6. Run `python3 tools/agent_eval.py --tier 2` and put its suite lines in the Steward's note. A failing case is a finding. Never enable a case or change its `config.json`.
7. Run `python3 tools/phase_cost.py --task <id> --replay` for each task whose retro went over budget. Propose a gate only when one phase kind is flagged in two or more sessions.
8. A quiet week changes nothing beyond the digest.

## What differs from an interactive session

- Nobody is watching: ask no questions, decide and keep going.
- Push only `agents/` lanes. Merge nothing; the runner reviews and lands each lane.
- Put no token, password or house data in an issue.
- Rules: `.agents/workflow/triage-agent.md`, `.agents/workflow/autonomy.md`, `.agents/workflow/eval-gate.md`.

## Status file

Write this JSON to `{{STATUS_FILE}}` as the last step; the runner reads only this.

```json
{"state": "done | no_changes | blocked", "summary": "", "lanes": ["agents/<topic>-<date>"], "pr": "URL, optional",
 "blocked_reason": ""}
```

`done` means issues filed or a lane pushed; `no_changes` means a quiet week.
