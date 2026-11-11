# Change loop

> **What:** the order every change follows, and the system-API-first rule for custom UI machinery. **Read when:** before any code change.

## Rung 0

Custom scroll, blur, mask, material, list, header, sheet, paging or layout machinery is written only after a rung-0 note. The note names three things:

1. **The system API** that does the job on the deployment target and on each later iOS major version, even where the answer is "nothing".
2. **A precedent:** an Apple sample or documentation page, or an open implementation.
3. **Why it is not enough,** in one sentence. A performance reason carries a measurement ([performance](../testing/apple/performance.md)); a design reason carries the recorded decision.

- The note is a research note ([research-note](../skills/research-note/SKILL.md)); every option in a design comparison that adds machinery carries one, and the system-API option is built even if it loses.
- At review a missing note is a major finding; custom code where a system API fits is a blocker.
- The verdict for each existing custom component is in [system-api-audit](../design/apple/system-api-audit.md).

## The loop

| Step | Rule |
|---|---|
| 1. Source | Read the web dashboard source for the surface: entities, displayed states, services, navigation edges. |
| 2. Spec | Update `.agents/pages/<id>/spec.md` (platform-neutral) and the platform file. |
| 3. Pattern | Find the owning pattern with `tools/pattern_guard.py` and `contracts/components.json` before writing a view, modifier or helper. Extend the canonical component; write the rung-0 note before any machinery. |
| 4. Visible? | Find the surface in the mockup atlas. A visible change goes through [propose-first](propose-first.md); the level comes from [autonomy](autonomy.md#levels). |
| 5. Implement | Work in the lane's folders. Entity IDs live in `HassCore/Config`, never inline in views. |
| 6. Test | Tests ship with the change and assert behavior, not only compilation. Run the per-change tier, not the full suite ([test tiers](../testing/apple/README.md#test-tiers)). |
| 7. Self-review | Run the `swiftui-pro` skill on a SwiftUI diff; the repo's overrides are in [swiftui](../platforms/apple/swiftui.md) and win where the skill disagrees. UIKit screens follow [uikit-port](../platforms/apple/uikit-port.md). |
| 8. Verify | Check the result on the simulator against the mockup and update the mockup in the same change. Motion ships with signposts and a performance test. |
| 9. Record | Put what the change taught in its home ([docs-conventions](docs-conventions.md#homes)). A pattern's doc changes in the same change as its code. |
| 10. Land | Ship, review and merge as in [pr-lifecycle](pr-lifecycle.md). |

- `tools/pattern_guard.py` reports zero errors on every pull request; it runs in `pr-checks`.
- A reported bug is worked with the [fix-reported-issue](../skills/fix-reported-issue/SKILL.md) skill, a new shared control with [add-control](../skills/add-control/SKILL.md), a page port with [port-page](../skills/port-page/SKILL.md).
