# Jev corpus

> **What:** every Jev question the agent system uses or may use, by role: the planned set, the derived candidates, what each answer produces and who consumes it, and the rules for promoting and retiring questions. **Read when:** adding a Jev question, wiring a hint or KPI to a Jev answer, or asking whether a question earned its place. Mechanics and measured numbers for the active questions are in [decision-models](decision-models.md); derived candidates and their measurements are in `contracts/jev/derived/` (`candidates.json`, `measurements.md`, `labels/`).

## The outputs model

A Jev answer is never an end. Each one is a **typed value with one consumer**, and the consumer decides what it may do with it:

| Answer becomes | Consumer | May do | May never |
|---|---|---|---|
| A **hint line** in a prompt or tool output | An agent (Orchestrator, Coder, Reviewer) | Reorder where it looks first | Skip a check, change a level downwards |
| A **ledger field** (`build/tasks/*.json`: level raise, `rounds.owner_qa`, `device_families`, a waiver quote) | `tools/tasks.py`, the Orchestrator | Raise a level; record a fact with its quote | Lower a level, flip `passes` |
| A **router branch** (surface, page, severity, needs-info) | The triage Router | Choose the worker prompt, lane, queue order | Close an issue that names a defect; write to the owner |
| A **hook decision** | A hook in `tools/hooks/` | Make a rule stricter (block an auto flip, ask once for evidence) | Loosen a rule, trap an agent twice |
| A **Steward KPI row** | The weekly Steward job and owner digest | Count, trend, flag | Change agents, hooks or questions on its own (the Steward writes specs; Coders build; a Reviewer judges) |

One rule decides every design: **code decides what it can state exactly, first; Jev may only make that decision stricter, or fill the gap where no rule exists.** Safety gates (L3 areas, signing, device access, Home Assistant locks and alarms) are code; a Jev answer can raise a level, never grant access.

Each question file declares its consumer in `description`. A question with no named consumer is not added.

## Corpus by role

"Planned" questions are written by `ar-jev-tools` into `contracts/jev/questions/`; "derived" ones live as candidates in `contracts/jev/derived/candidates.json` and become files only when promoted to shadow. Fit and measurements for the derived ones are in the candidates file.

| Role | Planned | Derived (candidates) |
|---|---|---|
| Orchestrator | `route.role`, `owner_msg.kind`, `brief.complete`, `report.complete`, `design.user_visible` (level raise), `decision.needs_owner` (post-research gate), `design.target_decided` (gate route hint) | `owner_msg.reports_failed_fix`, `owner_msg.partial_approval`, `owner_msg.defers_or_cuts_scope`, `owner_msg.wants_visuals`, `task.needs_physical_device`, `task.touches_signing_or_credentials` |
| Researcher | `research.section_relevant`, `research.evidence`, `research.contradicts`, `research.injection`, `research.release_impact`, `research.source_kind` | `research.question_kind`, `research.needs_measurement` |
| Designer | `design.new_pattern`, `component.exists`, `design.user_visible` | `task.device_scope`, `design.change_scope`, `design.reply_adds_requirement` |
| Coder | `change.kind`, `code.custom_machinery`, `tests.pick` | `pr.user_visible` |
| Verifier | `tests.pick` | `digest.failure_cause`, `evidence.claims_poses` |
| Reviewer | `review.finding_family`, `check.tests` (shadow, no signal) | `finding.severity`, `review.pr_body_states_why` |
| Steward | `transcript.turn_kind`, `owner_msg.kind`, `learning.home`, `owner_msg.about_workflow` (hint for Entry B) | `turn.waiting_narration`, `owner_msg.standing_rule`, `owner_msg.asks_status`, `session.kind`, `workflow.friction_kind` |
| Triage Router | `triage.duplicate`, `route.role`, `owner_msg.about_workflow` (Steward Entry B hint) | `request.surface`, `request.page`, `request.severity`, `request.needs_info`, `request.ha_side`, `request.web_parity` |
| HA operator | none | `ha.change_risk` (floor in code first; raise only) |
| Menial | none: its work is fixed commands, no judgment to ask | none |

Active today (see [decision-models](decision-models.md)): `context.patterns`, `context.precedents`, `route.complexity`, `review.finding_family`, `design.user_visible` v2 and `decision.needs_owner` (raise-only, decision-gate corpus 2026-11-02); shadow: `check.tests`. Rejected after measurement: `decision.kind` (confident misses in the direction that skips the Designer; the two nouls replace it).

Measured on local labels (2026-11-01, see `measurements.md`): `turn.waiting_narration` AUC 0.99, `pr.user_visible` 0.99, `owner_msg.reports_failed_fix` 0.96, `owner_msg.partial_approval` 0.93, `owner_msg.standing_rule` 0.86; choices `digest.failure_cause` 0.92, `task.device_scope` 0.82, `route.role` 0.80, `change.kind` 0.80, `owner_msg.kind` 0.80, `request.surface` 0.60 (do not use on PRs), `transcript.turn_kind` 0.48 as written (0.69 after one rewording; use `turn.waiting_narration` instead).

## Promotion: shadow to hint

