# Agent knowledge router

> **What:** the entry map for `.agents`. **Read when:** always, right after [AGENTS.md](../AGENTS.md); jump straight to the one file your task needs.

## By task

| Task | Read |
|---|---|
| Port or change a page | [pages](pages/README.md), then `pages/<id>/spec.md`; [port-page](skills/port-page/SKILL.md) |
| Add or change a control | [add-control](skills/add-control/SKILL.md) |
| Touch shared behavior | [patterns](patterns/README.md) |
| Restyle a surface; the app icon | [direction-g](design/direction-g.md), [its plan](design/direction-g-plan.md) |
| See how a surface looks and moves | [mockups](design/mockups/README.md) |
| A visible choice | [propose-first](workflow/propose-first.md), [design-decision](skills/design-decision/SKILL.md) |
| Write or review SwiftUI | [swiftui](platforms/apple/swiftui.md) and the `swiftui-pro` skill |
| Fix a reported issue | [fix-reported-issue](skills/fix-reported-issue/SKILL.md) |
| The issue form, the request repo, headless sessions | [feedback](pages/settings/feedback.md), [triage-agent](workflow/triage-agent.md) |
| Sign-in, tokens, Keychain | [auth](platforms/apple/auth.md) |
| Websocket, backgrounding, caching | [connection-lifecycle](platforms/apple/connection-lifecycle.md) |
| Location and device sensors | [location](platforms/apple/location.md), [its screen](pages/settings/location.md) |
| Changing the live Home Assistant | [ha-operations](platforms/apple/ha-operations.md) |
| Push notifications | [push](platforms/apple/push.md) |
| The shared `mobile_app` registration | [mobile-app](platforms/apple/mobile-app.md) |
| Decide what tests to write | [strategy](testing/apple/strategy.md) |
| Run tests on iPhone, Duo, iPad | [devices](testing/apple/devices.md) |
| Versions and release notes | [versioning](workflow/versioning.md) |
| TestFlight, privacy manifests | [testflight](platforms/apple/testflight.md) |
| A red or queued check, the nightly run | [ci](workflow/ci.md) |
| Levels, the owner-only set, house data, credentials | [autonomy](workflow/autonomy.md), [security](workflow/security.md) |
| Edit these docs | [docs-conventions](workflow/docs-conventions.md) |

## By platform

| Form factor | Design |
|---|---|
| iPhone | [iphone](design/apple/iphone.md) |
| iPadOS | [ipados](design/apple/ipados.md), [split-view](design/apple/split-view.md) |
| iPhone Duo | [duo](design/apple/duo.md) |
| watchOS | [watchos](design/apple/watchos.md) |

Architecture for all of them: [architecture](platforms/apple/architecture.md).

## Folders

| Folder | Holds |
|---|---|
| [workflow/](workflow/README.md) | The process rules, one home each |
| [design/](design/README.md) | Per-platform HIG decisions and screen classification |
| [platforms/](platforms/README.md) | Architecture, auth, connection lifecycle, build and run |
| [pages/](pages/README.md) | One folder per web route: `spec.md` and per-platform notes |
| [patterns/](patterns/README.md) | Cross-screen behavior with one canonical component each |
| [skills/](skills/README.md) | Repeatable procedures |
| [testing/](testing/README.md) | Test phases and tooling |
| [decisions/](decisions/README.md) | Why and when a rule changed; never required reading |
| [archive/](archive/README.md) | History only; never rules |
