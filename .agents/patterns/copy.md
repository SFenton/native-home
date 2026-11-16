# Copy

> **What:** how the app words itself: voice, terms, case, length, string ids, and which text the house can override. **Read when:** you add, move or reword text a person sees or hears, or touch the strings table.

- HIG: Writing ("Keep and reference a list of common terms"; "Choose a capitalization style per UI element type and apply it consistently"), Alerts, Buttons, VoiceOver.
- Copy is authored English; nothing is localised.
- Canonical components: `HassCore/Weather/WeatherCopy.swift` (`WeatherCopy`, the keyed-table form) and `HassCore/Text/PluralCopy.swift` (`PluralCopy`, the plural rule). TODO(orchestrator): name the one HassCore lookup that takes over from both and from every `*Copy` enum.
- These records keep their own words: [alerts](alerts.md), [state-message](state-message.md), [app-name](../platforms/apple/app-name.md).

## Voice

- Plain and short, verb first, active voice. Address the person as "you"; never "we" (HIG Writing).
- A failure says what happened, then the next step, without blame (HIG Writing). No "please", "sorry" or "oops".
- Contractions with a straight apostrophe, US spelling, the serial comma. An ellipsis is the single character `…`.
- The product is "S+H" and the server is "Home Assistant", in full.

## Terms

One word per concept. The right column is never written for that concept.

| Concept | Write | Not |
|---|---|---|
| Retry | Try Again | Retry |
| A failed action | Couldn't `<verb>` | Could not, Unable to, "`<thing>` failed" |
| A failed load | Unable to Load `<Subject>` | Couldn't Load |
| A standing block | Can't `<verb>` | Cannot, Unable to |
| An entity with no state | Unavailable | Offline, Not Available |
| The device without a network | Offline | No Connection, Not Connected |
| Session | Sign In, Sign Out; the noun is "sign-in" | Log In, Log Out |
| Power | Turn On, Turn Off; the state is On or Off | Enable, Disable, Enabled or Disabled for a two-state thing |
| Destroy a record | Delete | Remove |
| Take out of a list or draft | Remove | Delete |
| Pick an option | Choose | Select, Pick |
| Mark items in a list | Select | Choose |
| This device | this iPhone, this iPad (`{{device}}`) | this phone, this device |
| Stopped by a person | Canceled | Cancelled |
| Work under way | a gerund plus `…` | three dots; a bare gerund on a visible label |

## Case, form and length

Max counts the characters of the rendered string, with the catalog's sample arguments. It is the id's catalog `maxLength`: the Studio warns above it and the app never truncates by it. No entry exceeds 240 characters, or 2,000 in an id marked `multiline`.

| Surface | Case | Form | Max |
|---|---|---|---|
| Alert and dialog title | see [alerts](alerts.md) | | 40 |
| Button, menu item | Title Case | verb first, at most three words, no punctuation (HIG Buttons) | 24 |
| Tile action verb | Title Case | a verb, or a verb and its object | 12 |
| Tile title | Title Case | noun phrase, no period | 24 |
| Tile subtitle, state word, status pill | Title Case | fragment, no period ("All Closed") | 16 |
| Navigation, sheet and page title | Title Case | noun phrase, no period | 28 |
| Section header | Title Case | noun phrase; no colon, no period | 32 |
| Row title | Title Case | noun phrase, no period | 40 |
| Row subtitle | Sentence case | fragment, no period | 60 |
| Empty and error state title | Title Case | fragment, no period ("No Chores Due") | 32 |
| Alert or state message, footer, help text | Sentence case | full sentences, each with its period (HIG Alerts) | 160 |
| Inline failure or status line | Sentence case | a full sentence with its period | 80 |
| Progress label on a control | Title Case | gerund plus `…` ("Turning On…") | 24 |
| Field placeholder | Sentence case | an example or a description, no period (HIG Writing) | 32 |
| Accessibility label | the visible string; else Title Case | names the thing, never its control type; no period | 80 |
| Accessibility value | as its parts | joined by a comma and a space; the state last | 80 |
| Accessibility hint | Sentence case | third-person verb, no subject, no period ("Opens its details") | 60 |

## Ids

- Grammar: `<area>.<component>.<slot>[.<role>]`, with `_one` or `_other` appended to a plural pair.
- Each segment is lower camel case. The base id matches `^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*){2,4}$` and is at most 120 characters.
- `area` is the feature (`rooms`, `vacuum`), never the kind of view: a slot is drawn on several surfaces, so its surface is catalog data. `common` holds words every area shares; `custom` is reserved for authored ids.
- `slot` names the meaning, never the wording (`retry`, not `tryAgain`), so a reworded string keeps its id. An id never changes meaning.
- `role` is `a11y`, `hint` or `value`: the spoken form of a visible slot. Without one, VoiceOver reads the visible string.
- Plural: `_one` when `count` is exactly 1, `_other` for every other count. A pair has both members.

## Placeholders

- The form is `{{name}}` and nothing else: no expression, no nesting, no escape.
- Names come from this list: `count` (an integer; it selects the plural), `name` (an entity, room, person or item name from Home Assistant), `title` (a page or node title), `value` (a formatted number with its unit), `time`, `date`, `duration`, `device` ("iPhone" or "iPad"), `noun` (another slot's text).
- The app formats every argument before it substitutes. An override may drop a placeholder and never adds one. A string has at most three.
- Text is plain: no HTML, no Markdown, no control or format character, no leading or trailing space. A newline appears only in an id marked `multiline`.
- One slot holds one whole sentence. Never join slots into a sentence, except through `noun`.

## Inline or slot

| Text | Home |
|---|---|
| Names or describes one authored node: a tile title, section header, row label, page title, chrome label, setup explanation | an inline prop on the node |
| Chosen or composed by the app, or drawn on several surfaces: state words, failures, empty states, count nouns, progress labels, built-in questions | a slot in the table |
| Shown before a publication exists, or read by the system: sign-in, layout recovery, permission rationale, App Intents, Siri phrases, `Info.plist` | compiled only; the catalog lists it as boundary |
| Names and states that Home Assistant sends | data, never copy |

- The test: when two nodes of one type could want different words, the text is inline; when the app picks the words, it is a slot.
- Resolution order: the node's inline prop, then the table entry, then the compiled default. The table holds overrides only.
- An array of candidate strings that sizes a view reads the same lookup, so the longest override is measured.
- User-facing text is never a literal in a view.

## Pinned

These ids carry `overridable: false` in the catalog; the table cannot reword them.

1. Alarm: the arm and disarm verbs, every alarm state word, the disarm question and its message, and their spoken forms.
2. Lock: Lock, Unlock, every lock state word including the jammed state, and the unlock question.
3. Garage door: Open, Close, and its state and progress words.
4. The words for no state on any tile: "Unavailable" and "Unknown".
5. Cancel, and every destructive-role button label (HIG Alerts: "Always title a button that cancels the alert's action 'Cancel'").
6. A sentence that says what leaves the device or what is erased.

Other cover and valve words are overridable and carry the catalog's `safety` flag, on which the Studio warns. Inline text on a node bound to an alarm or a lock gets the same warning. Every other accessibility string is overridable.

## Migration

- A string that moves into the catalog keeps its default byte for byte, proved by an equality test per id. That is not a visible change and needs no proposal.
- A string that did not exist, or a default reworded to meet this record, is a visible change: [propose-first](../workflow/propose-first.md).
- A default that breaks a rule here stays until its proposal is approved. When it is longer than its budget, its `maxLength` is its own length.
- Whoever rewrites a file takes its literals, and retires that file's `*Copy` enum in the same change.
