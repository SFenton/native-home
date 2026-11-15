# Layout recovery boundary (page)

> **What:** what the server-driven root shows while no published layout is on screen: waiting, nothing published, update required, or unavailable. **Read when:** you touch `UKServerUIRecoveryBoundary.swift`, the host's `showStatus`, or the boundary copy.

- Mockup: [server-ui-boundary.html](server-ui-boundary.html) · shipped
- Source: `apple/Sources/HassUI/UIKitPort/ServerUI/UKServerUIRecoveryBoundary.swift`, `apple/Sources/HassUI/UIKitPort/ServerUI/UKServerUIProductionHost.swift`, `apple/Sources/HassUI/UIKitPort/Design/UKStateMessage.swift`
- Spec: `.agents/design/server-ui-boundary.md` · Patterns: state-message, copy, alerts, hinge-avoidance
- States covered: default (waiting), empty (nothing published), update, error, error-no-actions, clear-alert, sign-out-alert, sign-out-failed, ax5
- Motion: none; a change of state swaps the view
- Devices: iPhone, folded Duo, unfolded Duo (portrait, landscape), iPad (portrait, landscape)
- Open notes: the page draws today's strings. The review lists five fixes; the reworded set is the proposal `proposals/server-ui-boundary-copy`. No device capture exists.
