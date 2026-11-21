# Eval gate

> **What:** how the agent system changes itself: the lanes, the eval gate every such change passes, and the rules that keep the grader independent of what it grades. **Read when:** changing an agent file, skill, hook, tool, decision-model question or the triage runner, or adding an eval case.

## Self-change

- Agent, skill, hook, tool and decision-question changes pass `tools/agent_eval.py` and independent review; run the gate before pushing.
- A self-change lane branches `agents/<topic>-<date>` from the workflow base.
- Every plain pull request runs two jobs. `tier0-emit` runs the base collector against the head in an isolated VM and emits observations. `pr-policy` trusts the base code and exact event SHAs, treats the artifact bytes as hostile data and publishes the verdict. A red result blocks the pull request.
- Recorded observations can be fabricated by a hostile change, so replay guards accidents; independent review of the changed code is the control. The owner still reviews workflow wiring and owner-held grader, review and deny inputs.
- The author never reviews or records the verdict.
- A headless session pushes lanes and lists them as `lanes` in status; it never lands them.
- A pull-request lane lands normally ([landing](pr-lifecycle.md#landing)). A lane without one uses `tools/lane_land.py`, which runs the gate and tool tests, merges the passed head and pushes the base.
- The runner uses `lane_land.py` with a Reviewer from a trusted checkout ([triage-agent](triage-agent.md)); an interactive session waits for a recorded `pass`.
- A refused merge or push lands nothing; the tool reports it and the runner files a Workflow issue.
- One lane changes agent behavior or eval grading, never both; `tools/lane_land.py` refuses the mix.
- The trusted base runs the harness, cases and measuring code; the lane never grades itself.
- Question thresholds only tighten, and a new question starts in shadow ([jev](jev.md)).

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
