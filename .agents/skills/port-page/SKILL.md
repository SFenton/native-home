---
name: port-page
description: Ports a React dashboard page to the native UIKit app, from the entity inventory and page spec to the screen, gallery and tests. Use when starting a page port from the web dashboard.
---
# Port a page

> **What:** procedure for bringing a web page to the UIKit app. **Read when:** starting a page port. Rules: [uikit-port](../../platforms/apple/uikit-port.md), [feature lane](../../platforms/apple/uikit-port-feature-lane.md).

1. Find the page in the web dashboard (`src/pages`) and its entities (`src/constants`). A `menial` can build the entity inventory.
2. Write `.agents/pages/<id>/spec.md`: layout, entities, states, services and navigation edges, each cited as `repo@sha:path:line`.
3. Classify the page in [split-view](../../design/apple/split-view.md).
4. Look the surface up in the [mockup atlas](../../design/mockups/README.md); add or update its mockup ([mockup-hub](../mockup-hub/SKILL.md)).
5. Add the entity IDs in `HassCore/Config/<Area>Config.swift` and any non-UI model, route or policy in `HassUI`.
6. Build the screen in `HassUI/UIKitPort/Features/<Feature>/` from the port's existing components: a page view controller, views bound to their entity boxes, sheets through the shared modal controller. A missing shared piece is extended in place under `UIKitPort/Design/`, with its pattern doc.
7. Add the gallery fixture page for the feature under `UIKitPort/Gallery/`.
8. Test: unit tests for logic, a UX journey and an accessibility test on iPhone, Duo and iPad ([testing](../../testing/apple/README.md)).
9. Update [pages](../../pages/README.md) and `PROGRESS.md`.
