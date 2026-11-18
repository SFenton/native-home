# Badges

> **What:** a count or short text on the top trailing corner of a tile or chip. **Read when:** a node shows a count or word about itself.

- `sh.badges@1`: `ServerUILayoutRules.badge` gives the text; `UKServerUIBadgeViews.show(_:on:)` (`HassUI/UIKitPort/ServerUI/UKServerUIBadgeViews.swift`) draws it in the one `UKSegmentBadge` capsule (HIG, Badging).
- A badge run that finds the text it already shows draws nothing and counts `logic.skippedEqual` ([logic-evaluation](../testing/apple/logic-evaluation.md)).
- A value of 0 or empty text draws nothing. The badge keeps what it showed while its value loads, so a reconnect never blanks it.
- A badge can be a count of several entities (`sh.count@1`, [logic-evaluation](../testing/apple/logic-evaluation.md)). A person-filtered count keeps what it showed until the viewer is known; a count nothing can answer yet keeps it too, and one it cannot answer at all draws nothing.
- VoiceOver reads it as its own element, labelled "Badge, 3"; with no text it is not an element.
- Tests: `ServerUILayoutTests`, `ServerUIParityRoundOneHostedTests`, `ServerUICountHostedTests` (a count badge, with and without a viewer filter, on iPhone, Duo and iPad).
