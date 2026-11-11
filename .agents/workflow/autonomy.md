# Autonomy

> **What:** the levels that say how far a loop runs by itself, the set only the owner decides, and the gate that parks app-wide UI changes. **Read when:** routing a task, raising its level, or deciding whether anything waits for the owner.

## Levels

| Level | Covers | The loop |
|---|---|---|
| L0 invisible | Logic, performance, tests, tooling, refactors that draw the same pixels | Runs through merge |
| L1 visible, decided | Parity with the web dashboard, an existing rule applied to more surfaces, a fix back to the atlas or a spec | The Designer decides within the existing pattern; runs through merge; before and after go in the PR |
| L2 design | A visible choice with no decision on record | Builds options, the Designer judges and records the pick, the pick merges ([propose-first](propose-first.md)) |
| L2 policy | A trade-off that changes nothing drawn, worded, animated or navigated | The orchestrator writes a decision note, it is judged, the pick merges |
| L3 owner-only | The set below | The loop files a proposal and never merges it |

- When unsure between two levels, take the higher; `tools/tasks.py set-level` raises one and refuses to lower it.
- Visible is defined in [propose-first](propose-first.md#what-is-visible).
- Neither L2 form waits for the owner: a pick that ends `needs_decision` without `decision.owner_only` is sent back to be judged and merged.
- Only L3 and a park from the [app-UI gate](#app-ui-gate) end `needs_decision` with `decision.owner_only` set to the reason.
- Every level merges through an independent review ([landing](pr-lifecycle.md#landing)); a change to agents, hooks, skills or tools also passes the [eval gate](eval-gate.md).

## Owner-only

The owner alone decides and merges changes to:

| Class | Includes |
|---|---|
| Credentials and secrets | Tokens, keys, the credential loaders, the folders that hold them |
| Signing and release | Certificates, profiles, store keys, the release pipeline and every file its jobs run or import |
| Physical devices | Automation that drives a real device |
| The review record | The verdict recorder, its reader, its guard, the Reviewer's agent file |
| Session deny lists | The guards enforcing a headless session's deny list |
| Git plumbing | Git's own configuration and hooks directories |
| Owner acknowledgements | The commands that accept an unverified base or skip a gate for one PR |
| App-wide UI | A broad, app-wide visible change the owner did not request |

- The path list is `DEFAULT_PROTECTED` in `tools/lane_land.py`, plus `protected_paths` in `tools/triage/config.json` and the release closure from `tools/release_closure.py`. `tools/pr_land.sh` and `tools/lane_land.py` refuse a change that touches it.
- Everything outside the set is autonomous, the merge path and the guards included.
- Separately, a path in `.github/CODEOWNERS` merges only with the owner's approval ([landing](pr-lifecycle.md#landing)).

## App-UI gate

The gate decides whether a visible change needs the owner. `tools/jev_gate.py` prints it for a plan; `tools/pr_land.sh` and `tools/lane_land.py` enforce it at merge.

| Work | Autonomous when | Otherwise |
|---|---|---|
| Requested by the owner | The decision model confirms the change matches the request | Park |
| Started by an agent | The decision model confirms the change is local to one screen | Park |
| Decision model unavailable | Never | Park |

- A park is `needs_decision` with `decision.owner_only` set to `fixed_set`, `app_wide`, `unmatched` or `gate_unavailable`.
- A parked change builds only what the owner needs to see the options. The Designer never picks a change the gate parked.
- A plan quotes the owner's request on an `Owner's request:` line when one exists.
- At merge a request counts as the owner's only when the runner vouches for the request issue or the quote sits inside a prompt the owner typed (`tools/hooks/owner_prompt_log.py`). Text an agent wrote never vouches.
- A merged app-UI change carries a design decision record or cites an existing record or pattern ([propose-first](propose-first.md#record)).
- A mockup edit that draws the same is not app UI.
- At plan time the gate is a hint for the orchestrator's own answer to the same question ([jev](jev.md)).
