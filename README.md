# S+H

**S+H**: native iOS, iPadOS and watchOS apps for a Home Assistant house, modeled on the React dashboard in [`SFenton/ha-sfenton-react-dash`](https://github.com/SFenton/ha-sfenton-react-dash). Built with UIKit on top of [HAKit](https://github.com/home-assistant/HAKit); SwiftUI only where Apple requires it (widgets, Live Activities and watchOS).

**Status:** scaffold. Sign-in, the websocket connection, the cached entity store and the Home screen exist; other tabs are placeholders.

## Build

Requires Xcode 27.1+ (iPhone Duo SDK) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd apple
swift test                 # HassCore and HassDesign unit tests (runs on the Mac host only as a test runner; macOS is not a supported app platform)
xcodegen generate          # writes FentonHome.xcodeproj
open FentonHome.xcodeproj  # run the FentonHome scheme on an iPhone or iPad simulator
```

Gates: `tools/apple_coverage.sh` (95% logic line coverage on the Mac host; UX is not measured) and `tools/ios_uitest.sh --env shell` (journeys and accessibility audits on iPhone, iPhone Duo and iPad).

## Setup

Run `tools/setup.sh` once per checkout. It installs the tracked git hooks (`core.hooksPath` = `.githooks`: the pre-push hook: the house-denylist check, see [house-data-gate](.agents/workflow/house-data-gate.md#pre-push-hook-owner-2026-11-07)) and reports whether a denylist was found (counts only).

## Where to start

- [Agent entry point and invariants](AGENTS.md)
- [Knowledge router](.agents/README.md)
- [Plan, lanes and progress](PROGRESS.md)
