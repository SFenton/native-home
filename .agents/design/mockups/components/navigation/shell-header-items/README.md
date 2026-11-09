# Header: menu button, Quick Links and Profile (component)

> **What:** The header buttons per window: two circles, the Duo rail group, material circles before iOS 26. **Read when:** you touch ShellHeaderItems, ShellHeaderGrouping or ShellChrome.

- Mockup: [shell-header-items.html](shell-header-items.html) · shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/Shell/ShellHeader.swift`, `apple/Sources/HassUI/App/Shell/ShellHeaderGrouping.swift`, `apple/Sources/HassUI/Features/Rooms/QuickLinksSheet.swift`
- Spec: `.agents/design/direction-g.md`, `.agents/design/apple/iphone.md`, `.agents/design/apple/duo.md`, `.agents/design/apple/ipados.md` · Patterns: header-edge-fade
- States covered: iphone, duo-vertical-rail-one-glass-group, ipad-with-menu, pre-ios26-material-circles, title-styles, grouping, ax5, kit swatches
- Motion: title collapse (system); three sheet or overlay transitions
- Devices: iPhone, folded Duo, unfolded Duo (portrait: the iPhone header; landscape: the vertical bar), iPad (portrait, landscape)
- Open notes: A compact iPad window (no menu, inline-large title) is not drawn. The owner's "Header buttons" canvas could not be read as a page; the mockup follows code and docs.
