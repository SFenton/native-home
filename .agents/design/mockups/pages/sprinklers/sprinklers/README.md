# Sprinklers (page)

> **What:** how the Sprinklers page looks today: two B-hyve controller cards. **Read when:** you change the page, its cards or its status pills.

- Mockup: [sprinklers.html](sprinklers.html) · in flight (`claude/section-sides`) · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Sprinklers/SprinklersScreen.swift`, `HassDesign/StatusPill.swift`, `HassDesign/ModuleList.swift`
- Spec: `.agents/pages/sprinklers/spec.md`, `ios.md` · Patterns: module-list, status-pill, dynamic-grid
- States covered: default, idle, watering, battery low, hub unavailable, controller unavailable, fault, loading (= unavailable), refreshing, offline, reconnecting, long text, sheet open, AX5.
- Motion: watering colour, hub tone (state 0.6 s); push, sheet present and dismiss.
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape.
- Open note: No loading UI or empty state exists; the offline-controller state is what a cold launch reads.
- Open note: Helper `pages/sprinklers/_vacation-sprinklers.js` holds fixtures and builders for every sprinklers item (promote to kit: nine symbols, the day picker, the pinned bar).
- Rollout M (2026-10-28): the controller row is a navigation tile (water family, `stop.fill` Stop Watering disc dimmed while idle, chevron) above the status-pill module; ids `sprinklers.controller.<id>` + `.action.stop`.
- In flight (`claude/section-sides`, [section-sides](../../../../section-sides.md)): partly folded Duo, each section wholly on one side (fold columns); state `duo-part-fold`. Every other pose unchanged.
