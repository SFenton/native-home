# Back is the system chevron with no title

Decision: A, ship plain `.minimal`. Every page sets `navigationItem.backButtonDisplayMode = .minimal`, so Back is the system chevron alone; VoiceOver says "Back" and the long-press menu lists the page titles. Options judged: A, plain `.minimal` and accept the system's spoken "Back"; B, set the label on UIKit's private BackButton view to keep the previous title; C, drop `.minimal` (default title or a generic "Back" title). The owner picked system Back with no title (pick 6 of `build/design/global-chrome/proposal.md`, section 4).
Replaces: none
Rule home: .agents/patterns/page-base.md
Gate: matches_request=yes. The owner chose the option; the Designer's HIG reading below only records why it is allowed.

## Options judged

- A, plain `.minimal`. Won: it is exactly the system control the owner picked. HIG, Navigation bars: the standard Back button retraces the hierarchy and a bar stays uncluttered when its controls use standard symbols without text. On the glass bars the chevron sits in its own circle and leaves room for a long title at every text size, including AX5 beside two circles. Cost, measured on iOS 27 on iPhone: the system names a minimal Back "Back", not the previous page's title, so the proposal's claim that the label keeps the previous title was wrong.
- B, set the label on UIKit's private BackButton view. Lost: it reaches into UIKit internals that any OS update can break.
- C, drop `.minimal` (the previous title beside the chevron, or a generic "Back" title). Lost: it contradicts pick 6; a long previous title also makes the system shorten or drop it, so the bar changes shape from page to page.

The proposal's section 4 fallbacks were tried and do not restore the name: a previous-page `backBarButtonItem` with an empty title and the label "<title>, Back", `backButtonTitle`, and an item titled with the page name (which also draws the title and breaks `.minimal`).

## What the app draws

Nothing. Back is the system component; the app sets only the display mode, once, in `UKPageViewController.viewDidLoad`. No page sets `backButtonTitle`, `backBarButtonItem` or its own mode, so a subclass inherits it.

## Checks

- Hosted, on iPhone, iPhone Duo and iPad: the mode is `.minimal` on each page class the test can build, a class list guard names every subclass of the page base, and the composed server page is checked through a renderer fixture.
- Accessibility journey, same families, default size and AX5: the pushed page's `BackButton` is a button that speaks "Back" with no title beside it. On the folded Duo the rail's Back has no label with or without this change (measured with the default title too); that gap is not part of this pick.
- The long-press menu is system-owned and has no public read; the previous pages keep their titles, which is what it lists.
