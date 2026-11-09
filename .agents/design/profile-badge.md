# Profile attention badge: size, position and text-size cap

> **What:** how big the Profile button's attention badge is, where it sits on the disc, and how far it grows with Dynamic Type, on the iOS 26 header and the Duo rail. Decided 2026-11-04 (T-profile-badge-size, three Designer rounds). **Read when:** touching `UKProfileButtonView`'s badge, `UKShellHeaderItems.badge`, `ProfileButton.badgeTypeRange`, or any bar item's count badge.

Mockup: [profile-button](mockups/components/navigation/profile-button/profile-button.html) (also in the [hub](mockups/README.md)). Owning rule: [direction-g.md](direction-g.md), header buttons.

## Goal

The owner reported, with a screenshot of the Duo unfolded landscape rail: "the notifications status is massively oversized and mispositioned on the profile chip". Measured before the fix (iOS 26 simulators, "9+"):
- On every bar the capsule was about 37 x 31 pt. It was held at the accessibilityMedium caption1 size at every text size, so it was wider than the 30 pt rail disc and about 0.84 of the 44 pt header disc.
- On the iPhone header it sat on the disc's corner. On the iPad header and both Duo rails it sat over the top centre of the photo and hid its upper half.

## Decision

Decision: 2026-11-04, judged three questions over three build rounds; picked the drawn badge on the header, an xLarge text cap and a capsule sized like the system badge.

**1. Header position.**
- Options judged:
  - A: keep the system `UIBarButtonItem.badge` on the header's custom-view item (built, f70c8e12).
  - Lever A: draw the badge in `UKProfileButtonView` as an `.alwaysOriginal` image (built, 26e4a0dd).
  - Lever B: an image-backed header item that keeps the system badge (specified, not built, because lever A passed).
- Picked lever A, because the system badge on the custom-view item landed inside the photo. Its centre was 13 pt from the disc's 45 degree point on iPhone and iPad, and on iPhone that was worse than before the fix.
- Why the system badge moved: it is anchored to the item's layout cell, not to the disc. The disc overhangs that cell because the item hides the bar's shared glass. A margin around the view moved the disc, not the badge.
- Lever A puts the "9+" centre at (-8.2, +7.2) pt from the disc's bounding corner, against a target of (-8, +7). It is the badge `UKProfileButtonView` already drew before iOS 26, so there is one component, not a parallel one. It is drawn into an image because the bar's foreground treatment had turned a plain drawn red capsule white.

**2. Text-size cap.**
- Options judged: accessibilityMedium (built, f70c8e12: 36 x 30 at AX5), xxxLarge (estimated about 31 x 25) and xLarge (built, 26e4a0dd).
- Picked xLarge, because it is the only step at which "9+" stays narrower than the 30 pt rail disc. Measured: about 26-27 x 21. accessibilityMedium was the size the owner called "massively oversized". It is also the cap the initials on the same disc already have.

**3. Capsule metrics.**
- Options judged: the drawn label's old metrics (built, 26e4a0dd: 27 x 16, against 24.3 x 18 on the rail) and metrics matching the system badge (built, cea05a38).
- Picked the system metrics, because with the old metrics the badge changed shape when the Duo rotated from the rail to the header.
- Final measurements, header against rail:

  | Text, size | Header | Rail |
  |---|---|---|
  | "9+" default | 24 x 18 | 24.3 x 18 |
  | "3" default | 18 x 18 | 18 x 18 |
  | "9+" AX5 | 26 x 21 | 27 x 20.7 |
  | "3" AX5 | 21 x 21 | 21 x 20.7 |

  Every pair is within 1 pt.

Evidence: the Verifier's pose captures for each round, from iPhone, iPad, Duo folded, Duo unfolded landscape (the owner's pose), and Duo rotated left and right, at default and AX5. Pixel-measured. They are kept as working files in `build/evidence/T-profile-badge-size/` and are not committed.

HIG:
- Toolbars: "A custom version should retain the standard appearance, expected behavior, fit with the interface, and consistent implementation throughout the app."
- Tab bars: "Reserve badges (red oval, white number or exclamation point) for critical new/updated information".
- Typography: "Make sure your layout adapts to all font sizes, keeping text and glyphs legible". The count stays in the item's accessibility value, and the Large Content Viewer title is "Profile, 9+".

Gate: matches_request=yes. Recorded honestly: `tools/jev_gate.py` answered unsure and parked the task. The owner then approved it in session on 2026-11-04 ("Fix both (Recommended)"), so the request match is the owner's own confirmation, not Jev's. The commit carries `Owner-Request: in-session 2026-11-04, "Fix both"`.

## Rules this adds

- **Size.** On every bar the badge is caption1 bold, 18 pt tall at the default text size: 24 x 18 for "9+", 18 x 18 for one digit. A drawn badge copies the system badge's metrics: `height = max(18, round(lineHeight + 4))` and `width = max(height, ceil(textWidth) + 7)`. The header's badge and the rail's stay within 1 pt of each other.
- **Position.** On a disc, the badge's trailing edge is 4 pt past the disc and its top 2 pt above it, which puts its centre on the disc's 45 degree point. A standard item's system badge (the Duo rail) may sit up to about 6 pt from that point; the header disc may never carry it inside the photo.
- **Rail Large Content title.** The rail item's `title` is "Your Summary, 9+" (the bar item's title is the only text the Large Content Viewer shows); its `menuRepresentation` keeps "Your Summary", so the "…" overflow menu text is unchanged (owner, 2026-11-01).
- **Text-size cap.** The badge text follows Dynamic Type only up to xLarge (`ProfileButton.badgeTypeRange`), the same cap as the initials. A bar badge marks the button, and its count is spoken in the item's value and shown by the Large Content Viewer.
- **Colour on a custom-view bar item (iOS 26).** Draw coloured chrome inside a custom-view bar item into an `.alwaysOriginal` image. The bar's foreground treatment recolours plain subviews.
- **Still across push and pop (2026-11-05).** Every shell bar item carries a stable `UIBarButtonItem.identifier` on iOS 26 (`shell.profile`, `shell.quickLinks`, `shell.arc`, `shell.menu`), so the bar treats a page's items as the same ones across push and pop and keeps them still instead of cross-fading a new custom view. Do not share one item set between pages: UIKit moves a bar item to the page it was last set on and empties the other (hosted run 2026-11-05).

## Not in scope

The iPhone Quick Links to Profile gap of 16.3 pt is the same before and after this change. It is the iOS 26.5 departure recorded in [direction-g.md](direction-g.md) (header buttons), not part of this decision.
