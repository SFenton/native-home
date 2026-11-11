# Build and run

> **What:** how to build, test and run the Apple apps. **Read when:** building or testing.

```bash
cd apple
swift test                  # Core, Design and hosted UI tests on the Mac host (test runner only; macOS is not a supported platform, so never build or run the app for Mac)
xcodegen generate           # regenerates FentonHome.xcodeproj from project.yml (the project file is git-ignored)
xcodebuild -project FentonHome.xcodeproj -scheme FentonHome -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

## Physical device

```bash
xcodebuild -project FentonHome.xcodeproj -scheme FentonHome -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/fh-dd -allowProvisioningUpdates build
xcrun devicectl device install app --device <UDID> /tmp/fh-dd/Build/Products/Release-iphoneos/FentonHome.app
xcrun devicectl device process launch --device <UDID> --terminate-existing com.sfenton.home
```

- Signing team `3Q9X8JX23S` lives in `project.yml`; never set it only in Xcode, because `xcodegen generate` discards it.
- Target the phone by UDID, not name: a simulator can share the name (for example "iPhone 18 Pro").
- If `devicectl list devices` leaves a wired, paired phone at `connecting` and device commands hang, CoreDeviceService is wedged; quit Xcode (or `kill` your user's `CoreDeviceService` PID) and it relaunches on demand.

## Notes

- Coverage gate: `tools/apple_coverage.sh` (95% logic, Mac host only; UX line coverage is not measured, owner 2026-11-10). Device journeys: `tools/ios_uitest.sh` ([devices](../../testing/apple/devices.md)).
- iPhone Duo APIs (`onHingeChange`, vertical bar) need the iOS 27.1 SDK; builds with an older SDK must add `FENTON_IOS_SDK_BEFORE_27_1` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS`.
- Boot, drive and build only inside a `tools/devcap.py` hold, which waits for machine-wide capacity ([capacity](capacity.md)); never reset another project's devices. Slim what you boot with `tools/sim_slim.sh UDID` inside the hold ([slim simulators](capacity.md#slim-simulators)).
- Keep the `UILaunchScreen` key and the `LaunchBackground` color asset, or older runtimes fall back to legacy compatibility frames (FestivalNativeApps finding).
