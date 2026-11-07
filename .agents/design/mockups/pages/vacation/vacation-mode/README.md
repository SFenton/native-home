# Vacation Mode (page)

> **What:** Settings > Vacation > Vacation Mode: the mode card, checklist or dates, solo trip status. **Read when:** you change the vacation page, its sheet or alert.

- Mockup: [vacation-mode.html](vacation-mode.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Vacation/VacationModeScreen.swift`, `VacationComponents.swift`, `HassCore/HouseholdAway/VacationModeController.swift`
- Spec: `.agents/pages/vacation/spec.md`, `ios.md`, `.agents/patterns/schedule-date-fields.md` · Patterns: schedule-date-fields, module-list, info-box
- States covered: default (2 of 5), checklist complete, blocked enable (error), pending sheet, on, invalid range, Solo Trip engaged and needs attention, unavailable, turn-off alert, offline, reconnecting, AX5.
- Motion: mode card tint cross-fade, checklist check (quick); sheet and alert transitions.
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape.
- Open note: Solo Trip engaged repeats the title and notice title; the checklist-to-dates swap is not animated (candidates).
- Rollout M (2026-10-28): the mode card is an action tile (text, one `power` disc; green, blue when Pending); off opens the dates sheet, on asks the alert; ids `vacation.modeCard` (+ `.confirm`/`.cancel`).
