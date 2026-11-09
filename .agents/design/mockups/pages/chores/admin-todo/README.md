# Admin To-Do (page)
> **What:** the admin to-do list pushed from Settings (Alex only): no list header, rename, no delete, check-off runs a script. **Read when:** you change the admin To-Do page or its sheets.
- Mockup: [admin-todo.html](admin-todo.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/Chores/{ChoresScreen,TodoPageView,TodoListSection}.swift`, `HassCore/Config/ChoresConfig.swift`, `HassCore/Todo/*`, `Settings/SettingsScreen.swift` · Spec: `.agents/pages/chores/spec.md`, `ios.md`, `settings/ios.md` · Patterns: module-list, floating-actions, motion
- States covered: default, loading (per-list arc), refreshing (same as default), empty, error, offline, reconnecting (and today's chip), long-text, swipe, context menu, delete confirm, ax5
- Motion: row leaves and returns (standard 0.3 s, 0.2 s fade reduced), arc to rows; transitions: push, Add sheet, Edit sheet, Delete dialog (push from Settings)
- Devices: iPhone, Duo folded, Duo unfolded landscape and portrait, iPad portrait and landscape (single column everywhere: no split adopter)
- Open notes: rows show no image indicator (images are only sent on create); hidden from Sam.
