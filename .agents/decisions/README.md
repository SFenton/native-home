# Decisions

> **What:** why and when a rule changed, one file per decision. **Read when:** you record a decision; never required reading.

- File name `YYYY-MM-DD-slug.md`; the first lines are `Decision:` (what was chosen and the options judged), `Replaces:` (the wording or decision it supersedes, or `none`) and `Rule home:` (the file that now states the rule).
- Append-only: a file is never edited or deleted; a later decision names what it replaces. `tools/rules_lint.py --base` enforces it.
- A rule file never links here and no agent loads this folder at spawn. The rule itself lives in its one home, undated.
- App-UI picks land here too: the `Decision:` line names the judged options, which satisfies the design gate in `tools/lane_land.py`.
