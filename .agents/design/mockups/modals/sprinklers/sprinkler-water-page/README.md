# Water a zone now (pushed) (modal)

> **What:** the pushed Water Now page: Run Time stepper and Start Watering. **Read when:** you change the zone watering flow.

- Mockup: [sprinkler-water-page.html](sprinkler-water-page.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Sprinklers/SprinklersScreen.swift`, `SprinklerControllerSheet.swift`, `apple/Sources/HassCore/Sprinklers/SprinklerFormat.swift`
- Spec: `.agents/pages/sprinklers/spec.md`, `ios.md` · Patterns: modal-sheet, optimistic-actions
- States covered: default, another zone running, mode off, unavailable zone, sending (loading), error, offline, 60 min, closed, AX5; dark and light.
- Motion: none of its own; system push and pop.
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape.
- Open note: Review fix candidate: Start Watering has no in-button arc while sending.
