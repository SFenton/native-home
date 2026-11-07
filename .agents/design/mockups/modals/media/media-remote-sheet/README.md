# Media remote sheet (modal)
> **What:** One sheet for every TV: the 3 x 3 pad with power, volume card, transport keys, and Apps, Devices and Hue Sync sections. **Read when:** you change `MediaRemoteSheet`, the remote controls or a remote config.
- Mockup: [media-remote-sheet.html](media-remote-sheet.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/MediaRemote/MediaRemoteSheet.swift`, `MediaRemoteControls.swift`, `MediaRemoteTabs.swift`, `HassCore/Config/MediaRemotes.swift` · Spec: `.agents/patterns/media-remote.md`, `.agents/design/direction-g.md` · Patterns: media-remote, modal-sheet, content-gate
- States covered: default, loading (gate), error, offline, off, keyboard (+ typed), pressed, apple-tv, theater, music-room, apps (+ loading, playing), devices (+ music, unavailable), hue (+ unavailable), large, closed, ax5 (+ hue); dark and light
- Motion: key press (quick), power colour (state), keyboard form (flagged: .default, not a token), content gate; transitions: present, tab cut, dismiss
- Devices: iPhone, Duo folded, Duo unfolded landscape, iPad portrait and landscape (two columns in landscape)
- Open notes: height .full (no medium or fitted); docs say `.hassSheet(.page)`; subtitle "Plex · Playing" needs app_name; Duo hinge placement not run on a device; shared helpers in `components/media/_media-lights-cameras.js` (promote to kit)
