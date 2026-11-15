# Server field and missing house layout

> **What:** the Server row on sign-in (the owner's 2026-11-06 request, reversing the 2026-10-17 "no address field"), and where a house layout (the `fenton_home/house_config` document) that is missing, loading, broken or newer than the build is shown. **Read when:** you change sign-in, `LoginModel`, `HassServer`'s default, `HouseConfigStore` status handling, or the Home Assistant settings modal's Server section.

Task `house-config-design-states` (plan steps 6 and 10 of `build/research/house-config-runtime.md`; owner answers in `build/decisions/house-config-runtime.md`). Mockup: [proposal](mockups/proposals/house-config-states/house-config-states.html) (sign-in Options A, B, C and missing-layout Options A, B, C on all six windows, with the decided rules). The atlas pages [login](mockups/pages/login/login/login.html) and [home](mockups/pages/home/home/home.html) still map the app as it is; the implementing PR updates them.

## The request

Owner, 2026-11-06: "No discovery for now- just a textbox for you to enter the URL of HASS." Sign-in gets a server URL field; plan step 10's discovery is dropped; step 7's release build setting (`HASS_DEFAULT_SERVER`) may still prefill it. Step 7 also deletes the compiled house values, so a missing document becomes a state the person sees instead of a silent fallback.

**Evidence.** The owner's tier for this migration runs no simulator captures per change, so the options were judged from live-size atlas drawings built on the kit's sign-in and Home helpers (`pages/login/_login-launch-flows.js`) and from the code: `UKLoginViewController` / `UKLoginParts` (the module, rows, failure card and inline error), `LoginModel.Failure`, `HassServer`, `HouseConfigStore.Status` (`idle`, `loading`, `ready`, `notConfigured`, `integrationMissing`, `newerSchema`, `invalid`), `HouseConfigSource`, `UKStateMessageView`, `UKPendingValueBar` and `UKHomeAssistantSettings`. The end-of-migration capture pass (below) confirms the pick on devices.

## Decisions

Decision: 2026-11-06, judged sign-in Option A (a Server row as the first row of the one glass module: Server, Username, Password), B (a server step first: Server and Continue, then today's form under a "Signing in to ... Change" line) and C (today's form with a "Server ... Change" line under the module that expands into its own module); picked A, because it is the textbox the owner asked for, in the form people already use, with one more row and no new screen or hidden state. HIG Text fields: "Evenly space multiple fields; stack vertically when possible, with consistent widths" (A is three equal rows; C mixes a line and a module). HIG Entering data: "Be clear about the data you need ... You can prefill reasonable defaults" (A shows the field at all times, prefilled). B lost: every fresh sign-in becomes two screens, a new root state with Back and its own motion, for a check that A gets anyway, because step 1 of the login flow (`POST /auth/login_flow`) sends no password, so a wrong address is caught before credentials leave the phone. C lost: the address hides behind Change, so a wrong prefill is easy to miss; the form has two looks; and the owner asked for a visible textbox.

Gate: matches_request=yes (the brief's app-UI gate, `tools/jev_gate.py`: autonomous, local to a screen and owner-requested; the missing-layout states are plan step 6 of the same owner-approved migration)

Within A, the details below were decided by the Designer (propose-first: details inside the picked option). The saved-document rule and the missing-entity rule had no real alternative: the no-reload invariant settles them.

## Rules: the Server field (sign-in)

1. **Placement.** The first row of the glass module, above Username, same `UKLoginRowView` (label column 96 pt scaled, row 52 pt scaled, label above the field at accessibility sizes). Reading and Return order: Server, Username, Password, Sign In. On iPad and the unfolded Duo the column stays at most 460 pt and keeps its hinge placement.
2. **Label and hint.** Label "Server"; VoiceOver label "Server address"; placeholder `homeassistant.local:8123` (Home Assistant's own default address, generic).
3. **Keyboard.** `keyboardType = .URL`, `textContentType = .URL`, `autocapitalizationType = .none`, `autocorrectionType = .no`, `spellCheckingType = .no`, `smartDashesType = .no`, `smartQuotesType = .no`, `returnKeyType = .next`, `clearButtonMode = .whileEditing` (HIG Text fields: "show the appropriate keyboard type (such as numbers or URLs)", "Display a trailing Clear button"). Sign In needs all three fields filled (`canSubmit`).
4. **Normalising** (`HassServerAddress.parse`, HassCore, pure): trim; drop path, query, fragment and a trailing slash (as `HassServer.init` does); keep an explicit port. With no scheme, a **local host** gets `http://` and every other host gets `https://`, whatever its port. A local host is exactly what the app's ATS setting (`NSAllowsLocalNetworking`) lets through: a `*.local` name, `localhost`, a single-label name (no dot), or an RFC 1918, link-local or loopback IPv4 address, or an IPv6 address that is loopback, link-local (`fe80::/10`), unique-local or an IPv4-mapped private address. An IPv6 address is accepted only in brackets (`[fe80::1]:8123`); bare, it is `badAddress`. An internationalised (IDN) host is punycode in the URL and Unicode in the field. An explicit `http://` to any other host is `badAddress` (rule 5): the password never travels in clear text off the home network. The field shows the normalised address after it ends editing. Examples:

   | Typed | Becomes |
   |---|---|
   | `homeassistant.local:8123` | `http://homeassistant.local:8123` |
   | `homeassistant:8123` (single label) | `http://homeassistant:8123` |
   | `192.0.2.10:8123` | `http://192.0.2.10:8123` |
   | `ha.example.com` | `https://ha.example.com` |
   | `ha.example.org:8123` | `https://ha.example.org:8123` (a port never makes a host local) |
   | `http://ha.example.com` | `badAddress` |
   | `https://ha.example.com/lovelace/0?x=1` | `https://ha.example.com` |
   | `[fe80::1]:8123` | `http://[fe80::1]:8123` (local IPv6, brackets kept) |
   | `[2001:db8::1]` | `https://[2001:db8::1]` (public IPv6) |
   | `fe80::1` | `badAddress` (an IPv6 address needs its brackets) |
   | `münchen.example` | URL `https://xn--mnchen-3ya.example`; the field shows `https://münchen.example` |

5. **Errors, inline and next to the field** (HIG Writing: "Show errors next to the field and say how to enter information correctly"). Each puts a red hairline round the Server row (top corners follow the module), the red line with the warning glyph under the module, focus back in Server with the text kept, and a VoiceOver announcement, like a refused password:

   | Failure | When | Line |
   |---|---|---|
   | `badAddress` | the field ends editing or Sign In is pressed with text that does not parse, or `http://` to a non-local host | "Enter the address you open Home Assistant with, like homeassistant.local:8123." |
   | `notHomeAssistant` | `POST /auth/login_flow` answers, but not with a login flow (404, HTML, JSON without `flow_id`) | "Home Assistant didn't answer at that address. Check it and try again." |

   Unreachable (no answer: DNS, TLS, timeout, offline, gateway error) keeps today's card with Details and Try Again, reworded because the address may now be mistyped: title "Can't reach Home Assistant", body "Check the server address and that this phone is online. If both are right, Home Assistant may be restarting; try again in a minute." No hairline on Server for this one: the address may be right. Wrong password and two-step are unchanged.
6. **Prefill and memory.** Fresh form: the last server signed in to successfully (`RememberedAccountStore.server`, `UserDefaults`, not a secret), else the build's `HASS_DEFAULT_SERVER` (Info.plist), else empty with the placeholder. Debug builds keep `FENTON_HASS_SERVER` above both. A deliberate sign-out keeps the server and the username for the next form. No field takes focus by itself on appear (the intro plays first).
7. **Welcome back** (session expired): Server and Username are read-only rows (one element each: "Server, ha.example.com"; middle truncation when long), only Password is editable. Use a Different Account returns to the fresh form with the server still filled and the username empty.
8. **Switching servers** is sign out, then sign in with another address. Settings' Home Assistant modal keeps the address read-only. A different server starts with no saved layout or snapshot (both are keyed by server and cleared at sign-out), so it starts at the recovery boundary.
9. The footnote stays: "Your password goes only to your Home Assistant. S+H keeps a sign-in key in your Keychain, never the password."

## Identifiers and labels

The Coder's tests key on these; the mockup draws the same names but this list is the source.

| Element | Accessibility identifier | VoiceOver label and value |
|---|---|---|
| Server field (rules 1 to 3) | `login.server` | label "Server address", value the typed text |
| Server, read-only in welcome back (rule 7) | `login.server.readonly` | one element: "Server, <host>" |
| Username, Password, Sign In, inline error line, failure card | unchanged: `login.username`, `login.password`, `login.submit`, `login.error`, `login.error.card` | unchanged |
| House Layout row (rule 16) | `haSettings.houseLayout` | "House Layout, <value>" |

Reading order on sign-in: Server, Username, Password, Sign In.

## Rules: the house layout on every page

10. **A saved house document always wins.** While `HouseConfigSource.current` holds a document (this session's or the cache's), the layout on screen reads it, whatever the server says about the house document. The House Layout row says so (rule 16). A status change never blanks, re-fades or reorders the screen.
11. **No house document yet.** A published layout whose data sources need the house document is held, not rejected (`inputsPending`), and commits when the document arrives. With no last good layout the root shows the recovery boundary's waiting state ([server-ui-boundary](server-ui-boundary.md)). No page draws a skeleton.
12. **A house-document problem is named in one place:** the House Layout row (rule 16). Its value is the status's title from `HouseConfigCopy.entry(_:)`. No page draws a house-layout state message.

    | Status (no document) | Title |
    |---|---|
    | `integrationMissing` | Add the S+H Home Integration |
    | `notConfigured` | Home Isn't Set Up Yet |
    | `invalid` | Unable to Read the House Layout |
    | `newerSchema(found:)` | Update S+H |
    | `timedOut` | Unable to Load the House Layout |

13. **The document is picked up without the person acting.** A store whose status is not `ready` resubscribes on every reconnect and every return to the foreground (`resubscribeIfNeeded`), because HAKit retries a live subscription and not a refused one.
14. **Which screens.** None has a house-layout state of its own. Before a layout is on screen the recovery boundary is the whole root, and it carries Sign Out.
15. **A configured entity missing from Home Assistant** (the document names it, the first state set lacks it) draws exactly as an unavailable entity: the tile, chip or row reads "Unavailable", dimmed by the entity-tile rule, and is never hidden or moved (no reflow when it comes back). Before the first state set it pulses like any pending value.
16. **The Home Assistant modal's House Layout row** (Server section, after Version; identifier `haSettings.houseLayout`; a plain info row): "Loaded"; "Loaded, N not found" with a section footer "Not found in Home Assistant: <up to 5 entity ids>, and N more. Their tiles show Unavailable."; "Saved copy" with the footer "Home Assistant can't send the house layout right now (<reason in words>), so S+H shows the copy it saved."; "Waiting for Home Assistant"; and, with no document, the state's title. Everyone sees it; it is the only place a stale or partial layout is visible.

## End-of-migration capture pass

On GitHub Actions after the move (owner, 2026-11-06), the Verifier captures, on iPhone, the folded Duo, the unfolded Duo (portrait, landscape flat and landscape partly folded) and iPad (portrait and landscape), at the default size and AX5, and judges each against the proposal mockup:

- Sign-in: fresh with no server (placeholder, Sign In off), prefilled, `badAddress`, `notHomeAssistant`, unreachable card, welcome back (server and username read-only), the URL keyboard up on the folded Duo (Sign In reachable by scrolling), long address read-only (middle truncation).
- The root with no last good layout: each recovery boundary state ([server-ui-boundary](server-ui-boundary.md)), Try Again busy, and the partly folded Duo (the column in the leading region).
- A saved layout with the server answering `integrationMissing` (page unchanged, modal row "Saved copy"), and a missing entity (tile Unavailable, modal row and footer).
- Accessibility audits on each: labels and order (Server, Username, Password, Sign In; the boundary's heading, message, then its buttons), 44 pt targets, AX5 with no clipping.

## Rules that change elsewhere

- `.agents/platforms/apple/auth.md` "Sign-in screen": the server is no longer fixed; the Coder replaces the "no address field" sentence and the error table with rules 1 to 9 (in the implementing PR, with the code).
- `.agents/pages/home/spec.md` States: the first-sign-in row and the new rows (updated in this change).
- `.agents/patterns/state-message.md`: the `newerSchema` exception to "a failed load always has a way forward" (the Coder adds it with the first consumer).
