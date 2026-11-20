# Floating tab bar (component)

> **What:** The five-tab bar: glass capsule on iPhone, the same capsule on the unfolded Duo in portrait, vertical bar on the folded Duo and in unfolded landscape (owner, 2026-10-26), at the top of the window on iPad. **Read when:** you touch MainTabView tabs, AppSection or the Chores badge.

- Mockup: [tab-bar.html](tab-bar.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/UIKitPort/ServerUI/UKServerUIRenderer.swift`, `apple/Sources/HassUI/UIKitPort/ServerUI/UKServerUIChrome.swift` (the publication authors the layout)
- Spec: `.agents/design/direction-g.md`, `.agents/design/apple/iphone.md`, `.agents/design/apple/duo.md`, `.agents/design/motion.md` · Patterns: motion
- States covered: in-context (iPhone, folded Duo, unfolded Duo portrait, iPad), each tab selected, badge, vertical, chores-with-badge, ax5, page-hides-chrome (a page that hides the tabs, Quick Links and Profile)
- Motion: tab cut, badge update
- Devices: iPhone, folded Duo, unfolded Duo portrait, iPad portrait; page-hides-chrome adds unfolded Duo landscape
- Hiding: a page whose document sets `hides.tabs`, or a document with `tabsVisibility: root-only`, shows no tab navigator while it is on top; `hides.items` drops header buttons. Back and a sheet's Close stay; on the Duo's vertical bar Back is in the rail. The bar hides and returns with the push and Back (system animation, no slide under Reduce Motion).
- Open notes: The system speaks the badge after the tab name; "N overdue" is the flyout row's label only. Bar labels do not scale at AX5.
