# Sheet bottom gap

> **What:** why a content-fitted sheet no longer leaves an empty band under its last control, chosen 2026-10-28 (option B, "fit to content"). **Read when:** touching `SheetFit`, `SheetChrome` or a sheet's bottom padding, or asking why a fitted sheet is 34 pt shorter than its detent.

Proposal: [sheet-bottom-gap.html](mockups/proposals/sheet-bottom-gap/sheet-bottom-gap.html) (also in the [hub](mockups/README.md)). It compared today (A), fit to content (B) and a 17 pt margin (C); **B** is the decision.

## The bug

`hassSheet()` fitted sheets asked the system for a custom detent of `content + header + bottom inset`, and the bottom inset included the home-indicator safe area. UIKit measures a custom detent up from the bottom safe area and adds that area itself, so the safe area was counted twice: a detent `D` is a sheet `D` plus the safe area tall. Measured 2026-10-28 with the sheet probe (`FENTON_SHEETFIT_PROBE=1`): the page's scroller had 34 pt more viewport than content on an iPhone 17 Pro and the folded iPhone Duo (iOS 26.5 to 27.1) and 20 pt more on an iPad in portrait, and the last control floated that far above the home-indicator area.

## The decision (owner, option B)

- The detent is `content + header + whatever lies below the content beyond the bottom safe area` (`SheetFit.wantedHeight(contentHeight:topInset:bottomInset:systemBottomInset:)`, `SheetFit.bottomBeyondSafeArea`). The safe area is the window's (`LargeDetent.bottomSafeArea()`: 34 on iPhone and the folded Duo, 20 on iPad), set on the model as `systemBottomInset`. A pinned bar or any other inset beyond the safe area stays in the detent.
- `SheetChrome.bottom` is that same remainder, normally 0, so a predicted camera sheet (`chrome.top + predicted + chrome.bottom`) agrees with a measured one. The fallback chrome's bottom is 0.
- The page area (`setSheetHeight`), `isCutShort` and `maxSheetHeight` keep their measure (above the bottom safe area) and now agree with the detent exactly: a sheet that got what it asked for reads its detent.
- Stored values from older builds are not reused: `sheetFit.heights.v1` and `sheetChrome.v1` became `v2` (a `v1` height would reopen 34 pt too tall and then move), and the old tables are deleted at launch and by `SheetMemory.clearAll()`.
- iPad needed the same rule: its fitted form and page sheets are custom-detent sheets too in portrait (hosting view 456 for a 436 detent). In landscape the centred sheet has no bottom safe area (the page reads 0), so nothing changes there.
- Debug only: `FENTON_SHEETFIT_LEGACY=1` draws the old detent so one build can be measured both ways (`SheetBottomGapJourneyTests`).

## Measured (probe, 2026-10-28; detent before, after)

| Sheet | iPhone 17 Pro | Folded iPhone Duo | iPad Pro 11 portrait |
|---|---|---|---|
| Camera viewer, Front Door | 517, 483 | 565 (pinned at 554, cut short), 523 (fits) | 760, 741 |
| Camera viewer, Driveway | 351, 317 | 369, 335 | 436, 416 |
| Last control to the window's bottom edge (Front Door) | 88 pt, 56 | 81, 58 | 63, 44 |
| Quick Links, tiles: last tile to the bottom edge | 89, 56 | 92, 58 | 63, 43 |

The proposal's folded Duo Front Door estimate (about 531) used the pinned sheet's 82 pt header; unpinned the header is 74 and the detent 523.

## Rules this adds

- A fitted sheet's last control sits one page padding above the home-indicator area; a journey asserts the gap (`SheetBottomGapJourneyTests`, `testQuickLinksFitsThePageOnTop`) and that the page's scroller holds no more viewport than content.
- Anything that stores or predicts a sheet height stores the detent in this measure; change the measure, change the storage key.
