# Home Assistant companion app

> **What:** the official Home Assistant iOS app built from source onto our simulators, for side-by-side comparison of pages and modals. **Read when:** checking a native page against how Home Assistant's own app presents the same entities.

- It is not on the App Store for simulators, so `tools/ha_companion.sh build` builds `home-assistant/iOS` `main` into `~/repos/home-assistant-iOS-upstream`, and `tools/ha_companion.sh install [--boot] <simulator>…` installs and launches it (bundle `io.robbie.HomeAssistant.dev`, shown as "Home Assistant Δ"). First built 2026-10-13 at `ae71c80`.
- Never build in `~/repos/home-assistant-iOS`: that is the owner's own checkout with local changes, and the case-insensitive disk also matches `-ios`.
- Signing: ad-hoc (`CODE_SIGN_IDENTITY=-`), not `CODE_SIGNING_ALLOWED=NO`. An unsigned build has no app-group entitlement and traps at launch.
- Pre-build the repo's `Tools/build_tool` packages (the script does). Inside xcodebuild the SwiftGen phase stalled for 25 minutes fetching SwiftLint.
- The repo uses Swift packages only; no CocoaPods or `bundle install` is needed (its Gemfile needs Ruby 3.2+ and only serves fastlane).
- Runtimes: iOS 27.1 runs only iPhone Duo; iPhone 17 Pro needs iOS 27.0.
- Sign-in is the owner's, once per simulator, in the app. Agents never type the password into it.
- Installed so far: `iPhone 17 Pro (Audit)`. Install on the Duo and iPad simulators through the shared simulator-capacity tool once it lands; until then each thread may install it on its own simulator.
- Compare with its default dashboard and entity more-info dialogs; it is a WebView of the Home Assistant frontend, so it shows Home Assistant's own behavior, not our React dashboard's.
