# Rules surface reset

Decision: the rule surface is layered with one home per rule, and a lint plus a write-time hook enforce it; options judged: A trim in place, B re-layer with enforcement, C generate rules from a database; picked B.
Replaces: dated, attributed and appended rule text (each correction added as a new paragraph in a rule file), line-count budgets set at the current maximum, and the dated `Decision:` line in a design doc as the record of a design pick.
Rule home: `.agents/workflow/docs-conventions.md`, with budgets and forbidden patterns in `contracts/rules-surface.json`.

Rule text states only present-tense defaults. Dates, attribution, references, change words and status go to this folder, the PR or `PROGRESS.md`. `tools/rules_lint.py` runs in pr-checks and the tool tests; `tools/hooks/rules_guard.py` refuses new violations at write time; budget changes are owner-visible diffs. Every markdown file is in a layer or in the contract's `unchecked` list with a reason. The reference layer carries a per-file ratchet (`contracts/rules-ratchet.json`) that the lint compares with the base, so it only falls. The pre-push hook is owner-only and does not run the lint in this change.
