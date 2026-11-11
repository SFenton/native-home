# Derived Jev questions: measurements (2026-11-01)

> **What:** how well Jev (`jev-1.13.0`) answers the derived questions and four planned ones against labels I wrote from this project's own text. **Read when:** deciding whether a question may move from shadow to hint ([jev-corpus](../../../.agents/workflow/jev.md)).

## Method and honesty notes

- **Labels** (`labels/*.jsonl`, 39 to 80 items each) are mine, written from the text itself with a one-line reason; sources: 488 owner messages in the 23 session histories, 223 merged PRs, 95 distinct digest lines from 245 test digests, and 5,900 assistant text turns of the project's transcripts. Where a ground truth exists in the repo I used it: files changed (`request.surface`), `Release-Note` trailers (15 of the `pr.user_visible` PRs). A single labeller is the biggest weakness: borderline items (a "yes" with a clause; a PR that is half tooling) were decided by me and could be decided otherwise.
- **Wording was fixed before measuring**, once, except `transcript.turn_kind.v2` (below), which is tuned on the same labels and therefore optimistic.
- **Redaction:** items containing keys, tokens, IPs, hashes, team or account ids, other people's names, pasted blocks or `key`/`secret`/`password` were dropped before labelling; email-like strings, long hex and home paths were masked. Nothing else was sent.
- **Keyword baselines** (`baselines.py`) were written after I had read the labels, so they are flattering to the baseline.
- **Spend:** about 930 Jev calls, roughly 0.02 USD at the 4.2 cents per million input tokens rate (cap was about 2 USD). Raw answers are in `results/*.jsonl` (no text). Re-run with `python3 contracts/jev/derived/measure.py <id>`; the wording measured is the wording in `candidates.json` / `probes.json`.
- **Targets** are the `accept` / `target.precision` values the question files will use: 0.85, 0.8 for `partial_approval`.

## Derived candidates

| Question | Type | n (pos) | Result | Threshold suggestion | Promote? |
|---|---|---|---|---|---|
| `turn.waiting_narration` | noul | 80 (23) | AUC 0.988; p>=0.3: precision 1.00, recall 0.87; p>=0.5: 1.00 / 0.61. Keyword baseline 0.83 / 0.87 | Count at p>=0.3 (KPI only) | Yes, for the KPI |
| `pr.user_visible` | noul | 79 (37) | AUC 0.987; p>=0.7: precision 0.90, recall 0.95; p>=0.85: 0.97 / 0.78; p<0.3 missed no positive (31 items). Keyword baseline 0.55 / 0.87 | Suggest "needed" at p>=0.7, "none" at p<0.3, say nothing between (10 of 79 in the band) | Yes, as a hint |
| `owner_msg.reports_failed_fix` | noul | 59 (26) | AUC 0.957; p>=0.5: precision 0.955, recall 0.81; p>=0.7: 1.00 / 0.27. Keyword baseline 0.77 / 0.92 | Count at p>=0.5; 25 of 59 fall in 0.3 to 0.7, so never act below 0.5 | Yes, as counter and hint |
| `owner_msg.partial_approval` | noul | 43 (17) | AUC 0.930; p>=0.5: precision 0.65, recall 1.00; p>=0.85: 0.81 / 0.77 | Tighten-only use (block the auto flip, print the hint) at p>=0.5: a false positive costs one line. Any use that counts it as a fact needs p>=0.85 | Tighten-only: yes |
| `owner_msg.standing_rule` | noul | 58 (28) | AUC 0.858; p>=0.7: precision 0.80, recall 0.57; p>=0.85: 0.77 / 0.36. Keyword baseline 0.92 / 0.43 | None passes the 0.85 target; queue at p>=0.5 for a human to read | No: stay shadow, gather more labels |
| `task.device_scope` | choice | 50 | Accuracy 0.82; confidence>=0.6: 0.91 on 68%; >=0.8: 0.93 on 58%. Errors: no_ui as all_families 5 of 12, duo_only as all_families 2 of 13; one all_families as iphone_only | Abstain to `all_families` below 0.6 (the safe direction: extra poses, never fewer). Only 1 iphone_only and 0 ipad_only item exist | Yes, widening only |
| `request.severity` | score (4) | 39 | Spearman 0.83; exact 0.90 (majority guess 0.64); within one level 1.00. Mean score by true level 0.57 / 1.00 / 1.89 / 3.00 | Queue order by score; level 3 also needs the keyword floor (2 crash items only, 6 "broken" items) | Order only; re-measure with more severe items |
| `digest.failure_cause` | choice | 49 | Accuracy 0.92; confidence>=0.6: 0.98 on 92%. Misses: layout vs real 2, stale vs real 1, infra vs timing 1. Compile errors 8/8 | Use at confidence>=0.6; the digest's INFRA regexes and "No matches found" still decide first | Yes, after the regex floor |
| `request.surface` | choice | 73 | Accuracy 0.60; confidence>=0.8: 0.71 on 71%. mockups 4/11, rules_docs 4/14, tests 7/14 | Do not use on PR text: the changed files give the answer exactly. Only for issues that have no files, and then re-measure on issues | No |

