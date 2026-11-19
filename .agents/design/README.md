# Design

> **What:** per-platform design decisions. **Read when:** making any visual or navigation choice.

| File or folder | Holds |
|---|---|
| [apple/](apple/README.md) | iPhone, iPad, Duo, Watch decisions and the screen classification |
| [direction-g.md](direction-g.md) | The app's visual language: wallpaper, materials, sheets, colour families, chips, tiles, signature controls, arc spinner |
| [action-navigation-tiles.md](action-navigation-tiles.md) | Action, navigation and read-only tiles: discs, chevron, feedback kinds, garage disc, widen-then-ticker (owner, option B, 2026-10-26) |
| [setup-flow.md](setup-flow.md) | The setup sheet (Notifications, Time Sensitive, Location), the Settings → Notifications entries and iPad location, with their mockups |
| [settings-version-row.md](settings-version-row.md) | Settings → About → Version: the build text, tap to copy, and its mockups |
| [vacuum-sheet-redesign.md](vacuum-sheet-redesign.md) | The vacuum sheet: no room names on the map, three equal status tiles, pop-up settings with the animated Water and Fan rows, Use Area / Use Rooms tiles, selection tiles for Rooms and Auto-Clean, action tiles with footers (owner, option B with amendments, 2026-10-28) |
| [duo-widths.md](duo-widths.md) | Short rows of tiles fill their section (one-row grids equal shares, multi-row grids whole tracks on the track lines; exceptions), one section column in a tall window at every text size, the final unpaired section spans when flat (owner rules, 2026-11-03) |
| [house-config-states.md](house-config-states.md) | Sign-in's Server row (owner request 2026-11-06, reversing "no address field") and where a missing house layout is shown: the House Layout row, a saved document always wins, missing entities read Unavailable (judged and picked 2026-11-06) |
| [section-sides.md](section-sides.md) | Partly folded Duo: every section wholly on the leading or trailing side of the hinge (fold columns), the per-page side table, the one-section rule and the exceptions (owner request, judged and picked 2026-11-03) |
| [weather-card-header.md](weather-card-header.md) | The Home weather card's header layout, the ticker for long conditions, and its mockups |
| [sheet-bottom-gap.md](sheet-bottom-gap.md) | Fitted sheets no longer leave an empty band under their last control: the detent leaves out the bottom safe area the system adds |
| [weather-chevron-contrast.md](weather-chevron-contrast.md) | The weather carousel's disabled Previous and Next: one fade to 55%, never `.plain` on top |
| [live-activity-problem-notice.md](live-activity-problem-notice.md) | The Live Activity problem card after a failed button press: the notice takes the instruction's place |
| [profile-badge.md](profile-badge.md) | The Profile attention badge: 24 x 18 at default, on the disc's corner on every bar (the header draws it, the rail uses the system badge), text capped at xLarge (2026-11-04) |
| [mockups/proposals/state-message/state-message.html](mockups/proposals/state-message/state-message.html) | Empty and error states centred in the space a page leaves: before and after for Chores, Summary tabs, Recipes, Inventory and Accessibility 5 |
| [state-styled-tile.md](state-styled-tile.md) | The state-styled tile: classes and the active flag, the four layers and the unchanged-layer rule, the disc and the arc, the closed indicator list, the transition table, the flap guard, the warning pulse, Reduce Motion and VoiceOver |
| [core-grammar-surfaces.md](core-grammar-surfaces.md) | The generic authored controls: choice surfaces, the toggle line, the status line for unavailable and disabled, `enabledWhen`, `ask`, slider range, format and commit, and the Studio preview |
| [pending-controls.md](pending-controls.md) | Between a tap and Home Assistant's answer: the optimistic value, the waiting arc, the failed face, defaults by call and the authored `pending` settings |
| [server-ui-boundary.md](server-ui-boundary.md) | The recovery boundary of the server-driven root: its four states, actions, hinge placement and words |
| [kept-text.md](kept-text.md) | A text slot showing a kept value (`sh.text-keep@1`) is drawn and spoken exactly as live; before any answer it draws its fallback |
| [state-glyph-tint.md](state-glyph-tint.md) | A state style rule's `glyphTint` (`sh.state-style-glyph-tint@1`): the icon colour per state, its fallback, where it draws, contrast and accessibility |
| [state-styles.md](state-styles.md) | Built-in state styles, the request phase, how the door, lock and alarm tiles map onto them, and the Studio's style library |
| [controller-bound-controls.md](controller-bound-controls.md) | Proposal (awaiting owner): removing `Binding(get:set:)` closures that forward to controllers |
| [mockups/proposals/long-titles/long-titles.html](mockups/proposals/long-titles/long-titles.html) | Page titles lead the navigation bar and carousel when long: today beside proposed on iPhone, iPad and the Duo |
