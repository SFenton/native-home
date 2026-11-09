# Media (page)
> **What:** Every TV and media source in the house by room: the room's TV leads and opens its remote; sources and quick launches run in place. **Read when:** you change `MediaScreen`, `MediaPageConfig` or the media tiles.
- Mockup: [media.html](media.html) · status in flight (`claude/section-sides`) (action and navigation tiles, #186) · reviewed 2026-10-23
- Source: `HassUI/Features/Media/MediaScreen.swift`, `HassCore/Config/MediaPageConfig.swift`, `HassDesign/GlassTile.swift`, `DynamicGridLayout.swift` · Spec: `.agents/pages/media/spec.md`, `ios.md` · Patterns: entity-tile, media-remote, dynamic-grid
- States covered: default, loading (pending bars), refreshing, error (unavailable), offline, reconnecting (+ was), all-off, xbox-source, long-text, ax5, closed
- Motion: source tile on (state 0.6 s), lead fill, pending pulse; transitions: push from Quick Links, sheet to the remote
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape (1, 2 or 3 section columns)
- Open notes: no empty state; the Streamer is not on this page (web parity); shared helpers in `components/media/_media-lights-cameras.js` (promote to kit)
- Change log: 2026-10-27 action tiles (claude/action-nav-tiles). remote lead tiles are navigation tiles with actions: off shows Power beside the chevron; playing shows previous, play/pause, next below the text and the volume slider (writes on release), full-row tile only. Source and script tiles are unchanged.
- Change log: 2026-10-28 tile rollout R: Studio sources (Game too) use the selected face with a check disc; Handheld Console and Media Room streaming box are action tiles with a tracked power disc.
- In flight (`claude/section-sides`, [section-sides](../../../../section-sides.md)): partly folded Duo, each section wholly on one side (fold columns); state `duo-part-fold`. Every other pose unchanged.
