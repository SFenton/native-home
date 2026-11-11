---
name: self-change-lane
description: Carries one change to agents, skills, hooks, tools, the triage runner or Jev questions through a lane, the eval gate and an independent review. Use when acting on a Steward action or any change to how the agents work.
---
# Self-change lane

> **What:** how one change to the agent system travels from a spec to a reviewed lane. **Read when:** you carry out a Steward action, or change `.claude/agents`, `.agents/skills`, `.agents/workflow`, `tools/hooks`, `tools/triage` or `contracts/jev`. Rules: [eval-gate](../../workflow/eval-gate.md), [autonomy](../../workflow/autonomy.md#owner-only).

1. **Check the scope.** An action that touches an owner-only item is not built: file it as an issue with the labels `Workflow` and `On Hold`, with the spec and the evidence paths, after checking the open `Workflow` issues for a duplicate.
2. **Check the switch.** `python3 tools/triage/hass_triage.py status` names every kill switch that is set (`self-changes: PAUSED by ...`). When one is, write the note and change nothing.
3. **Cut the lane.** Branch `agents/<topic>-<date>` from `origin/<workflow base>`; `workflow_base` is in `tools/triage/config.json`. One action, one lane.
4. **Build.** A `coder` commits the change in small commits that end with `Release-Note: none` and the co-author trailer, in the layer the spec names, with the test or eval that proves it.
5. **Keep the evals apart.** A lane that changes agents, skills, hooks or Jev questions never touches `evals/`, `contracts/jev/derived/labels`, splits, graders or thresholds.
6. **Prove it.** Run the touched tests and the eval gate: `python3 tools/agent_eval.py`. A lane that fails twice is dropped and filed as a `Workflow` issue with its spec.
7. **Hand it over.**
   - Headless session: `git push origin agents/<topic>-<date>` and list the branch under `"lanes"` in the status file. Open no pull request, run no `lane_land.py`, write no review verdict. The runner reviews and lands the lane; a lane it refuses returns as a `Workflow` and `On Hold` issue.
   - Interactive session: an independent `reviewer` passes the exact head, then land by the route [eval-gate](../../workflow/eval-gate.md#self-change) gives for a lane with or without a pull request.
8. **Never** merge or push the workflow base yourself, review your own lane, or write or remove a kill switch.
