# SwiftUI Pro skill

> **What:** how this repo applies the vendored SwiftUI Pro skill. **Read when:** writing or reviewing any SwiftUI, or opening a PR that touches `apple/`.

The skill lives at [`.claude/skills/swiftui-pro`](../../.claude/skills/swiftui-pro/SKILL.md), vendored from [twostraws/swiftui-agent-skill](https://github.com/twostraws/swiftui-agent-skill) v2.0.0 (commit `f980071`, MIT, `LICENSE` beside it). Claude Code loads it from the repo, so every session in a checkout of `main` has `/swiftui-pro`. Other agents read `SKILL.md` and its `references/` directly.

## When to use it

| Moment | Do |
|---|---|
| Writing SwiftUI | Load the reference files for what you touch (views, data, navigation, accessibility, resizability) |
| Before opening a PR | Run `/swiftui-pro` on your diff; fix findings in your files, list the rest in the PR body |
| Reviewing a PR | Opus runs it as part of final review; a deprecated-API or accessibility finding is major |
| Deep performance work | Load `references/performance-plus.md` only for a requested or measured problem |

## Repo overrides

The skill's own rule is "check the deployment target first". Ours is **iOS 17 / watchOS 10**, Swift language mode 6.0, built with Xcode 27.1. Where the skill and the repo disagree, the repo wins:

| Skill rule | Here |
|---|---|
| iOS 26/27-only APIs (`ConcentricRectangle`, `safeAreaBar`, `ToolbarOverflowMenu`, `reorderable`, native `WebView`, `ForEach(x.enumerated())`) | Only behind `if #available`, with the iOS 17 path kept. Not a finding on its own |
| `Tab` API instead of `tabItem()` (iOS 18) | Required when the target reaches 18; until then `#available` or leave `tabItem` |
| Compiler-only rules (`@ContentBuilder`, `@Entry`, `alert(_:item:)`, `ForEach` in `toolbar`) | Apply: they back-deploy |
| One type per file | Applies to new files. Do not split existing files as a drive-by; do it in the owner lane |
| `@State` and `@Environment` properties are `private` | A view split by area into `View+Area.swift` extensions (Chores, 2026-10-30) drops `private` on the members its extensions read, since Swift `private` stays in one file. Keep `private` on anything one file uses; the type itself stays internal to `HassUI`. Cost: a non-private `@State` initial value (`TodoPageView`'s `TodoDraftStore`) is evaluated again on every parent rebuild, so keep class-valued state private where one file can own it |
| No computed `some View` helpers | Extract when a helper is reused or the body is long; small private helpers of one concern can stay |
| Shared constants enum for spacing, fonts, radii | That enum is `HassDesign` tokens. Extend it, never add a second one |
| Size-class layout, never device checks | Same as our `SplitPolicy` rule ([split-view](../design/apple/split-view.md)); iPhone stays portrait-locked |
| Prefer system sheets and `presentationDetents` | Present with `.sheet(item:)` and the detents in [modal-sheet](../patterns/modal-sheet.md). There is no shared sheet chrome type yet (see [audit/ui](../archive/audit/ui.md)) |
| Apple HIG | Still cite the HIG via the `apple-hig` skill; SwiftUI Pro does not replace it |

## House rules that came out of the code-consistency sweeps

- **No `Binding(get:set:)` in a body.** A control showing a controller's value uses `ControllerToggle`, `ActionToggle`, `ControllerStepper`, `ControllerPicker` or `ControllerBinding.make(_:send:)` (`HassDesign/ControllerControls.swift`). A presenter driven by an optional uses `$item.isPresent()`. A view's own state bound to another representation uses `Binding.projected(read:write:)` (an `HH:MM` string as a `Date`, a text field with a limit) or `Binding.contains(_:)` (one toggle per set member), named in a private computed property, not inline. A side effect of a change (Sleep forces Display off) goes in `.onChange`.
- **A button action that starts async work calls a named method** (`start()`, `apply()`), not an inline `Task`.
- **Weights, washes and states are tokens.** `HassTokens.Typography` (`sectionTitle`, `rowTitle`, `bodyEmphasis`, `footnoteEmphasis`, `captionEmphasis`) for the design's semibold styles, `HassTokens.Wash` for notice washes, `HassTokens.ControlState` for dimmed and pressed opacities, `HassTokens.Tint` and `Ink` for colours. Tone colours in views come from `Ink.success`, `warning`, `danger` and `error`, never `.green`, `.orange` or `.red`.
- **UIKit colours live in `Color.adaptive` / `HassTokens.Ink`.** A view file builds no `UIColor`; read a colour's components with `Color.resolve(in:)`.
- **Notices.** `InlineAlert` (warning, error) and `InfoBox` (success, neutral) are the only notice views ([info-box](../patterns/info-box.md)).
- **Empty and error states.** `StateMessage` / `CenteredStateMessage`; no `ContentUnavailableView` ([state-message](../patterns/state-message.md)).
- **Newer API behind availability.** `safeAreaBar` (iOS 26) for custom control bars, `toolbarBackgroundVisibility` and `toolbarVisibility` (iOS 18), each with the iOS 17 spelling in the other branch; `GlassEffectContainer` around neighbouring glass.
- **Grammar.** A count in a `Text` uses `^[\(n) item](inflect: true)`. A count built into a `String` spells out the singular (`n == 1 ? "sensor" : "sensors"`): the inflect markup is not resolved by `String(localized:)` in the host tests.

