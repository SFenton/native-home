# Home Improvement Tasks (page)
> **What:** home improvement tasks in four date lists; Add Task preassigns "Home Improvement". **Read when:** you change this page or the Home Tasks quick link.
- Mockup: [home-improvement-chores.html](home-improvement-chores.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/Chores/{ChoresScreen,TodoPageView,TodoListSection}.swift`, `HassCore/Config/ChoresConfig.swift`, `HassCore/Todo/*` · Spec: `.agents/pages/chores/spec.md`, `ios.md` · Patterns: module-list, floating-actions, motion
- States covered: default, loading (per-list arc), refreshing (same as default), empty, error, offline, reconnecting (and today's chip), long-text, swipe, context menu, delete confirm, ax5
- Motion: row leaves and returns (standard 0.3 s, 0.2 s fade reduced), arc to rows; transitions: push, Add sheet, Edit sheet, Delete dialog
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape (single column everywhere: no split adopter)
- Open notes: tile says "Home Tasks", page says "Home Improvement Tasks"; far-off dues read in weeks and months.
