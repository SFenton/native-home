# Map orientation and corner button groups (proposal, decided)
> **What:** the owner-review page for flipping the vacuum map and placing buttons in its corners, and what the build settled. **Read when:** you want to know why the map buttons and the flip work as they do. The current design is [vacuum-sheet](../../modals/vacuums/vacuum-sheet/vacuum-sheet.html) and [vacuum-map-canvas](../../components/vacuums/vacuum-map-canvas/vacuum-map-canvas.html).
- Mockup: [vacuum-map-controls.html](vacuum-map-controls.html) · status decided
- Owner request: flip the map horizontally, vertically or both; any number of buttons as a row or a column in each of the four corners, in an order the owner sets; the app handles what does not fit. Gate: `matches_request=yes`.
- Rules: `.agents/patterns/map-controls.md`.
- Built as drawn: one glass shape per group, 44 pt buttons, 8 pt from the card's edges, 12 pt between groups; the flip after the rotation; badges, markers and buttons never mirror; nothing authored draws Locate alone at top leading.
- Settled by the build, where this page differs or was silent:
  - A vacuum command on the map (Clean, Pause, Return to Dock) follows the command tiles: hidden when the vacuum does not offer it, dimmed with its reason when offered but blocked. So Clean is hidden, not dimmed, while the robot is unavailable; the page's "Robot unavailable" state still draws Pause and Return to Dock.
  - Locate is hidden while the robot is unavailable, as before.
  - More is a system menu (`UIMenu`) of the buttons that did not fit, in order, each with its symbol and label; a blocked one is disabled with its reason.
  - A dimmed button draws its symbol at 40%, not the 38% of this page's style.
  - Up to 8 buttons in a group.
- Evidence: `build/evidence/screens/native-mapctl-cd641867/index.md`, `build/evidence/vacuum-map-ctl/native.md`.
- The Studio inspector on this page is a web surface; it is not part of the app's atlas.
