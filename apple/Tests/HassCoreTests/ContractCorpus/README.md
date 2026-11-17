# Shared publication corpus

One set of publication envelopes that both the Studio (TypeScript) and the native app (Swift) must treat the same way.
Both repositories carry this directory byte for byte; change it in one and copy it to the other.

- `accept/*.json`: full schema-2 publication envelopes. Each must decode.
- `reject/*.json`: each must fail, and the first issue (issues sorted by pointer, then code, which is what the app
  throws) must equal the `issue` recorded in `index.json`: `code`, `pointer`, and `capability` when the code is
  `unsupported_capability`. The files are raw bytes; some (duplicate keys) are not producible by `JSON.stringify`.
- `index.json`: every file once, its expected outcome and a note. A few older entries still carry a `houseScripts` list;
  it is ignored now that the app accepts any script (no house document is needed).
- `capabilities.pending.json`: Studio-owned, sorted. Capabilities the Studio compiles and the corpus exercises that the app does not list
  yet. Shipped and pending are disjoint and the Studio's supported list is their union. When the app ships a capability, one app change
  adds it to its list, regenerates `capabilities.json`, moves its `pending-*` cases from `reject/` to `accept/` with the real expectation
  and drops it from this file.
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

The `state-style-*` files (8 accept, 26 reject, and the `fills` cases below) cover `sh.state-style@1`: the document-level style library (rules, fallback,
actions, request settings, the closed indicator list, the arc refused on a state with an action) and the `state-tile` node
(style id, the tile's built-in style, per-state overrides). They are written by `scripts/generate-state-style-corpus.ts`; do not
edit them by hand. The `state-style-fills-*` files (6 compiled, 12 refused; a compiled case is `reject/pending-state-style-fills-*`) cover `sh.state-style-fills@1`, still pending:
a per-state `fill` (the document's `solid-rgb`) on a rule or the fallback, and the style's `hiddenWords`. The refused ones are a bad channel, a
fill that is not a `solid-rgb`, a fill on a tile override, a rule that gives `unavailable` a class other than unknown, and bad hidden words.
`state-styles/built-in.json` is the eight built-in styles as data: not a case, but a fixture the Studio and the
app both test their own built-in data against.

**Pending cases.** An envelope that declares a pending capability is refused by the app's shipped list at the first capability it does not
list, before anything else (`unsupported_capability`, pointer `/capabilities/<n>`). Such a case lives in `reject/`, is marked `"pending": true`,
and records that refusal as its `issue`, so the app's test already passes with no native change. A case the Studio compiles is named
`reject/pending-<family>-*.json`; a case the Studio refuses for its own reason also records `studioIssue`, the Studio's first issue (the app
reads `file`, `outcome`, `issue` and ignores the other keys). The Studio test holds both: the shipped list gives `issue`, the Studio gives
`studioIssue` (or none). Every pending capability must appear in a case the Studio compiles.

**Promotion.** Once the app ships a capability, a case that declares no other pending id is an ordinary case: a compiled one is
`accept/<family>-*.json` (the `pending-` prefix dropped), a refused one stays `reject/<family>-*.json` with `issue` set to what was `studioIssue`
(the app must give the same first issue), and neither carries `pending`. A case that also declares a still-pending id stays pending and its
`issue` points at the first id the app does not list. The generators decide this from `capabilities.json` through `scripts/corpus-handshake.ts`,
so shipping an id is: update `capabilities.json` and `capabilities.pending.json`, move the id from `pending.ts` into the explicit list in
`compiler.ts`, and rerun the generators. Shipped through native-ingest L0 to L3, NT1 and L1b: every capability but `sh.pipeline@1`,
`sh.pipeline-operands@1` and `sh.list-parts@1` (`sh.list-read@1`, `sh.raw-state@1` and `sh.state-style-fills@1` shipped after, native-ingest ni-grammar2 and ni-door), and the five TC3 ids `sh.bound-options-read@1`, `sh.bound-row-parts@1`, `sh.check-face@1`, `sh.grid-min-columns@1` and `sh.tile-disc-rules@1`.

The `parts-*` files (60: 19 accepts, `accept/parts-*`, and 41 plain refusals, `reject/parts-*`; the five TC3 ids shipped with native-ingest ni-parts, so none is pending any more) cover the five TC3 ids in five families: options, disc, columns, row and check. They are written by `scripts/generate-parts-corpus.ts`; do not edit them by hand.

The `pipeline-*` files (16 compile, 93 refused; a compiled case is `accept/pipeline-*`: the ids are promoted, so nothing is pending) cover `sh.pipeline@1` and `sh.pipeline-operands@1`, the Data Flow data source: its
three request kinds (a service with a response, an entity attribute, a live subscription from the closed list `todo-items` and
`weather-forecast`), refresh, parameters, the closed step list, the output, the authored `schema` the steps must produce, and the reads
and nodes that name a flow. The accepted files rebuild Overdue Chores (live), Upcoming Chores and Expired Food with demo entity ids.
They are written by `scripts/generate-pipeline-corpus.ts`; do not edit them by hand.

The `conditions-`, `rules-`, `app-state-` and `home-status-` files (and their `pending-` twins) cover the one expression grammar outside a flow:
the `compare`, `in` and `exists` leaves and reads of any model source (`sh.conditions@1`), the `choose` rule, the `expr` authored string and the
`conditional` look (`sh.rules@1`), the `app-state@1` source (`sh.app-state@1`) and the `count`, `total` and `unavailableCount` fields of a home status
(`sh.home-status-counts@1`). They are written by `scripts/generate-expression-corpus.ts`; do not edit them by hand.

The `enabled-when-`, `tile-look-`, `bound-color-`, `bound-symbol-`, `text-fallback-`, `badge-`, `action-rules-`, `confirm-when-`, `tab-fallback-`, `list-parts-` and `date-format-` files (and their `pending-` twins) cover the lane L-asks ids (`sh.enabled-when@1`, `sh.tile-look@1`, `sh.rules@1` colors and symbols, `sh.badges@1`, `sh.action-rules@1`, `sh.confirm-when@1`, `sh.tab-fallback@1`, `sh.list-parts@1`, and the date format under `sh.pipeline-operands@1`). They are written by `scripts/asks-corpus.ts` through the same generator. Evaluation cases name a subject kind (`operand`, `condition`, `fill`, `symbol`, `text`, `badge`, `enabled`, `faces`, `action`, `asks`) with its answer.

The `number-format-`, `text-format-`, `list-read-` and `raw-state-` files (and their `pending-` twins) cover the four grammar additions the climate controls need
(`minimumFractionDigits` and the title-case format under `sh.pipeline-operands@1`, the list reads `sh.list-read@1`, the raw state read `sh.raw-state@1`). They are written
by `scripts/grammar2-corpus.ts` through the same generator. Their evaluation cases add one environment key: `env.raw` maps a source id to what the host's raw state read
gives (`{status: 'value', value: 'unknown'}`); a source not listed has no entity and is unavailable. `env.reads` may hold arrays for a list attribute.

The `text-format-words-` files and the `format-words-case-*` evaluation cases (and their `pending-` twins) cover the `words` text case under the pending `sh.text-case-words@1`: `{ text: { case: "words" } }`
splits at `_` and at a space, capitalizes an ASCII first letter, keeps empty parts and joins with one space. The `appearance-` files (and their `pending-` twins) cover the light and dark colour pair
`solid-appearance { light, dark }` under the pending `sh.solid-appearance@1`, in a glyph, a fill, a rule case, a bound colour's fallback, a room card colour and a state style fill. Both are written
by `scripts/grammar2-corpus.ts` through the same generator. Two older refusals (`bound-color-glyph-standard-fallback`, `state-style-fills-fill-standard`) stay plain rejects but were re-pinned: widening a slot to take a pair changed their first issue from `missing_required` at `.../blue` to `unknown_variant` at `.../type` (a native promotion item).

The `tile-ink-` files (and their `pending-` twins) cover the pending `sh.tile-ink@1` (TC5): a state tile's `glyphTint` and `discGlyphTint` (each a `solid-rgb` or a `solid-appearance`
pair, so a pair also declares `sh.solid-appearance@1`) a state tile's `cellFit` (`fill` or `natural`, only a state tile) and a state style rule's `fillInk` (`white` or `soft`, only beside a `fill`, which also needs `sh.state-style@1` and
`sh.state-style-fills@1`). They are written by `scripts/grammar2-corpus.ts` through the same generator; there are no evaluation cases, since the fields only draw.

