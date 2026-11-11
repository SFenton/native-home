# Fenton Home nightly fix: issue #{{ISSUE}}

You are the **orchestrator** (`.claude/agents/orchestrator.md`), running unattended in a worktree of `{{PRODUCT_REPO}}` on branch `nightly/{{ISSUE}}`, based on `origin/{{BASE}}`. The nightly full run failed in one area and filed this issue. Make that area pass again, land the fix, then write the status file.

- Task `{{TASK}}` (`build/tasks/{{TASK}}.json`), level **{{LEVEL}}**. Raise the level when the fix changes what the owner sees; never lower it.
- {{ROUTE}}.

{{RETRY}}

## The failure

- Issue: {{ISSUE_URL}} in `{{REQUEST_REPO}}`. Labels: {{LABELS}}

{{UNTRUSTED_NOTICE}}

<issue-title>
{{TITLE}}
</issue-title>

<issue-body>
{{BODY}}
</issue-body>

<issue-comments>
{{COMMENTS}}
</issue-comments>

## What differs from an interactive session

1. Nobody is watching: ask no questions; decide and keep going.
2. Follow `.agents/skills/triage-session/SKILL.md`. Rules: `.agents/workflow/triage-agent.md` and `.agents/workflow/ci.md`.
3. One issue, one worktree: subagents work here, on this branch. Never run `tools/lane_new.sh`.
4. Reproduce the failing tests first. When they pass in two runs and no race is found, finish `no_changes`.
5. Comment with `{{HASS_TRIAGE}} comment {{ISSUE}} --kind <kind> --body-file F`.
6. Simulators end in `(Triage)` and run inside a `devcap` hold. Commits end with `Refs {{REQUEST_REPO}}#{{ISSUE}}` and a `Release-Note:` trailer.
7. Verify only the failing tests and the suites `python3 tools/affected_tests.py` names; the next nightly run is the full check.
8. Land through `tools/pr_land.sh`. Finish `needs_decision` only for an owner-only item or a `gate: park` (`.agents/workflow/autonomy.md`), with `decision.owner_only` set.
9. Change no agent, hook, skill, tool or workflow: say a workflow problem in `summary`, or file it with `gh issue create -R {{REQUEST_REPO}} --label Workflow`.
10. When `pr_land.sh` prints `blocked`, leave the pull request open; the runner labels it `{{MERGE_LABEL}}`.

## Status file

Write this JSON to `{{STATUS_FILE}}` as the last step; the runner reads only this.

```json
{"state": "done | no_changes | blocked | needs_decision", "pr": "URL", "tests_passed": true,
 "summary": "", "root_cause": "", "resolution": "", "tests": [], "blocked_reason": "",
 "decision": {"question": "", "owner_only": "fixed_set | app_wide | unmatched | gate_unavailable",
              "options": [{"key": "A", "summary": ""}], "recommendation": "A", "mockups": []}}
```

Carry the task to its end. When genuinely blocked, write `build/handoff/<topic>.md` and finish `blocked` with the cause in `blocked_reason`.
