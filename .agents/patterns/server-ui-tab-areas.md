# Tab areas

> **What:** the areas of a tab container, each drawn once for the tabs that name it. **Read when:** you change a tab container, its bar or its fallback.

- `sh.tab-blocks@1`: areas stack top to bottom in document order. `UKServerUIAreaStack` (`HassUI/UIKitPort/ServerUI/UKServerUITabAreas.swift`) keeps one panel per area id, never per tab.
- A tab change adds the panels of the areas that begin to show and removes the ones that stop. A panel shown on both tabs is not touched, so a shared map keeps its picture and zoom (AGENTS.md, "No reload").
- An area has no chrome. An area that begins to show fades in; Reduce Motion never animates.
- `sh.tab-bar@1` places the bar and labels the tabs; `sh.tab-fallback@1` names the tab to open when the chosen one cannot show.
- Tests: `ServerUILayoutTests`, `ServerUILayoutCorpusTests` (`tab-blocks-*`).
