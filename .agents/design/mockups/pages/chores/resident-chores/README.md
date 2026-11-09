# Resident chores (Alex's, Sam's) (page)
> **What:** one template for Alex's Chores and Sam's Chores: Past Due, Due Today, Upcoming, No Due Date including unassigned tasks. **Read when:** you change a resident page or the viewer-personal copy.
- Mockup: [resident-chores.html](resident-chores.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/Chores/{ChoresScreen,TodoPageView,TodoListSection}.swift`, `HassCore/Config/ChoresConfig.swift`, `HassCore/Todo/*` · Spec: `.agents/pages/chores/spec.md`, `ios.md` · Patterns: module-list, floating-actions, motion
- States covered: default, loading (per-list arc), refreshing (same as default), empty, error, offline, reconnecting (and today's chip), long-text, swipe, context menu, delete confirm, ax5, Sam's instance (3 states), empty for the other viewer
- Motion: row leaves and returns (standard 0.3 s, 0.2 s fade reduced), arc to rows; transitions: push, Add sheet, Edit sheet, Delete dialog
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape (single column everywhere: no split adopter)
- Open notes: catalog says "Your Tasks" title; code titles the page "Alex's Chores" for everyone (only the tile reads "Your Chores").
