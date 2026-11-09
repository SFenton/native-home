# ChipRail (scroll, wrap) (component)
> **What:** the status chip row: one scrolling row on every width, across the whole page and the Duo hinge (owner, 2026-10-26), wraps only at accessibility sizes (then stops 24 pt short of a hinge), starts at the leading margin; plus FlowLayout. **Read when:** you change ChipRail, FlowLayout or add a page with chips.
- Mockup: [chip-rail.html](chip-rail.html) · status shipped (#183) · reviewed 2026-10-23
- Source: `apple/Sources/HassDesign/{ChipRail,ChipRailLayout,FlowLayout,HostedHorizontalScroll}.swift`, `HassUI/Features/Home/StatusRail.swift`, `Rooms/RoomTiles.swift`
- Spec: `.agents/patterns/status-rail.md` · Patterns: status-rail, resume-lifecycle
- States covered: variants (scroll, wrap, left, hinge from the kit), flow (vacuum chips, room order, recipe chips), in-context (Home, Security, room, Duo, iPad), ax5
- Motion: chip colour cross-fade (0.6 s); rail reflow (none)
- Devices: iPhone, iPad portrait, Duo unfolded landscape
- Open notes: the scroller is UIKit by design; FlowLayout uses in the vacuum and recipe sheets are stand-ins owned by other batches; every chip state is in the Home mockup.
