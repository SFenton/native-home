# Camera tile and grid (component)
> **What:** A camera card on Home and Security: stream over snapshot, name capsule with a live dot, four in a 2 x 2 grid. **Read when:** you change `CameraGrid`, `CameraTile` or the stream pool.
- Mockup: [camera-tile.html](camera-tile.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/Home/CameraGrid.swift`, `Cameras/CameraLiveView.swift`, `CameraStreamPool.swift` · Spec: `.agents/patterns/camera-streams.md`, `dynamic-grid.md`, `image-cache.md` · Patterns: camera-streams, dynamic-grid, image-cache
- States covered: live, connecting, stalled, paused, redacted, grid, ax5
- Motion: arrival stagger, phase fade, shared stream (not animated)
- Devices: size classes via the Device control
- Open notes: the kit CameraTile adds a pill the app does not draw; shared helpers in `components/media/_media-lights-cameras.js` (promote to kit)
