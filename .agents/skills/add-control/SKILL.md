---
name: add-control
description: Procedure for adding a reusable control to HassDesign, with a rung-0 system API check, states, accessibility and tests. Use when a control will appear on more than one screen.
---
# Add a control

> **What:** procedure for a reusable control. **Read when:** a control will be used on more than one screen.

0. **Rung 0.** If the control needs custom scroll, blur, mask, material, list, header, sheet, paging or layout machinery, name the system API on iOS 17, 18 and 26, an Apple sample or OSS precedent, and why it is not enough, with a measurement if the reason is performance ([change-loop](../../workflow/change-loop.md#rung-0-system-api-first)). Prefer a system control with a style or modifier over a new view.
1. Check [patterns](../../patterns/README.md) first; extend an existing component if one fits.
2. Specify states (on, off, pending, unavailable), accessibility (label, value, traits, actions) and the service it calls.
3. Implement in `HassDesign` (pure UI) taking values and closures, never an `EntityStore`.
4. Add a pattern doc row and unit tests for any state mapping.
