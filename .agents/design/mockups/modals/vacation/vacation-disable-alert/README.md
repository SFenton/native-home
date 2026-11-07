# Turn Off Vacation Mode? (alert) (modal)

> **What:** the confirm alert shown when an engaged Vacation Mode card is tapped. **Read when:** you change the turn-off flow or alert copy.

- Mockup: [vacation-disable-alert.html](vacation-disable-alert.html) · shipped · reviewed 2026-10-23 (author self-check; skill reviewers replace it)
- Source: `apple/Sources/HassUI/Features/Vacation/VacationModeScreen.swift`, `HassCore/Config/VacationConfig.swift`
- Spec: `.agents/pages/vacation/ios.md` · Patterns: optimistic-actions
- States covered: default, offline, AX5 (stacked buttons), closed. Dark only (presented from the always-dark page; derived).
- Motion: system alert fade; the card cross-fade after Turn Off.
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape.
- Open note: Shipped title is longer than the catalog title; the code is drawn.
- Open note: Alert appearance is derived, not seen on a device.
- Rollout M (2026-10-28): the alert is the Vacation Mode action tile's confirmation (tile or disc); button ids are now `vacation.modeCard.confirm` / `.cancel`.
