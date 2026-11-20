# A page may hide the tabs and header buttons for itself

Decision: for marking what is global (pick 4), options A, B and C were judged: A with the owner's per-page hide is picked. A is the Show row on each chrome item ("Every page" or "First page only"); the owner picked it and added that a page can hide any chrome item for itself. Option B, a separate "Global" switch, lost because it adds a word that needs explaining and a second control that can disagree with Show. Option C, nothing to mark, lost because it is not configurable, which the owner asked for.
This change lands the native half of the per-page hide: `pages[].hides { tabs, items }` (`sh.page-chrome-hide@1`) and `navigation.tabsVisibility: root-only` (`sh.tabs-visibility@1`). The Studio's "Hide on this page" group is its own lane.
Replaces: none
Rule home: .agents/patterns/page-base.md
Gate: matches_request=yes. The owner chose it (pick 4 of `build/decisions/parity-loop.md`: "A, but another option on individual pages to hide any chrome element/elements if the user wants"); the rules are section 2 of `build/design/global-chrome/proposal.md`.

## Options judged

- A, the Show row, with a per-page hide. Won: the owner's pick. One control that already exists says what global means without the word, and a page overrides it only by hiding.
- B, a "Global" switch beside Show. Lost: a second control that can disagree with the first.
- C, nothing to mark, all app chrome global. Lost: not configurable.

## The rule as built

- Hide only. A page cannot show what the app sets to the first page only; an item is hidden when either says so (`ServerUIChromeHide`).
- Back and a sheet's Close are not chrome and are never hidden. The shell menu's id is refused by the compiler.
- Where the window shows columns there is one bar, and the page opened last decides, the same page that decides in a narrow window.
- The tab navigator hides and returns alongside the push and Back with the system bar animation (`UITabBarController.setTabBarHidden(_:animated:)`). Under Reduce Motion it is not animated.
- On the Duo's vertical bar the rail stays with the status and Back; only its tabs and its Quick Links and Profile group leave.

## HIG

- Tab bars: "Keep the bar visible between sections (a temporary, self-contained modal may cover it)". Hiding the tab navigator on a page is the author's departure, chosen by the owner. The Studio check for a tab's first page that hides Tabs names the one case that strands the person.
- Toolbars: "The standard Back button retraces an information hierarchy and Close dismisses a modal". Back and Close stay on every page that hides chrome, so the way out is always there.
- Accessibility: "When Reduce Motion is on, reduce automatic and repetitive animation". The bar changes with no slide.

## Checks

- Unit (`ServerUIChromeHideTests`) and hosted (`ServerUIChromeHideHostedTests`, `ServerUIChromeHideGalleryCaseTests`) on iPhone, iPhone Duo and iPad: each of tabs, items, both, root-only and columns; push and Back restore; a cancelled Back swipe; Reduce Motion; a sheet untouched; hidden items absent from the accessibility tree and Back present.
- Verifier pose matrix at 262c787e, 210 stills: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape, default and AX5, Reduce Motion on iPhone and iPad landscape. Every end state matches the rules above. The slide itself is asserted by the hosted tests, not seen in stills.
- Atlas: `components/navigation/tab-bar`, state `page-hides-chrome`, on all three families.
