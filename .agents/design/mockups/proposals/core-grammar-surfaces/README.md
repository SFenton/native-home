# Core grammar surfaces (proposal)
> **What:** the generic authored controls that replace the family composites, with the owner's answers to three questions. **Read when:** you need the reasons behind a bound choice, toggle line, slider, `ask`, `enabledWhen` or the pending arc.
- Mockup: [core-grammar-surfaces.html](core-grammar-surfaces.html) · status decided · decision: the core-grammar-surfaces owner-picks record in `.agents/decisions/`
- Source: `apple/Sources/HassUI/UIKitPort/ServerUI/UKServerUIShellPrimitives.swift`, `UKServerUIControlBinding.swift`, `apple/Sources/HassCore/ServerUIComposition/ServerUIBoundControl.swift` · Spec: `.agents/design/core-grammar-surfaces.md`, `.agents/design/pending-controls.md` · Patterns: rows, option-picker, alerts, optimistic-actions, settings-section
- Picked: a disabled reason on the control's own status line; chips as the wrapping grid; while Home Assistant answers, the optimistic value, then the arc after an optimism timeout until a change, with per-control settings
- Rejected: a group footer for the reason; the scrolling rail and the joined segments; for pending, the held value, the arc alone and both
- States covered: the surfaces as they ship, unavailable, the slider film, `ask`, the pending sequence on a row, a tile and a script button, Reduce Motion, Accessibility 5, every rejected option
- Sections: the pending phases and defaults with their sources, the Studio panel sketch
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape
- Open notes: drawn from the kit, no device capture; not built (lane L0)
