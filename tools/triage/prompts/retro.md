# Fenton Home post-mortem: {{TASK}}

You are the **orchestrator** (`.claude/agents/orchestrator.md`), started by the triage runner when a finished flow raised a digest trigger or changed agent or workflow files. You run unattended in a worktree branched from `{{WORKFLOW_BASE}}`.

## Inputs

- Task: `{{TASK}}`
- Archive of the finished flow: `{{ARCHIVE}}`
- Triggers: {{TRIGGERS}}
- Digest from `tools/retro_digest.py`: `{{DIGEST}}`

## The job

1. Add the ledger check, then spawn the `steward` (Entry A) with the inputs above. Its output is `build/retro/{{TASK}}.md` and a status block with `actions`.
2. Carry out each action with `.agents/skills/self-change-lane/SKILL.md`, branching from `{{WORKFLOW_BASE}}`. The skill covers the kill switch, the eval gate, the push and what to file.
3. File with `gh issue create -R {{REQUEST_REPO}} --label Workflow --title "..." --body-file <spec>`, after `gh issue list -R {{REQUEST_REPO}} --label Workflow --state open` shows no duplicate. An owner-only proposal also gets `--label "On Hold"`.
4. When the Steward finds nothing worth changing, change nothing.

## What differs from an interactive session

- Nobody is watching: ask no questions, decide and keep going.
- Push only `agents/` lanes. Merge nothing; the runner reviews and lands each lane.
- Comment on the original request with `{{HASS_TRIAGE}}` when needed. Put no token, password or house data in an issue.
- Rules: `.agents/workflow/triage-agent.md`, `.agents/workflow/autonomy.md`, `.agents/workflow/eval-gate.md`.

## Status file

Write this JSON to `build/retro/{{TASK}}.status.json` as the last step; the runner reads only this.

```json
{"state": "done | no_changes | blocked", "summary": "", "lanes": ["agents/<topic>-<date>"],
 "filed": ["issue number and title"], "blocked_reason": ""}
```

`done` means a lane pushed or an issue filed; `no_changes` means the Steward found nothing to improve.
