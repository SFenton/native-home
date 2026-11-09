# Docs conventions

> **What:** rules that keep `.agents` small and routable. **Read when:** adding or moving any `.agents` file.

| Rule | Detail |
|---|---|
| Header | Line 1 `# Title`; next non-empty line `> **What:** … **Read when:** …` |
| Routers | Every folder has a `README.md` linking every child, except `pages/<id>/` and `controls/<id>/` |
| One platform per file | `spec.md` is platform-neutral; Apple form-factor detail goes in `ios.md`, `ipados.md`, `duo.md`, `watchos.md` |
| Size | Soft budget 200 non-empty lines per file |
| Content | Durable rules, decisions and gotchas. No run logs; git history keeps those |
| Unknowns | Write `TODO(orchestrator): …` rather than guessing |

## Current vs history

Agents see only what is true now. A rule doc, spec, pattern record or mockup states the current rule or design and nothing else: no "was", no "in flight" once it has merged, no dated experiments, no earlier rounds of a decision.

- **History goes to [.agents/archive/](../archive/README.md).** Move run logs, measurements, superseded plans and the earlier rounds of a decision there, in the same PR that makes them stale, and add a row to the archive router. An archived file starts with `> **Archived <date>.**` and says where the current rule lives.
- **Link to history only to explain why.** A rule doc may end with one line such as "Why: decision log". It never makes the reader open the archive to learn the rule.
- **Status docs stay short.** [PROGRESS.md](../../PROGRESS.md) is the current plan in at most 60 lines. Finished work leaves it for the archive; per-feature status lives in the mockup atlas `catalog.json`.
- **A decision is recorded once, as its outcome.** The rule doc says what to do; the proposal, mockup and archive entry say what was considered. Superseded proposals are marked `superseded` in `catalog.json` and sit in the hub's "Why" section ([mockups](../design/mockups/README.md#the-rules-for-agents)).
- **Claims about CI, hooks and tools must be true today.** Say "runs in pr-checks" only for what [`pr-checks.yml`](../../.github/workflows/pr-checks.yml) runs, "nightly" for what [`nightly.yml`](../../.github/workflows/nightly.yml) runs ([ci](ci.md)); a gate that is only planned is called planned.
- **Moving a file means fixing its links.** Grep the old path across `.agents`, `tools`, `apple` comments and the root docs before you commit.
