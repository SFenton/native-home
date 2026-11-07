# Sign-in form parts (component)
> **What:** the fields module, failure card, inline error, Sign In capsule and ground of the sign-in screen, on the sign-in ground. **Read when:** you change `LoginFields`, `LoginRow`, `LoginFailureCard` or `LoginInlineError`.
- Mockup: [login-form-parts.html](login-form-parts.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Login/LoginFields.swift`, `LoginRow.swift`, `LoginFailureCard.swift`, `LoginInlineError.swift`, `SignInGround.swift`, `SignInStyle.swift`
- Spec: `.agents/platforms/apple/auth.md`, `.agents/design/direction-g.md` · Patterns: motion
- States covered: fields (fresh, filled, welcome back, working, wrong, long), failure card (collapsed, expanded, failed), inline errors, capsule (disabled, enabled, working, Try Again), ground and glow, AX5
- Motion: Details chevron (quick), fields dim (quick), glow up (0.5 s)
- Devices: size classes only (iPhone, iPad): the column is 412 pt on a regular width
- Open notes: LoginRow uses onTapGesture to focus its field; drawn on the glow because the thin module needs it; local helper `Mock.LL` (promote to kit)
