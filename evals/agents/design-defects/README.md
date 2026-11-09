# Design-defect eval

> **What:** 72 defects the owner found on a device and reported in chat, each with the commit before its fix, used to measure whether the Verifier plus Designer would have caught it before deploy. **Read when:** changing the Verifier, the Designer, the `pose-matrix` skill or a hook that judges design behavior.

Source: the owner's messages in the UIKit-port session (`4ac44105`, 57 cases, 2026-10-30 to 2026-11-01), the SwiftUI main session (`b2164581`, 2026-10-16 and 17) and the physical-device performance session (`7c5a44f2`, 2026-10-27). The owner was the QA in those sessions; the cases are what a review should have caught first. Quotes are the owner's words (at most 25 words; `...` marks a cut). No credentials, addresses or names beyond the owner's words about the app.

## Files

- `cases/dd-<slug>.json`: one case. Fields in `schema.json`: `id`, `date`, `source`, `owner_report`, `surface` (atlas catalog id or null), `poses`, `app` (`uikit` or `swiftui`), `category`, `pre_fix_ref`, `fix_ref`, `fix_confidence`, `expected`.
- `validate.py`: checks schema, catalog ids and that refs exist. Run it after editing a case.

By category: layout 18, parity 11, navigation 12, sizing 12, motion 8, perf 4 (design cannot see these; the correct verdict asks for a measurement), alignment 3, crash 3, a11y 1.

`pre_fix_ref` is the first parent of `fix_ref`, matched by commit subject and date, so check `fix_confidence`: `high` is a commit whose subject names the defect, `medium` a plausible match, `low` a guess. Cases with `null` refs have no known fix; they are graded only on pose evidence against a current checkout. UIKit-port refs are on `claude/uikit-port` (merged lanes); a ref missing from a clone needs `git fetch origin claude/uikit-port`.

## Grader

For each case, the grader (Opus, given only the case's `expected` and `owner_report`, never the fix diff) reads the Designer's verdict and scores:

- **flagged:** the verdict names the defect, in the right pose and surface, with evidence from the pack (a frame, a tree line or a screenshot path). 1.0
- **partial:** the verdict names the area or symptom but not the defect (for example "the sheet looks large" for a 70% sheet), or names it in the wrong pose, or without evidence. 0.5
- **missed:** not mentioned, or the verdict passes the surface. 0. A `pass` verdict on a case whose fix is known is the costly kind: count it separately as `false_pass`.

Perf cases score flagged only when the verdict declines to judge from stills and requests the named measurement.

**Headline metric: the share of owner-found defects caught before deploy** = (flagged + 0.5 x partial) / cases, reported overall, by category, by pose and by `app`. Track `false_pass` and the Designer's findings with no matching case (candidate false alarms, reviewed by hand, never counted as errors automatically).

## How Phase B runs it

`run.py` does everything except the judging. Agents only do steps 3 and 4 (Verifier) and 5 and 6 (Designer, grader). Designer-visible paths are under `build/evals/design-defects/<run-id>/`, with case directories named `case-<hash>` (Designer brief, `pack-<ref>` link, `<ref>/verdict.md` only). Grader-only material (`plan.json`, grader briefs, `grade.json`) lives in the sibling tree `build/evals/design-defects/<run-id>.grader/case-<hash>/`, which no Designer brief names, so the Designer cannot browse to case ids, owner reports, expected text or fix refs.

1. **Select.** `python3 evals/agents/design-defects/run.py select [--category C] [--confidence high] [--app swiftui|uikit] [--limit N] [--seed S]` writes `<run-id>.grader/plan.json` and prints the run id. Stratified across categories; `null` refs are skipped; `perf` only with `--category perf`.
2. **Prepare.** `run.py prepare <run-id> <case-id> [--ref pre|fix]` creates (or reuses) a detached worktree `.claude/worktrees/dd-<hash>-<pre|fix>` (named by case hash, never the slug) at the ref (fetching `origin claude/uikit-port` if the ref is missing) and prints the pose-matrix commands for the case's `poses`, each inside `tools/devcap.py run --sim`. It does not build or boot anything.
3. **Verify.** The Verifier runs those commands with the [pose-matrix](../../../.agents/skills/pose-matrix/SKILL.md) skill and writes the evidence pack at `<worktree>/build/evidence/dd-<hash>-<pre|fix>/manifest.json`. Simulators only; two `infra` failures stop the case.
4. **Brief the Designer.** `run.py brief <run-id> <case-id> [--ref pre|fix]` writes `designer-brief-<ref>.md`: the pack (through a neutral `pack-<ref>` link) and the surface's atlas mockup. Never the owner report, `expected` or the fix ref. The Designer writes `<ref>/verdict.md`. The manifest carries only the hashed worktree name; keep the Verifier's notes free of the defect.
5. **Grade.** `run.py grade-brief <run-id> <case-id> [--ref pre|fix]` writes `<run-id>.grader/case-<hash>/grader-brief-<ref>.md` (report, expected, rubric, output schema). The Opus grader reads the Designer's `<ref>/verdict.md` and writes `<run-id>.grader/case-<hash>/<ref>/grade.json`: `{case, score, label, false_pass, evidence_cited, notes}`. Labels for `pre`: `flagged`, `partial`, `missed`, `false_pass`, `infra` (add `infra_class`; rerun, never scored). For `fix` runs: `clean`, `false_alarm`, `infra`.
6. **Score.** `run.py score <run-id>` writes `build/evals/design-defects/<run-id>.json` and `.md`: headline (flagged + 0.5 x partial) / scored cases, by category, pose and app, the `false_pass` count, false alarms on fixed commits, infra results (excluded and listed) and cases not yet graded.
7. **Clean up.** `run.py cleanup <run-id>` removes the run's `dd-` worktrees.

Run `--ref fix` through steps 2 to 5 for the cases flagged: the verdict should pass, which measures false alarms.

Cases that need a physical device are not in the set; the Duo is never automated.

## Runs

| Run | Cases | Caught before deploy | False passes | Note |
|---|---|---|---|---|
| `20261102-041600-s0` (2026-11-01 pilot) | 4 (swiftui, iphone, high confidence: alignment, parity, navigation, sizing) | 100% (4 flagged) | 0 | Upper bound: the pack paths named the defect (`dd-<slug>-pre`); worktrees are now named by case hash. Its local `build/` files (old layout) were not kept. |
