# Token economy

> **What:** the rules that keep usage proportional to the work: how to wait, which model does what, and how simulators and builds are shared. **Read when:** starting a session or lane, launching a build or test, or spawning an agent.

Cost is turns times context; a turn that only waits costs as much as one that works.

## Waiting

- **Never poll or sleep-loop.** Run a long command as `tools/bg_run.py LABEL -- COMMAND` in the background and end the turn; the completion notice carries a digest. `tools/hooks/no_poll.py` refuses the loops.
- **Read the digest, not the log.** Open the log only for a failure the digest cannot explain.
- **Infra is the machine, not the test.** Rerun once, then report it.
- **Long jobs carry a timeout.** `tools/bg_run.py --expect-minutes` prints the value; `tools/hooks/bg_timeout_guard.py` refuses a long background test run without one.
- **Wait silently.** Woken with nothing new to say, end the turn with no text. A waiting stop is said once.
- **Commit before a background job.** An agent makes a work-in-progress commit before launching one.
- **A turn that ends on a running job is `blocked`** with `blocked_reason: "waiting_bg: <label>"`. The orchestrator treats that worktree as live and messages the agent instead of dispatching another.
- **A headless session cannot be woken,** so `tools/hooks/stop_continue_guard.py` refuses to end it while its background job or agent runs.
- **A session carries its task to the end.** Context size and turn count are never reasons to hand off.

## Models

| Work | Runs on |
|---|---|
| Orchestration, specs, design decisions | The orchestrator and the Designer, on the largest model |
| Research, implementation, verification, post-mortems | Researcher, Coder, Verifier, Steward, on the mid model |
| Re-runs, log reading, status checks, git chores | Menial, on the smallest model |
| Final review | The Reviewer, on its own model, never the orchestrator's |

- The model and effort of each role are its agent file's frontmatter; no doc copies them.
- Escalating a Researcher or Coder to the largest model is explicit on the Agent call (`model` and `effort`) and justified by demonstrated need. A brief's text does not set a model.
- A built-in helper agent is spawned with a cheap model named on the call.
- A mechanical re-run goes to Menial, never a heavier role.
- `tools/hooks/agent_model.py` refuses a spawn that breaks these; its message gives the fix.

## Tests

- Run the cheapest check that can fail first: a filtered unit run, then the journeys the change touches, on the families it affects.
- After a family has a baseline, a fix round reruns only the failed tests and the changed journeys.
- The full suite, full coverage and all-family runs belong to the nightly and release tiers ([test tiers](../testing/apple/README.md#test-tiers)). `tools/hooks/tier_guard.py` refuses an unfiltered run.
- `tools/affected_tests.py` names the suites, journeys and families a diff needs.
- Extend an existing tool instead of rebuilding its job by hand: lanes, shipping and digests have scripts.

## Capacity

- Every simulator, physical device and heavy compile runs inside a `tools/devcap.py` hold. Never boot a simulator outside one ([capacity](../platforms/apple/capacity.md)).
- `tools/ios_uitest.sh` and `tools/apple_coverage.sh` take the hold and slim the simulator themselves; a simulator booted any other way is slimmed with `tools/sim_slim.sh`.
- A slot wait yields. An agent passes `--max-wait` to its hold; when the wait runs out it reports `blocked` with `blocked_reason: "slot_wait: <gate>"` and does not retry in a loop.
- A process kill is scoped to the agent's own work; the machine is shared with other sessions, the CI runner and simulators.
- Scroll cost is measured with `tools/ios_scrollcost.sh` ([performance](../testing/apple/performance.md)).
