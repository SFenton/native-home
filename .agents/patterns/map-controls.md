# Map controls

> **What:** the buttons over a map card, the fit rule and the map orientation. **Read when:** changing a button over a map, the map's flip, or the contract that authors them.

Contract: `sh.surface-controls@1` and `sh.surface-orientation@1` (Studio `agents/studio-ux2@7dddfa9`).

The overlay ([overlay](overlay.md)) is not a second way to place map buttons: a button over a map is a map control.

| Piece | File |
|---|---|
| Fit rule (shared oracle), corners, constants | `HassCore/Vacuums/MapControlFit.swift` |
| Orientation (`flipHorizontal`, `flipVertical`) | `HassCore/Vacuums/MapOrientation.swift` |
| Decoded groups, defaults, Locate rules | `HassCore/ServerUIComposition/ServerUIMapControls.swift` |
| Shape and compiler | `ServerUIMapControlsShape.swift`, `ServerUIMapControlsCompiler.swift` |
| Corner groups, glass, More menu | `HassUI/UIKitPort/Design/UKMapControlsView.swift` |
| Visibility, dimming, actions | `HassUI/UIKitPort/ServerUI/UKServerUIMapControls.swift` |
| The card that hosts them | `UKVacuumMapFrame` |

- **Groups.** Up to four, one per corner, each a row or a column of 1 to 8 buttons in authored order. A button is 44 pt, 8 pt in from the card edge, 12 pt apart (HIG, Buttons: a 44 pt target). The Studio and the app share one fit rule and one set of per-size counts (`MapControlFitTests`).
- **Fit.** A group of one counts as a column. The crossing neighbour takes one slot; `k = floor(available / 44)`. More than `k` buttons shows `k - 1` and a More button whose `UIMenu` lists the rest in order, each with its symbol and label (HIG, Menus). The app handles overflow; the Studio only warns.
- **Nothing authored** draws today's map: Locate at top leading, one glass circle.
- **State.** `map` Locate shows only while the robot is available. `source-command` takes the state of the command tiles: shown only when the vacuum offers it, dimmed when blocked, the reason spoken as the VoiceOver value. A service call or navigation follows its own `visibleWhen`, `enabledWhen` and symbol or label rules.
- **Orientation.** One flip on the vacuum source, applied in `MapGeometry.matrix` after the rotation, in screen space, so the picture and everything on it (rooms, area, handles, robot) move together and taps stay consistent. Badges, markers and these buttons never mirror. Hatching keeps its on-screen direction. The area editor nudges by screen direction.
- **Kept text.** Text slots keep through `UKServerUILayoutMemory.discLabelText` (`sh.text-keep@1`, rule in [kept-text](../design/kept-text.md)): a `keep` slot draws its last answer while unavailable, drawn and spoken as live.
- **Accessibility.** Each button has a label, an optional hint and the `button` trait; a dimmed button adds `notEnabled` and its reason as the value. Corner order is the reading order. Large content viewer images are set. Reduce Transparency and Increase Contrast give an opaque plate and an outline.
- Tests: `MapControlFitTests`, `MapOrientationTests`, `ServerUIMapControlsTests`, the corpus cases `surface-controls-*` and `surface-orientation-*`, and the hosted `UKHostedMapControlsTests` on iPhone, Duo and iPad.
