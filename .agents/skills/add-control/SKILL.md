---
name: add-control
description: Adds a reusable control with a system-API check, states, accessibility and tests. Use when a control will appear on more than one screen.
---
# Add a control

> **What:** procedure for a reusable control. **Read when:** a control will be used on more than one screen.

1. **Rung 0.** Prefer a system control with a style or modifier over a new view. Custom machinery needs the rung-0 note first ([change-loop](../../workflow/change-loop.md#rung-0)).
2. Check [patterns](../../patterns/README.md); extend an existing component when one fits.
3. Specify the states (on, off, pending, unavailable), the accessibility (label, value, traits, actions) and the service it calls.
4. Implement it as pure UI that takes values and closures, never an `EntityStore`: under `HassUI/UIKitPort/Design/` for app screens ([controls](../../platforms/apple/uikit-port-design-controls.md)), in `HassDesign` for widgets, Live Activities and the Watch app.
5. Add the pattern doc row and unit tests for any state mapping.
