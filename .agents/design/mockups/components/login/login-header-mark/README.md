# Sign-in header: mark, name, line (component)
> **What:** the house-and-heart mark, "S+H" and one line, or the welcome back monogram, title and line. **Read when:** you change `LoginHeader`, `SignInMark`, `SignInMonogram` or `HouseHeartShape`.
- Mockup: [login-header-mark.html](login-header-mark.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Login/LoginHeader.swift`, `SignInMark.swift`, `SignInMonogram.swift`, `apple/Sources/HassDesign/HouseHeartShape.swift`
- Spec: `.agents/platforms/apple/auth.md`, `.agents/design/direction-g.md`, `.agents/platforms/apple/live-activities-per-job.md` (section 8, corner mark) · Patterns: motion
- States covered: fresh, welcome back (with and without initials), the mark in all eight icon colours, the transparent ring on three grounds, AX5
- Motion: mark spring (0.86 to 1.03 to 1) and monogram spring, each with its Reduce Motion path
- Devices: size classes only (iPhone, iPad)
- Open notes: in the real screen the header's opacity hides the mark's rise; the SVG is a stand-in for the Shape (same 100-unit coordinates)
