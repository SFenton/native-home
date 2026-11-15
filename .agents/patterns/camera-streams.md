# Camera streams

> **What:** how live camera video is shared, started, stopped and brought back. **Read when:** touching `CameraStreamPool`, `CameraLiveModel`, a camera tile or the viewer, or anything that asks Home Assistant for a stream.

- **One stream per camera.** `CameraStreamPool` owns one `CameraLiveModel` per camera; every tile and the viewer show it. Once shown it is retained for the session (`CameraStreamRetention`); a stream that fails every mode drops its retention. Views call `pool.appear` / `pool.disappear` and never start a stream themselves.
- **A stream no view shows is paused after 4 s.** Retention keeps a shown stream running so Home, Security and the viewer share it instantly, but a page with no camera must not keep all four decoding.
  `CameraStreamPool.disappear` schedules `pauseAfterHidden` (4 s, long enough that a tab switch between pages that both show the camera never pauses it).
  When it fires with no viewers the session releases the camera (`CameraStreamRetention.release`) and `CameraLiveModel.pause()` keeps the last live frame (`pausedFrame`) on the tile's snapshot layer.
  A view showing the camera again cancels the pause or restarts the stream (`appear`); the last frame stays up until the first new one.
  Tests: `CameraStreamPoolTests`, `CameraStreamTests` (`release`).
- **Video draws only while on screen.** `RTCMTLVideoView` draws on the main thread, and `CAMetalLayer.nextDrawable` blocks there when the layer is clipped away or mid-rotation.
  Every video surface is a `LiveVideoSurface` (`UKCameraLiveView` in UIKit) that removes itself from the track and sets `RTCMTLVideoView.isEnabled = false` unless `OnScreenMonitor` says it is on screen:
  in a window of a foreground-active scene, nothing hidden or transparent up the chain, inside the viewport of every clipping ancestor and scroll view, and no window size change in the last 450 ms (rotation, fold).
  `UKCameraLiveView` reports presence to the pool from the monitor, so a tile below the fold lets its stream pause after 4 s.
- **Modes.** WebRTC through go2rtc (`auth/sign_path` then `/api/webrtc/ws`), then HLS (`camera/stream`), then the snapshot. Each mode has a first-frame timeout. The viewer's pill says `Live` in either mode (VoiceOver's value still says "a few seconds behind" for HLS). A stream that fell back to HLS goes back to WebRTC by itself (next bullet).
- **A stream on HLS upgrades to WebRTC in the background.** HLS is a fallback that runs seconds behind; WebRTC usually missed its 10 s budget only because the network was still settling after the app returned.
  Once HLS shows its first frame, `CameraLiveModel` waits `defaultUpgradeDelays` (15, 45 and 120 s, one attempt each, then HLS stays) and opens a second WebRTC session out of sight (`candidatePeer`).
  On its first decoded frame `promoteCandidate()` tears HLS down, hands the peer to the views and calls `CameraStreamState.upgrade(to:)`, so the phase stays live throughout: no snapshot, no re-fade, and the watchdog restarts on the new source.
  A failed or timed-out attempt is dropped and the next delay follows. `stop()`, `suspend()`, a stall, a restart and every mode change cancel the pending or open attempt, so a camera nobody shows never upgrades.
  Tests: `CameraUpgradeTests`, `CameraStreamStateTests`.
- **Never blank, never re-fade.** The snapshot (`CameraSnapshotView`) is drawn over the player whenever the phase is not live, and the player is the only thing that changes. So whatever stops a stream must also move the phase off live (`CameraLiveModel.suspend()` on background); a stopped model that still says live is a black frame that reads "Live".
- **Background and return.** Every stream suspends when the app enters the background; on `willEnterForeground` the pool first makes the websocket answer (`HassConnection.ensureLive`), then starts the wanted streams that are not running; the tiles keep their snapshot until the first frame.
- **Commands for a stream must be bounded.** HAKit drops a command caught by a socket reset without calling its completion, so `await sendCommand` can hang forever. `signPath` and `cameraStreamPath` carry `HassConnection.streamCommandTimeout` (10 s), and a model waits for a connected socket before its first command. Any new "ask Home Assistant, then show it" step needs a timeout the same way.
- **A failed stream retries by itself.** A stream that fails every mode (`onExhausted`) drops its retention, but while a view still shows it and the app is in the foreground the pool retries after 2, 4, 8, 16 and 32 s (`CameraStreamPool.defaultRetryDelays`; web `stream-manager.js` reconnects the same way).
  Attempts reset when the stream goes live, a view appears, the app returns or the socket becomes ready; retries are cancelled in the background and never start behind the connection check.
