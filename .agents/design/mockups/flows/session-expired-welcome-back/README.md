# Session expired, welcome back (flow)
> **What:** a refused token ends the session; the sign-in layer fades in as "Welcome back, <first name>" with the account read-only and only the password to type. **Read when:** you change `AppSession.sessionExpired`, the welcome back mode or Use a Different Account.
- Mockup: [session-expired-welcome-back.html](session-expired-welcome-back.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/AppSession.swift`, `RootView.swift`, `Features/Login/LoginModel.swift`, `LoginView.swift`, `LoginHeader.swift`
- Spec: `.agents/platforms/apple/auth.md`, `.agents/design/motion.md` · Patterns: motion
- States covered: rejected token, the layer swap, welcome back (finished, intro frame, working), wrong password, unreachable, use a different account, plain form, long-text, AX5
- Motion: layers cross-fade (0.35 s), intro again, failure appears (quick), different account (quick)
- Devices: iPhone, Duo folded and unfolded, iPad
- Open notes: the expiry replays the full intro and the next arrival (signOut resets MotionPolicy; undocumented); the window colour behind the fade is not confirmed
