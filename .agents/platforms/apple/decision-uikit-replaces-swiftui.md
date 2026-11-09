# Decision: the UIKit app replaces the SwiftUI app

> **What:** the owner's decision of 2026-11-01 and what it removed and kept. **Read when:** you find a doc or test that mentions "both apps", `FentonHomeUIKit` or the SwiftUI screens.

**Decision (owner, 2026-11-01):** the UIKit app is the app. `FentonHome` (`com.sfenton.home`, "S+H") is now the UIKit build; the SwiftUI iOS app, the side-by-side `FentonHomeUIKit` target (`com.sfenton.home.uikit`) and the SwiftUI screens in `HassUI` are deleted.

## Why

The UIKit port reached UX parity and was measured against the SwiftUI app for frame rate, memory, CPU and GPU ([uikit-port](uikit-port.md)). Keeping two apps doubled every lane's work and let them drift.

## Removed

- The SwiftUI app shell (`FentonHomeApp`), the `FentonHomeUIKit` app target and its copies of the extensions; the extensions are one set again.
- SwiftUI-only screens, components and hosted tests in `HassUI` and `apple/Apps/iOSTests`.
- `tools/uikit_journeys.sh` (the SwiftUI journeys run against the one app with `tools/ios_uitest.sh`).

## Kept, and why

- `HassCore`, `HassDesign`: shared logic and tokens. HassDesign's SwiftUI views stay because widgets, Live Activities and the Watch app draw with them; Apple requires SwiftUI there.
- `FentonActivityViews`, the widget extension, the notification service and content extensions (the content extension is the UIKit camera view), the Watch app.
- In `HassUI`, the non-UI types the UIKit app calls (routes, `ShellNavigator`, policies, models, configs, fixtures, copy) and static helpers that used to sit in SwiftUI view files.
- `apple/Apps/iOSUITests`: the journeys, retargeted to the UIKit app in a follow-up lane.

## Identity carried over

Bundle ids, app group, Keychain group and the `mobile_app` registration are unchanged ([app-name](app-name.md)). The wifi-info entitlement, `CFBundleSpokenName`, `INAlternativeAppNames`, ATS settings, the `fentonhome` URL scheme and the `FENTON_UITEST_NO_ANIMATIONS` launch hook moved to the UIKit app.

## Upgrade from the SwiftUI app

Installing the UIKit build over the SwiftUI build (same bundle id) launched to a black screen (found 2026-11-02 on the owner's Duo and a long-used simulator; a fresh install was fine). Cause: iOS persists each `UISceneSession` with its configuration, delegate class included. A session the SwiftUI app left behind (backgrounded before termination) reconnects with `SwiftUI.AppSceneDelegate` and never calls `application(_:configurationForConnecting:options:)`; that delegate makes no window here. Rule: the app delegate returns the `Default` configuration with `UKSceneDelegate` for new windows and, on `UIScene.willConnectNotification`, replaces any window scene's delegate that is not a `UKSceneDelegate` (`UKSceneUpgrade.needsAdoption`). `UKSceneDelegate.connect` builds the window once per scene, so UIKit's own `scene(_:willConnectTo:)` and the adoption cannot make two. Reproduce: `main`'s SwiftUI Debug app, launch, background it (open Settings), terminate, install the UIKit app over it, launch.
