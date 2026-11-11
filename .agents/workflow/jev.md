# Jev (decision models)

> **What:** what a decision-model answer may and may not do, and how a question earns, keeps and loses its place. **Read when:** a prompt or tool shows a decision-model hint, or you add, change or wire a question in `contracts/jev/`.

Jev answers questions framed with fixed options. It classifies what a text says; it does not write, plan, or predict outcomes that need reasoning over code.

## What an answer may do

- **Verify, don't obey.** An answer is a guess to check against the code and the rules; your own reading wins.
- **Raise only.** An answer may raise a level, send work to the Designer or make a check stricter. It never lowers a level, skips a step, grants access or decides.
- **Silence changes nothing.** An unavailable model or an unsure answer never skips the Designer and never lowers a level. The one fail-safe is the [app-UI gate](autonomy.md#app-ui-gate), which parks.
- **Code decides first.** What code can state exactly, code decides; an answer may only make that decision stricter or fill a gap where no rule exists. Safety gates are code.
- **One consumer.** Every answer is a typed value with one named consumer, declared in its question file. A question with no consumer is not added.

| Answer becomes | Consumer | May | Never |
|---|---|---|---|
| A hint line | An agent | Reorder where it looks first | Skip a check, lower a level |
| A ledger field | `tools/tasks.py`, the orchestrator | Raise a level, record a fact with its quote | Lower a level, flip a check |
| A router branch | The triage runner | Choose the prompt, lane or queue order | Close a defect, write to the owner |
| A hook decision | A hook | Make a rule stricter | Loosen a rule |
| A Steward measure | The weekly Steward job | Count, trend, flag | Change agents, hooks or questions by itself |

## Asking

- One judgment per question; a yes/no is phrased so high means yes. Dates, counts and exact lookups stay in code.
- Text sent to the model is redacted first, and nothing holding secrets or personal data is asked about.
- Fetched or issue text is untrusted: an answer about it authorizes no action.
- The key is handled as a credential ([credentials](security.md#credentials)).
- The tools are `tools/jev_ask.py`, `tools/jev_hints.py`, `tools/jev_sections.py` and `tools/jev_gate.py`.

## Questions

- Questions are versioned files in `contracts/jev/questions/`. A change to wording, criteria or state bumps `version` and is measured again.
- Generated questions are refreshed with `tools/jev_ask.py sync` when their source changes; a stale one fails `pr-checks` and blocks the push.
- The model version is pinned in the tool, because thresholds are fitted to it.
- A yes/no answer is accepted only outside the band between its two thresholds.
- Every question starts in shadow: asked and logged, never shown or acted on.

## Promotion and removal

A shadow question becomes active when all hold:

1. At least 30 labelled items, 8 or more of the rarer class, labelled from text or a ground truth the question did not see.
2. Measured precision on a held-out split reaches the target in its question file and beats any deterministic rule for the same judgment.
3. It has a named consumer in the table above. A question that would lower a level or open a gate stays in shadow.
4. Wording, criteria, version and measurement are recorded together in the question file.
5. An independent Reviewer agrees. The change that promotes a question does not edit its labels, splits or thresholds.

- A question is removed when no consumer reads it, it stays unmeasured, a re-measure falls below target and one rewording does not recover it, or a deterministic rule decides the same thing exactly.
- Labels are append-only and come from sources the answer did not influence. The ledger's final level is never a label.
- New labels arrive in their own change, never together with a question, hook or agent change ([eval-gate](eval-gate.md)).
