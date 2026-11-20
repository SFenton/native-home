# Section sides on a partly folded Duo

> **What:** while the iPhone Duo is partly folded (book pose), each top-level section of a Studio page sits wholly on one side of the hinge, as the page's Partly Folded setting in the Studio says; the rules the app draws by. **Read when:** you touch `UKFoldColumns`, `FoldColumns`, `ServerUIFoldSides`, a page's body hosting, or author a page's Two Sides setting.

Mockups: the `duo-part-fold` states of the atlas pages Home, Security, Climate, Custom Lights, Sprinklers, Room page, Kitchen, Bedroom 1 and Media. Hub: the owner's private mockup gallery (link kept outside the repo).

## Source

The Studio sets the sides per page (its Partly Folded setting, `sh.fold-sides@1`); the app ingests it and draws what the Studio's rule says, so the binary holds no page layout. A section is pinned with Leading Side or Trailing Side, and VoiceOver reads the same order partly folded as flat when the pins keep document order.

## Rules

1. **Where.** Sides are drawn only while the page uses them (`layout.foldSides: auto`, or a component pinned `leading` or `trailing`) and `FoldColumns.resolve(container:isRegularWidth:hinge:)` answers for the page body's own frame: a hinge band crosses the window, the window is wider than tall and each side is at least 360 pt. Every other case is the single column, frame for frame. Never a device check.
2. **The unit** is one top-level component of the page that holds a slot, with everything under it, whatever its type. It is never divided. A page whose top level is one container leads and the trailing side stays empty, with no placeholder; the app never looks inside it.
3. **Sides.** One pure rule in `HassCore` (`ServerUIFoldSides.resolve`), the same as the Studio's `resolveFoldSides`: the notification banner and the pinned bar hold no slot; the run of status rails at the top spans, as does a `span` in that run (a later `span` is refused); the rest alternate by position, the first leading; an explicit side wins and keeps its position in the count. The shared corpus (`evaluation/fold-sides-*`) pins it on both sides.
4. **Order inside a side** is document order. There is no rank and no rule naming a section.
5. **Hidden.** A component a rule hides takes no room and keeps its slot: the others on its side move up or down, nothing changes side.
6. **Top strip.** Spanning entries stack in document order across the page; a scrolling rail runs over the band. The notification banner sits in the strip, the leading region wide.
7. **Widths.** The leading side is the region before the band, the trailing side the region after it. Each keeps the page's leading and trailing padding at its own edges. The page's `maxWidth` is ignored while split and applies when flat. Right to left mirrors the sides, and no side frame meets the band.
8. **Text size.** Two sides at every size. At accessibility sizes every top-strip entry heads the leading column in document order and the trailing side starts at the top, level with it. A text-size change while split reflows on `standard`.
9. **Panes and sheets.** Never sides on a sheet (the Studio refuses `foldSide` there), on a page shown inside a column, or on a page that hosts columns (`navigation` other than `stack`). A page whose body is one scrolling collection keeps that scroller and narrows it to the leading region.
10. **Reading order** while split: the strip, the leading side top to bottom, then the trailing side. The container sets `shouldGroupAccessibilityChildren` and lists its sections through `accessibilityElements`; flat it returns the default. After a posture reflow it posts `.layoutChanged` with no argument, so focus stays where it is.
11. **Motion.** The page hosts its keyed root views in one `UKFoldColumns` in both poses, so a posture change only moves frames inside `UKReflow` (`standard`; Reduce Motion cross-fades in 0.2 s). Nothing is re-parented, re-created or re-faded. The scroll offset is clamped to the new height inside the same animation, a pose reversed mid-flight retargets from the current frames, and the first layout of a page that opens partly folded sets the pose without animation. The hinge is read from an observer of `windowHinge`, never during layout.
12. **Grids.** A grid's `fold` prop is unchanged; a grid inside a side never meets the band, so `page` and `container` draw the same there.

## Authoring advice

- A page with one slot-holding component (a list, a grid, one section) sits in the leading side beside an empty one. Leave such a browsing page on One Column.
- A section that must stay at the top of its side is pinned to it; a side stacks in document order.
- To divide a long section across the band, make its blocks top-level components.

## Families

Changes only on the iPhone Duo, unfolded, landscape, partly folded. Unchanged by construction (no band): iPhone, folded Duo, unfolded portrait, flat unfolded landscape, iPad portrait and landscape.

## HIG

- Designing for iPhone Duo, reserved regions: "Folding region | Present when partially open; divides the inner display into usable regions while excluding the center fold."
- Designing for iPhone Duo: "Avoid extreme changes: move only what's necessary"; "Preserve functionality, element state, hierarchy, and access across displays/poses" (rules 4 and 10).
- Layout, Hierarchy: "Place important content toward the top/leading side in reading order".
- Accessibility, Reduce Motion: replace axis moves with fades (rule 11). Motion: "let people cancel animations rather than wait for completion".
- The HIG does not ask for whole sections on one side; the owner chose it, and it wins over web parity.

## Rung 0

No system API lays out variable-height, live-bound sections around a reserved region: `UIView.reservedRegions` and `UIHingeInteraction` (iOS 27.1) only report it; compositional layout needs reused cells and split view owns navigation. `UKFoldColumns` is the custom container ([system-api-audit](apple/system-api-audit.md)); `shouldGroupAccessibilityChildren` is the system API for reading order.
