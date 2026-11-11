# Propose, build, judge, record

> **What:** how a change someone will see or feel is decided: the agents build options, the Designer judges them from evidence and records the pick, the pick merges. **Read when:** before writing code for any change to UI, layout, copy, motion, navigation or a shared pattern.

## What is visible

| Visible | Not visible |
|---|---|
| Anything a person sees or feels change: layout, sizing, spacing, copy, icons, materials, motion, haptics, navigation, sheet behavior | Crashes and logic bugs with no visible difference |
| A new screen, control, tile, chip, sheet or setting | Performance, tests, tooling, docs, refactors that draw the same pixels |
| A change to a shared pattern | Restoring behavior a spec, pattern or mockup already states |
| A fix with more than one reasonable visual answer | An option already chosen and recorded |
| A default that changes what a screen shows when it opens | The timing or frequency of a state that exists, or the default of an existing setting, with the same control, look, words and motion |

When unsure, treat the change as visible.

## Decide

Nothing here waits for the owner; what does is in [autonomy](autonomy.md#owner-only).

1. **State the cause or goal** with measured evidence.
2. **Build up to 3 options** that are different answers, starting from the surface's mockup. One build is enough when the fix is unambiguous or the request names one specific result. An option that adds custom machinery carries its [rung-0](change-loop.md#rung-0) note.
3. **Capture evidence** of each option on every affected family, at the default and an accessibility text size, and in the states that break it: long text, empty, error, offline ([pose-matrix](../skills/pose-matrix/SKILL.md)).
4. **The Designer judges** from the evidence, the HIG, the existing patterns and the decisions on record, in that order of authority after an explicit owner choice. It picks one option and says why the others lost. Decision-model answers are hints ([jev](jev.md)).
5. **Record the pick** (below).
6. **Merge only the pick**, verified and reviewed like any change ([change-loop](change-loop.md)). The PR names the options judged and shows the built result.

- Within the chosen option the agent decides the details and records them.
- A design comparison runs at most 3 rounds; after that the Designer picks the best built option and records it.
- A reversal by the owner is a new request, handled the same way.

## Record

- The pick is recorded with the [design-decision](../skills/design-decision/SKILL.md) skill: the goal, the options judged, the pick and the reason, and the rules it adds.
- The surface's mockup and atlas entry change in the same pull request; `tools/mockups_check.py` fails a pull request that leaves its own in-flight marker.
- A bug fixed back to a documented design cites the existing record or pattern instead of a new one.
- `tools/lane_land.py` refuses an app-UI change without a record and a passing [app-UI gate](autonomy.md#app-ui-gate).

## Policy picks

A trade-off with nothing visible changing and no decision on record is an L2 policy pick. The orchestrator writes a decision note in `build/decisions/` with the question, each option's cost and what a person would notice, the recommendation and what is unmeasured. The orchestrator or the Designer judges it and the pick merges. It needs no mockup.
