# Settings section

> **What:** a settings page's header + description + controls block, and the pieces that go in it. **Read when:** building a settings-style page (Admin, Guests, Vacation, Sprinklers…).

- `SettingsSection(title:paragraphs:content:)` (`HassDesign/SettingsSection.swift`, web `SettingsSection.tsx`): `HassTokens.Typography.sectionTitle` (`.title3.bold()`, the one section-header font) header with the heading trait, each description paragraph as its own `.subheadline` text in `HassTokens.Ink.secondary`, then the content. Pages stack sections in a `ScrollView` with `Spacing.xl` between them.
- `InlineAlert(_:)`: a warning under the control it concerns (orange triangle, tinted rounded background, primary text); VoiceOver reads "Warning: …".
- `SelectableOptionRow`: one choice in a single-choice set (icon, label, description, checkmark; `.isSelected`; description as the hint). Lay several out with `DynamicGridLayout(minCellWidth: 300, maxColumns: 2)`. Web `ScheduleListRow`.
- Read-only entity values use the read-only entity tile ([entity-tile](entity-tile.md)).

## Section headers, disclosure chevrons and disabled reasons (owner, 2026-10-24)

- **One section-header font.** `HassTokens.Typography.sectionTitle` is `.title3.bold()`; `PageSectionHeader`, `SettingsSection` and `FilterSection` all use it, and the car block is a `SettingsSection`. A bare `FormHeader` inside a `Form` keeps the system header size and case (`proposals/titles-and-headers`). Tile titles are `HassTokens.Typography.tileTitle` (`.subheadline.bold()`).
- **A chevron means push, and nothing else.** `SettingsLinkRow.showsChevron` defaults to false. Set it only for a row that pushes without a `NavigationLink` (the household topics, which push on a phone and fill the detail pane beside the list). Rows that present a sheet or a cover (Home Assistant, Feedback, App Icon) draw no accessory and carry an accessibility hint ("Opens ..."). A `NavigationLink` draws its own chevron. **Owner exception (2026-10-27):** the Settings → Notifications rows (Notifications and Time Sensitive Notifications, `NotificationsSettingsSection`) draw a chevron although they leave the app for iOS Settings, because the owner wants the row to read as a way in; they say "Opens Settings" in their accessibility hint. Do not extend this to other rows that leave the app. A light tile that opens a sheet draws a power button, not a chevron (`BrightnessTile`). The same holds for the Climate advanced-controls rows, the Sprinklers controller row, the vacuum cleaning-report row and the weather card numeral: they open sheets and draw no accessory (a row that must stay a Button because a NavigationLink failed to present on the folded Duo keeps the Button and only loses the accessory). A pop-up `Menu` wears the up-down chevron; Custom Lights' Lighting Mode is one.
- **Say why a control is disabled.** Disable instead of hiding, and put the reason in text beside it: the Sprinkler schedule's Days footer ("Choose at least one day.", `SprinklerSchedulePage.applyBlocker`); the Vacation confirmation sheet keeps Confirm present but disabled with the date error above it (`AwayActionButton(isEnabled:disabledReason:)`).

- **Canonical (UIKit).** `UKSectionBlock.settings(title:paragraphs:content:)` in `UIKitPort/Features/Household/UKHouseholdParts.swift`. `UIKitPort/Design/UKSettingsSection.swift` holds its pieces (`UKInlineAlertView`, `UKSelectableOptionRow`, `UKFormText`, `UKInfoBoxView`).
- **Composed settings controls.** `UKServerUISettingsAtom` pins its child to its own edges, so a settings control in a module list (a `UIStackView` sized by system fitting) has the child's height under Auto Layout, not 1 pt.
- **Owned files** (also in `contracts/patterns.json`): `UIKitPort/Design/UKSettingsSection.swift`, `UIKitPort/Features/Settings/UKSettingsStack.swift` (`UKSettingsStackCell`), `UIKitPort/ServerUI/UKServerUIPreferenceRow.swift`, `HassDesign/InsetGroupedMetrics.swift`, `UIKitPort/Design/UKLayoutViews.swift` (`UKPageSectionHeaderView`).

## Settings rows in a module list

- **One group per `module-list` section.** `UKModuleListView` draws the one 26 pt continuous fill, clips rows and their press wash, and draws every hairline (0.5 pt, between rows only, hidden from VoiceOver). A settings row is content, padding and a wash, never a card ([module-list](module-list.md)). A group's rows are the rows of one published `module-list` section; the publication decides which rows share a group.
- **Row kinds** (`UKSettingsRowKind`, declared by the row: a settings link is `.link`, the provider's blur and badge are `.control`, reset is `.textButton`, version is `.link`): `.link` (glyph and text, 15 pt above and below a 44 pt minimum, 74 pt at Large), `.textButton` (text alone, 15 pt, 74 pt), `.control` (a switch, a slider: 10.5 pt, 65 pt for the switch, 83 to 86 pt for the slider; no wash).
- **Content insets.** 15 pt leading, 17.5 pt trailing, a 34 pt glyph column and 12 pt to the text, so text starts at 61 pt after a glyph and at 15 pt otherwise. The padding does not scale; the text grows and wraps, never truncates.
- **Hairlines.** Each takes its leading and trailing insets from the row above: 15 pt under a text or control row, 61 pt under a glyph row, 15 pt for every row at accessibility text sizes (the glyph sits above the text); 16 pt short of the trailing edge.
- **Press.** A row with an action washes its whole width and height; the slider and switch rows draw no wash.
- **The Settings root** uses the page section header (`UKPageSectionHeaderView`, title3 bold) and the publication's spacing and padding tokens: no native Settings gap, margin or readable width, so the group's edges sit at the page padding in every window.
- `InsetGroupedMetrics` holds the row metrics only (row and control padding, glyph column, leading and trailing content inset, hairline trailing inset).

## Server-driven Settings rows draw the recorded row kinds

- `reset-background-blur` is a `.textButton`: action ink, no glyph, 74 pt (15 pt above and below a 44 pt minimum), leading aligned at 15 pt, dimmed and disabled at the default value.
- `app-version` is the Version row of [settings-version-row](../design/settings-version-row.md): the `info.circle` glyph, the build text trailing, a tap copies it.
- VoiceOver reads the spoken version as its value and "Copies the version to the clipboard." as its hint; a copy plays the confirmation haptic.
- Neither row draws a chevron, and the node's authored icon is ignored. A chevron stays on a row that pushes.
- `UKServerUIPreferenceRow` draws both.
- `settings-link` rows pin to their cell (`UKServerUISettingsLink`), so a module list gives each the cell's own height.
