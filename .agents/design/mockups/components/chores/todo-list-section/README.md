# Todo list section and item row (component)
> **What:** one list as a section: header, warning, arc, and checkable rows; page and sheet surfaces. **Read when:** you change the row, its due label, swipe actions or the Summary chore tabs.
- Mockup: [todo-list-section.html](todo-list-section.html) · status shipped · reviewed 2026-10-23
- Source: `HassUI/Features/Chores/{TodoListSection}.swift`, `HassDesign/ModuleList.swift`, `HassCore/Todo/*` · Spec: `.agents/pages/chores/ios.md` · Patterns: module-list
- States covered: section, thin, every row variant, done, loading, error, swipes, context menu, ax5; page and sheet
- Motion: row leaves (standard 0.3 s), check colour (state 0.6 s)
- Devices: iPhone, Duo, iPad (the Device control picks the size class)
- Open notes: done look is unreachable today (completed items are hidden); promote to kit.
