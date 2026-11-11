# Apple platform

> **What:** Swift architecture and runtime invariants. **Read when:** writing any Swift.

| File | Holds |
|---|---|
| [architecture.md](architecture.md) | Package layout and shared components |
| [auth.md](auth.md) | Sign-in flow, token storage and refresh |
| [connection-lifecycle.md](connection-lifecycle.md) | Websocket, backgrounding, snapshot cache, in-place updates |
| [build-and-run.md](build-and-run.md) | XcodeGen, SwiftPM tests, simulators |
| [swiftui.md](swiftui.md) | Rules for the SwiftUI that remains, and where they override the `swiftui-pro` skill |
| [capacity.md](capacity.md) | Machine-wide simulator, device and build slots (`tools/devcap.py`) |
| [app-name.md](app-name.md) | The public name "S+H", its spoken name, search keywords, Spotlight pages and App Shortcuts |
| [location.md](location.md) | Location and device sensors through `mobile_app` |
| [live-activities.md](live-activities.md) | Live Activities spec: the Home activity, the S+H Home Integration job engine, push-to-start and update tokens; §0 holds Phase 1's verified facts and device checks |
| [live-activities-ha-automations.md](live-activities-ha-automations.md) | The Home Assistant automations Phase 1 applied (2026-10-17, retiring): start, update, end and the activity's buttons |
| [live-activities-per-job.md](live-activities-per-job.md) | Live Activities v2: one activity per job and per device problem, wire contract v2, the `fenton_home` engine, stop and cancel flows, slots, views, lanes |