`evaluation/*.json` is the expression **evaluation** corpus: an operand or a condition, an environment (`reads` keyed `<source>/<path>`, a
viewer, a clock, an item, parameters, and `flow` for flow mode) and the exact answer (`yes`, `no` or `unknown` for a condition; `value`, `loading`
or `unavailable` for an operand). The Studio runs it in `tests/expression-corpus.test.ts`; the app's evaluator must agree byte for byte.

`pipelines/*.json` is the Data Flow **evaluation** corpus, a new kind: not envelopes but a flow, the data its request returned, a clock, and
the exact answer (`{status: "ok", output}` or `{status: "over-budget"}`, with the step cost where it matters). The Studio runs it in
`tests/pipeline-corpus.test.ts`; the app's evaluator must give the same answers byte for byte. The cases pin the four places JavaScript
and Swift disagree (text order, text equality, number text, rounding) and the step budget. `compiles: false` marks the few cases that run
a step on data the compiler refuses, to pin that evaluation is total; `expectedShape` is the hand-written shape after the steps. Written by
the same generator, with hand-written expectations: do not edit by hand.

The `component-`, `ref-`, `param-` and `body-` files (and their `pending-` twins) cover the lane L-linked id `sh.component-ref@1`: the `componentLibrary`
key, the `component-ref` node, parameters (kinds `entity-id` and `state-id`, `label`, `origin`), bindings, template-owned `sources` and `args`; the `component-example-*` files are the four
template examples (light button, vent tile, humidifier sheet, bed sheet), compiled with placeholder entity ids. They are written by `scripts/generate-component-corpus.ts` through the same generator. The
accepted ones are pending (the app's list refuses them with `unsupported_capability`); the rejected ones name the code the Studio's compiler gives.

The `repeat-`, `records-`, `flow-extras-` and `owned-flow-` files (and their `pending-` twins) cover the two pending ids of the weather-gen data lane WG-S2: `sh.repeat@1` (a flow output `records`, the node `repeat` with its paging and
placeholder, the `item` operand in a node slot, the `index` operand, and the Data Flows a saved component owns in `flows`) and `sh.flow-extras@1` (the steps `min`, `max`, `running-sum` and `annotate`, the date styles `hour` and `weekday`, and the `progress` operation
of a `date` operand). They are written by `scripts/wgflow-corpus.ts` through the same generator; do not edit them by hand. A saved component entry's `flows` field is new: native must decode it and
expand each use's copy as `<reference id>~<flow id>`. The evaluation cases are the `date-hour-*`, `date-weekday-*`, `date-progress-*` and `index-*` files in `evaluation/`, and the `min-`, `max-`, `running-sum-`, `annotate-`, `index-` and `records-`
files in `pipelines/`; `evaluation/*.json` environments gain one key, `index` (the position of the item). Their expected values are worked out by hand from `WeatherFormat.swift`, `WeatherDates.swift`, `WeatherRails.swift`,
`WeatherPrecipitationTimeline.swift` and `WeatherPresentation.swift`, cited in each note.

The `chart-` and `linear-gauge-` files cover `sh.chart@1` and `sh.linear-gauge@1` (weather-gen lane WG-N3): a bar, line or area chart over literal points or `source-points` (a Data Flow's records, with a limit and a
label and value operand each), the domain kinds `fixed`, `ceiling` and `two-step`, the axis, the unknown-value stubs, a chart over a repeat's list, and the gauge's scale, stops, spans, marker and spoken value. Their
`pending-` twins from the Studio became `accept/` and `reject/` cases here; the `evaluation/` cases (`chart-*`, `gauge-*`) pin the math in `ServerUIChartMath` and `ServerUIGaugeMath` to the Studio's
`chart-math.ts` and `gauge-math.ts`. Do not edit them by hand; copy them from the Studio.
