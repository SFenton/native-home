# Tap feedback

> **What:** the one haptic vocabulary and the failure feedback built on it. **Read when:** a control changes the house, plays or should play a haptic, or reports a failed call.

Owner decision 2026-10-24 (proposal `feedback-haptics`, option A). HIG: [Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics) (confirm an action, one feel for like controls).

- **Component:** `HassDesign/TapFeedback.swift`. `TapFeedback` names the four patterns; `TapCounter` is the trigger a control bumps from its action; `View.tapFeedback(_:trigger:)` is the one wrapper around `sensoryFeedback`, so a control never calls `sensoryFeedback` for a tap itself. `View.failureFeedback(_:)` plays `.error` when a flag turns true.
- **The four patterns.**

| Pattern | Plays | Where |
|---|---|---|
| `TapFeedback.tap` (`.impact(weight: .light)`) | on the tap itself | toggle, command and choice tiles (`GlassTile`), alarm modes, remote keys (`RemoteIconButton`, `PowerButton`), fan rail buttons, vacuum actions and Locate, camera Snapshot, Sound and Record, chore check-off |
| `TapFeedback.step` (`.selection`) | each detent | the dial, `BrightnessTile`, the 5% `PercentSliderRow` |
| `TapFeedback.failure` (`.error`) | when a call fails or an answer is refused | failed tile face, `FailureCaption`, `failureAnnouncement`, a refused password, a chore rollback, a snapshot that did not save |
| `TapFeedback.confirmation` (`.success`) | when input is read | a barcode or date read in `ScanItemSheet`; the build text copied by Settings → About → Version |

- **Rules.** No heavier impact for a lock, garage door or alarm: the family carries meaning, never the weight. The tap plays on the tap, not when Home Assistant confirms; there is no late success haptic, because a slow device would buzz seconds after the finger left. A tile that opens a page plays nothing. Haptics never carry information alone: colour, text and the VoiceOver announcement stay. iOS has no per-app switch; the system silences `sensoryFeedback` with System Haptics off and on hardware without a Taptic Engine, so there is no in-app setting.
- **Adding a control.** Own a `@State private var taps = TapCounter()`, call `taps.tap()` in the action, add `.tapFeedback(trigger: taps.count)` to the control. For a list that shares one action across rows, put the counter in the row, not the section (one trigger per row would fire every row at once).
- **Failure.** See [optimistic-actions](optimistic-actions.md), Failure: `announceFailure(_:)` (HassDesign/TransientFailure.swift) is the one function that posts the VoiceOver notice; when a shared `Announcer` lands it replaces the body.
- **Tests:** `Tests/HassDesignTests/TapFeedbackTests.swift` (the vocabulary, the counter, `playsTapFeedback`, `TransientFailure`), `Tests/HassUITests/FailureFeedbackTests.swift` (copy, scan haptics, failed faces, and hosted accessibility flows that tap a failing lock, guest toggle and alarm mode).

## Guards

Checked by `python3 tools/pattern_guard.py` against `contracts/patterns.json` (comment lines are ignored).

- `tap-feedback/no-uikit-haptics`: Haptics go through TapFeedback / tapFeedback(_:trigger:), never a UIKit feedback generator (tap-feedback). Scans `**/*.swift`.
- **UIKit counterpart.** `UKTapFeedback` in `UIKitPort/Design/UKDesignSupport.swift` is the one UIKit haptic helper and the only file allowed a feedback generator; everything else in the port calls it.
- `tap-feedback/literal-sensory-feedback`: Name the haptic with a TapFeedback constant (TapFeedback.step), not a literal feedback (tap-feedback). Scans `**/*.swift`.

### Known debt

Each file below still breaks its guard and is allowed until it is fixed; remove the row and the registry `debt` entry together.

| File | Guard | What to do |
|---|---|---|
| `apple/Sources/HassUI/UIKitPort/App/Login/UKLoginViewController.swift` | `tap-feedback/no-uikit-haptics` | creates its own feedback generator; call `UKTapFeedback` instead |
| `apple/Sources/HassUI/UIKitPort/Design/UKClimateThermostatDial.swift` | `tap-feedback/no-uikit-haptics` | creates its own feedback generator; call `UKTapFeedback` instead |
| `apple/Sources/HassUI/UIKitPort/Design/UKPercentSliderRow.swift` | `tap-feedback/no-uikit-haptics` | creates its own feedback generator; call `UKTapFeedback` instead |
| `apple/Sources/HassUI/UIKitPort/Design/UKStateMessage.swift` | `tap-feedback/no-uikit-haptics` | creates its own feedback generator; call `UKTapFeedback` instead |
| `apple/Sources/HassUI/UIKitPort/Design/UKThermostatDial.swift` | `tap-feedback/no-uikit-haptics` | creates its own feedback generator; call `UKTapFeedback` instead |
