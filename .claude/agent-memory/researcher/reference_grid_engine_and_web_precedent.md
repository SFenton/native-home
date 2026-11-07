---
name: grid-engine-and-web-precedent
description: Where the S+H tile-grid arithmetic lives, where the web fill precedent can be read, and shell gotchas for grepping this repo
metadata:
  type: reference
---

- Grid arithmetic is one path: `HassDesign/DynamicGridLayout.swift` (`DynamicGridMetrics`, pure) called by `UKGridSolver` in `HassUI/UIKitPort/Design/UKDynamicGrid.swift`. Three view classes call the solver (`UKDynamicGridView`, `UKDynamicGridLayout`, and `UKFlexGridView` in `Features/Household/UKHouseholdParts.swift`). The SwiftUI `DynamicGridLayout` has no shipping consumer (checked 2026-11-03). Verify before relying on this.
- `dynamic-grid.md` can be stale against the code (content-aware spans are "superseded" in the doc but live in the solver as of 2026-11-03): read the code first.
- Web fill precedent: `~/repos/ha-sfenton-react-dash` is a symlink into an unmounted sparsebundle volume; the readable copy is `~/repos/ha-sfenton-react-dash-insensitive-20260917` (dated 2026-09-17, sha 11cdab2). `src/components/core/DynamicGrid.tsx` and `dynamicGridLayout.ts` hold `fillRows`.
- Duo window sizes in docs (`mockups/_kit/lib/devices.js`) are partly unmeasured: unfolded portrait 669 x 951 is by symmetry; the owner's screenshot implied 703 wide.
- Shell: in zsh, an unquoted `--include=*.swift` after grep args fails with "no matches found"; quote it. `echo =====` also errors; use printf.
- `python3 tools/tasks.py flip <task> <check> --evidence <file>` works from a Researcher session (it ran without being blocked).
