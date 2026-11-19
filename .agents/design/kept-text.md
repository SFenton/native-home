# Kept text

> **What:** how a server-composed text slot looks and sounds while it shows a kept value (`sh.text-keep@1`, `whenUnavailable: "keep"`). **Read when:** you touch a text slot's host (text node, tile title or subtitle, status pill, row, info box, dial, collection empty message, local control subtitle), its VoiceOver value, or propose a staleness cue.

Proposal: [text-keep.html](mockups/proposals/text-keep/text-keep.html). Atlas: [kept-text](mockups/components/loading/kept-text/README.md). Contract: Studio `docs/native-composition.md`, "Keeping unavailable text (sh.text-keep@1)".

## Rules

1. **Kept text is drawn and spoken exactly as live.** No glyph, no grey or other ink change, no "last known" or other VoiceOver cue, no announcement when a slot moves between live and kept. An authored spoken value (`value.spoken`, `a11y.value`) is spoken unchanged. Live and kept tiles keep the same frame height.
2. **Before any answer, the fallback.** A `keep` slot whose source is unavailable before it was ever answered draws its authored fallback ("No reading"), or the host's usual empty or unknown text when none is authored. It never draws the loading look (placeholder, pending bar, "Loading").
3. **Loading keeps what it showed**, under both policies: a reconnect or a cold launch from the snapshot never blanks or flashes a slot (AGENTS "No reload on reopen").
4. **Recovery is silent.** Kept back to live changes only the text, when it changed, in the same frame; a real text change announces as any live change does (`announcement: valueChange`).
5. **Every read or expr text slot can keep.** The memory of a slot lives on the retained node (`UKServerUINode.textMemories`, keyed by slot name) or the retained row, so a publication update, a content-size change or a layout-direction change draws the kept text again.
6. **Staleness lives in the Studio.** The app does not show it. A future cue (glyph, grey step, spoken suffix) is a visible change and goes through [propose-first](../workflow/propose-first.md).

## HIG

- Loading, "Show something quickly": the last answer is shown instead of "Unavailable", and before an answer the authored fallback.
- VoiceOver, "keep labels current as interface and content change": the label and value stay the text that is drawn.
- Color ("Avoid relying solely on color") does not come into play: A draws no state, so colour has nothing to carry.

## Where

- Engine: `apple/Sources/HassCore/ServerUIComposition/ServerUITextKeep.swift` (`ServerUIUnavailablePolicy`, `ServerUITextMemory`).
- Hosts: `UKServerUIBindings.string(_:memory:)` through `UKServerUITextMemories`, from `UKServerUIPage`, `UKServerUIPage+Rules`, `UKServerUIDataParts`, `UKServerUIStyleParts`, `UKServerUIShellAtoms` and `UKServerUIStateTileViews`; `UKServerUIRow` and the map controls keep their own.
- Gallery: `UKTextKeepGallery`.
- Tests: `ServerUITextKeepTests`, `ServerUITextKeepHostedTests`, `ServerUITextKeepRerenderHostedTests`, `iOSUITests/KeptTextJourneyTests`.
- Copy rule: [copy](../patterns/copy.md).
