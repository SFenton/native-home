# Change loop

> **What:** the per-change procedure. **Read when:** before any code change.

## Rung 0: system API first

Before any custom scroll, blur, mask, material, list, header, sheet, paging or layout machinery, the spec (and the proposal, if visible) names three things:

1. **The system API** that does it on iOS 17, on 18 and on 26 (for example `presentationSizing(.fitted)`, `scrollTargetBehavior`, `onScrollGeometryChange`, `scrollEdgeEffectStyle`, `glassEffect`, `Layout`), even where the answer is "nothing before 18".
2. **A precedent**: an Apple sample or documentation page, or an open-source implementation that solves it.
3. **Why it is not enough**, in one sentence. If the reason is performance, with a measurement (`tools/ios_scrollcost.sh`, Time Profiler, a signpost); "it felt slow" does not count. If the reason is a design choice, the owner's decision.

A missing note is a major finding at review ([pr-lifecycle](pr-lifecycle.md)); custom code where a system API plainly fits is a blocker. [system-api-audit](../design/apple/system-api-audit.md) records the verdict for every custom component that exists today.

## Steps

1. **Source.** Read the React source for the surface (`ha-sfenton-react-dash/src/pages`, `src/components`, entity IDs in `src/constants`). Note entities, displayed states, services called and navigation edges.
2. **Spec.** Update `.agents/pages/<id>/spec.md` (platform-neutral) and the platform file (`ios.md`, `ipados.md`, `duo.md`, `watchos.md`).
3. **Pattern check and rung 0.** For a task you only have as text, `python3 tools/jev_hints.py preread --title "..." --body-file task.md` prints a ranked pre-read of likely patterns, files and complexity (or nothing without a key: the key file `~/.config/fenton-hass/typesafe.key` (or `TYPESAFE_API_KEY` when there is no file); a guess to verify, [decision-models](decision-models.md)). Find the owner with the registry, not by scrolling: `python3 tools/pattern_guard.py which <file>` for a file, `python3 tools/pattern_guard.py index` for the list, `contracts/components.json` for a view or modifier by name. If the behavior exists elsewhere, extend the canonical component in [patterns](../patterns/README.md). If it needs machinery the system may already provide, write the rung-0 note above first.
4. **Propose.** Find the surface in the [mockup atlas](../design/mockups/README.md) first. If the change is visible, stop here: build a mockup page and a recommendation, share it, and wait for the owner's pick ([propose-first](propose-first.md)). Skip only for changes that render the same pixels.
5. **Implement** the chosen option in your lane's folders. Entity IDs go in `HassCore/Config`, never inline in views.
6. **Test.** Unit tests for logic in `HassCore`/`HassDesign`; UI and accessibility tests with each UI change.
7. **Review** your diff with `/swiftui-pro` ([how](swiftui-pro.md)) and fix what it finds in your files.
8. **Verify** on the simulator against the mockup, update the surface's atlas mockup (states, motion, a11y, status) in the same PR, then commit small and update [PROGRESS.md](../../PROGRESS.md).
9. **Land.** Ship, review and merge as in [pr-lifecycle](pr-lifecycle.md).
10. **Guard lane** (any change to a `tools/hooks/*_guard.py`). The brief states the standard, tripwire or wall, linking [ci](ci.md); every claim about an external API carries the probe command and its output; and the rows exist in `tools/tests/guard_tables/<guard>.tsv` (`command`, `block|allow`, `why`; both sides) before the first review. A bypass or a false positive found later is a new row first, then the fix; `test_guard_tables.py` replays the rows through the guard's `main` and keeps `uncovered.baseline` (hooks with no table) from ever growing.

Scope a check against what it guards: a test-harness change proves itself with its touched tests, the coverage-tool tests and the first nightly, not a full coverage run (owner, 2026-11-05).
