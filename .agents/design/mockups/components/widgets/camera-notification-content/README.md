# Camera notification expanded view (component)

> **What:** the black 16:9 view in an expanded camera notification: snapshot, spinner, red Live badge. **Read when:** you change the NotificationContent extension or the live camera path.

- Mockup: [camera-notification-content.html](camera-notification-content.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Apps/NotificationContent/NotificationViewController.swift` · Spec: `.agents/platforms/apple/push.md` · Patterns: none
- States covered: default (live, with button), loading, snapshot, live, failed, buttons, ax5
- Motion: snapshot to live (no app animation)
- Devices: iPhone, iPhone Duo folded
- Open notes:
  - Live video never started on the owner's device (push.md 2026-10-15); Live is drawn from code, unconfirmed.
  - Failure is silent in release builds (review: fix).
- Helper: `components/live-activity/_widgets-liveactivity.js` (Live Activity, island, small family, notification and Watch stand-ins; promote to kit).
