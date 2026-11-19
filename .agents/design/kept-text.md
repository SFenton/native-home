# Kept text

> **What:** how a server-composed text slot looks and sounds while it shows a kept value (`sh.text-keep@1`, `whenUnavailable: "keep"`), chosen by the owner 2026-11-19. **Read when:** you touch a text slot's host (text node, tile title or subtitle, status pill, row, local control subtitle), its VoiceOver value, or propose a staleness cue.

Proposal: [text-keep.html](mockups/proposals/text-keep/text-keep.html) (A plain, B spoken, C marked). Atlas: [kept-text](mockups/components/loading/kept-text/README.md). Contract: Studio `docs/native-composition.md`, "Keeping unavailable text (sh.text-keep@1)".

Decision (owner, 2026-11-19): judged Option A, B and C; the owner picked **A**, explicitly, after seeing all three with screenshots on iPhone, Duo and iPad, because kept text should look and sound exactly like a live value: no glyph, no colour change, no VoiceOver change.

Gate: parked as `matches_request=unsure` (2026-11-18); the owner then picked A, so `matches_request=yes`.

## The question

A text slot with `whenUnavailable: "keep"` whose source reads unavailable after at least one answer keeps drawing that last answer ("kept"). Should a kept value look or sound different from a live one?

## The options judged

- **A, plain.** Kept is drawn and spoken exactly as live: same token, weight and alpha, no glyph, same VoiceOver label, value and hint, no announcement on entering or leaving kept. **Picked.**
- **B, spoken.** Drawn as A; the element's VoiceOver value gains ", last known", once per element.
- **C, marked.** B, plus the kept text steps to `HassTokens.Ink.unavailable` grey where the live ink is a neutral, and a leading `clock.arrow.circlepath` glyph sized to the text.

Designer's advisory lean was **C**: a reading that may be hours old should not look current to anyone, and C reused the grey unavailable tiles already use, with a glyph so it never relied on colour alone (HIG Color, "Avoid relying solely on color"). **Overridden by the owner.** The evidence also counted against C: on iPhone and Duo folded the glyph wrapped "21.5 degrees" in a two-column tile, so tiles grew a line when a sensor dropped, and a Home Assistant restart would mark many slots at once. The A, B and C captures are kept outside the repo in `build/evidence/claude-text-keep/abc-archive/`.

## Rules

1. **Kept text is drawn and spoken exactly as live.** No glyph, no grey or other ink change, no "last known" or other VoiceOver cue, no announcement when a slot moves between live and kept. An authored spoken value (`value.spoken`, `a11y.value`) is spoken unchanged. Live and kept tiles keep the same frame height.
2. **Before any answer, the fallback.** A `keep` slot whose source is unavailable before it was ever answered draws its authored fallback ("No reading"), or the host's usual empty or unknown text when none is authored. It never draws the loading look (placeholder, pending bar, "Loading").
3. **Loading keeps what it showed**, under both policies, as before: a reconnect or a cold launch from the snapshot never blanks or flashes a slot (AGENTS "No reload on reopen").
4. **Recovery is silent.** Kept back to live changes only the text, when the text changed, in the same frame; a real text change announces as any live change does (`announcement: valueChange`).
5. **Staleness lives in the Studio.** The app does not show it. Any future cue (a glyph, a grey step, a spoken suffix) is a new visible change and goes through [propose-first](../workflow/propose-first.md); it does not reopen this decision silently.

## HIG

- Loading: "**Show something quickly:** otherwise people may think the app is broken; use placeholder text, graphics, or animations until content arrives." The last answer is shown instead of "Unavailable", and before an answer the authored fallback.
- VoiceOver: "be sure to keep labels current as interface and content change." The label and value stay the text that is drawn; kept and live text are the same content.
- Color and Accessibility ("Avoid relying solely on color", "Convey state and function with shapes or icons in addition to color") do not come into play: A draws no state, so there is nothing colour alone could carry.

## Where

Engine: `apple/Sources/HassCore/ServerUIComposition/ServerUITextKeep.swift` (`ServerUIUnavailablePolicy`, `ServerUITextMemory`, `ServerUITextOutcome`). Hosts: `UKServerUIBindings.string(_:memory:)`, called from `UKServerUIPage` (text node, status pill value and detail, glass tile subtitle), `UKServerUIPage+Rules` (local control subtitle), `UKServerUIShellPrimitives` (`UKServerUIRow`: primary, secondary, value) and `UKServerUIStateTileViews`. Gallery: `UKTextKeepGallery`. Tests: `ServerUITextKeepTests`, `ServerUITextKeepHostedTests`, `iOSUITests/KeptTextJourneyTests` (label, value, glyph count and frame height identical live and kept on each host; no "last known" in any read; the fallback before an answer). Copy rule: [copy](../patterns/copy.md).
