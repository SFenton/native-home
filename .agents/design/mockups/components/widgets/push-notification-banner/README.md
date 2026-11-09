# S+H push notification banner, system UI with actions (component)

> **What:** what the app puts in a notification: copy, attachment, up to four buttons, thread and interruption level. **Read when:** you change the notification service extension, push payloads, categories or attachments.

- Mockup: [push-notification-banner.html](push-notification-banner.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Apps/NotificationService/NotificationService.swift`, `apple/Sources/HassUI/App/Push/PushCoordinator.swift`, `apple/Apps/iOS/PushPreview.swift`, `HassCore/Push/PushPayload.swift`, `PushCategory.swift` · Spec: `.agents/platforms/apple/push.md` · Patterns: none
- States covered: default (title, subtitle, body), camera, actions, timeSensitive, threads, ax5
- Motion: clear_notification removal (system)
- Devices: iPhone, iPhone Duo folded (system UI)
- Open notes:
  - System-drawn: layouts approximate iOS; content is from tools/push_fixtures.
  - The camera thumbnail did not show on the iOS 27.0 simulator preview (push.md); unconfirmed on a device.
- Helper: `components/live-activity/_widgets-liveactivity.js` (Live Activity, island, small family, notification and Watch stand-ins; promote to kit).
