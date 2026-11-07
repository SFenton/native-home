# Remote app tile, device row and Hue Sync tab (component)
> **What:** The remote's non-pad pieces: the app tile, the device row (switch, choice, state) and the Hue Sync list. **Read when:** you change `MediaRemoteTabs`.
- Mockup: [media-remote-app-tile.html](media-remote-app-tile.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/MediaRemote/MediaRemoteTabs.swift`, `MediaRemoteController.swift` · Spec: `.agents/patterns/media-remote.md`, `image-cache.md` · Patterns: media-remote, image-cache
- States covered: app tile (loaded, loading, white, running, unavailable, on a page), device row, Hue Sync (syncing, unavailable), ax5
- Motion: app ring (state; gap flagged)
- Devices: size classes via the Device control
- Open notes: stand-in lettered artwork; promote MLC.appTile, deviceRow, hueTab to the kit; shared helpers in `components/media/_media-lights-cameras.js` (promote to kit)
