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

`MediaRemotes.config(forMediaPlayer:)` maps a media player to its remote (web `MEDIA_PAGE_REMOTE_HASH_BY_ENTITY_ID`).

## Rules

- **Service calls are verbatim from the web.** Configs hold `ServiceCall`s; `target` goes out as `entity_id`. The keyboard sends `androidtv.adb_command` to the media player with `input text '<text>'`, each `'` written `'\''` (the web's `submitTextPrompt`; the brief said `remote.send_command`, the web wins). Blank text sends nothing.
- **Streamer presses go straight to `remote.send_command`** on `remote.demo_bedroom_1_1`. Departure from web: the web calls `script.demo_remote_send_command_1`, which runs in `single` mode and drops a press arriving while the previous one runs. Power and app launch still use their scripts.
- **State actions** (`.state`) decide from the displayed (optimistic, else live) state of the action's entity, else the control's entity; a device with a `stateResolver` decides from its resolved, held state.
- **Optimistic values** exist only for `optimisticEntityIds` (Studio). They clear on confirmation (`liveChangeEntityIds`: on any live change), on a failed call (by generation), or after the intent's revert time. Volume has its own 2.5 s overlay; Hue Sync intents revert after 8 s.
- **Game Console hold:** the Studio Game Console tile keeps showing `on` for 45 s after its resolved live state drops, unless an optimistic value shows or one of its reset entities changes (web `useHeldDeviceState`).
- **Disabled:** d-pad, navigation and playback when the control entity is off, unavailable or unknown; volume when the volume entity is off or unavailable. The volume section shows while the speaker is on, or always with `showVolumeWhenOff` (if the entity exists). App tiles with a state entity disable while it is unavailable; actionable devices disable while unavailable.
- **Direction G** (`.agents/design/direction-g.md`, mockup n4): the sheet is a G sheet (`modalChrome`, `#2C2C2E` cells on the `#1C1C1E` ground); the subtitle names the running app and state ("Streaming A · Playing", `.sheetSubtitle`, iOS 26+). The grid is Back, Up, Power; Left, Select, Right; Home, Down, Keyboard (an empty corner without a keyboard), grey circles with white glyphs. Under it: the inline keyboard while open, the volume card (name, level, Mute; the slider between Volume Down and Volume Up) and Pause/Play. Devices and Hue Sync are inset lists: switches for toggles and commands, a checkmark choice for selections (Studio sources, HDMI input), segmented controls for sync mode and intensity, the brightness field under intensity. App tiles are artwork squares with the name under them and a pink (`ColorFamily.media`) ring plus "Playing" while active. Departures from the web: re-tapping the chosen sync mode does not restart syncing; the Devices tiles are list rows.
- **Power:** a round d-pad-sized button in the pad's top-right cell, right of Up . Icon red (`Palette.red`) while on, green while every rule entity is in its inactive states; it stays enabled while the directions disable, since it is how the device turns on. VoiceOver label is the config label ("Power"); the value is On/Off (Voice Control also accepts "Power On"/"Power Off"); it is a switch only where the config gives toggle semantics (Studio).
- **Loading:** the sheet is a `ContentGate` ([content-gate](content-gate.md)): a centered spinner until every app tile's artwork (all tabs, so switching tabs never shows a tile loading) has loaded into `ImagePipeline` ([image-cache](image-cache.md)), then the spinner fades out and the whole content fades in at once. `MediaRemoteSheet.prefetch` stops waiting after 4 s and late images fill their tiles when they land. A reopen whose artwork is already in memory opens with no spinner and no fade.
- **Sections:** only those with content (`MediaRemoteConfig.tabs`; Controls reads "Remote"), in the shared bottom glass bar (`modalTabBar`, id `remote.tabs`; a menu at accessibility text sizes); no bar for a single section.
- **Layout:** two columns (the grid leading for every section, the section trailing, 50/50 so the Duo hinge falls between them) only when `SplitPolicy` allows a split for the *window* and the sheet is ≥ 640 pt wide; otherwise one scrolling column per section, with the grid only in Remote (the keyboard key switches back to Remote when it opens the field). Never a device-name check.
- **Accessibility:** d-pad group labeled "<title> remote controls"; buttons use their config labels; light haptic per d-pad press; ≥ 44 pt targets (d-pad 64–104 pt, round buttons 44–88 pt, scaled with Dynamic Type); app tiles, selection devices and HDMI rows carry `.isSelected`, sync mode and intensity are segmented controls; Hue Sync toggles and toggle devices are switches; read-only devices are not buttons; the keyboard button reads Expanded/Collapsed.
- **Sliders** commit on release, or at once for steps without a drag (VoiceOver adjust), instead of one call per point.
- Game artwork is bundled in the web build, not on the server; the tile shows its icon until `/local/images/apps/Game.jpg` exists.

## Tests

### Configured native atoms (schema 2)

`remote-control` nodes bind a typed `media-remote@1` source to a retained
`ServerUIRemoteSession`, wrapping an existing `MediaRemoteController` on the same
`EntityStore` and explicitly injected caller. `media-remote-config@1` constructs that
session from a closed authored descriptor: configured calls, optimistic targets,
apps, devices and explicit console-state inputs. The renderer never looks up
`MediaRemotes` or embeds the remote feature controller. Unknown provider,
app/device key, unsupported native symbol or missing optional controller section
rejects preflight before acceptance. Parent promotion must call
`UKServerUIRenderer.preflight(_:remoteProviders:store:)`; preflight without a
provider registry rejects publications that require a remote.

The renderer initializer prepares, preflights and installs one provider set before
acceptance. Equal descriptors retain sessions; changing the store or transport is
rejected. Page cards have separate stable `cards[].key` identities so a page's
source-selection sensor cannot accidentally inherit the Devices tab's player target.
Device atoms support explicit `row` or `tile` presentation. Artwork injection is
`remoteArtwork(providerId, appKey)`, resolved against the prepared app catalog.
Local-tab focus switching, bottom-bar placement and wide two-pane composition remain
the shared shell's responsibility; a compiled recipe is not a paired-crawl verdict.

The canonical UIKit controls in `UKMediaRemoteControls.swift` and
`UKMediaRemoteTabs.swift` now also accept appearance/state values and intent
closures; their original controller initializers remain the native binding
wrappers. `EntityState.showing(_:)` lives in Core so both bindings share the same
feedback projection. The controller tracks its configured media player for
card play/pause feedback in addition to its configured optimistic entities.

Authors choose key positions, labels, SF Symbols/blank Select, rotation, spoken
active/inactive copy, app artwork policy, state labels, Hue options/order and
keyboard/error copy. Volume's canonical geometry is explicit: position 0 is
Mute above the slider, 1 is Down and 2 is Up beside it. Card action appearances
are authored in order; `MediaTransportActions` still decides eligibility,
supported features, command and feedback. Card navigation is a separate typed
navigation action. Each atom negotiates only its `sh.remote-<kind>@1` capability
plus the source/binding capabilities. Frozen first-slice capabilities do not change.
Studio uses the generated structured inspector, not a raw-JSON requirement.

Authored device tiles retain the canonical media/power family and may use
resident-aware PC titles through the narrow `roomResidentId` read. Redaction or
an absent identity preserves the authored title. These tile-only fields are
rejected on device rows, which do not render them.

`ServerUIRemoteSession` pins keyboard target/text through acknowledgement,
retains draft and native focus on rejection, blocks duplicate submission/cancel
while sending, and revalidates every value intent at activation. Source or
attachment removal, retargeting, reordering and reparenting are blocked during
drafts, slider gestures, actual calls (even without optimistic writes) or
unconfirmed feedback. Compatible publications and trait changes retain native
instances. Errors use authored inline copy plus sanitized parent diagnostics.

Rung 0: retain `UIControl`, `UITextField`, `UISlider` and the existing segmented
choice/menu adaptation, rather than adding a gesture, text-input, navigation or
state interpreter. This preserves the canonical native press and focus behavior.
Design references: Apple HIG [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons),
[Text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields),
[Sliders](https://developer.apple.com/design/human-interface-guidelines/sliders)
and [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).
No redesign is claimed.

The synthetic all-atom corpus is `HassCoreTests/ServerUIRemoteFixture.json`,
mirrored at Studio `tests/fixtures/remote-composition.json`. The atomic corpus
is not a complete production page/sheet recipe. Local tabs with content fades,
geometric two-pane attachment, inset form/collection containers and artwork
content-gating remain shell-owned integration requirements. Existing atlas
mockups remain the canonical reference; new configured surfaces are not visually
certified until parent device/AX/motion evidence exists for all three families.

Focused evidence: `ServerUIRemoteContractTests`, `ServerUIRemoteSessionTests`,
hosted `ServerUIRemoteRendererTests` and Studio `composition-remote.test.tsx`.
