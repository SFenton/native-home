# Sprinkler controller card (component)

> **What:** one controller as a module card: low battery alert, row, four status pills. **Read when:** you change the card or its pills.

- Mockup: [sprinkler-controller-card.html](sprinkler-controller-card.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Sprinklers/SprinklersScreen.swift`, `HassDesign/StatusPill.swift`
- Spec: `.agents/pages/sprinklers/ios.md` · Patterns: status-pill, module-list
- States covered: idle, watering, battery low, hub unavailable, unavailable, fault, unknown and no-history strings, in context.
- Motion: none of its own (pill tone cross-fade only).
- Devices: iPhone and iPad size classes; page surface only.
- Open note: Registered locally as SprinklerControllerCard; not in the kit list.
- Rollout M (2026-10-28): the controller row is a navigation tile with a Stop Watering disc and chevron above the status-pill module; ids `sprinklers.controller.<id>` + `.action.stop`.