Every question starts as `mode: shadow` (asked, logged, never shown). It becomes `active` when **all** hold:

1. At least **30 labelled items**, labelled from text or a ground truth the question did not see, in `contracts/jev/derived/labels/<id>.jsonl` (or the production equivalent), including at least 8 of the rarer class.
2. Measured precision at the question's suggested threshold is **at least `target.precision` in its question file** (0.85 by default; 0.8 for tighten-only hints), and beats the deterministic floor listed in the candidate where one exists.
3. A named consumer exists and the question's output is one of the five in the outputs model; a question that would lower a level or open a gate stays shadow forever.
4. Wording, criteria, `version` and the measurement are recorded together (`decision-models.md` table and the `evidence` field). Any wording or criteria change bumps `version` and sends it back to step 2.
5. Promotion is autonomous once items 1 to 4 hold on a held-out split and an independent Reviewer agrees (owner, 2026-11-02: the owner is no longer the approver). The change that promotes a question may not edit its labels, splits or thresholds (decision 2 in the plan: the evaluator only gets stricter).

Promotion for a choice question uses accuracy at the abstain confidence (`accept.min_confidence`), reported with coverage. A question measured below target stays shadow; retire it if it cannot get there with one rewording.

## Retire

A question is **retired** (file moved to `contracts/jev/retired/` with its last measurement, hint removed) when any hold:

- **Unused:** 30 days in which no consumer read its answer (calls log shows asks, nothing consumed it).
- **Unmeasured:** 30 days after reaching shadow without a measurement entry meeting promotion item 1.
- **Decayed:** a re-measure after wording or model change falls below target and one rewording does not recover it.
- **Superseded:** a deterministic rule now decides it exactly, or the model/tool it served was removed.

The Steward runs the check weekly from `build/jev/calls.jsonl` and `build/jev/derived` KPI output and lists retirements in the owner digest for information. Retiring is autonomous once the reason is code-checked and an independent Reviewer agrees (owner, 2026-11-02), and never in the same change that edits the question's labels, splits or thresholds. An unusual run of retirements pauses the loop.

## Next 10 to derive

Not yet in `candidates.json`; each is a single judgment over text with a clear consumer.

1. `rule.applies_to_task` (noul-set, one per AGENTS.md invariant): which invariants the brief must cite; a `context.patterns` for rules.
2. `agent_report.status_matches_summary` (noul): status `done` while the summary says blocked or failing; Reviewer/Orchestrator hint, stricter only.
3. `proposal.has_recommendation_and_options` (noul): propose-first lint on a mockup proposal (at least two options and a stated pick).
4. `brief.single_deliverable` (noul): the brief asks for more than one deliverable; split before dispatch.
5. `pr_comment.requests_change` (noul): whether a PR review or CI comment asks for a code change (auto-fix loop trigger vs noise).
6. `owner_msg.relates_to_open_pr` (choice over open PR titles plus none): bug reports attach to the lane already working that area (generalise-fixes).
7. `hook_block.is_correct` (noul): was a hook block a true catch or a hook bug, from the block message and the command; Steward tool-bug queue.
8. `handoff.note_complete` (noul-set: state, next step, open question, files): lint `build/handoff/*.md` before a session ends (blocked-work notes only).
9. `build_warning.matters` (noul): Xcode warnings worth a ledger entry versus the known-noise list.
10. `issue.has_repro_steps` (noul): a request issue contains steps or a screen name; feeds `request.needs_info` with a cheaper first check.

Data needed before measuring several candidates already listed: 30 closed request issues (`request.page`, `request.needs_info`, `request.ha_side`), 30 reviewer findings with severities (`finding.severity`), and Workflow issues (`workflow.friction_kind`). `tools/jev_miss.py` (`--task T` or `--since 7d`) joins logged gate and shadow answers with outcomes Jev did not produce and writes `build/jev/misses.jsonl`; rows that can be labels are staged in `build/jev/harvest/<question>.jsonl`. Allowed truth sources: the independent Reviewer's verdict record (`check.tests` is true when a tests finding exists; green CI is not its truth), no app-UI path and no `Release-Note:` other than `none` (`design.user_visible` false only; a UI path or note gives no truth), and the Reviewer record only for the answer's own head (else `stale_truth`), CI conclusion and an owner prompt-log reply (dated quote; no reader yet). The ledger's final level is only a miss signal (`self_influenced`, agents raise levels from the gate's own hints) and is never staged. `owner_msg.*`, `turn.*` and `research.*` stay `needs_blind_label` (blind second labeller plus adjudication). Gate and shadow rows carry no state text and the answer cache cannot be joined to them, so such rows are `needs_state` and are not staged; logging the state needs a change to the protected `tools/jev_ask.py`, a follow-up. Appending vetted rows to `labels/` is a separate append-only Coder lane, never in the same change as a question, hook or agent change.

Privacy redaction (2026-11-08): 13 rows in 9 files under `contracts/jev/derived/labels` and `scenarios` were edited in place to remove private repo names, paths and a room-access id scheme. Only `text` or `plan` changed; every label is unchanged. This is a recorded departure from the append-only rule.
