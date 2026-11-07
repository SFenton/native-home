# Navigation flyout drawer (component)

> **What:** The full-height overlay drawer for regular width and the iPhone menu button. **Read when:** you touch NavigationFlyout, ShellNavigator or the menu button.

- Mockup: [navigation-flyout.html](navigation-flyout.html) · shipped (full-height drawer, dimmed top safe area and iPhone edge swipe are on main, #140) · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/Shell/NavigationFlyout.swift`, `apple/Sources/HassUI/App/Shell/ShellNavigator.swift`, `apple/Sources/HassUI/App/Shell/AppSection.swift`
- Spec: `.agents/design/apple/ipados.md`, `.agents/design/direction-g.md`, `.agents/design/apple/iphone.md` · Patterns: motion, header-edge-fade
- States covered: open, badge-on-chores, selected-settings, ax5, closed, panel alone
- Motion: slide and scrim on standard 0.3 s (Reduce Motion: quick cross-fade); three transitions
- Devices: iPhone, iPad portrait, unfolded Duo portrait (no drawer on the folded Duo or in unfolded landscape: vertical bar, no menu button)
- Open notes: direction-g.md still says the edge swipe is off on iPhone; the code enables it. The kit draws the material with CSS blur.