- **A live stream whose frames stop is restarted (frame-stall watchdog).** Web parity: `public/rtc/stream-manager.js` `FRAME_STALL_MS = 8000` and `FRAME_CHECK_MS = 1000`.
  `CameraLiveModel` runs one watchdog task per live stream, started on the first frame and cancelled by `stop()`, `suspend()` and every mode change; once a second it feeds a frame count to `HassCore.FrameStallDetector` (pure; 8 s without the count advancing).
  WebRTC counts decoded frames in `WebRTCFrameMonitor` (one locked increment on the decoder thread); HLS uses the player's play position.
  On a stall the model tears the stream down, puts the phase back to connecting (the snapshot cross-fades back over the player, the live dot goes, the viewer's pill reads when it was last live) and calls `onStalled`; the pool restarts it through its retry backoff.
  Debug fault injection: `FENTON_CAMERA_FREEZE_ONCE=<go2rtc stream id>` freezes that camera's reported count once per launch.
- **Every surface uses the pool.** Home's tiles, Security's tiles and the viewer all go through `CameraGrid` / `CameraLiveView` / `CameraStreamPool.shared`, keyed by `HomeConfig.Camera.id` (the entity id). There is no second pool, key or config; do not add one. Moving between pages opens one stream per camera (`testSecurityTilesShowTheStreamsHomeAlreadyHas`). `CameraGrid(idPrefix:)` gives Security's tiles `security.camera.<stream>` so journeys can tell the pages apart.
- **Cards are nearly square.** `CameraTile.aspectRatio` is 1 : 0.78 as the web's tile, fill-cropped and centred; the name label starts with one indicator that cross-fades in place (`CameraTile.indicator(for:isOffline:)`, 0.2 s `quick`):
  the red live dot while the stream shows frames, the inline `ArcSpinner` while it connects, and `icloud.slash` when the app has no network or every mode failed.
  VoiceOver reads the tile's value (`Live` / `Snapshot`); the indicator is decorative. The viewer keeps each camera's own `aspectRatio` and fits.
- **Signalling sockets are released with their stream.** Each WebRTC peer owns a `SignallingSocket` with its own ephemeral `URLSession`, invalidated on `cancel()` and on deinit.
  `Camera.signallingSockets` in the `ResourceCensus` counts sockets whose session has not ended; `SignallingSocketTests` and `ResumeCyclesJourneyTests` bound it.
- **Restart rules** (the pool's `startStalled`): when the socket becomes ready again (`HassConnection.didBecomeReadyNotification`) or the app returns, start each wanted stream that is not running or has failed. Streams that are live or still connecting are left alone, so a healthy stream is never rebuilt and launch does not start twice. Nothing starts behind a backgrounded app or ahead of the connection check.
- **Teardown must release what the system keeps.** `tearDownPlayers` empties an HLS `AVPlayer` (`replaceCurrentItem(with: nil)`, video output removed) before dropping it ([resume-lifecycle](resume-lifecycle.md)).
  Each model reports `Camera.players`, `Camera.attempts` and `Camera.observations` and the pool `CameraPool.*` to the `ResourceCensus`; `CameraStreamPoolTests` cycles background and return and requires the set to match the first launch.
- **Tracing.** `CameraTrace` writes the lifecycle to the unified log (`com.sfenton.home`, category `Cameras`) and, in Debug, to the app group's `push-trace.log` ([push](../platforms/apple/push.md), "Debugging on a phone"). Read it first when a camera "does not come back".
- **Tests.** Pool lifecycle, sharing across surfaces and retries with a fake opener: `HassUITests/CameraStreamPoolTests.swift`. Socket checks: `HassCoreTests/HassConnectionLivenessTests.swift`.
  Stall rule: `HassCoreTests/FrameStallDetectorTests`; watchdog and restart: `CameraStreamPoolTests` (Frame stalls). Device journeys: `CameraJourneyTests`; the long ones background the app for 60 s, past `ConnectionLifecycle.backgroundGrace`.
- Web sources: `SFenton/WebRTC` `www/stream-manager.js`, `rtcStreamRetention.ts`. Page notes: [home/ios.md](../pages/home/ios.md). Design: [direction-g.md](../design/direction-g.md), Controls → Cameras.

## Configured composition cameras

Schema 2.0 adds the negotiated `sh.camera-stream@1`, `sh.camera-tile@1`,
`sh.camera-video@1`, `sh.camera-controls@1` and `sh.camera-viewer@1` capabilities;
the frozen first slice stays unchanged. `ServerUICameraDescriptor` carries
literal camera/snapshot entity IDs, the go2rtc stream ID, aspect ratio, explicit
recording support and authored status/permission copy. It never contains a URL,
token, arbitrary service or HouseConfig lookup. Both compilers reject duplicate
camera entity identities and mismatched tile/viewer attachments. A pooled
entity cannot be rebound to a different RTC stream ID during the session.

| Component | Ownership |
|---|---|
| `UKCameraControlStripView` | Value/closure buttons plus a feedback view; shared canonical/SDUI measurement, AX stacking and RTL layout, no store |
| `UKCameraViewerGeometry` | Existing stacked/split video/control geometry, shared by canonical and configured content |
| `UKServerUICameraSource` | Injected context, EntityBoxes, existing pool, recording/snapshot intent lifetimes |
| `UKServerUICameraView` | Keyed tile, video, controls or viewer-content primitive; never a feature controller |

`camera-tile` works inside the existing `tile-grid`; it is not a second camera
grid implementation. It presents an authored modal containing a matching
`camera-video` or `camera-viewer`. The configured viewer requires page width,
full height and dark appearance, using the ordinary native modal path. It
adds **no zoom**. The atlas ID `zoom-transition` is historical, not permission
to add motion. Existing nonconfigured viewer callers retain their own fitted
sheet/conditional-transition policy; extraction does not change it.

Configured controls have 1–3 ordered, unique `snapshot`, `sound`, or `record`
intents. Every control supplies idle/active/busy/failure titles, idle/active/
failure symbols, and an `action` or `danger` tint token. No target, copy, control
order or state glyph is inferred from a page ID. Record requires the descriptor's
`input_boolean.*` state and `script.*` target; the adapter uses the canonical
`script.turn_on` toggle and `OptimisticActions` six-second confirmation overlay.
The actual call stays pinned even if that overlay confirms or expires early.
Sources and control attachments cannot be removed, retargeted, reparented or
changed while an intent or Photos-denied recovery is pending.

Only visible video surfaces acquire pool presence through `OnScreenMonitor`.
Isolated composition hosts may supply `UKCameraReadProvider`: an explicit
camera/RTC/snapshot allowlist over the existing connection and stream pool.
The renderer and reader must receive the same pool. Snapshot reads accept only
the configured entity's same-origin `entity_picture`; no session or arbitrary
service API is exposed. Missing or mismatched readers reject publication
adoption. Recording continues through the separate command caller, including
the rejecting caller in preview.
Controls alone do not start a stream. The pool retains its four-second hidden
pause, last frame, fallback, retry and foreground policy. Configured privacy
opaquely conceals live, paused and still content, mutes audio, disables intents
and releases visible presence. Missing/unavailable entities show authored copy,
not manufactured success. Viewer/control removal mutes shared audio.

Snapshot uses the existing `CameraSnapshotSaver` (live frame, then configured `entity_picture`) and its Photos `.addOnly` authorization at the gesture. Saving disables repeat taps; success settles after two seconds; failure stays visible until another attempt. Denial uses a native `UIAlertController` with authored copy and stays pinned until acknowledged. Tests inject a saver.

### System precedent and design authority

This extracts the existing circle controls and frame measurement; it adds no layout system, RTC client, modal or permission UI.
UIKit owns the alert and the shell owns the single page scroller and modal. Apple HIG:

- [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy): request permission only when the feature needs it; Snapshot keeps the on-intent authorization path.
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout): the strip stacks at accessibility sizes so nothing clips.
- [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode): immersive media viewing may be dark-only; the configured viewer keeps it.
- [Motion](https://developer.apple.com/design/human-interface-guidelines/motion): the full-height, no-zoom path uses existing native motion and Reduce Motion behavior.

The matching synthetic fragments are
`apple/Tests/HassCoreTests/ServerUICameraFixture.json` and Studio's
`tests/fixtures/camera-composition.json`. Focused contracts:
`ServerUICameraCompositionTests` / `composition-camera.test.tsx`; parent-run
hosted regressions: `ServerUICameraIntentTests` and `ServerUICameraJourneyTests`.
The latter includes all-family tile/viewer/return and AX5 layout definitions;
definitions and compiler acceptance are not executed device or visual evidence.
