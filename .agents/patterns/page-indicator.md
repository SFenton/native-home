# Page indicator

> **What:** the one page indicator for every paging row and carousel (Food suggestions, the Weather sheet, the hourly rows). **Read when:** adding a carousel, or any control that pages.

- `PageIndicator(page:pageCount:label:identifier:ink:onSelect:)` (`HassDesign/PageIndicator.swift`). The app draws it (a wider capsule for the current page and small dots in the card's ink, `quickTransition` 0.2 s), so it follows the card ink instead of the system's `UIPageControl` colours (owner, 2026-10-24: option A of `proposals/page-indicators`).
- **Tap to move.** The strip is full width and at least 44 pt tall and is two tap zones: the leading half goes back one page, the trailing half forward (HIG, Page controls). It does nothing past either end.
- **One accessibility element.** Label (what pages, e.g. "Suggestion page"), value "Page 2 of 5", an adjustable action (swipe up and down) and the identifier. The tap zones are for touch; assistive technology pages with the adjustable action.
- **Dots up to ten pages**; from eleven pages the dots give way to a "4 of 12" label in the same strip with the same tap zones (`PageIndicator.dotLimit`, `showsCount(pageCount:)`). The hourly row reaches 12 pages at AX5.
- **The repeat** (`sh.repeat@1`, `UKRepeatView`) pages through `UKServerUIPagedRow`, which owns this indicator. The document sets the page size (`paging.compact`/`regular`, scaled by text size), not the control.
- **Previous and next** (`paging.buttons`, regular width only) sit either side of the dots in the text ink, 44 pt, at 0.3 opacity with no page that way (the Studio's footer).
- HIG, Page controls: the indicator stays the one place that names the page. The buttons add a second route for pointer and keyboard use and never replace it.
- **Moves report back.** `UKPagedRowView` calls `onFirstVisibleChange` when a requested move settles, animated or a jump.
- Reduce Motion is read through `UKMotion.reduceMotion`, so a test can set it. The indicator, the buttons and the adjustable value then follow `page` after Next, a tap on a half, or a VoiceOver swipe.
- Consumers: `SuggestedRecipesCarousel` (Food), `WeatherPagedCarousel` (Weather sheet and the hourly and daily rows), and the repeat. A new carousel uses this component; never draw dots by hand.
- Tests: `PageIndicatorTests` (rules), `PageIndicatorTapTests` (hosted: one named 44 pt element; the macOS tree does not expose the adjustable value or take a click on it), `WeatherJourneyTests.testSheetCarouselScrolls` (device).