Confusion summary (derived):

- `request.surface`: docs, mockups and tests described in app words land in `app_ui` (13 of the 29 misses).
- `task.device_scope`: tooling and CI PRs read as `all_families` (5): harmless, since the floor (no UI files) decides first.
- `digest.failure_cause`: the 4 misses are all between neighbouring classes.

## Planned questions, measured against inline wording

The question files are being written by `ar-jev-tools`; the wording below is mine (`probes.json`). Re-measure after reconciliation.

| Question | n | Accuracy | By confidence | Weak classes | Note |
|---|---|---|---|---|---|
| `route.role` | 60 | 0.80 | >=0.8: 0.97 on 62%; >=0.6: 0.90 on 82% | designer 5/8 (read as coder), verifier 2/4, coder 14/18 | Items were owner messages, not issues. 1 steward, 1 ha_operator, 1 owner item only. Use the 0.8 band; below it the Orchestrator decides |
| `change.kind` | 80 | 0.80 | >=0.8: 0.91 on 69% | test 2/7 and perf 4/7 are read as bugfix; refactor 4/6 | Titles such as "Journey health" and "Fix scroll cost" are bugfix-shaped; probably hold `test` and `perf` back or add the title prefix rule to the criteria |
| `owner_msg.kind` | 75 | 0.80 | >=0.8: 0.91 on 60% | rule 4/8 (read as new_task or redirect), decide 5/8, bug_report 6/8, question 6/8 | `rule` overlaps `new_task` in my own labels ("Fix those issues in a new worktree. In addition, enforce..."): expect 0.75 real accuracy. status_ping 8/8 and redirect 8/8 |
| `transcript.turn_kind` (v1) | 80 | 0.48 | >=0.6: 0.50 | result 1/20: read as progress (17), wait 11/23 | Wording failure: "progress" swallowed everything |
| `transcript.turn_kind` (v2) | 80 | 0.69 | >=0.8: 0.84 on 54% | blocker 2/6, progress 10/20 | v2 added "choose result when it reports a finding" and made progress an action only. Tuned on the same labels: treat 0.69 as an upper bound |

## Failures and surprises

- `transcript.turn_kind` v1 scored 0.48 on six options: one option written as "what it did or is doing" absorbed waiting and results. A noul that asks only the interesting question (`turn.waiting_narration`) reached AUC 0.988 on the same turns. Prefer a noul per interesting category to a wide choice.
- `task.device_scope`'s `ipad_only` and `iphone_only` classes have almost no labels. The owner almost never scopes work to one device, so the saving rests on `duo_only` (13 of 50 items) and `no_ui`.
- `request.severity` is strong on this sample but the high end is thin (2 crashes). Do not trust the 3 band without more cases.
- `request.surface` shows the limit of text-only classification: PR bodies describe what the app looks like even when the change is a mockup or a test. Where a diff exists, code beats Jev.
- Every sampled owner message that was a bare "Yes" has no context in this test: in production the state must include the proposal title, or `owner_msg.kind`'s `approve` will be judged without what is approved.
- Not measured for lack of labels: `finding.severity` (14 findings in `build/review`), `request.page`, `request.ha_side`, `request.needs_info` (3 issues exist, all pipeline probes), `ha.change_risk`.

