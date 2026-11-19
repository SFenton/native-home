# The iPad shows its tabs in the system top tab bar

Decision: (1) VoiceOver order of the iPad top bar, options A, B and C were judged: A is picked, keeping the system order (Back, title, Quick Links, Profile, then the tabs). Option B, reordering the tab controller's view, lost because the tabs still read after the circles. Option C, hand-building accessibilityElements on the private navigation-bar container, lost because it overrides system containers that can break on any update.
(2) The bar is at the top in portrait too, because the system places it there in any regular-width iPad window (the owner said "whichever the modern system design is"). The items are system-drawn at 36 pt, 41 pt from AX3.
Replaces: none
Rule home: .agents/design/apple/ipados.md
Gate: matches_request=yes. The owner chose the system tab bar at the top (pick 3 of `build/design/global-chrome/proposal.md`, section 1); the reading-order pick is the Designer's and is recorded below.

## Options judged

- A, keep the system order. Won: HIG, Tab bars (iPadOS) and Accessibility (VoiceOver) favour system components with their native behaviour. The layout order is Back or Close, title, tabs, Quick Links, Profile; VoiceOver reads Back, title, Quick Links, Profile, then the tabs. The system tab bar (`_UITabContainerView` > `_UIFloatingTabBar`) sits outside the navigation bar's platter that holds Back, the title and the two circles, so the tabs follow them. The spec's order is amended to the system's.
- B, reorder the tab controller's view. Lost: the tabs still read after the circles, so it adds custom code and does not reach the spec order.
- C, hand-build `accessibilityElements` on the private navigation-bar container. Lost: it overrides system containers that can break on any OS update.

## Placement and size

- Portrait and landscape both get the top bar: the system draws tabs at the top in any regular-width window and at the bottom when compact (HIG, Tab bars, iPadOS). The app has no placement code; `ShellNavigationStyle.resolve(isRegularWidth:hasHinge:)` only drops the menu button and the flyout edge swipe.
- The items are system-drawn: 36 pt at default text and 41 pt from AX3, under the 44 pt target. The labels grow up to AX3 and stop; the page title truncates first.

## Checks

- Hosted, on iPhone, iPhone Duo and iPad (`ServerUITopTabBarHostedTests`): the bar is never hidden and in `.tabBar` mode, no menu item and no edge swipe on regular width, the menu stays on compact, the flyout is hidden from accessibility only with the top bar.
- Verifier pose matrix on fixtures: the tab bar is a `toolbar` to XCUITest with `tab-*` buttons; the order read in the tree is the one recorded above. Real VoiceOver is the owner's check.
