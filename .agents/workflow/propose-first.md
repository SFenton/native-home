# Propose, build, judge, record

> **What:** how a change the owner will see or feel gets decided: the agent builds up to 3 options, the Designer judges them from evidence and records the pick, the chosen one lands. Nothing waits on the owner. **Read when:** before writing code for any change to UI, layout, copy, motion, navigation or a shared pattern. (The file keeps its old name: other docs link it.)

Owner decision (2026-11-03, replaces the 2026-10-23 gate): when a design or trade-off choice is real, "Should pick the best option- either Jev or operator handles. If we need to implement {n} options and then decide based on screenshots/functionality, that's acceptable." The owner may reverse a pick later; that is a new request, not a stalled one. The weather header ([doc](../design/weather-card-header.md)) is still the model for the record.

## When it applies

| Applies | Does not apply |
|---|---|
| Anything a person will see or feel change: layout, sizing, spacing, copy, icons, materials, motion, haptics, navigation, sheet or detent behavior | Crashes and logic bugs with no visible difference |
| A new screen, control, tile, chip, sheet or setting | Performance, tests, tooling, docs, refactors that render the same pixels |
| A change to a shared pattern ([patterns](../patterns/README.md)) | Restoring behavior a spec or pattern doc already states; the fix is the spec |
| A fix with more than one reasonable visual answer | An option already chosen and recorded (build it) |
| | Timing or frequency of a state that already exists, with the same look, words and motion ([owner rule](#timing-and-defaults-are-not-visible)) |

When unsure whether a change is visible enough, treat it as visible.

## The app-UI gate: when the owner is needed

Owner clarification (2026-11-03): "app UI changes" that need the owner are **broad, app-wide changes not explicitly requested by the owner**. `python3 tools/jev_gate.py --plan-file <plan>` prints the outcome as hint lines and a machine-readable last line, `gate: autonomous|park basis=request|agent answer=yes|no|unsure|unavailable`. Write the plan with an `Owner's request:` line (the owner's words) when an owner request exists.

1. **Request-driven work** (the plan has an `Owner's request:` section): Jev `design.matches_request` (state `pair` = `Request: <owner's words>` then `Change: <the plan or built result, including the chosen option>`; autonomous only on an accepted yes, p >= 0.8). Accepted yes: autonomous (build up to 3 options, the Designer judges, land). No or unsure: park for the owner. This covers detailed asks (the proposal must match) and vague ones (if Jev cannot confirm a match, the owner decides). A broad app-wide change (palette, typography, app icon, global navigation) is approved when the owner asked for it specifically or `design.matches_request` is a confident yes.
2. **Agent-initiated work** (no owner request: retro and Steward lanes, nightly fixes): Jev `design.app_wide` (state `change` = the plan). Autonomous only on a confident no (p < 0.3: the change is local to a screen); yes or unsure counts as app-wide: park.
3. **Jev unavailable or a question file missing**: park (fail safe).

Parking is `needs_decision` with `decision.owner_only` set to `app_wide` (agent-initiated), `unmatched` (request not confirmed) or `gate_unavailable`. The gate is a hint for the orchestrator's own judgement of the same two questions, not a replacement; when it parks, nothing is built beyond what is needed to show the owner the options.

## Timing and defaults are not visible

Owner rule (2026-11-02): a change only to the timing or frequency of a state that already exists (delays, timeouts, retries, refresh intervals, how long something stays connected or cached, thresholds), with the same look, words and motion, is not "see or feel". It needs no mockup.

Owner rule (2026-11-03, confirmed): the default value of an existing setting, with the same control, look, words and motion, is treated the same way. A default that changes what a screen shows when it opens (the sort order, the grouping, which items appear) is still visible: the page is drawn differently.

A trade-off with nothing visible changing and nothing on record (the camera stream grace period, 4 s or 30 s) is **L2 policy**: the orchestrator writes a decision note (`build/decisions/<task>.md`: the question, the options with what the owner would notice and the cost of each, the recommendation, what is unmeasured) and the Designer or orchestrator judge it the same way (below), then it lands.

## The procedure

1. **Cause or goal.** What is wrong or wanted, with measured evidence (point sizes, the failing string, a screenshot).
2. **Build up to 3 options.** Genuinely different answers (one when the fix is unambiguous: a before and after). Start from the surface's mockup in the [atlas](../design/mockups/README.md) (`catalog.json` finds it). Each option that adds custom scroll, blur, mask, material, list, header, sheet, paging or layout machinery carries its rung-0 note ([change-loop](change-loop.md#rung-0-system-api-first)); include the system-API option even if it loses. Build them as throwaway branches or a flag in the worktree, or as live-size mockups when the app cannot show the difference.
3. **Capture the evidence.** Screenshots and behaviour of each option on every affected family (iPhone, Duo, iPad) at the default and an accessibility text size, and in the states that break it (long text, empty, error, offline), via the pose matrix ([pose-matrix](../skills/pose-matrix/SKILL.md)).
4. **The Designer judges.** From the evidence only: screenshots, behaviour, the HIG (cite the section), existing patterns and the owner's rules; Jev `design.user_visible`, `decision.needs_owner` and `design.target_decided` are hints, never the verdict. It picks one option and says why the others lost.
5. **Record the pick** with the `design-decision` skill in `.agents/design/<topic>.md`: the goal, a line `Decision: <date>, judged Option A, B and C; picked B, because ...`, the rules it adds. Keep the mockup, update the surface's atlas entry (status `in-flight:<branch>` while another branch is unmerged; a PR's own `inFlight` marker is cleared and the status set to `shipped` before it merges, and `mockups_check.py` fails it in CI otherwise) and link it from [design/README.md](../design/README.md). Add a line `Gate: app_wide=no` (agent-initiated) or `Gate: matches_request=yes` (with `Owner-Request: <ref>` in a commit message) copied from the gate. `tools/lane_land.py` refuses a lane that changes app UI without this record and a passing gate (or a `Design: <path>` citation of an existing record or pattern, for a bug fixed back to documented design).
6. **Land the pick** like L0 and L1: only the chosen option is merged, verified per the [change loop](change-loop.md), reviewed and landed with `tools/pr_land.sh`. The PR names the options judged and the pick, and shows the built result. The owner gets it in the digest and may reverse it.

Within the chosen option the agent decides the details and records them. A "just do it" from the owner for a change skips the options (one build, still recorded).

## Mockup atlas

Every page, modal, component and flow has a mockup on iPhone, Duo and iPad in [.agents/design/mockups](../design/mockups/README.md); update the surface's mockup in the same PR as the change. Mockups map the app; the code and recorded decisions win. The owner browses them in the one hub Artifact (`python3 tools/mockups_hub.py`; skill [mockup-hub](../../.agents/skills/mockup-hub/SKILL.md)); never publish a mockup as its own Artifact.

## What still waits for the owner

Only `needs_decision` with `owner_only` set: the fixed set ([agent-roster](agent-roster.md#autonomy-levels)) and a `gate: park` from the app-UI gate above. The runner parks that PR (`Needs Decision`, `pr_land.sh` refuses it). A design or policy pick that finishes `needs_decision` without `owner_only` is sent back to be judged and landed.

**Questions to the owner (2026-11-04).** `AskUserQuestion` is for owner-only decisions only; see [agent-roster](agent-roster.md#questions).
