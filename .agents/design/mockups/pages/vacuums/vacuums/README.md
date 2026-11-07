# Vacuums (page)
> **What:** the Vacuums page: three robot tiles, a one-line summary and three Auto-Clean switches, split on landscape iPad and unfolded Duo. **Read when:** you change `VacuumsScreen`, the robot tiles or the Auto-Clean list.
- Mockup: [vacuums.html](vacuums.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Vacuums/VacuumsScreen.swift, HassUI/Features/Home/HomeRoute.swift, HassCore/Vacuums/VacuumAutoCleanController.swift` (paths under `apple/Sources/` unless full) · Spec: `.agents/pages/vacuums/spec.md, ios.md` · Patterns: vacuum-sheet, dynamic-grid, module-list
- States covered: all docked, cleaning, mixed (cleaning + needs attention), paused/returning, unavailable (= loading), refreshing, offline, reconnecting, long text, sheet open, ax5; empty has no UI (noted)
- Motion: tile colour and band, Auto-Clean switch, reconnecting arc; transitions: push from Quick Links, tile to sheet
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape (split), iPad portrait and landscape (split)
- Open notes: tile opens `.page, height: .full` (ios.md says `.page`); unavailable robots are not given isUnavailable; spec.md describes VacuumTile, native uses GlassTile
- Rollout M (2026-10-28): robot tiles are navigation tiles with Start/Pause and Dock discs (Dock dimmed while docked) and a chevron; ids `vacuums.tile.<map>` + `.action.start_pause` / `.action.dock`.
