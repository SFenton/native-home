# Push and pop within a section stack (flow)

> **What:** A page pushed under a section root and back, with the header buttons kept. **Read when:** you touch a navigationDestination, HomeRoute or pageChrome.

- Mockup: [push-pop-navigation.html](push-pop-navigation.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/MainTabView.swift`, `apple/Sources/HassUI/Features/Home/HomeRoute.swift`, `apple/Sources/HassUI/App/Shell/ShellHeader.swift`
- Spec: `.agents/design/motion.md`, `.agents/patterns/motion.md`, `.agents/design/apple/iphone.md`, `.agents/design/direction-g.md` · Patterns: motion, header-edge-fade, page-backdrop
- States covered: root, push, pushed-page-keeps-header-buttons, swipe-back, pop-back, popped, long-title, ax5
- Motion: system push, pop, interactive swipe back, content in the first frame
- Devices: iPhone, folded Duo, unfolded Duo landscape, iPad (both)
- Open notes: Pop and ZoomClose signposts are not recorded yet. Mid-transition states are static compositions.
