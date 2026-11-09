# Sign in, fresh and welcome back (page)
> **What:** the sign-in root layer a signed-out phone shows, in every state the code draws, on iPhone, Duo and iPad. **Read when:** you change `LoginView`, its copy, errors or intro, or need the sign-in look for another mockup.
- Mockup: [login.html](login.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/Features/Login/` (LoginView, LoginModel, LoginHeader, LoginFields, LoginRow, LoginFailureCard, LoginInlineError, LoginCopy, SignInGround, SignInStyle, SignInMark, SignInMonogram), `HassDesign/HouseHeartShape.swift`, `App/RootView.swift`
- Spec: `.agents/platforms/apple/auth.md`, `.agents/design/direction-g.md` ("Sign-in"), `.agents/design/motion.md` · Patterns: motion
- States covered: default, filled, username-remembered, loading (working), welcome-back (+ filled, error), error (wrong password), offline (unreachable card, Details expanded), failed, two-step, intro frames (0, 0.6, 0.9 s), long-text, ax5; refreshing, empty and reconnecting are explained in notes
- Motion: intro, intro under Reduce Motion, press and working, wrong password, failure card, Details chevron; transitions: launch ground, Sign In to Home, welcome back to fresh
- Devices: iPhone, Duo folded, Duo unfolded (both), iPad (both); the form is a column of at most 460 pt
- Helper for the whole batch: [`../_login-launch-flows.js`](../_login-launch-flows.js) (not kit; promote candidates listed in the notes)
- Open notes: the intro mark's rise is hidden by the header's opacity (docs say it springs in first); the sign-in layer is not hinge-aware on the unfolded Duo; split-view.md still calls sign-in a modal
