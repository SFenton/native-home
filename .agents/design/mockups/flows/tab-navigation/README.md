# Tab navigation (flow)

> **What:** Switching sections, re-tapping the selected tab, and the Chores badge. **Read when:** you touch MainTabView, ShellNavigator.reselect or ScrollToTop.

- Mockup: [tab-navigation.html](tab-navigation.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/MainTabView.swift`, `apple/Sources/HassUI/App/Shell/ShellNavigator.swift`, `apple/Sources/HassUI/App/Shell/ScrollToTop.swift`
- Spec: `.agents/design/motion.md`, `.agents/design/direction-g.md`, `.agents/design/apple/iphone.md`, `.agents/design/apple/duo.md` · Patterns: motion, header-edge-fade
- States covered: home, tab-cut, pushed-on-home, re-tap-pops-to-root, second-tap-scrolls-top, at-top, chores-badge, chores-badge-none, duo-folded-rail, ax5
- Motion: tab cut, re-tap pop, scroll to top; three transitions
- Devices: iPhone, folded Duo, iPad portrait, unfolded Duo (portrait and landscape)
- Open notes: Regular width shows the flyout row instead of the bar. motion.md says scrollTo; the code uses setContentOffset(animated:).
