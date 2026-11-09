# App icon badge

> **What:** the home-screen icon's badge shows the same number as the Profile button's attention badge. **Read when:** touching the badge, `ShellAttention`, or push payload `aps.badge`.

Owner request (2026-10-20).

## The number

`ShellAttention.count(store:viewerUserId:)` (`HassUI/App/Push/AppIconBadgeSync.swift`): the viewer's overdue chores plus expired food (`ProfileSummary.counts(...).attention`); 0 until the viewer is a known resident. `ShellHeaderButtons` passes the same value to `ProfileButton`.

## While the app runs

- `MainTabView` has a `.task(id:)` keyed on the count and the setting; it calls `AppIconBadgeSync.shared.update(count:)`, which calls `UNUserNotificationCenter.setBadgeCount(_:)` (iOS 16+) and skips repeats.
- Authorization already includes `.badge` (`SystemPushPlatform`).
- `AppSession.signOut` calls `AppIconBadgeSync.shared.clear()` (badge 0).
- Settings -> Appearance -> "Show count on app icon" (`showAppIconBadge`, default on). Off sets the badge to 0.

## While the app is closed

Nothing in the app recomputes the count while it is closed: it is derived from live entity states over the websocket, and no background task connects to Home Assistant. The icon keeps the last value the app set. No `BGAppRefreshTask` was added: iOS runs it rarely and unpredictably, and it would need a headless sign-in and websocket connection for a number that could still be hours stale.

What keeps it current: S+H Home Integration (`SFenton/ha-fenton-push` PR #8) puts the count in `aps.badge` on every alert push to a resident's device (overdue chores plus locally expired food, food held in Vacation Mode), computed on the server from the same entities as `ProfileSummary`; iOS applies it with no app code. The badge therefore refreshes whenever a push arrives, not on a timer. An automation's own `data.push.badge` wins. Caveat: a server-set badge ignores the in-app toggle until the app next opens. Deploy status: see the PR.

## Testing

`HassUITests/AppIconBadgeSyncTests` (injected setter).
