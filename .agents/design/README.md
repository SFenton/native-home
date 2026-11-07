# Design

> **What:** per-platform design decisions. **Read when:** making any visual or navigation choice.

| File or folder | Holds |
|---|---|
| [apple/](apple/README.md) | iPhone, iPad, Duo, Watch decisions and the screen classification |
| [direction-g.md](direction-g.md) | The app's visual language: wallpaper, materials, sheets, colour families, chips, tiles, signature controls, arc spinner |
| [direction-g-plan.md](direction-g-plan.md) | Phases, components, dependencies and verification for moving the app to direction G |
| [action-navigation-tiles.md](action-navigation-tiles.md) | Action, navigation and read-only tiles: discs, chevron, feedback kinds, garage disc, widen-then-ticker (owner, option B, 2026-10-26) |
| [setup-flow.md](setup-flow.md) | The setup sheet (Notifications, Time Sensitive, Location), the Settings → Notifications entries and iPad location, with their mockups |
| [settings-version-row.md](settings-version-row.md) | Settings → About → Version: the build text, tap to copy, and its mockups |
| [vacuum-sheet-redesign.md](vacuum-sheet-redesign.md) | The vacuum sheet: no room names on the map, three equal status tiles, pop-up settings with the animated Water and Fan rows, Use Area / Use Rooms tiles, selection tiles for Rooms and Auto-Clean, action tiles with footers (owner, option B with amendments, 2026-10-28) |
| [duo-widths.md](duo-widths.md) | Short rows of tiles fill their section (one-row grids equal shares, multi-row grids whole tracks on the track lines; exceptions), one section column in a tall window at every text size, the final unpaired section spans when flat (owner rules, 2026-11-03) |
| [house-config-states.md](house-config-states.md) | Sign-in's Server row (owner request 2026-11-06, reversing "no address field") and what every page shows with no house layout: first-sign-in skeleton, state messages per server answer, a saved layout always wins, missing entities read Unavailable (judged and picked 2026-11-06) |
| [section-sides.md](section-sides.md) | Partly folded Duo: every section wholly on the leading or trailing side of the hinge (fold columns), the per-page side table, the one-section rule and the exceptions (owner request, judged and picked 2026-11-03) |
| [weather-card-header.md](weather-card-header.md) | The Home weather card's header layout, the ticker for long conditions, and its mockups |
| [sheet-bottom-gap.md](sheet-bottom-gap.md) | Fitted sheets no longer leave an empty band under their last control: the detent leaves out the bottom safe area the system adds |
| [weather-chevron-contrast.md](weather-chevron-contrast.md) | The weather carousel's disabled Previous and Next: one fade to 55%, never `.plain` on top |
| [profile-badge.md](profile-badge.md) | The Profile attention badge: 24 x 18 at default, on the disc's corner on every bar (the header draws it, the rail uses the system badge), text capped at xLarge (2026-11-04) |
| [mockups/proposals/state-message/state-message.html](mockups/proposals/state-message/state-message.html) | Empty and error states centred in the space a page leaves: before and after for Chores, Summary tabs, Recipes, Inventory and Accessibility 5 |
| [controller-bound-controls.md](controller-bound-controls.md) | Proposal (awaiting owner): removing `Binding(get:set:)` closures that forward to controllers |
| [mockups/proposals/long-titles/long-titles.html](mockups/proposals/long-titles/long-titles.html) | Page titles lead the navigation bar and carousel when long: today beside proposed on iPhone, iPad and the Duo |
