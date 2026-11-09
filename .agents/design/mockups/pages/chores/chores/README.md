# Chores (tab root) (page)
> **What:** the Chores tab: Quick Links with counts, then the viewer's own lists by Past Due and time of day. **Read when:** you change the Chores tab, its Quick Links, swipe actions or the Add Task button.
- Mockup: [chores.html](chores.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/Chores/{ChoresScreen,TodoPageView,TodoListSection}.swift`, `HassCore/Config/ChoresConfig.swift`, `HassCore/Todo/*`, `ChoresModel.swift`, `TodoListAlignment.swift` · Spec: `.agents/pages/chores/spec.md`, `ios.md` · Patterns: module-list, floating-actions, motion, dynamic-grid, entity-tile
- States covered: default, loading (per-list arc), refreshing (same as default), empty, error, offline, reconnecting (and today's chip), long-text, swipe, context menu, delete confirm, ax5, vacation, viewer-sam
- Motion: row leaves and returns (standard 0.3 s, 0.2 s fade reduced), arc to rows; transitions: push, Add sheet, Edit sheet, Delete dialog, swipe settle
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape (single column everywhere: no split adopter)
- Open notes: docs say large detent and splits (the code fits sheets, no split); a long tile title can touch its count; first-launch empty flash is read from code, not reproduced; helper `pages/chores/_chores.js` is shared by all 14 chores mockups.
- Rollout M (2026-10-28): Quick Links are navigation tiles (chevron, no numeral) whose state line is "N open · M overdue" / "Nothing open"; ids `chores.link.<page>` kept.
