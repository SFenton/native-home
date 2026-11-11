# Fenton Home weekly source check: the Researcher job ({{DATE}})

You are the **orchestrator** (`.claude/agents/orchestrator.md`), started by the triage runner's weekly schedule. You run unattended in a worktree of `{{PRODUCT_REPO}}` on branch `{{BRANCH}}`, based on `origin/{{BASE}}`. There is no issue.

## The job

1. Spawn the `researcher` to re-check its source catalogue (`.claude/agent-memory/researcher/MEMORY.md` lists the sources) for anything new:
   - the Home Assistant Swift client the app builds on: releases and breaking changes;
   - the Home Assistant frontend and websocket API: changes to the entity, service-call and auth flows the app uses;
   - Apple HIG and UIKit and SwiftUI release notes for the app's targets;
   - the shared simulator and release tooling this repository ports.
2. Its brief names the output `build/research/weekly-{{DATE}}.md` in watch mode of the `research-note` skill: what changed, why it matters to the app, the source and the date read, a confidence.
3. Memory updates under `.claude/agent-memory/researcher/` are invisible work: a `coder` commits them on `{{BRANCH}}` with `Release-Note: none`, then land them with `.agents/skills/land-pr/SKILL.md`. Leave `build/research` uncommitted.
4. Anything that implies product work becomes an issue on `{{PRODUCT_REPO}}`: `gh issue create --label Workflow`, after `gh issue list --label Workflow --state open` shows no duplicate.
5. A quiet week changes nothing.

## What differs from an interactive session

- Nobody is watching: ask no questions, decide and keep going.
- Write no product code and change no agent, hook or Jev question.
- Merge only through `tools/pr_land.sh`.
- Rules: `.agents/workflow/triage-agent.md`, `.agents/workflow/change-loop.md`.

## Status file

Write this JSON to `{{STATUS_FILE}}` as the last step; the runner reads only this.

```json
{"state": "done | no_changes | blocked", "summary": "", "pr": "URL, optional", "blocked_reason": ""}
```

`done` means something changed (a note, an issue or a memory update); `no_changes` means a quiet week.
