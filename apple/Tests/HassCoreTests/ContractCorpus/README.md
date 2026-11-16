# Shared publication corpus

One set of publication envelopes that both the Studio (TypeScript) and the native app (Swift) must treat the same way.
Both repositories carry this directory byte for byte; change it in one and copy it to the other.

- `accept/*.json`: full schema-2 publication envelopes. Each must decode.
- `reject/*.json`: each must fail, and the first issue (issues sorted by pointer, then code, which is what the app
  throws) must equal the `issue` recorded in `index.json`: `code`, `pointer`, and `capability` when the code is
  `unsupported_capability`. The files are raw bytes; some (duplicate keys) are not producible by `JSON.stringify`.
- `index.json`: every file once, its expected outcome and a note. A few older entries still carry a `houseScripts` list;
  it is ignored now that the app accepts any script (no house document is needed).
- `capabilities.json`: the capability strings the app compiler supports, sorted, generated from
  `ServerUICompositionPublication.supportedCapabilities`. The Studio asserts its own list equals this file; the app asserts
  its Swift list equals it. Adding or renaming a capability on one side fails the other side's test until the file and
  both lists agree.
- `accept/fixture-*.json` are the shared test fixtures, byte-identical to `tests/fixtures/*.json`. The other accept
  files were captured from documents the Studio test suite compiles, chosen so the accepted files together name every
  capability, plus hand-authored provider documents (`device-*`), `family-modal-handoff` and the `collection-pull-to-refresh-*` pair.

Origin of the reject cases: the five bedroom fields the app removed (`tonightScript`, `outsideScheduleScript`,
`scheduleSetTopic`, `hotFlashBrokerScript`, `householdAwayScript`), remote commands outside the per-slot service
vocabulary (`ServerUIServiceVocabulary.swift`), keys that are equal only after Unicode NFC normalisation, an unknown
capability, a capability manifest that does not match the document, schema 1 envelopes, the reserved `__proto__`
key, Home-node actions that try `replace`, and a non-boolean `pullToRefresh`.

The `grammar-*` files (14 accept, 45 reject) cover the generic grammar of native-home commit 7154723: `call-service`
actions, bound controls (toggle, stepper, slider, choice, button), the operand and predicate language, `visibleWhen`
on nodes and tabs with `whenUnknown`, and `selectedWhen` on local tabs. They are written by
`scripts/generate-grammar-corpus.ts` from the shared first-slice fixture; do not edit them by hand. The eight remote
vocabulary rejects became accepts when the per-slot service tables and the house-script check were removed
(native-home 4237c97).

The `todo-collection-*` files (5 accept, 18 reject) cover the `todo-collection@1` source, the record page that house
configuration's `chores.pages` used to define: lists with an optional user-id rule and completion script, what Add creates,
the empty state and the resident variant. They are written by `scripts/generate-todo-collection-corpus.ts` from the same
fixture; do not edit them by hand. `todo-collection-collection-without-source` records that a todo collection node whose
source is not defined still compiles: the app shows nothing for it and never reads house configuration.

The `state-style-*` files (8 accept, 26 reject) cover `sh.state-style@1`: the document-level style library (rules, fallback,
actions, request settings, the closed indicator list, the arc refused on a state with an action) and the `state-tile` node
(style id, the tile's built-in style, per-state overrides). They are written by `scripts/generate-state-style-corpus.ts`; do not
edit them by hand. `state-styles/built-in.json` is the eight built-in styles as data: not a case, but a fixture the Studio and the
app both test their own built-in data against.
