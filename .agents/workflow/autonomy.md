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
- A pick that ends `needs_decision` without `decision.owner_only` is sent back to be judged and merged.
- Only L3 and a `route=pr` park from the [app-UI gate](#app-ui-gate) end `needs_decision`.
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

`tools/jev_gate.py` prints whether a visible change needs the owner; `tools/pr_land.sh` and `tools/lane_land.py` enforce it at merge.

| Work | Autonomous when | Otherwise |
|---|---|---|
| Requested by the owner | The decision model confirms the change matches the request | Park |
| Started by an agent | The decision model confirms the change is local to one screen | Park |
| Decision model unavailable | Never | Park |

- A park prints `route=session` or `route=pr`. On `session` the orchestrator has the Verifier capture up to 3 options on the affected families, shows them with one line each, has the owner type the pick, and records it citing `Owner's request:`.
- On `pr` it finishes `needs_decision` with `decision.owner_only` set to `fixed_set`, `app_wide`, `unmatched` or `gate_unavailable`; the runner posts the question on the pull request. The Designer never picks a parked change.
- A plan quotes the owner's words on an `Owner's request:` line.
- At merge a request counts as the owner's only when the runner vouches for the request issue or the quote sits in a prompt the owner typed (`tools/hooks/owner_prompt_log.py`); agent-written text never does.
- A merged app-UI change carries or cites a design decision record or pattern ([propose-first](propose-first.md#record)).
- A mockup edit drawing the same is not app UI.
- At plan time the gate is a hint for the orchestrator's own answer ([jev](jev.md)).
