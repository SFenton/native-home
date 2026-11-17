# Flows

> **What:** every flow mockup, by area, generated from [catalog.json](../catalog.json). **Read when:** you need to see how a flow looks today, or to find the mockup to update. Sequences across screens: launch, sign-in, navigation, offline.

## shell (13)

| Mockup | Id | Status | Surfaces | Relations |
|---|---|---|---|---|
| [Cold launch, signed in (snapshot, no intro)](launch-cold-signed-in/launch-cold-signed-in.html) | `launch-cold-signed-in` | shipped | iphone, duo, ipad |  |
| [Cold launch, signed out (intro)](launch-cold-signed-out/launch-cold-signed-out.html) | `launch-cold-signed-out` | shipped | iphone, duo, ipad |  |
| [Flyout navigation (iPad, unfolded Duo, iPhone menu button)](flyout-navigation/flyout-navigation.html) | `flyout-navigation` | shipped | iphone, duo, ipad |  |
| [Notification, Spotlight and Live Activity deep links](notification-deep-link/notification-deep-link.html) | `notification-deep-link` | shipped | iphone, duo, ipad |  |
| [Offline and reconnect](offline-reconnect/offline-reconnect.html) | `offline-reconnect` | shipped | iphone, duo, ipad |  |
| [Push and pop within a section stack](push-pop-navigation/push-pop-navigation.html) | `push-pop-navigation` | shipped | iphone, duo, ipad |  |
| [Quick Links to a page (sheet closes, then push)](quick-links-to-page/quick-links-to-page.html) | `quick-links-to-page` | shipped | iphone, duo, ipad | opens `quick-links` |
| [Session expired, welcome back sign-in](session-expired-welcome-back/session-expired-welcome-back.html) | `session-expired-welcome-back` | shipped | iphone, duo, ipad |  |
| [Sheet presentation, detents and dismissal](sheet-presentation/sheet-presentation.html) | `sheet-presentation` | shipped | iphone, duo, ipad |  |
| [Sign out (Account sheet or Home Assistant settings)](sign-out/sign-out.html) | `sign-out` | shipped | iphone, duo, ipad | opens `sign-out-alert`, `ha-sign-out-dialog`, `sign-out-failed-alert` |
| [Sign-in to Home arrival](sign-in-to-home-arrival/sign-in-to-home-arrival.html) | `sign-in-to-home-arrival` | shipped | iphone, duo, ipad |  |
| [Tab navigation (tab bar, re-tap, badge)](tab-navigation/tab-navigation.html) | `tab-navigation` | shipped | iphone, duo, ipad |  |
| [Zoom transition (designed, not wired)](zoom-transition/zoom-transition.html) | `zoom-transition` | designed-not-wired | iphone, duo, ipad |  |

Open any file in a browser (`python3 -m http.server --directory .agents/design/mockups`). How to author or update one: [_kit/AUTHORING.md](../_kit/AUTHORING.md).
