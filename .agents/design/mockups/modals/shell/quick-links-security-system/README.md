# Quick Links: Security System (modal)

> **What:** the alarm card pushed inside Quick Links (SecurityControls), or the state alone without a connection. **Read when:** you change the Quick Links security detail or the shared alarm card.

- Mockup: [quick-links-security-system.html](quick-links-security-system.html) · shipped · reviewed 2026-10-23 (author draft; skill reviewers replace it)
- Source: `apple/Sources/HassUI/` Features/Rooms/QuickLinksSheet.swift; Features/Security/SecuritySystemSheet.swift; HassCore/Config/SecurityConfig.swift
- Spec: .agents/pages/security/spec.md, ios.md, rooms/ios.md · Patterns: modal-sheet, optimistic-actions
- States covered: default, loading (arming), error (unavailable), offline, disarmed, armed-away/night, triggered, state-only, disarm-confirm, medium/large/fitted (large only), ax5; dark and light
- Motion: mode select; transitions: push in, disarm alert
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape
- Open notes:
  - Same card and alert as modals/security/security-system-sheet.
  - Back only, no Close (see quick-links).
- Shared helper: `pages/rooms/_rooms.js` (rooms batch; list of kit promotions in its header).
- Rollout L (2026-10-28): the Quick Links tile that opens this card carries the Arm Home / Disarm disc; the mode buttons here are unchanged.