## Decision-gate corpus (2026-11-02)

The questions for the post-research gate ([agent-roster](../../../.agents/workflow/agent-roster.md#roles)): is a change visible in the owner's sense, and does it need the owner's pick? Owner rule of 2026-11-02: a change only to when or how often an existing state appears is not visible ([propose-first](../../../.agents/workflow/propose-first.md#what-is-visible)).

### Method

- **Corpus:** `scenarios/decision-gate.jsonl`, 165 scenarios across 17 areas (every page plus settings, shell, connection, platform and engineering). Each has the owner's request, the orchestrator's plan after research, `visible` and `kind` (none, policy, design). Three authors (Sonnet) wrote 55 each from the page specs and patterns against `scenarios/decision-gate.rubric.md`, with quotas for tricky cases: timing-only changes that sound visual, value corrections that sound visual, defaults, and changes to both timing and drawing.
- **Two labellers:** an Opus labeller relabelled all 165 blind (text and rubric only). Agreement: `visible` 162/165 (Cohen's kappa 0.96), `kind` 163/165 (0.98). I adjudicated the 3 disagreements:
  - inventory-04 and vacation-06 went to design: one option on the table changes what is drawn or said.
  - media-04 kept visible.
  - inventory-10 went to design under a rubric clarification made during labelling: a default that regroups the page is drawn differently.
- **Agreement is high partly by construction:** the plans state what the research found ("the pattern already says…", "options: …"), as production plans should. Real plans may be vaguer. Expect lower numbers on them.
- **Wording was committed before the corpus existed** (6614ad6e). The split is stratified by (kind, visible): dev 41, test 124. Dev numbers were good enough that nothing was reworded, so the test numbers are clean held-out results.
- **Spend:** about 1,000 calls, about 0.02 USD.

### Results (test split, 124 scenarios; `results/*.test.jsonl`)

| Question | Input | Result | Use |
|---|---|---|---|
| `design.user_visible` v1 (shipped wording, no criteria) | plan | AUC 0.772; p>=0.6 says yes on 91, right on 54 | Retired by v2: it reads "see or feel" as anything a person notices, so every timing change counts |
| `design.user_visible` v1 | request | AUC 0.822; p>=0.6 right 54/100 | |
| **`design.user_visible` v2** | plan | **AUC 0.994; p>=0.6 right 50/50; p<0.3 right 61/64; 10 in the band** | Active, raise-only: p>=0.6 sends the work to the Designer |
| `design.user_visible` v2 | request | AUC 0.925; p>=0.6 right 44/45; p<0.3 right 59/64 | Active at intake, raise-only: L0 to L1 |
| `decision.kind` (choice: none, policy, design) | plan | Accuracy 0.895; conf>=0.8: 0.952 on 68%. Misses: design read as policy 9, none as policy 4 | Rejected (see below) |
| **`decision.needs_owner`** | plan | **AUC 0.999; p>=0.5 precision 0.984, recall 0.926; p>=0.7 1.00 / 0.46** | Active, raise-only: p>=0.5 makes it L2 |
| needs_owner >= 0.5, then v2 >= 0.3 → design, else policy | plan | 115/124 = 0.927 | The composite replaces `decision.kind` |

On the dev split the same questions scored: v1 AUC 0.714, v2 0.992, `decision.kind` 0.976, `needs_owner` 1.000. v2 held up from dev to test. `decision.kind` fell from 0.98 to 0.90.

By area, v2 on plan text decided 114 of 124 test scenarios outside the band and got 111 right. The 3 misses were one each in connection, inventory and rooms. No area fell below 4/5.

Sanity check on the case that started this: the camera grace plan from dry run DRY-9999 (4 s against 30 s, same tile) scored v2 p=0.06 (not visible) and needs_owner p=0.77. That routes to a decision note with no Designer, which is what the owner asked for.

### Why `decision.kind` is rejected

Its misses are in the dangerous direction and confident. A plan where one option changes what is drawn was read as `policy` at 0.96 (inventory-04), 0.97 (inventory-10), 0.91 (climate-07, security-03). Acting on that would skip the Designer. It is the same failure as `transcript.turn_kind` v1: one wide option swallowed a narrower one. Two nouls, each asking only the interesting question, beat the choice. Use the composite, and only in the raise direction.

### Limits

- **Synthetic corpus.** The labels are agents' readings of the owner's rule, not the owner's own. Re-measure on the first 30 real gate plans (the shadow log in `build/jev/shadow.jsonl` and the ledger's `level_history`).
- **Request text is weaker than plan text.** It often cannot say whether a decision exists. Intake uses only v2's yes direction.
- **Rare-shape gaps.** Haptic frequency (climate-07) and "remember the last pick" defaults are each represented by only a few items.
- **One test item shaped the rule.** home-05 is the camera-grace case from the dry run that prompted the owner's rule and the v2 wording. It sits in the test split. One item does not move the AUC, but it is not strictly unseen.
- **State shape differs from production.** The probes sent the scenario text as a lone `body` field (`design.user_visible`) or `plan` field. Production sends `title`, `body` and `files` for `design.user_visible`, and `jev_gate.py` passes a title when the orchestrator gives one. Expect small shifts.
- **Re-measure source.** Active questions do not write `shadow.jsonl`. `tools/jev_gate.py` and the runner's intake raise append each answer (question, subject, value, p, whether a hint was printed; no text) to `build/jev/gate.jsonl`, and raises land in the ledger's `level_history`. Re-measure against the owner's decisions on the first 30 real gate plans.
- **The defaults clause is the orchestrator's, not yet the owner's.** The labels apply it ([propose-first](../../../.agents/workflow/propose-first.md#what-is-visible)). If the owner rejects it, relabel the 10 default items and re-measure.

## Target-decided corpus (2026-11-02)

The third gate question, `design.target_decided`: when a change is visible, has the owner (or a pattern, decision, parity or guideline) already chosen the result? The owner asked for it after dry run DRY-9998 (single-page Settings motion). There the owner named the motion they wanted, but the gate sent the work to a full Designer options round that cost 217k tokens.

### Method

- **Corpus:** `scenarios/target-decided.jsonl` has 126 visible scenarios. They are:
  - the 80 visible items of the decision-gate corpus;
  - 45 new ones written by one Sonnet author against `scenarios/target-decided.rubric.md`: 20 already chosen with a scope, rule or build pick left, 10 already chosen with nothing to pick, and 15 open;
  - one real case: DRY-9998.
- **Two labellers.** The first labels for the 80 older items were derived from their `kind`: none meant chosen, design meant open. An Opus labeller relabelled all 126 blind.
  - Agreement was 108/126 (kappa 0.72).
  - Every disagreement was on a derived label. On the 46 new and real items the two agreed 46/46.
  - I took the blind label on 16, where the owner's words name the result. I kept the derived label on 2: chores-01 ("somewhere else" leaves where the Undo goes open) and shell-03 ("down the side" fits a sidebar or an overlay).
  - Lesson: `kind=design` does not imply "not chosen". Many design items had the owner name the result, with only a rule exception left.
- **Wording was committed before the data** (ede3776a). Splits: dev 32, test 94, with the real case in test. Dev was not used to reword.

### Results

- **Test split (94 items):** AUC 0.937, and **precision 1.00 at every threshold from 0.3 to 0.85** (it holds down to about 0.13): 33/33 at p>=0.5, 22/22 at p>=0.8. It never said "chosen" for an open item.
- **Recall is the weak side:** 0.58 at 0.5.
- **The two sources differ:** the older decision-gate items scored AUC 0.88, and the new items 1.00. The new items are probably written more cleanly.
- **Dev split (32 items):** AUC 0.994.

### The real case and how plans must be written

DRY-9998 written as the gate originally saw it (options A to D, as if all were open) scored **0.08** in the test run (`results/design.target_decided.test.jsonl`; 0.07 in a single check without the `Request:` prefix). The same case written target-first (`scenarios/dry-9998-target-first.md`, one call, not part of the test split) scored **0.56**. Target-first means the owner's words, then "target the owner named: the unfolded Duo column motion", then the research, then only the remaining choices.

Jev reads the plan literally: a plan that lists every option as open reads as undecided. The gate now requires target-first plans (`agent-roster.md`, `worker.md`).

### Use

- **Active, hint-only.** Bands are 0.5 yes and 0.3 no.
- **A yes may suggest an L1 Designer spec instead of L2 options.** That moves work down, so the orchestrator decides. Jev never lowers a level by itself.
- **Promotion to acting alone** needs the owner, plus a re-measure on real gate plans (`gate.jsonl` and the owner's picks). The point precision of 33/33 has a 95% lower bound of about 0.89, below the 0.95 bar for a move down.

## Owner-message corpus: `owner_msg.about_workflow` (2026-11-02)

Steward entry B: does an owner message ask about how the agents work, rather than about the app or a one-off task?

- **Corpus:** 120 of the owner's own messages from the session histories, redacted. Messages containing keys, tokens, URLs, IPs, emails or other people's names were dropped, and home paths masked. The 5 items that mention "key" or "token" contain no secret. One Sonnet author labelled them, an Opus labeller relabelled them blind, and the two agreed on 103/120 (kappa 0.69).
- **Adjudication:**
  - 16 went to the blind labeller. One-off orchestration (split this batch, merge this change here, skip checks once), chores, status notes and temporary instructions are not about the agents. Test-gate granularity is.
  - 1 went to the author: "this all comes off the uikit worktree" became a standing rule.
  - Final: 35 true, 85 false.
- **Wording committed before the data** (e6900e03). Split: dev 30 / test 90, stratified. No rewording was done.
- **Test results (90 items):**
  - AUC 0.962;
  - p>=0.5: precision 0.905 (19/21), recall 0.73;
  - p>=0.7: precision 0.93;
  - p>=0.85: 10/10.
- **Dev results (30 items, 9 positive):** AUC 0.78. Dev is small and noisy, so treat the test number as the estimate, with a wide interval.
- **Pooled dev + test (120):** p>=0.5 precision 23/28 = 0.82, below the 0.85 target; p>=0.7 precision 16/18 = 0.89. So the yes band starts at **0.7** (tightened after review, 2026-11-02).
- **Use:** active as a hint, yes at p>=0.7. It adds the Steward and never skips a step. The rule decides first: the `Workflow` label, or work touching `.claude/agents`, `.agents/workflow`, `tools/hooks`, `tools/triage` or `contracts/jev`.
- **Re-measure** on the next 30 routed owner messages using `gate.jsonl`.


## L2 gate corpus: `design.matches_request` and `design.app_wide` (2026-11-03)

These two questions decide L2 autonomy. Owner rules, 2026-11-03:
- Request-driven work lands only when the change matches the owner's ask.
- Agent-initiated work parks if it is app-wide.
- Jev unavailable parks.

**Corpus**
- `scenarios/l2-matches.jsonl`: 120 request/change pairs, half high-detail and half low-detail asks, half matches. The camera and settings-motion requests appear with their true changes and four drifts each.
- `scenarios/l2-appwide.jsonl`: 100 changes, 40 app-wide.
- A Sonnet author wrote them. An Opus labeller relabelled them blind and agreed on all 220 (kappa 1.00).
- **Read that as a warning:** the corpus is written with clean contrasts and is easier than real plans. Treat the numbers as an upper bound.
- Wording was committed before the data (faaa54e2). The `matches` split is grouped by request so a request never appears in both dev and test; dev 33 / test 87. The `app_wide` split is stratified by id; dev 25 / test 75. No rewording.

| Question | Test result | Band in use |
|---|---|---|
| `design.matches_request` | AUC 0.928. p>=0.8: precision 30/31 = 0.97, recall 0.64. Detail levels behave alike at 0.85: high 10/10, low 12/13. Two real matches sat below 0.3. | Yes ≥ 0.8 → autonomous. Anything else parks. |
| `design.app_wide` | AUC 0.999. p>=0.5: precision 28/28. Below 0.3: 46 items, 1 actually app-wide (a 3% miss). | < 0.3 → local (autonomous). Otherwise parks. |

- **Dev split:** `matches_request` AUC 0.971, `app_wide` 1.000.
- **Both move work down** (no owner pick), so the band sits where precision ≥ 0.95, and the rest parks.
- **Re-measure** on the first real gate plans: `gate.jsonl` against the owner's later corrections.
