# Kept text (component)
> **What:** a server-composed text slot showing its last answer while its source is unavailable (`sh.text-keep@1`): drawn and spoken exactly as live. **Read when:** you touch a text slot host or propose a staleness cue.
- Mockup: [kept-text.html](kept-text.html) · status shipped
- Source: `apple/Sources/HassCore/ServerUIComposition/ServerUITextKeep.swift`, `apple/Sources/HassUI/UIKitPort/ServerUI/UKServerUIBindings.swift`, `UKServerUIPage.swift`, `UKServerUIShellPrimitives.swift`, `UKServerUIStateTileViews.swift`, `apple/Sources/HassUI/UIKitPort/Gallery/UKTextKeepGallery.swift` · Spec: `.agents/design/kept-text.md` · Patterns: copy, entity-tile, status-pill
- States covered: live, kept (identical to live), before-answer (the fallback), reconnecting (keeps what was shown), recover, ax5
- Motion: none (kept and live are the same frame)
- Devices: iPhone, Duo folded, Duo unfolded portrait and landscape, iPad portrait and landscape
- Decision: the owner's option A, plain ([kept-text](../../../../kept-text.md); proposal `proposals/text-keep`)
- Open notes: the text node and row are local helpers (promote to kit); Duo unfolded poses and rotation were not captured (infra).
