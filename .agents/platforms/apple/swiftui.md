# SwiftUI

> **What:** the repo's rules for the SwiftUI that remains (HassDesign's views, the widget extension, Live Activities, the Watch app), and where they override the `swiftui-pro` skill. **Read when:** writing or reviewing any SwiftUI.

The skill lives in `.claude/skills/swiftui-pro`. Run it on every SwiftUI diff ([change-loop](../../workflow/change-loop.md)); a deprecated-API or accessibility finding is major. Where the skill and this file disagree, this file wins. The deployment targets and the Swift language mode are in `apple/Package.swift`.

## Repo overrides

| Skill rule | Here |
|---|---|
| APIs newer than the deployment target | Only behind `if #available`, with the deployment-target path kept. Using the older API is not a finding on its own. |
| Compiler-only features that back-deploy | Apply. |
| One type per file | Applies to new files. An existing file is split in a change that owns it, never as a drive-by. |
| `@State` and `@Environment` properties are `private` | Private wherever one file uses the property. A view split across extension files drops `private` only on the members its extensions read; class-valued state stays private in one file. |
| No computed `some View` helpers | Extract a view when a helper is reused or the body is long; a small private helper of one concern may stay. |
| A shared constants enum for spacing, fonts and radii | That enum is `HassTokens` in HassDesign ([design-tokens](../../patterns/design-tokens.md)). Extend it; never add a second one. |
| Size-class layout, never device checks | Layout follows the geometric `SplitPolicy` ([split-view](../../design/apple/split-view.md)). |
| System sheets and `presentationDetents` | Present with `.sheet(item:)` and the detents in [modal-sheet](../../patterns/modal-sheet.md). |
| Design guidance | The HIG is still cited through the `apple-hig` skill; this skill does not replace it. |

## House rules

- **No `Binding(get:set:)` in a view body.** A binding to another representation of a view's state is a named private computed property or a `Binding` extension. A side effect of a change goes in `.onChange`.
- **A button action that starts async work calls a named method,** never an inline `Task`.
- **Weights, washes and states are tokens** from `HassTokens`. Tone colours come from its ink tokens, never a literal system colour.
- **A view file builds no `UIColor`.** Adaptive colours come from `Color.adaptive` and the ink tokens.
- **Notices** use the two notice views of [info-box](../../patterns/info-box.md) and no other.
- **Empty and error states** use [state-message](../../patterns/state-message.md), never `ContentUnavailableView`.
- **Newer API sits behind availability,** with the deployment-target spelling in the other branch.
- **Counts.** A count in a `Text` uses inflection markup; a count built into a `String` spells out the singular and the plural.
