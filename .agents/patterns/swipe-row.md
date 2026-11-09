# Swipe row

> **What:** swipe actions for a row in a `VStack` or `LazyVStack` (any non-`List` stack; iOS 18 and later). **Read when:** a stack page's rows need swipe actions, or you touch `SwipeActionRow`.

Owner decision 2026-10-27: the to-do pages move from `List` to `ScrollView` + `LazyVStack` (a profile put 55% of the main thread, while scrolling, in the `List` collection view creating and self-sizing a cell for every row that entered the viewport, 3 to 4 ms each, redone on every pass). `.swipeActions` only works on `List` rows before iOS 27, so the row brings its own.

HIG: [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables), swipe actions. The primary, non-destructive action leads; secondary and destructive actions trail, the destructive one outermost; a full swipe performs the outermost action of its side; every swipe action is also reachable another way (the context menu, VoiceOver actions) because a swipe is not discoverable. Feedback: [Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics) (a detent). Motion: Reduce Motion swaps the spring for a short ease ([motion](motion.md)).

## Component

`HassDesign/Swipe/`:

| Type | Does |
|---|---|
| `SwipeActionRow(id:leading:trailing:topRadius:bottomRadius:background:content:)` | The row. `content` slides; `background` (the module's share) stays; the action buttons grow out of the edge behind the sliding content and exist only while the row is swiped or open |
| `SwipeAction` | One button: title, symbol, tint, destructive, identifier, `perform` |
| `SwipeGeometry` | The arithmetic, apart from any view (unit-tested): follow the finger, rubber band, hard stop at the row's edge for a full swipe, arm at half the row, snap open past half the actions or on a flick toward them, else closed, buttons sharing the revealed width then the outermost growing |
| `SwipeCoordinator` and `swipeRowContainer()` | One open row per page. Apply `swipeRowContainer()` to the `ScrollView`: a row that starts a swipe closes the others, scrolling closes the open row (`onScrollPhaseChange`), a tap on the page or on another row closes it and does nothing else: the open row and the other rows cover themselves with a tap overlay, and the page's other controls (the Chores quick-link tiles) ask `SwipeCoordinator.consumesTap()` before acting, so the closing tap does not also navigate. A row that leaves the screen while open clears the open id (`onDisappear`), and a new drag cancels the previous swipe's pending release and come-back tasks |

`swipeRowContainer()` needs iOS 18 (the to-do pages keep their `List` before that). Chores wires it through `TodoStackSection` (the stack section) and `TodoListActions` (HassUI), which is the one source of the swipe buttons, the context menu and the check-off for the `List` section (iOS 17) and the stack one.

## Where it matches the system's swipe

- Axis decided at the first movement. iOS 18 and later: a `UIPanGestureRecognizer` (`SwipePanRecognizer`, `UIGestureRecognizerRepresentable`) whose `gestureRecognizerShouldBegin` fails it at once on a vertical start (`SwipeGeometry.isHorizontal`). A simultaneous SwiftUI `DragGesture` on every row left the page's scroll dead after its first gesture on iOS 26 (bisected 2026-10-28; `ScrollKeepsMovingJourneyTests`), so there is no `DragGesture` path: `UIGestureRecognizerRepresentable` needs iOS 18, and **on iOS 17 the to-do pages keep their `List` and its system swipe actions** (`TodoPageView.pageScroller`).
- The row follows the finger one to one; a side with no actions resists like a rubber band; a side with actions stops hard at the row's edge when it allows a full swipe.
- Full swipe: half the row arms it; crossing the threshold either way plays `TapFeedback.step`; releasing armed slides the row out, runs the outermost action and, if the row is still listed (a done look, a cancelled confirmation), brings it back 0.45 s later.
- Leading order and mirroring: logical offsets flip in right-to-left layouts; the buttons are laid out with the outermost at the screen edge.
- Fills, symbol over label, white ink at 4.5:1 (the caller's tints). Identifiers stay on the buttons (`todo.swipe.<action>.<id>`).
- The module's first and last rows round the actions' outer corners with the card's radius.

## Where it cannot

- The system's buttons are UIKit views with its own rubber-band curve and haptic; the curve here is the standard `(1 - 1/(x*c/d + 1)) * d` and the haptic is `selection`.
- VoiceOver gets no system "Actions" rotor entries from the swipe: the content names them itself as `accessibilityActions` (in this order: Undo when offered, Complete or Mark Not Done, Edit, Delete, with their swipe labels; `TodoItemRow(exposedActions:)`, `TodoItemRow.voiceOverActions`).
- The row's tap-to-close overlay, not the system, swallows the tap that closes an open row.

## iOS 27

iOS 27 adds `swipeActionsContainer()`. `SwipeActionRow` tried `.swipeActions` inside it and dropped it (the experiment switch is gone). Reasons: on the Duo's iOS 27.1 simulator its buttons read "Delete, Delete" to VoiceOver and a full swipe did not complete the chore (2026-10-27), and the simulator A/B showed no per-frame difference between it and the custom row (Duo, iOS 27.1, VStack page: main_ms 703 vs 668 on Chores, 970 vs 935 on the long house). The custom row runs on every OS.

## Look

The actions draw as iOS 26 draws the system's: a tinted capsule with the white glyph and the action's name under it in secondary ink, on the module's own background, with the row sliding off it (the system also rounds the sliding row's inner corner; this one slides square, clipped to the row). Mockups: [pages/chores](../design/mockups/pages/chores/README.md) show the row at rest; the swipe is a transient state and was not mocked.

## Rules

- A lazy page's rows with swipe actions use `SwipeActionRow`; never a second drag implementation.
- Rows are direct children of the page's stack (a `Group` or `ForEach` body), never wrapped in a stack of their own. (The Chores stack is a plain `VStack` that builds every row when the page opens; a `LazyVStack` also works.)
- A side's buttons never cover more than 45% of the row (`SwipeGeometry.maxActionsFraction`, under the 50% full-swipe arm): at AX3 to AX5 a button's scaled width is up to about 230 pt and two would be wider than a 343 pt row, so the buttons shrink together. Without the clamp the open threshold (half the buttons) sat past the arm and a release that should open performed Delete, and an open row clipped Edit.
- Don't clip the row to the module's rounded shape: that is an offscreen pass for every row on screen. The row clips to its rectangle and the actions round their own outer corner.

## Tests

`Tests/HassDesignTests/SwipeGeometryTests.swift` (thresholds, snap, full swipe, flick, one open row, actions wider than the row, tap consumption); `ChoresSwipeJourneyTests` (leading full swipe completes, trailing swipe reveals Delete outermost and Edit, partial drag opens, Delete confirms, context menu Edit); `ChoresViewTests.theStackRowExposesItsSwipeActionsToVoiceOver` (the VoiceOver actions per row state and their handlers); the accessibility sweep for chores and groceries.
