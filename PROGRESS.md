# Fenton HASS Native: current plan

> **What:** what is being built now and next, and who owns which seam. **Read when:** planning a lane or picking up work. Per-surface status is the mockup atlas [catalog.json](.agents/design/mockups/catalog.json). Budget: 60 lines, 900 words; a backlog item is one line.

## 1. Seams

A lane reads anything and edits only what it owns; ask in your report for a change in a shared seam.

| Seam | Owner |
|---|---|
| `apple/Package.swift`, `apple/project.yml`, `HassCore/Auth`, `Connection`, `Entities`, `HassDesign/`, `HassUI/App/`, `HassUI/UIKitPort/App/` and `UIKitPort/Design/` | orchestrator (lanes may add new files to the design folders) |
| `HassUI/UIKitPort/Features/<Feature>/`, `HassUI/Features/<Feature>/`, `HassCore/<Feature>/`, `HassCore/Config/<Area>Config.swift` | the lane for that feature |
| `apple/Tests/**`, `apple/Apps/iOSUITests/**` | tests for your own files only |
| `.agents/pages/<id>/`, `.agents/controls/<id>/` | the lane for that page or control |
| `.agents/**` (the rest), `tools/`, `.claude/` | orchestrator |

## 2. Now

- **Server-driven UI is the only root.** The compiled shell, tab catalog and pages are removed; `UKServerUIRenderer` composes the layout from the publication in Home Assistant (`fenton_home/ui_publication`), and the Studio is the only writer ([architecture](.agents/platforms/apple/architecture.md#server-driven-root)). Reader enrollment and the publisher endpoint are gone.
- **Transport and state.** `fenton_home` 1.4.1 is deployed to prod; the prod publication is at revision 2. The last-good cache is keyed by origin and user.
- **Rules reset:** the rule surface is re-layered with one home per rule, budgets and a lint ([docs-conventions](.agents/workflow/docs-conventions.md)). Open, owner-only: `.githooks/pre-push` does not run `tools/rules_lint.py` yet. The reference-layer ratchet in `contracts/rules-ratchet.json` falls as files are trimmed.
- **House config at runtime:** the schema, store and transport are in `HassCore/Config/HouseConfig*.swift` and `AppSession` reads the store. Open: the mockups scrub, and renaming the house-bound names in code and tests.
- **Release pipeline:** a push to `main` bumps the version and builds a signed IPA on a hosted runner (`ios-release.yml`). Owner steps: [checklist](.agents/platforms/apple/testflight.md#release-pipeline-owner-checklist).

## 3. Next

- **Server-driven lanes still open:** routes; folding the house config into the publication; setup; the copy table; chrome items; retiring the fixed-shape providers; Studio ergonomics; logic coverage to 95%; the U12 renderer collaborators; unfolded Duo evidence.
- **Hosted CI:** remove the Linux skips in `test_devcap`, `test_hass_creds`, `test_xc_watch` and `test_agent_roster`; the repository variables `HOSTED_MACOS` and `DENYLIST_STRICT` are the owner's to switch on.
- **Jev key:** the owner places the key file the Jev tools read ([jev](.agents/workflow/jev.md)).
- **Location and device sensors:** the `mobile_app` registration runs in shadow; next are the device readers and sensors ([location](.agents/platforms/apple/location.md), [mobile-app](.agents/platforms/apple/mobile-app.md)).
- **Watch app:** a target stub only; glanceable status and a handful of controls.

## 4. Backlog

- Duo Back label: the pushed page's system Back reports an empty accessibility label on the folded Duo; label it and restore the Duo assertion in the single-page motion journey.
- iPad has no flyout since the top tab bar (global chrome pick 3, 2026-11-18); the iPad single-page journeys no longer wait on the flyout bug.
- Measured against felt performance: deferred by the owner.

## 5. Where to look

| Need | Read |
|---|---|
| How to work a change | [change-loop](.agents/workflow/change-loop.md), [propose-first](.agents/workflow/propose-first.md) |
| How a surface looks and moves | [mockup atlas](.agents/design/mockups/README.md) |
| The rules for a screen or control | [.agents/README.md](.agents/README.md) |
| A procedure for one task | [skills](.agents/skills/README.md) |
| Why something is the way it is | The record homes in [docs-conventions](.agents/workflow/docs-conventions.md#homes) |
