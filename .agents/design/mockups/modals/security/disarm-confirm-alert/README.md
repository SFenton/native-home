# Disarm the Security System? (alert)
> **What:** the system alert that always precedes Disarm: red Disarm, Cancel kept. **Read when:** you change the alarm card's Disarm behaviour or any confirmation of a hard-to-undo action.
- Mockup: [disarm-confirm-alert.html](disarm-confirm-alert.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Security/SecuritySystemSheet.swift` (AlarmPanel `.alert`), `HassCore/Config/SecurityConfig.swift`, `SecurityScreen.swift` · Spec: `.agents/pages/security/ios.md`, `spec.md` · Patterns: modal-sheet, optimistic-actions
- States covered: default (over the sheet, Home behind), from-security, on-page (the card on the Security page, no sheet), triggered, ax5 (stacked buttons); dark and light side by side in the gallery
- Motion: system alert scale and fade; on confirm the card shows Disarmed at once and cross-fades (state 0.6 s). Transitions: Disarm tap, Cancel
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape
- Open notes: an alert has no loading, error, offline or detent states (explained in the mockup's notes); on the page the alert is always dark; the system chooses the button order
