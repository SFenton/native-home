---
name: design-decision
description: Decides a design question the owner has not settled, by owner choice, HIG, then web parity, and records a judged pick. Use when a choice changes navigation, presentation or a shared pattern.
---
# Design decision

> **What:** how agents decide a design question the owner has not settled, and where the decision is recorded. **Read when:** a choice changes navigation, presentation or a shared pattern. Rules: [propose-first](../../workflow/propose-first.md).

1. Check the HIG (`apple-hig` skill) and the web behaviour.
2. Apply the precedence: the owner's explicit choice, then the HIG, then web parity, then convenience.
3. When the precedence, a registered pattern or a detail inside an option the owner picked settles it: decide, write the resulting rule in the owning doc, and tell the owner in the thread or the pull request.
4. Otherwise run the app-UI gate: `python3 tools/jev_gate.py --plan-file <plan>`. On `gate: park` do not pick ([autonomy](../../workflow/autonomy.md#app-ui-gate)).
5. Build up to 3 options, capture screenshots and behaviour on the affected families, and judge them from that evidence.
6. Record the decision as a new file `.agents/decisions/<YYYY-MM-DD>-<slug>.md` with these lines:
   - `Decision:` the options judged, the pick and why each other lost;
   - `Replaces:` the rule or decision it replaces, or `none`;
   - `Rule home:` the file that holds the resulting rule;
   - `Gate:` `app_wide=no` for agent-initiated work, or `matches_request=yes` for owner-requested work.
7. Write only the resulting rule, undated, in its rule home, and delete the wording it replaces.
8. Update the surface's atlas mockup ([mockup-hub](../mockup-hub/SKILL.md)).
