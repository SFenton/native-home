# Cold launch, signed out (flow)
> **What:** the launch ground, then the 1.2 s intro on the sign-in layer (glow, header, form), once per session; Reduce Motion cross-fades. **Read when:** you change the intro, `MotionTokens.Intro` or `MotionPolicy`.
- Mockup: [launch-cold-signed-out.html](launch-cold-signed-out.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/RootView.swift`, `Features/Login/LoginView.swift`, `SignInGround.swift`, `HassDesign/Motion/MotionTokens.swift`, `App/Motion/MotionPolicy.swift`
- Spec: `.agents/design/motion.md`, `.agents/design/direction-g.md`, `.agents/platforms/apple/auth.md` · Patterns: motion, telemetry
- States covered: ground at 0 s, glow 0.25 s, header 0.55 s, title rise 0.75 s, form rise 0.95 s, done 1.16 s, Reduce Motion (mid and end), AX5
- Motion: ground fade, the intro (sampled, token by token), the intro under Reduce Motion
- Devices: iPhone, Duo folded and unfolded, iPad
- Open notes: the mark's rise is hidden behind the header's opacity (code vs docs); a sign-out or an expired session replays the intro
