# Media remote

> **What:** the media remote sheet (the 3×3 remote grid with power, and the Remote/Apps/Devices/Hue Sync sections) shared by every TV in the house. **Read when:** opening a remote from any screen, adding a remote, or changing remote controls.

Web source: `ha-sfenton-react-dash@9ac2a46:src/components/hass/MediaRemoteModalContent.tsx`, `src/constants/mediaRemotes.ts`.

| Piece | File |
|---|---|
| Config model | `HassCore/Config/MediaRemoteConfig.swift` |
| The four remotes (Living Room Streamer, Primary Bedroom Streamer, Media Room Streamer, Studio) | `HassCore/Config/MediaRemotes.swift` |
| Action resolution, state helpers | `HassCore/MediaRemote/MediaRemoteLogic.swift` |
| Optimistic overlay, active hold, revert scheduler | `HassCore/Entities/OptimisticOverlay.swift` |
| Controller (reads, actions, Hue Sync) | `HassCore/MediaRemote/MediaRemoteController.swift` |
| Service seam (`HassServiceCalling`; `HassConnection` conforms) | `HassCore/MediaRemote/HassServiceCalling.swift` |
| Sheet and layout policy | `HassUI/Features/MediaRemote/MediaRemoteSheet.swift` |
| Power button, remote grid, round buttons, Remote section | `HassUI/Features/MediaRemote/MediaRemoteControls.swift` |
| Apps, Devices, Hue Sync sections | `HassUI/Features/MediaRemote/MediaRemoteTabs.swift` |
| Debug gallery page (`FENTON_GALLERY=media-remote`) | `HassUI/Features/Gallery/MediaRemoteGallery.swift` |

## Using it

```swift
.sheet(item: $remote) { config in
    MediaRemoteSheet(config: config, connection: connection)
        .hassSheet(.page)   // .large, drag indicator, page sizing on iPad
}
```

`MediaRemotes.config(forMediaPlayer:)` maps a media player to its remote (web `MEDIA_PAGE_REMOTE_HASH_BY_ENTITY_ID`).

## Rules

