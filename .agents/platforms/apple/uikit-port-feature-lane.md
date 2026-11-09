# UIKit port: feature lane brief

> **What:** how a feature lane of the UIKit port works, from setup to report. **Read when:** you are a feature lane (Home, Security, Climate, Chores, Settings, Rooms, Vacuums, Food).

## Read first
1. `AGENTS.md`: the invariants. Every build and simulator runs inside a `tools/devcap.py` hold; the scripts below already take it.
2. [uikit-port](uikit-port.md): the port's rules (location, `#if os(iOS)`, `UK` prefix, no SwiftUI on screen, reuse logic, identical accessibility).
3. The component guides: [design tiles](uikit-port-design-tiles.md), [design lists and sheets](uikit-port-design-lists.md), [design controls](uikit-port-design-controls.md), and [shell and page contract](uikit-port-shell.md). Build on these components. Never make a parallel one. If a component is missing or wrong, extend it in place under `UIKitPort/Design/` (keep its other callers working) and say so in your report.
4. Your feature's SwiftUI sources, its spec (`.agents/pages/<id>/`), its pattern records, its mockups (`.agents/design/mockups/`), its galleries (`apple/Sources/HassUI/Features/Gallery/`) and its journeys (`apple/Apps/iOSUITests/`).

## Rules
- **Ownership.** You own `UIKitPort/Features/<Feature>/` (including your `UK<Feature>Entry.swift`; replace its placeholders) and `UIKitPort/Gallery/UK<Feature>Gallery.swift`. You may add files there, and extend shared Design components carefully. Do not edit other features' folders. Do not edit the `App/` shell except for a one-line bug fix you report.
- **Screens.** Every page subclasses `UKPageViewController`. Push routes through `context.push(...)`. Sheets use `UKHassModalController` with the same detents and fit as `hassSheet`. Lists use the module list components.
- **Binding.** Bind views to the `EntityBox`es they show through the page's `bag` (`UKObservationBag`). Cells rebind in `configure` and clear in `prepareForReuse`.
- **Galleries.** Your `UKGallery.<lane>(_:)` returns the same fixture page the SwiftUI gallery shows, for every `FENTON_GALLERY_*` variable that gallery reads. Use `UKGalleryChrome.context(store:caller:)` and `UKGalleryChrome.wrap(_:context:)`. Reuse the SwiftUI galleries' fixtures and recorders; never copy them.
- **Identical.** Same text, symbols, colours, sizes, spacing, order, motion, accessibility identifiers, labels and values. When the SwiftUI view reads a model or helper, read the same one. If some logic lives only inside a SwiftUI `body`, extract it into a `static func` beside it, call it from both, and leave the SwiftUI behaviour unchanged.

## Waiting on builds
The Mac has two build slots, shared with other projects. A build can wait 20 to 50 minutes for a slot and then takes 2 to 8 minutes.
- Launch every build or shot run with the Bash tool's `run_in_background: true`, for example `tools/bg_run.py <lane>-build-N --timeout 7200 -- tools/uikit_build.sh`. Never detach it with `&`, `nohup` or `setsid`.
- Then end your turn. You are re-invoked when the command exits.
- If you are not woken, hand back one line, `WAITING <log path>`. The orchestrator resumes you.
- Write a large, careful chunk before each build. Fix every error and warning in your files each round.

## Verifying
- **Build:** `tools/uikit_build.sh`.
- **Side by side:** the SwiftUI reference app is at `<worktree>/apple/build/dd-FentonHome/Build/Products/Debug-iphonesimulator/FentonHome.app`.
  - Run `SWIFTUI_APP=<that path> tools/uikit_shot.sh --family iphone --surfaces FILE --out build/shots/<lane>`. FILE holds `name|ENV ...` lines covering every gallery state you port.
  - Read every PNG pair and fix the differences.
  - Then run it once with `--family ipad`.
- **Journeys:** `tools/ios_uitest.sh` runs the journeys in `apple/Apps/iOSUITests` against the app (`-only-testing:FentonHomeUITests/<YourJourneyClass>`). `tools/uikit_journeys.sh` is gone (owner, 2026-11-01: the UIKit app is the app).
  - Run your feature's journey classes that work on gallery fixtures. List them with `grep -l "FENTON_GALLERY=<page>" apple/Apps/iOSUITests/*.swift`.
  - A journey that fails because the port differs is a bug in your port. Fix the port, never the test.
  - A journey that needs a live sign-in is out of scope; list it.

## Done and report
- **Done means:** the feature is fully ported, the build is clean, the shots match on iPhone and iPad, your fixture journeys pass (or every failure is explained), and the work is committed on your branch. Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Report** in under 40 lines:
  - the files you made;
  - each journey class with its pass and fail counts;
  - what is not identical, and why;
  - your shared-component changes;
  - your logic extractions;
  - the build digest and screenshot paths.
