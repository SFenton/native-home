# Scroll fit (component)
> **What:** the app-wide rule "scroll only when there is something to scroll": a vertical scroller whose content fits is static (no bounce, no drag response, no indicator), one that overflows scrolls normally, a pull-to-refresh list always bounces. **Read when:** you add a page, sheet or list, change a text-size or window behavior, or add `.refreshable`.
- Mockup: [scroll-fit.html](scroll-fit.html) · status shipped (#152, owner decision 2026-10-24) · reviewed 2026-10-24
- Source: `apple/Sources/HassUI/App/MainTabView.swift`, `HassDesign/HassModal.swift`, `HassDesign/SheetFit.swift`, `HassDesign/ScrollFit.swift` · Spec: `.agents/patterns/scroll-fit.md`, `.agents/patterns/modal-sheet.md` · Patterns: modal-sheet
- States covered: short page (Special Device Modes) and long page (Home); short fitted sheets (Security System, camera viewer), a tall one (Recipe filters), the capped-at-large case (filters at AX5) and Weather; a short and an overflowing picker list; pull-to-refresh Inventory
- Measured, not drawn: every device shows a badge computed from the rendered content height against the viewport (`Static · fits (content 612 pt ≤ viewport 780 pt)` or `Scrolls · overflows by 148 pt`), a scroll indicator only on a scroller that scrolls, and the Home chip rail as the horizontal exclusion
- Matrix: the nine surfaces by six windows by default and AX5 text, from the same measurement (click a cell to open it); plus three side-by-side flips
- Motion: drag demos (scrolling stretches and springs back, static does nothing, pull to refresh shows the spinner); Reduce Motion holds an outline instead of travelling
- Devices: all six windows
- Kit: adds `Mock.scrollFit` (`_kit/lib/chrome.js`) and the `scrollFit` and `sections` options of `Mock.mount`
- Open notes: Expired food (also refreshable) is a tab in the Summary sheet and is represented by Inventory; page content counts the space under the floating tab bar, as SwiftUI does
