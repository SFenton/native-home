# Core grammar surfaces

> **What:** how the generic authored controls look and behave: choice surfaces, the toggle line, the status line for unavailable and disabled, `ask`, the slider's range, format and commit, and what a control shows while Home Assistant answers. **Read when:** you build, author or review a `bound-control`, `enabledWhen` or `ask`.

Mockup: [core-grammar-surfaces](mockups/proposals/core-grammar-surfaces/core-grammar-surfaces.html). Every surface draws a control that ships; none knows a device.

## Choice

| Surface | Use for | Draws |
|---|---|---|
| `segmented` | 2 to 4 short noun labels that stay visible | The row title, then the system segmented control as the row's body ([option-picker](../patterns/option-picker.md)) |
| `menu` | 5 or more options, long labels, or a secondary setting in a list | A pop-up button as the row accessory: the chosen label and the up-down chevron ([rows](../patterns/rows.md)) |
| `chips` | 3 to 12 options that are the main control and stay visible | A heading, then a wrapping grid of chips: cells at least 120 pt scaled with the text, at most 5 columns, 44 pt tall; the chosen chip is filled and checked |

- With no surface named, 2 to 4 options draw `segmented` and more draw `menu`.
- Accessibility sizes: `segmented` becomes its menu form; the `menu` accessory moves under the title. Chips fall to fewer columns, down to one. Labels wrap and never truncate.
- When no option's `selectedWhen` holds, no segment is selected and the control stays enabled.
- The Studio rejects `segmented` with more than 4 options and `chips` with more than 12.

## Toggle

| Surface | Use for | Draws |
|---|---|---|
| `row` | A setting in a module list | The list row with a trailing switch |
| `line` | A switch that belongs to the content of a card or sheet group | A body-size label, an optional leading symbol and a trailing switch, at least 44 pt, with no ground of its own |
| `tile` | A switch in a tile grid | The action tile ([action-tiles](../patterns/action-tiles.md)) |

- A `line` sits only inside a container that supplies the ground: a card, a sheet section or a form group. The Studio warns for a `line` placed straight on a page and offers `row`.
- At every text size the label wraps and the switch stays trailing.
- The switch is the one accessibility element and carries the label.

## Status line

The status line is the secondary text directly under a control's title: a row's subtitle, the line under a toggle line's label or a chip heading. A button's sits under the button. A tile adds the message to its state line after a middle dot. It holds one message, by this precedence.

1. **Unavailable:** the value cannot be read. The authored unavailable text; one text for `unavailable`, `unknown` and a missing entity.
2. **Disabled:** `enabledWhen` is false. The authored reason ([settings-section](../patterns/settings-section.md), "Say why a control is disabled").

- In both states the control draws at 50%, takes no input and keeps the last value it showed. The title keeps its ink.
- An unavailable slider drops its value text; an unavailable choice shows no selection.
- The message joins the control's accessibility value, and the control has the not-enabled trait.
- Unavailable never shows an arc.

## `enabledWhen`

- It carries a predicate, `whenUnknown` (`keep` by default, as `visibleWhen`) and a `reason`. The reason is required: one sentence that says what to do, sentence case, with a full stop.
- A disabled control stays in place. `visibleWhen` is for a control that does not apply; `enabledWhen` for one that applies but cannot act now.
- `enabledWhen` is checked again when a confirmation or an `ask` option is tapped.

## `ask`

An `ask` is an action sheet whose options each carry a call. It follows [alerts](../patterns/alerts.md).

- **When.** Choosing among calls after a deliberate tap. A yes or no about one call stays a `confirmation`.
- **Presenter.** The system action sheet, with the control that raised it as the popover source: the button, the row's accessory, or a tile's disc. Compact width draws the sheet with its Cancel; regular width draws a popover with no Cancel, and a tap outside cancels.
- **Title.** Required. Title Case, a short question naming the object, one line at the default size. A message is optional.
- **Options.** 2 to 4, in authored order. Labels are Title Case, one to three words, and say the result.
- **Destructive.** Only an option that loses data or the session. The Studio warns when a destructive option is not listed first.
- **Cancel.** Always "Cancel", never authored. It sends nothing.
- **At the tap.** The option's operands and `enabledWhen` are evaluated again. When the resolved call differs from the one resolved as the sheet opened, nothing is sent and the control reports a failure: "This changed while you were choosing. Try again."

## Slider

- `range` gives the minimum, maximum and step; `format` is a pattern with a `{value}` hole. With neither, the slider is 0 to 100 in steps of 5 with a percent sign.
- The value text sits at the trailing end of the title line, and under the title at accessibility sizes.
- **During a drag.** The thumb snaps to each step, the value text follows, and one selection tick plays per step. Live values do not move the thumb while a finger is on it.
- **After release.** The thumb shows the call's optimistic value, or Home Assistant's value when it declares none.
- The Studio warns above 40 steps and offers a stepper.
- One adjustable accessibility element; a swipe moves one step; the value is the formatted text.

## Commit modes

| Mode | The call goes out |
|---|---|
| `immediate` | At every step |
| `release` | Once, when the finger lifts |
| `debounced` | Once the value has rested for the app's delay |

- The delays are the app's, not authored. A slider with no mode named is `debounced`.
- Nothing drawn differs between modes.

## Pending

What a control shows while Home Assistant answers, the defaults by call and the authored settings: [pending-controls](pending-controls.md).

## Studio preview

- The evaluator resolves every operand and predicate to a value or `unknown`, with the app's rules; shared corpus cases hold both to the same answers.
- It reads live entity states when the Studio is connected, and states the author sets when it is not.
- Each control previews in its states: live, optimistic, waiting, disabled with its reason, unavailable and failed, at iPhone, Duo and iPad widths and at the default and largest text size.
- Each expression shows its resolved value and names the read that made it `unknown`.
- Each call shows a dry run: the resolved service, target and data for a chosen gesture. The preview never sends a call.
- An `ask` lists its options with each resolved call, as the sheet and as the popover.
- The preview is labelled approximate; a device is the reference.

## HIG

- Segmented controls: "about 5 on iPhone". Pop-up buttons: "options needn't stay visible".
- Toggles: "Use the switch style only in a list row". Departure: the toggle line has no card of its own.
- Action sheets: "Use an action sheet, not an alert, for choices related to an intentional action."; "Avoid letting an action sheet scroll."
- Popovers: "Avoid popovers in compact views."
- Typography: "Keep text truncation to a minimum as font size increases." Color: "Avoid relying solely on color".
- Writing: "Show errors as close to the problem as possible".
- Designing for iPhone Duo: "Standard, resizable components adapt with little adjustment."
