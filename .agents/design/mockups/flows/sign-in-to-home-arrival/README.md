# Sign-in to Home arrival (flow)
> **What:** the 0.9 s arrival after Sign In: the layer lifts, the backdrop settles, the header, chips, cards and tab bar come in; once per session. **Read when:** you change `HomeArrival`, `ArrivalMotion`, `ArrivalChromeProbe` or the arrival tokens.
- Mockup: [sign-in-to-home-arrival.html](sign-in-to-home-arrival.html) · status shipped · reviewed 2026-10-23
- Source: `apple/Sources/HassUI/App/RootView.swift`, `App/Motion/HomeArrival.swift`, `ArrivalMotion.swift`, `ArrivalKind.swift`, `App/Shell/ArrivalChrome.swift`, `Common/HouseBackdrop.swift`
- Spec: `.agents/design/motion.md`, `.agents/design/direction-g.md`, `.agents/platforms/apple/auth.md` · Patterns: motion, content-gate
- States covered: six frames sampled from the real tokens (0 to 0.9 s), first run (pending bars), Reduce Motion, AX5
- Motion: the whole arrival plus each piece alone (layer lift, backdrop, header, chips, cards, tab bar) and the Reduce Motion cross-fade
- Devices: iPhone, Duo folded and unfolded, iPad
- Open notes: call sites use 16 pt and an index cap of 5; `MotionTokens.arrivalRise` (8) and `arrivalStaggerCap` (8) are unused and motion.md quotes them; the Cameras header does not animate
