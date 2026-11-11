---
name: fix-reported-issue
description: Orders the work for one reported bug or feature, from pinning intent through precedent, reproduction, blast radius and tests. Use when starting any reported issue, before editing code.
---
# Fix a reported issue

> **What:** the order of work for one request from the request repo, whoever works it. **Read when:** starting any reported bug or feature, before editing code.

1. **Pin the owner's intent.** Quote their words (issue body, media, comments; the newest owner comment wins). Write one sentence: what they see when it is done. When two readings lead to visibly different designs, use [design-decision](../design-decision/SKILL.md).
2. **Find the precedent before the fix,** in this order:
   1. `python3 tools/jev_hints.py preread --title "..." --body-file task.md` ranks likely patterns and files: a guess to verify ([jev](../../workflow/jev.md)).
   2. Rung 0: custom machinery needs the system-API note ([change-loop](../../workflow/change-loop.md#rung-0), [system-api-audit](../../design/apple/system-api-audit.md)).
   3. The registered [pattern](../../patterns/README.md), then the same behaviour elsewhere in the app, then the web dashboard, then the HIG with the section cited.
   Fix the canonical component, never only the reported screen.
3. **Reproduce** on the reported device family; the issue's diagnostics give device, window size, text size and server version. Use a unit test, a hosted render, or the app on a simulator against the live server (`tools/ios_uitest.sh --env shell`).
   - Pick the instrument by the class of the report, cheapest first: a log or unit test for state and logic, a trace or log with timestamps for timing and ordering, a screenshot or recording for look and motion.
   - A server-side cause is fixed on the server with `tools/ha_change.py` ([ha-operations](../../platforms/apple/ha-operations.md)), not patched around in the app.
4. **Sweep the blast radius.** Check every consumer of the changed behaviour on iPhone, iPhone Duo and iPad; fix it or say why it is out of scope.
5. **Test the behaviour shift.** Unit tests for logic; a UX journey and an accessibility audit on each affected device family ([testing](../../testing/apple/README.md)).
6. **Record a rule only when one changed.** Apply the scope test ([docs-conventions](../../workflow/docs-conventions.md#scope-test)); a broad change rewrites the rule in its pattern, page or control doc. Everything else goes in the pull request description.
7. **Land** with the [land-pr](../land-pr/SKILL.md) skill.
8. **Report** in the issue: cause or approach first, then what changed, the tests and the screenshots per device. Reference the request with `Request: the private request repo's #N`; the runner closes it after the merge.
