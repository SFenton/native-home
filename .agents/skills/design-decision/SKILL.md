---
name: design-decision
description: Decides design questions the owner has not settled, using owner choice, HIG, then web parity, and routes visible choices to build-n-and-judge (propose-first). Use when a choice changes navigation, presentation or a shared pattern.
---
# Design decision

> **What:** how agents decide a design question the owner hasn't. **Read when:** a choice changes navigation, presentation or a shared pattern. Visible choices go through [propose-first](../../workflow/propose-first.md) before any code.

1. Check the HIG (`apple-hig` skill) and the web behavior.
2. Precedence: owner's explicit choice > HIG > web parity > convenience.
3. If the answer is owner-visible and the precedence above does not settle it, build up to 3 options, capture screenshots and behaviour on the affected families, judge them from that evidence and record the pick as `Decision: <date>, judged Option A, B and C; picked B, because ...` in `.agents/design/<topic>.md` ([propose-first](../../workflow/propose-first.md), owner 2026-11-03). Run the app-UI gate first (`tools/jev_gate.py`): on `gate: park` (a broad app-wide change the owner did not request) do not pick; record `Gate: app_wide=no` or `Gate: matches_request=yes` with the decision.
4. Decide yourself only what the owner's choice, a registered pattern or the HIG already settles, or details inside the option they picked. Record the rule and its reason in the owning doc, and tell the owner in the thread or PR so they can override.
