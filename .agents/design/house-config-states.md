# Server field and missing house layout

> **What:** the Server row on sign-in (the owner's 2026-11-06 request, reversing the 2026-10-17 "no address field"), and what every page shows when the house layout (the `fenton_home/house_config` document) is missing, loading, broken or newer than the build, once the compiled house values are gone. **Read when:** you change sign-in, `LoginModel`, `HassServer`'s default, `HouseConfigStore` status handling, the first-sign-in look of any page, or the Home Assistant settings modal's Server section.

Task `house-config-design-states` (plan steps 6 and 10 of `build/research/house-config-runtime.md`; owner answers in `build/decisions/house-config-runtime.md`). Mockup: [proposal](mockups/proposals/house-config-states/house-config-states.html) (sign-in Options A, B, C and missing-layout Options A, B, C on all six windows, with the decided rules). The atlas pages [login](mockups/pages/login/login/login.html) and [home](mockups/pages/home/home/home.html) still map the app as it is; the implementing PR updates them.

## The request

Owner, 2026-11-06: "No discovery for now- just a textbox for you to enter the URL of HASS." Sign-in gets a server URL field; plan step 10's discovery is dropped; step 7's release build setting (`HASS_DEFAULT_SERVER`) may still prefill it. Step 7 also deletes the compiled house values, so a missing document becomes a state the person sees instead of a silent fallback.

**Evidence.** The owner's tier for this migration runs no simulator captures per change, so the options were judged from live-size atlas drawings built on the kit's sign-in and Home helpers (`pages/login/_login-launch-flows.js`) and from the code: `UKLoginViewController` / `UKLoginParts` (the module, rows, failure card and inline error), `LoginModel.Failure`, `HassServer`, `HouseConfigStore.Status` (`idle`, `loading`, `ready`, `notConfigured`, `integrationMissing`, `newerSchema`, `invalid`), `HouseConfigSource`, `UKStateMessageView`, `UKPendingValueBar` and `UKHomeAssistantSettings`. The end-of-migration capture pass (below) confirms the pick on devices.

## Decisions

Decision: 2026-11-06, judged sign-in Option A (a Server row as the first row of the one glass module: Server, Username, Password), B (a server step first: Server and Continue, then today's form under a "Signing in to ... Change" line) and C (today's form with a "Server ... Change" line under the module that expands into its own module); picked A, because it is the textbox the owner asked for, in the form people already use, with one more row and no new screen or hidden state. HIG Text fields: "Evenly space multiple fields; stack vertically when possible, with consistent widths" (A is three equal rows; C mixes a line and a module). HIG Entering data: "Be clear about the data you need ... You can prefill reasonable defaults" (A shows the field at all times, prefilled). B lost: every fresh sign-in becomes two screens, a new root state with Back and its own motion, for a check that A gets anyway, because step 1 of the login flow (`POST /auth/login_flow`) sends no password, so a wrong address is caught before credentials leave the phone. C lost: the address hides behind Change, so a wrong prefill is easy to miss; the form has two looks; and the owner asked for a visible textbox.

Decision: 2026-11-06, judged missing-layout Option A (a state message in place of each page's content, the shell kept), B (a "Finish Setting Up" layer that replaces the shell, with Open Home Assistant and Sign Out) and C (an InfoBox notice at the top of each page over the pulsing skeleton); picked A, because it reuses the registered state-message pattern (one glyph, title, message and at most one action, centred in the free space), keeps tabs, Quick Links, Profile and Settings reachable, and changes in place when the server's answer changes. HIG Writing: "Provide clear next steps on any blank screens, with a button or link if possible." HIG Designing for iPhone Duo: "Preserve functionality, element state, hierarchy, and access across displays/poses." B lost: it removes navigation and Profile, adds a second root layer that would swap in and out of the shell when the status changes (a re-fade the no-reload rule forbids), and duplicates Sign Out. C lost: it keeps a loading skeleton pulsing under an error (HIG Progress indicators: "Keep indicators moving. If a process stalls, explain the problem and what people can do"), and a notice row at the top of a page is what the state-message pattern replaced ("Centred in the free space, never a row at the top").

Gate: matches_request=yes (the brief's app-UI gate, `tools/jev_gate.py`: autonomous, local to a screen and owner-requested; the missing-layout states are plan step 6 of the same owner-approved migration)

Within A and A, the details below were decided by the Designer (propose-first: details inside the picked option). The skeleton, the saved-layout rule and the missing-entity rule had no real alternative: the owner's "no full-screen spinner" (2026-10-24), motion.md section 5 and the no-reload invariant settle them.

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
8. **Switching servers** is sign out, then sign in with another address. Settings' Home Assistant modal keeps the address read-only. A different server starts with no saved layout or snapshot (both are keyed by server and cleared at sign-out), so it gets the first-sign-in skeleton.
9. The footnote stays: "Your password goes only to your Home Assistant. S+H keeps a sign-in key in your Keychain, never the password."

## Identifiers and labels

The Coder's tests key on these; the mockup draws the same names but this list is the source.

| Element | Accessibility identifier | VoiceOver label and value |
|---|---|---|
| Server field (rules 1 to 3) | `login.server` | label "Server address", value the typed text |
| Server, read-only in welcome back (rule 7) | `login.server.readonly` | one element: "Server, <host>" |
| Username, Password, Sign In, inline error line, failure card | unchanged: `login.username`, `login.password`, `login.submit`, `login.error`, `login.error.card` | unchanged |
| Home skeleton (rule 11) | `home.skeleton` | one element, label "Getting your home from Home Assistant"; the shapes are hidden |
| Any other page's skeleton (rule 11) | `page.skeleton` | the same label |
| State message container (rule 12) | `houseConfig.state` | the title is a heading, then the message; the glyph is hidden |
| State message action (rule 12) | `houseConfig.action` | the action title ("Open Integrations", "Open S+H Home Integration", "Open Repairs", "Try Again"; busy value "Trying Again") |
| House Layout row (rule 16) | `haSettings.houseLayout` | "House Layout, <value>" |

Reading order on sign-in: Server, Username, Password, Sign In. The header's "Connecting to Home Assistant" arc keeps its own label beside the skeleton.

## Rules: the house layout on every page

10. **A saved layout always wins.** While `HouseConfigSource.current` holds a document (this session's or the cache's), every page draws from it as usual, whatever the server says now (`notConfigured`, `integrationMissing`, `newerSchema`, `invalid`, a timeout, offline). Nothing on the page changes; the Home Assistant modal's House Layout row says so (rule 16). A status change never blanks, re-fades or reorders a page that has a document.
11. **First sign-in, no saved layout: a skeleton, never a spinner.** While there is no document and the store is `idle` or `loading` (offline included), each page whose body comes from the layout draws a skeleton in its own shape: Home has four chip capsules, the weather module, one section bar and four camera-shaped tiles (2 columns compact, 4 at 700 pt and wider; on a partly folded Duo the fold columns put the rail on top, the module leading and the tiles trailing); every other page has the generic one (a section bar and four tiles, a bar and two). Shapes are `UKPendingValueBar`'s fill and pulse (opacity 0.35 to 1 over 1.4 s; Reduce Motion: static at 65%; motion.md section 5, no shimmer). The header keeps the one "Connecting to Home Assistant" arc while connecting; offline it shows the offline chip instead, as today. When the document arrives the skeleton fades out (`quick`) and the page fades in and rises 4 pt in 170 ms (content-gate step 3; Reduce Motion fades only); values then pulse until states land, as today.
12. **No document and the server answered with a problem: a state message.** `UKStateMessageView` in place of the page's content, centred in the free space (`UKStateMessageOverlay`; on a window with a hinge band it sits in the leading region, by `HingeAvoidance`, never across the band). The page title, tabs or rail, Quick Links, Profile and Settings stay. The skeleton fades out and the message fades in (`quick`). The integration's name is one constant, `HouseConfigCopy.integrationName` (its manifest name, "S+H Home Integration", `SFenton/ha-fenton-home` manifest.json).

    | Status (no document) | Glyph | Title | Message, administrator or owner | Message, everyone else | Action (administrators only) |
    |---|---|---|---|---|---|
    | `integrationMissing` (`unknown_command`: not installed or older than the command) | `puzzlepiece.extension` | Add the S+H Home Integration | S+H gets your rooms, cameras and controls from the S+H Home Integration in Home Assistant. Install or update it there; S+H picks it up by itself. | S+H gets your rooms, cameras and controls from the S+H Home Integration in Home Assistant. Ask whoever manages your Home Assistant to install or update it. | Open Integrations: `/config/integrations/dashboard` |
    | `notConfigured` (`{configured: false}`) | `house` | Home Isn't Set Up Yet | The S+H Home Integration is installed but has no house layout yet. Add one in Home Assistant; S+H picks it up by itself. | The S+H Home Integration is installed but has no house layout yet. Ask whoever manages your Home Assistant to add one. | Open S+H Home Integration: `/config/integrations/integration/fenton_home` |
    | `invalid` (the server refused its file and raised a Repair, or the app could not decode the reply) | `exclamationmark.triangle` | Unable to Read the House Layout | Home Assistant lists what's wrong under Repairs. Fix it there; S+H picks it up by itself. | Ask whoever manages your Home Assistant to check Repairs. | Open Repairs: `/config/repairs` |
    | `newerSchema(found:)` | `arrow.down.circle` | Update S+H | This Home Assistant has a newer house layout than this version of S+H can read. Update S+H to see your home. | (same) | none: the way forward is an app update (recorded exception to the state-message rule that a failed load carries Try Again) |
    | `timedOut` (new: connected for 10 s with no answer; `DASHBOARD_PAGE_LOAD_TIMEOUT_MS` precedent) | `exclamationmark.triangle` | Unable to Load the House Layout | Home Assistant hasn't sent the house layout. Try again; if it keeps happening, restart Home Assistant. | (same) | Try Again (everyone): resubscribe; busy title "Trying Again" |

    Administrator means `HassUser.isAdmin || isOwner` from `HassConnection.currentUser()`, the modal's Settings gate. Until that answers, show the "everyone else" message without an action; when it says administrator, the message and the button swap in place (`quick`). The action opens the Home Assistant modal (`UKHomeAssistantSettingsViewController`) with that web page already pushed (a new `HomeAssistantSettingsView.WebPage` case per path); Back returns to the modal, Close to the page.
13. **"Picks it up by itself" must be true.** A store whose status is not `ready` resubscribes on every reconnect and every return to the foreground (HAKit retries a live subscription, not a refused one), and a `reload_house_config` push or a restart that installs the integration replaces the message with the page (rule 11's fade) with no action from the person.
14. **Which screens.** Every screen whose body reads a `HouseConfigSource` section shows rules 11 and 12 (Home, Security, Climate, Rooms and room pages, Media, Custom Lights, Sprinklers, Vacuums, Food, Vacation, Chores and the household topics). Navigation chrome, the Settings root, Profile's account and Sign Out, and the Home Assistant modal never depend on the document; if one does today, it falls back to its fixed items.
15. **A configured entity missing from Home Assistant** (the document names it, the first state set lacks it) draws exactly as an unavailable entity: the tile, chip or row reads "Unavailable", dimmed by the entity-tile rule, and is never hidden or moved (no reflow when it comes back). Before the first state set it pulses like any pending value.
16. **The Home Assistant modal's House Layout row** (Server section, after Version; identifier `haSettings.houseLayout`; a plain info row): "Loaded"; "Loaded, N not found" with a section footer "Not found in Home Assistant: <up to 5 entity ids>, and N more. Their tiles show Unavailable."; "Saved copy" with the footer "Home Assistant can't send the house layout right now (<reason in words>), so S+H shows its saved copy."; "Waiting for Home Assistant"; and, with no document, the state's title. Everyone sees it; only here does a stale layout show.
17. **Facade-built structure is rebuilt** on a new document or hash ([page-base](../patterns/page-base.md)).

## End-of-migration capture pass

On GitHub Actions after the move (owner, 2026-11-06), the Verifier captures, on iPhone, the folded Duo, the unfolded Duo (portrait, landscape flat and landscape partly folded) and iPad (portrait and landscape), at the default size and AX5, and judges each against the proposal mockup:

- Sign-in: fresh with no server (placeholder, Sign In off), prefilled, `badAddress`, `notHomeAssistant`, unreachable card, welcome back (server and username read-only), the URL keyboard up on the folded Duo (Sign In reachable by scrolling), long address read-only (middle truncation).
- Home and Security: the first-sign-in skeleton (online and offline), each state message as administrator and as a member, `timedOut` with Try Again busy, the skeleton-to-page and message-to-page transitions under Reduce Motion, the partly folded Duo (message in the leading region, skeleton in fold columns).
- A saved layout with the server answering `integrationMissing` (page unchanged, modal row "Saved copy"), and a missing entity (tile Unavailable, modal row and footer).
- Accessibility audits on each: labels and order (Server, Username, Password, Sign In; the skeleton's one element; the message heading then the button), 44 pt targets, AX5 with no clipping.

## Rules that change elsewhere

- `.agents/platforms/apple/auth.md` "Sign-in screen": the server is no longer fixed; the Coder replaces the "no address field" sentence and the error table with rules 1 to 9 (in the implementing PR, with the code).
- `.agents/pages/home/spec.md` States: the first-sign-in row and the new rows (updated in this change).
- `.agents/patterns/state-message.md`: the `newerSchema` exception to "a failed load always has a way forward" (the Coder adds it with the first consumer).
