# S+H native: agent entry point

> **What:** product and architecture invariants, the roles, the rules router. **Read when:** first; then [.agents/README.md](.agents/README.md) and [PROGRESS.md](PROGRESS.md).

## Invariants

- **Name.** People see **S+H**; bundle ids, groups and the `mobile_app` registration keep their technical names ([app-name](.agents/platforms/apple/app-name.md)).
- **Targets.** iPhone, iPhone Duo, iPad, Watch, widgets, Live Activities. macOS is not a target: add no macOS code, `#if os(macOS)`, destination, scheme, CI job or test step, and never extend what exists. `Package.swift` keeps `.macOS` only as the `swift test` host. Layout stays geometric, keeping a Mac target possible.
- **Native.** The iOS and iPadOS app is UIKit ([uikit-port](.agents/platforms/apple/uikit-port.md)). SwiftUI serves only widgets, Live Activities, watchOS and `HassDesign`. The only WebView is the full-screen Home Assistant settings modal.
- **Source of truth.** Home Assistant owns state and automation. The app signals intent through `HassConnection.callService`, shows optimistic state only for feedback, never duplicates automation logic. Agents change the live server only via `tools/ha_change.py` ([ha-operations](.agents/platforms/apple/ha-operations.md)).
- **One state path.** Entity reads go through `EntityStore`, connections through `HassConnection`. No second websocket, no REST polling.
- **Main thread.** A live change to one entity costs one box update; the full-state diff runs off it; a scrolling page writes no state per frame ([performance](.agents/testing/apple/performance.md)).
- **No reload.** Views bind to per-entity boxes updated in place; a reconnect or cold launch never blanks, re-fades or reorders a screen ([connection-lifecycle](.agents/platforms/apple/connection-lifecycle.md)).
- **Layering.** `HassCore` (no UI) sits below `HassDesign` (UI over values and closures, never `EntityStore`), below `HassUI`. All form factors share Core and Design; phone and tablet share `HassUI`. Differences live in layout policies, never forked screens.
- **Layout.** iPhone is portrait-locked; Duo and iPad rotate. Folded and portrait windows are single-page; wide landscape may split. `SplitPolicy` decides by geometry, never device ([split-view](.agents/design/apple/split-view.md)).
- **Sign-in.** Users sign in through Home Assistant's login flow; only the refresh token persists, in Keychain ([auth](.agents/platforms/apple/auth.md)).
- **Design authority.** Every UI decision cites its Apple HIG section; HIG wins over web parity, the departure recorded. The React dashboard `SFenton/ha-sfenton-react-dash` defines behavior and entity IDs: read it, never edit it, cite `repo@sha:path:line`.
- **Pattern first.** A behavior on several screens has one record in [patterns](.agents/patterns/README.md) and one canonical component. Extend it; sweep its consumers.
- **Mockup atlas.** Every surface has a current mockup for iPhone, Duo and iPad ([mockups](.agents/design/mockups/README.md)). Look it up before a change, update it in the same change, publish only through the hub ([mockup-hub](.agents/skills/mockup-hub/SKILL.md)).
- **Tests and docs.** New logic ships with unit tests; a UI change with a UX and an accessibility test per affected family, each written for all three families. Certification needs 95% logic and UX line coverage ([testing](.agents/testing/apple/README.md)). Swift carries DocC `///` and `// MARK: -` regions.

## Roles

Each role's file in `.claude/agents/` holds its scope and model; contracts: [agent-roster](.agents/workflow/agent-roster.md).

| Role | Job |
|---|---|
| Orchestrator | Plans and dispatches |
| Researcher | Sourced notes |
| Designer | Judges visible choices |
| Coder | Code and tests |
| Verifier | Device evidence |
| Reviewer | Independent review |
| Steward | Post-mortems |
| Menial | Re-runs and chores |

## Rules router

| Read | When |
|---|---|
| [autonomy](.agents/workflow/autonomy.md) | Levels; owner-only decisions |
| [change-loop](.agents/workflow/change-loop.md) | Any code change; rung 0 |
| [propose-first](.agents/workflow/propose-first.md) | A visible change |
| [pr-lifecycle](.agents/workflow/pr-lifecycle.md) | Worktrees, review, merging |
| [ci](.agents/workflow/ci.md), [versioning](.agents/workflow/versioning.md) | Checks, releases |
| [token-economy](.agents/workflow/token-economy.md) | Waiting, models, capacity |
| [security](.agents/workflow/security.md) | House data, credentials |
| [eval-gate](.agents/workflow/eval-gate.md), [jev](.agents/workflow/jev.md) | Changing agents, hooks, tools |
| [triage-agent](.agents/workflow/triage-agent.md) | Headless sessions |
| [docs-conventions](.agents/workflow/docs-conventions.md) | Editing rules |
