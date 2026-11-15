# The recovery boundary of the server-driven root

Decision: before a published layout is on screen the root shows one recovery boundary with four states: waiting ("Getting Your Layout"), nothing published ("No Layout Published"), a newer layout ("Update Required") and a failed load ("Layout Unavailable"). Each is the registered state message with at most one prominent action; the failed state adds Clear, and every state has Sign Out. The component, placement, actions and alerts are set as rules, each settled by a registered pattern, an approved rewording or the HIG (table below). The words were built as two options: A, the strings the branch ships with the two rewordings already approved; B, the rest reworded to the copy pattern. The app-UI gate parked the words for the owner, who picked A on 2026-11-15 ("A: keep as built"). The Designer had recommended B: A names a product that does not exist, uses "Unavailable" for a failed load, and in one state names two buttons that are not on screen. Those stay as known departures from the copy pattern.
Replaces: the missing-layout pick of 2026-11-06 (a state message in place of each page's content, the shell kept) and rules 11, 12 and 14 of `.agents/design/house-config-states.md` as they stood. The compiled pages that drew those states are removed (`2026-11-14-server-driven-root.md`).
Rule home: `.agents/design/server-ui-boundary.md`. `.agents/patterns/state-message.md` names it; `.agents/design/house-config-states.md` rules 10 to 14 are restated to match.
Gate: matches_request=yes. `tools/jev_gate.py` printed `gate: park basis=request answer=no route=session` on 2026-11-14, so the words went to the owner. The owner picked A in session on 2026-11-15 ("A: keep as built"): the built strings stay, apart from the two approved rewordings, "Getting Your Layout…" and the shared sign-out alert. Option B is not taken. The rows under "Settled without a pick" are decided under step 3 of the design-decision skill.

Owner's request (2026-11-14, for the root this boundary belongs to): "we have to be able to either connect to the app, or the app has to publish something that HASS can consume — we need to make a decision there." The owner chose "Publish into HA" and said: "The existing app should NOT be shipped/compiled as part of this effort."

## The four states as built

From `UKServerUIRecoveryBoundary.swift` and `UKServerUIProductionHost.showStatus` at `c86d435a`.

| State | When | Glyph | Title | Message | Actions |
|---|---|---|---|---|---|
| Waiting | The subscription has not answered, or a published layout is being prepared | `arrow.down.circle` | Getting Your Layout | Waiting for your Home Assistant to send the layout. | Sign Out |
| Nothing published | Home Assistant holds no layout | `exclamationmark.triangle` | No Layout Published | Your Home Assistant has no layout yet. Publish one from the Configurator, then try again. | Try Again, Sign Out |
| Newer layout | The layout names a capability this build lacks | `arrow.down.app` | Update Required | The layout published for your home needs a newer version of S+H. Update the app to see it. | Sign Out |
| Failed | Rejected, or the first-load deadline passed | `exclamationmark.triangle` | Layout Unavailable | No usable layout is available. Try again, or clear a rejected saved layout and download it again. | Try Again, Clear Rejected Layout, Sign Out |
| Failed, nothing to offer | The saved layout could not attach, or there is no store | `exclamationmark.triangle` | Layout Unavailable | The same message | Sign Out |

Clear asks "Clear Rejected Layout?" with Cancel and a destructive Clear Layout. Sign Out asks "Sign Out?" with Cancel and a destructive Sign Out.

## HIG basis

| HIG | Clause | How the boundary meets it |
|---|---|---|
| Loading | "Show something quickly: otherwise people may think the app is broken; use placeholder text, graphics, or animations until content arrives." | The waiting state is a glyph and words from the first frame. The sign-in layer holds until a layout commits or the deadline passes, so most people never see it |
| Progress indicators | "Keep indicators moving. If a process stalls, explain the problem and what people can do." | No indicator is drawn. When the first-load deadline passes, waiting becomes the failed state with Try Again |
| Feedback | "If a command can’t be carried out, say so and explain why" | Each state says what stopped the layout. As built the failed state gives no reason, and with nothing to offer it names Try Again and Clear: the owner kept the built words (option A) |
| Writing | "Provide clear next steps on any blank screens, with a button or link if possible." | Every state says what to do next; the two a retry can help carry Try Again |
| Writing | "Keep and reference a list of common terms for consistency." | The copy pattern's term list. As built, "the Configurator", "Unavailable" and three nouns for one saved layout break it; the owner kept them (option A) |
| Buttons | "Keep to one or two prominent buttons per view." and "Never make a destructive button primary" | One prominent button, Try Again. Clear and Sign Out are plain and ask first |
| Alerts | "Include Cancel if there’s a destructive action." | Both confirmations have Cancel |
| Designing for iPhone Duo | "use reserved-region APIs to keep important elements clear of the center" | The rule places the column in the leading region on a window with a hinge band. As built the code has no hinge handling: an implementation spec |

Departure: the boundary is always dark, like every page (direction-g, Layers).

## Settled without a pick, and what settles each

| Rule | Settled by |
|---|---|
| Each state is `UKStateMessageView`, centred in the free space; no `ContentUnavailableView`, no hand-built stack | The state-message pattern |
| One prominent action, Try Again, only where a retry can help; none on the update state | The state-message pattern and its recorded exception for a state only an app update fixes |
| Sign Out on every state | HIG Designing for iPhone Duo: "Preserve functionality, element state, hierarchy, and access across displays/poses." With no shell the boundary is the only way to the session. The 2026-11-06 option B lost partly for duplicating Sign Out beside a shell; here there is no shell |
| Clear only on the failed state, behind an alert | The alerts pattern: confirm what is hard to undo; destructive role where data is lost |
| No spinner and no skeleton | The owner’s "no full-screen spinner" (2026-10-24). A skeleton needs a page shape, and before a layout the root has none |
| In the leading region on a window with a hinge band | The state-message and hinge-avoidance patterns: a single object that cannot split |
| The waiting title is "Getting Your Layout…" | Rewording group 9, approved by the owner on 2026-11-14: a visible progress label ends in `…` |
| Sign Out presents `AlertCopy.signOut`; its failure presents `AlertCopy.signOutFailed` with `{{device}}` | Rewording group 7, approved on 2026-11-14, which names this site; the alerts pattern: one string per decision |
| The strings are compiled boundary copy, never in the table and never a literal in the host | The copy pattern, Inline or slot |
| A state change swaps the view with no animation | The no-reload invariant applies to a screen with content; the boundary has none to keep |

## The words: options A and B

Built in `mockups/proposals/server-ui-boundary-copy` on iPhone, iPhone Duo folded and unfolded, and iPad, at the default size and AX5. Layout, glyph sizes, actions and states are the same in both.

| String | A, as built | B, to the copy pattern | Why B differs |
|---|---|---|---|
| Nothing published, glyph | `exclamationmark.triangle` | `house` | Nothing failed. The 2026-11-06 record used `house` for "not set up yet" |
| Nothing published, message | Your Home Assistant has no layout yet. Publish one from the Configurator, then try again. | Your Home Assistant has no layout yet. Publish one in Native Home Studio, or ask whoever manages your Home Assistant. S+H shows it as soon as it’s published. | The Studio’s panel title in Home Assistant is "Native Home Studio" (its `config.yaml`); nothing is called the Configurator. B also speaks to a person who cannot publish. 157 characters, budget 160 |
| Newer layout, title | Update Required | Update S+H | The title the 2026-11-06 record gave the same state |
| Newer layout, message | The layout published for your home needs a newer version of S+H. Update the app to see it. | Your home’s layout needs a newer version of S+H. Update S+H to see your home. | Copy pattern, Voice: the product is "S+H" |
| Failed, title | Layout Unavailable | Unable to Load the Layout | Copy pattern, Terms: a failed load is "Unable to Load `<Subject>`"; "Unavailable" is an entity with no state |
| Failed, message | No usable layout is available. Try again, or clear a rejected saved layout and download it again. | S+H couldn’t use the layout from your Home Assistant. Try again, or clear the saved layout to download it again. | Copy pattern, Voice: what happened, then the next step |
| Failed with nothing to offer, message | The same message | S+H couldn’t use the layout from your Home Assistant. Sign out and sign in again to download it again. | A names two buttons that are not on screen |
| Clear, button and alert title | Clear Rejected Layout | Clear Saved Layout | One noun for the saved layout |
| Clear, alert message | Only this account’s downloaded layout will be cleared. Your Home Assistant sign-in is kept. | This clears the layout saved on this {{device}} for this account. You stay signed in to Home Assistant. | Copy pattern, Voice: active voice; Terms: this iPhone or this iPad |

## Evidence

- No device capture exists for this surface and no Verifier manifest was given. The judgement rests on the code and on the kit drawings in the atlas page and the proposal, rendered on all six windows.
- Read from the code, not captured: the hinge placement as built, AX5 wrapping, and the system tint of the two plain buttons.
- B’s sentence for the state with nothing to offer assumes sign-out clears the saved layout; the Coder confirms it before that sentence ships.

## The decision this replaces

From `.agents/design/house-config-states.md`, removed there:

> Decision: 2026-11-06, judged missing-layout Option A (a state message in place of each page's content, the shell kept), B (a "Finish Setting Up" layer that replaces the shell, with Open Home Assistant and Sign Out) and C (an InfoBox notice at the top of each page over the pulsing skeleton); picked A, because it reuses the registered state-message pattern (one glyph, title, message and at most one action, centred in the free space), keeps tabs, Quick Links, Profile and Settings reachable, and changes in place when the server's answer changes. HIG Writing: "Provide clear next steps on any blank screens, with a button or link if possible." HIG Designing for iPhone Duo: "Preserve functionality, element state, hierarchy, and access across displays/poses." B lost: it removes navigation and Profile, adds a second root layer that would swap in and out of the shell when the status changes (a re-fade the no-reload rule forbids), and duplicates Sign Out. C lost: it keeps a loading skeleton pulsing under an error (HIG Progress indicators: "Keep indicators moving. If a process stalls, explain the problem and what people can do"), and a notice row at the top of a page is what the state-message pattern replaced ("Centred in the free space, never a row at the top").
