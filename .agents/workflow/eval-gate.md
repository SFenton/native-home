# Eval gate

> **What:** how the agent system changes itself: the lanes, the eval gate every such change passes, and the rules that keep the grader independent of what it grades. **Read when:** changing an agent file, skill, hook, tool, decision-model question or the triage runner, or adding an eval case.

## Self-change

- A change to agents, skills, hooks, tools or decision-model questions passes the eval gate (`tools/agent_eval.py`) and an independent review before it merges. Run the gate yourself before pushing.
- A self-change lane is a branch `agents/<topic>-<date>` cut from the workflow base.
- The session that wrote a self-change never reviews it and never records its verdict.
- A headless session pushes only its lanes and lists them in its status file as `lanes`; the runner reviews each exact head and merges it through `tools/lane_land.py` ([triage-agent](triage-agent.md)).
- One change touches agent behavior (agents, skills, hooks, questions) or the evals, labels, splits and thresholds that grade it, never both. `tools/lane_land.py` refuses the mix.
- The gate cannot be changed by the change it grades: the harness, the cases and the measuring code run from the trusted base, never from the lane.
- Decision-model thresholds may only tighten in a lane, and a new question starts in shadow ([jev](jev.md)).

## Post-mortems

- Every flow ends with `tools/retro_digest.py`. A trigger it reports, or a flow that touched agent or workflow paths, starts a Steward post-mortem.
- A post-mortem yields at most 3 actions, each naming its layer, the exact change, the proving test and a metric. Each action becomes a self-change lane.
- An action fixes the failure in the layer that can enforce it; where to write anything else is in [docs-conventions](docs-conventions.md#homes).
- The Steward never implements or grades its own change, and never edits evals.
- The Steward takes the owner's direct requests about how the agents work.
- The runner reverts a merged lane whose flow metrics regress, through the normal review; a revert of a revert goes to the owner ([triage-agent](triage-agent.md)).

## Tiers

| Tier | Runs | Checks |
|---|---|---|
| 0 routing replay | Every lane | Recorded cases of deterministic code paths, replayed against the lane's code with recorded decision-model answers |
| 1 re-measurement | A lane that changes a question | The lane's question asked about the base's held-out items by trusted code; precision meets the question's target and ranking quality does not fall |
| 2 behavior replay | Weekly, in the Steward's job | Enabled trusted cases replayed through a model, capped by the case folder's `config.json` |

- The lane passes when its failing cases are a subset of the base's and it ran at least as many cases.
- The gate fails closed: an unreadable base, a case with no result, an unreachable decision model or an unmeasurable active question refuses the lane.

## Cases

- A case is one JSON file under `evals/agents/` with its source, kind, input and expected result; the kinds are in that tree's README.
- One case is added per class of incident, for the behavior as it should be, and is checked to fail without the fix.
- Cases are append-only: a lane adds a case and never edits or deletes one; the base's copy of a name wins.
- A case leaves service only by moving to the tree's retirement folder with a reason file whose evidence is checked. It still runs, report only, and still counts.
- A lane that takes a case out of service does not change the questions or runners that use it.