- **Service calls are verbatim from the web.** Configs hold `ServiceCall`s; `target` goes out as `entity_id`. The keyboard sends `androidtv.adb_command` to the media player with `input text '<text>'`, each `'` written `'\''` (the web's `submitTextPrompt`; the brief said `remote.send_command`, the web wins). Blank text sends nothing.
- **Streamer presses go straight to `remote.send_command`** on `remote.demo_bedroom_1_1` (owner's recommended option, 2026-10-15). Departure from web: the web calls `script.demo_remote_send_command_1`, which wraps that one call but runs in Home Assistant's default `single` mode, so a press arriving while the previous one runs is dropped. Power and app launch still use their scripts (the power script picks wakeup or suspend; the app-launch script wakes and waits 5 s).
- **State actions** (`.state`) decide from the displayed (optimistic, else live) state of the action's entity, else the control's entity; a device with a `stateResolver` decides from its resolved, held state.
- **Optimistic values** exist only for `optimisticEntityIds` (Studio). They clear on confirmation (`liveChangeEntityIds`: on any live change), on a failed call (by generation), or after the intent's revert time. Volume has its own 2.5 s overlay; Hue Sync intents revert after 8 s.
- **Game Console hold:** the Studio Game Console tile keeps showing `on` for 45 s after its resolved live state drops, unless an optimistic value shows or one of its reset entities changes (web `useHeldDeviceState`).
- **Disabled:** d-pad, navigation and playback when the control entity is off, unavailable or unknown; volume when the volume entity is off or unavailable. The volume section shows while the speaker is on, or always with `showVolumeWhenOff` (if the entity exists). App tiles with a state entity disable while it is unavailable; actionable devices disable while unavailable.
- **Direction G** (`.agents/design/direction-g.md`, mockup n4): the sheet is a G sheet (`modalChrome`, `#2C2C2E` cells on the `#1C1C1E` ground); the subtitle names the running app and state ("Streaming A · Playing", `.sheetSubtitle`, iOS 26+). The grid is Back, Up, Power; Left, Select, Right; Home, Down, Keyboard (an empty corner without a keyboard), grey circles with white glyphs. Under it: the inline keyboard while open, the volume card (name, level, Mute; the slider between Volume Down and Volume Up) and Pause/Play. Devices and Hue Sync are inset lists: switches for toggles and commands, a checkmark choice for selections (Studio sources, HDMI input), segmented controls for sync mode and intensity, the brightness field under intensity. App tiles are artwork squares with the name under them and a pink (`ColorFamily.media`) ring plus "Playing" while active. Departures from the web: re-tapping the chosen sync mode no longer restarts syncing (a segmented control has no re-tap); the Devices tiles became list rows.
- **Power:** a round d-pad-sized button in the pad's top-right cell, right of Up (owner, 2026-10-13: give the old power row back to the content; the Streamer Remote also keeps power in the top corner). Icon red (`Palette.red`) while on, green while every rule entity is in its inactive states; it stays enabled while the directions disable, since it is how the device turns on. VoiceOver label is the config label ("Power"); the value is On/Off (Voice Control also accepts "Power On"/"Power Off"); it is a switch only where the config gives toggle semantics (Studio). Departure from web: the web keeps a "Power On/Off" pill above the pad.
- **Loading:** the sheet is a `ContentGate` ([content-gate](content-gate.md)): a centered spinner until every app tile's artwork (all tabs, so switching tabs never shows a tile loading) has loaded into `ImagePipeline` ([image-cache](image-cache.md)), then the spinner fades out and the whole content fades in at once (owner, 2026-10-13). `MediaRemoteSheet.prefetch` stops waiting after 4 s and late images fill their tiles when they land. A reopen whose artwork is already in memory opens with no spinner and no fade.
- **Sections:** only those with content (`MediaRemoteConfig.tabs`; Controls reads "Remote"), in the shared bottom glass bar (`modalTabBar`, id `remote.tabs`; a menu at accessibility text sizes); no bar for a single section.
- **Layout:** two columns (the grid leading for every section, the section trailing, 50/50 so the Duo hinge falls between them) only when `SplitPolicy` allows a split for the *window* and the sheet is ≥ 640 pt wide; otherwise one scrolling column per section, with the grid only in Remote (the keyboard key switches back to Remote when it opens the field). Never a device-name check.
- **Accessibility:** d-pad group labeled "<title> remote controls"; buttons use their config labels; light haptic per d-pad press; ≥ 44 pt targets (d-pad 64–104 pt, round buttons 44–88 pt, scaled with Dynamic Type); app tiles, selection devices and HDMI rows carry `.isSelected`, sync mode and intensity are segmented controls; Hue Sync toggles and toggle devices are switches; read-only devices are not buttons; the keyboard button reads Expanded/Collapsed.
- **Sliders** commit on release, or at once for steps without a drag (VoiceOver adjust), instead of one call per point.
- `RemoteGlassTile` was dead and is deleted (tile rollout R): `GlassTile.Kind` carries selection and state.
- Game artwork is bundled in the web build, not on the server; the tile shows its icon until `/local/images/apps/Game.jpg` exists.

## Tests

Findings from the device runs (2026-10-11):

- Only one keyboard layout at a time: a `ViewThatFits` kept the unused variant's Send button in the accessibility tree, and XCUITest matched the hidden copy. Choose the layout with `AnyLayout` (row; stacked at accessibility sizes).
- A blank button label (`EmptyView`) collapses the round button to 0 pt; draw `Color.clear`.
- `GlassTile`'s `.disabled` sits inside its combined accessibility element, so unavailable tiles read as enabled; a caller that must report disabled applies `.disabled` again outside.
- At AX5 in two columns the d-pad is capped to its column (never under 44 pt).
- Journeys scroll with short drags in screen points anchored on the window, at the element's x, clear of the Duo's trailing vertical bar: `app.coordinate` gestures never reach the unfolded Duo's inner display, normalized coordinates stay portrait in landscape, and in two columns each side scrolls on its own.
- The unfolded Duo's inner panel boots in landscape; rotate in Device Hub for unfolded portrait.

- Unit (`HassCoreTests/MediaRemote*Tests.swift`): configs vs web, `.state` cases, Game Console resolver, text escaping, power color rule, disabled/visibility rules, optimistic commit/confirm/revert/failure, holds, Hue Sync.
- Hosted (`HassUITests/MediaRemoteViewTests.swift`): every remote × tab in one and two columns, AX5, all unavailable; layout policy; every mapped SF Symbol exists; keyboard and slider state.
- Device (`iOSUITests/MediaRemoteJourneyTests.swift`, gallery fixtures with a recording caller, never the house): calls sent, semantics, 44 pt targets, layout per pose, audits per tab (iPad both orientations) with the AX5 relaunch, screenshots.
