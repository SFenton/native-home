# Layout recovery boundary

> **What:** what the server-driven root shows while no published layout is on screen: its four states, their actions, placement and words. **Read when:** you touch `UKServerUIRecoveryBoundary.swift`, the production host's recovery ground, or the boundary copy.

- Mockup: [server-ui-boundary](mockups/pages/shell/server-ui-boundary/server-ui-boundary.html). Words awaiting a pick: [server-ui-boundary-copy](mockups/proposals/server-ui-boundary-copy/server-ui-boundary-copy.html).
- Transport and cache: [architecture](../platforms/apple/architecture.md#server-driven-root).
- HIG: Loading, Feedback, Writing, Buttons, Alerts, Designing for iPhone Duo.

## When it shows

- Only while the root has no layout on screen. A last good layout stays on screen through every state below.
- After sign-in the sign-in layer holds until a layout commits or the first-load deadline passes (`awaitFirstLayout`), so the waiting state is seen only when the layout is late.

## States

`UKServerUIProductionHost.Boundary` picks one state from the publication's remote state and status.

| State | When | Glyph | Title | Try Again | Clear |
|---|---|---|---|---|---|
| Waiting | The subscription has not answered, or a published layout is being prepared | `arrow.down.circle` | Getting Your Layout… | no | no |
| Nothing published | Home Assistant answered and holds no layout | `exclamationmark.triangle` | No Layout Published | yes | no |
| Update | The published layout names a capability this build lacks | `arrow.down.app` | Update Required | no | no |
| Failed | The layout was rejected, or the first-load deadline passed | `exclamationmark.triangle` | Layout Unavailable | yes | yes |
| Failed, nothing to offer | The saved layout could not attach to the scene, or there is no store | `exclamationmark.triangle` | Layout Unavailable | no | no |

The messages are the strings in `UKServerUIRecoveryBoundary.swift`.

## Rules

1. **One component.** Each state is a `UKStateMessageView` ([state-message](../patterns/state-message.md)) on the backdrop's base colour, with no header, tab bar or wallpaper.
2. **Placement.** The state is centred in the space above the plain buttons. The column scrolls when large text makes it taller than the safe area.
3. **Hinge.** On a window with a hinge band the whole column sits in the leading region ([hinge-avoidance](../patterns/hinge-avoidance.md)). Lying flat it is centred.
4. **One prominent action.** Try Again is the only prominent button, and it shows only where a retry can help. The update state has none. While a retry runs the state stays up and the button shows its busy title, "Trying Again…" (`BoundaryCopy.tryingAgain`).
5. **Clear and Sign Out** are plain text buttons at least 44 pt tall, below the state. Clear shows only on the failed state. Sign Out shows on every state, because the boundary has no other way out.
6. **Both ask first** with an alert that has Cancel and a destructive confirming button ([alerts](../patterns/alerts.md)). Sign Out presents `AlertCopy.signOut`, and its failure presents `AlertCopy.signOutFailed(device:)`, which names "this iPhone" or "this iPad".
7. **No spinner and no skeleton.** The waiting state is a still glyph and words. When the deadline passes it becomes the failed state, which says what to do.
8. **A message names only the actions on screen.**
9. **Words.** The strings are compiled boundary copy (`UKServerUIProductionHost.BoundaryCopy` and `Boundary`, in `UKServerUIRecoveryBoundary.swift`; [copy](../patterns/copy.md#inline-or-slot)): never in the table, never a literal in the host. A visible progress title ends in `…`.
10. **Motion.** A change of state swaps the view in place with no animation.

## Identifiers and VoiceOver

| Element | Identifier | VoiceOver |
|---|---|---|
| The state | `server-ui.production.recovery` | The title is a heading, then the message; the glyph is hidden |
| Try Again | `server-ui.production.retry` | Its title |
| Clear | `server-ui.production.clear` | Its title |
| Sign Out | `server-ui.production.signOut` | Its title |

Reading order: title, message, Try Again, Clear, Sign Out.
