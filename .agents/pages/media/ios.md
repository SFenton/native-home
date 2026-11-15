# Media (iPhone and iPad)

> **What:** how the renderer draws the Media page. **Read when:** changing the published Media page or `HassCore/Config/MediaPageConfig.swift`.

Media is composed from the publication ([architecture](../../platforms/apple/architecture.md#server-driven-root)); remotes use the canonical remote sheet ([media-remote](../../patterns/media-remote.md)).

- **Tiles.** Media-family glass tiles (pink when on, direction G) under section headers; rows of follow-up tiles share one height.
  - Lead tiles navigate and open their remote whatever the TV's state (the remote's power button turns it on).
  - A remote tile that is off shows Power beside its chevron. While playing, paused or buffering it adds previous, play/pause and next below the text and a volume slider that writes on release.
  - Source and script tiles are toggles (value On or Off) and disable while their entity is unavailable.
- **One controller per remote.** The source tiles and the remote sheet share one controller, so an optimistic source change shows on both (web `OptimisticActionStateBoundary`).
- **Layout.** Sections in a grid (minimum 340 pt, up to 3), tiles under the lead in a grid (minimum 140 pt, up to 4); both scale with Dynamic Type. Full-width push page in every pose; no split ([split-view](../../design/apple/split-view.md)). HIG: Layout, Buttons.
- Game shows the controller icon: its artwork is bundled with the web app, not on the server (the same gap as the remote's Apps tab).
