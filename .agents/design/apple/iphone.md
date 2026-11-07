# iPhone

> **What:** iPhone navigation and presentation decisions. **Read when:** building any iPhone screen.

- **Portrait only** (owner, 2026-10-10): Info.plist `UISupportedInterfaceOrientations~iphone` is portrait; never add landscape layouts for iPhone.
- Tab bar with the web's primary nav (`routes.ts` `PRIMARY_NAV_ROUTES`): Home, Security, Climate, Chores and Settings, five tabs, Settings last (owner, 2026-10-16). SF Symbols replace MDI icons. One `TabView` on every system (the glass floating bar on iOS 26). Quick Links is a header button, not a tab (the trailing `Tab(role: .search)` and `CompactTabLayout` are gone).
- Header: every page, root or pushed, carries two trailing buttons 12 pt apart, Quick Links (`quickLinks.open`, a 44 pt glass circle) then Profile (`ProfileButton`: a 44 pt monogram disc that is the whole button, or the person symbol on glass until the name is known; badged with overdue chores plus expired food; `nav.profile`; owner 2026-10-18, option A, FestivalNativeApps parity, HIG Toolbars item groupings; details in [direction-g](../direction-g.md), Navigation). Profile opens the Account sheet, the web's Your Summary ([settings/ios.md](../../pages/settings/ios.md)).
- Owner, 2026-10-20 (supersedes the 2026-10-16 inlineLarge rule on iPhone): the hamburger (`nav.open`, `.topBarLeading`) is the leading-most bar item; Quick Links and Profile stay trailing; the title is the standard large title below the bar (`.automatic` from `pageChrome()`) and collapses to a centred inline title on scroll. `.inlineLarge` would take the leading slot and push the hamburger right, so it is kept only where there is no hamburger (Duo rail, compact iPad). **Superseded 2026-10-28 (owner: "Bring back the title collapse as well", then "left align the title again"):** the large title returns and collapses into the system's leading-aligned inline title right of the hamburger (`.toolbarRole(.browser)`); a brief "no large title" rule of the same day was reversed ([header-edge-fade R7](../../patterns/header-edge-fade.md) (3) to (5)).
- Web hash modals (`#lights-overview`, `#security-system`, cameras) become SwiftUI sheets with `.presentationDetents([.medium, .large])`; camera viewers use `.large` only.
- Respect safe areas with system layout; never hard-code notch or Dynamic Island insets (web safe-area contract).

## Hamburger (owner, 2026-10-20)

The leading Open Navigation button is back on iPhone (44 pt, VoiceOver "Open Navigation", hint "Opens the navigation menu"), opening the existing `NavigationFlyout`. Tab-bar accessories may follow. Quick Links and Profile stay two separate circles, 12 pt apart. See [direction-g](../direction-g.md).
