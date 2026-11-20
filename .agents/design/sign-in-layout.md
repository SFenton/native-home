# Sign-in layout

> **What:** where the sign-in header and form sit in each window, how they stay inside the safe area, and what the keyboard moves. **Read when:** you change `UKLoginViewController`'s layout, or check a sign-in pose on iPhone, Duo or iPad.

What the screen holds, its copy, errors and states: [auth](../platforms/apple/auth.md). Mockups: [login](mockups/pages/login/login/README.md), [cold launch](mockups/flows/launch-cold-signed-out/README.md), [welcome back](mockups/flows/session-expired-welcome-back/README.md).

## Safe area

- The ground and glow fill the window.
- The scroll view that holds the header and form is pinned to `safeAreaLayoutGuide` on its leading and trailing edges, to the view's top, and to `keyboardLayoutGuide.topAnchor` at the bottom.
- Every field and button is therefore inside the safe area, and the form has no sideways scroll range.
- Apple Tech Talk 111461, "Respect safe areas": "place foreground elements like interactive controls within the safe area"; "background content may extend past the safe area".
- Apple Tech Talk 111466: "a full-width background image or header with scrollable foreground content that's inset".
- Read the guide, never a width: the Duo's vertical bar can sit on either side.
- Folded Duo: the scroll view is 382 pt wide and the fields 334 pt.
- The hinge band is measured against the scroll view's frame, not the window.

## One column or two regions

`SplitPolicy.geometry` over the scroll view's frame decides, never a device name: regular width, wider than tall, each region at least 360 pt. An accessibility text size always gets the column. HIG Layout: "Choose layout from size classes, not device type/idiom or orientation".

| Window | Layout |
|---|---|
| iPhone, folded Duo, unfolded Duo portrait, iPad portrait, a narrow iPad window | Column |
| Unfolded Duo landscape lying flat, iPad landscape | Two regions that meet at the midpoint |
| Unfolded Duo landscape partly folded | Two regions, one each side of the hinge band |
| Any window at an accessibility text size | Column |

- **Column.** Centred, `min(460, scroll width)` wide, moved to the leading region where the partly folded hinge crosses it. Mark 96 pt, name 34 pt bold, line Body.
- **Two regions.** The header and the form are each `min(460, region width)` wide with 24 pt margins, the header centred in the leading region and the form in the trailing region. The regions are leading and trailing and swap in right-to-left languages (HIG Right to left).
- The regions come from the scroll view's safe width, as every other split in the app does.
- Unfolded Duo, 84 pt side strip: 433 / 1 / 433 pt lying flat, 455.3 / 40.4 / 371.3 pt partly folded (form 371 pt, fields 323 pt). iPad landscape: 596 / 1 / 597 pt.
- Lying flat, the fold line runs through the leading edge of the form (the hinge posture rule).
- Folded Duo and unfolded Duo portrait keep the column: halves of 334 pt are under the 360 pt minimum.

## Alignment in two regions

- The block from the top of the glass module to the bottom of Sign In is centred in the scroll view's safe height. An inline error is inside that block. HIG Layout: "Align related elements".
- The header's centre is on the same line. The header is measured from the top of the mark's drawn shape to the bottom of the line: the house starts 12% of the mark's side below its frame (13.4 pt at 112 pt), the monogram disc fills its frame.
- The footnote hangs 16 pt under Sign In. In welcome back, Use a Different Account hangs 16 pt under Sign In and the footnote 16 pt under that.
- A failure card hangs 16 pt above the module and moves neither the fields nor Sign In (HIG Designing for iPhone Duo: "favor small adjustments over disappearing or dramatically shifting controls").
- None of the three moves the block or the header. When a card does not fit above the block, the form moves down far enough to fit it and the header stays.
- The header is at most 460 pt wide less its margins, as the form is, so its text wraps at the form's width.
- The header and the form keep at least 16 pt from the top and bottom of the scrolling content. Content taller than the height scrolls vertically; the block's centring gives way first.
- Header sizes: mark 112 pt (fixed), name 40 pt bold scaled with Large Title, line Title 3 (20 pt), so the header keeps scaling with Dynamic Type (HIG Typography, built-in text styles). The welcome back monogram is 103 pt, scaled as the column's 88 pt one is.

## Keyboard

- The scroll view ends at the keyboard. In two regions both the header and the form centre in the space above it, on one line (HIG Virtual keyboards: "Use the keyboard layout guide").
- What hangs under Sign In is reached by scrolling when the keyboard covers it.
- Nothing moves sideways when a field takes focus or the keyboard goes: column or split is decided from the window's height, never the keyboard-shortened scroll view.

## Motion and VoiceOver

- A change of layout (rotation, fold, unfold, partly folded to flat) moves the same views with `MotionTokens.standard`, or `quick` under Reduce Motion; on a rotation it runs inside the system's rotation. Text, focus and VoiceOver focus are kept. One `LayoutChange` interval (page `SignIn.layout`) spans it; `UKHostedSignInLayoutPerformanceTests` measures it.
- The intro plays the same pieces with the same timings in both layouts ([direction G](direction-g.md#launch-and-sign-in-motion)).
- VoiceOver order in both layouts, each field row its own stop: header, failure card, Server, Username, Password, inline error, Sign In, Use a Different Account, footnote.
