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
  yet. Shipped and pending are disjoint and the Studio's supported list is their union. Twenty ids were promoted after verification against native-home main and `ios/v2611.18.09`; the original remaining nine are unchanged, with the new `sh.flow-average@1` and `sh.text-keep@1` beside them (both shipped in the app since). When the app ships a capability, one app change
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
edit them by hand. The `state-style-fills-*` files (6 compiled, 12 refused; a compiled case is `accept/state-style-fills-*`) cover `sh.state-style-fills@1`, shipped:
a per-state `fill` (the document's `solid-rgb`) on a rule or the fallback, and the style's `hiddenWords`. The refused ones are a bad channel, a
fill that is not a `solid-rgb`, a fill on a tile override, a rule that gives `unavailable` a class other than unknown, and bad hidden words.
`state-styles/built-in.json` is the eight built-in styles as data: not a case, but a fixture the Studio and the
app both test their own built-in data against.

The `component-values-*` files (8 pending accepts, `reject/pending-component-values-*`, and 13 refused) cover `sh.component-values@1`, pending: a parameter of the kind
`value` and a `values` key on a `component-ref` that holds any JSON for it (a colour, a rule, `null` to remove an optional field, a field the body lacks,
a rule that names a private source), with the limits (16 entries, 8,192 bytes of canonical JSON each) and the refusals (overlapping bindings, an unknown
key, a `values` entry for a string parameter, an `args` entry for a value parameter, `null` on a required field, a value of the wrong shape, a binding of
`id`, a capability missing). They are written by `scripts/generate-component-corpus.ts`; do not edit them by hand.

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
`compiler.ts`, and rerun the generators. Shipped through native-ingest L0 to L3, NT1 and L1b: every capability. After them came `sh.pipeline@1`,
`sh.pipeline-operands@1` and `sh.list-parts@1` (native-ingest ni-flow, the L4 flow ids), `sh.text-case-words@1` and `sh.solid-appearance@1` (TC4 and TC4c), `sh.tile-ink@1` (TC5), and (`sh.list-read@1`, `sh.raw-state@1` and `sh.state-style-fills@1` shipped after, native-ingest ni-grammar2 and ni-door), and the five TC3 ids `sh.bound-options-read@1`, `sh.bound-row-parts@1`, `sh.check-face@1`, `sh.grid-min-columns@1` and `sh.tile-disc-rules@1`.

The `parts-*` files (60: 19 accepts, `accept/parts-*`, and 41 plain refusals, `reject/parts-*`; the five TC3 ids shipped with native-ingest ni-parts, so none is pending any more) cover the five TC3 ids in five families: options, disc, columns, row and check. They are written by `scripts/generate-parts-corpus.ts`; do not edit them by hand.

The `pipeline-*` files (16 compile, 93 refused; a compiled case is `accept/pipeline-*`; the pipeline ids shipped with native-ingest, so none is pending any more) cover `sh.pipeline@1` and `sh.pipeline-operands@1`, the Data Flow data source: its
three request kinds (a service with a response, an entity attribute, a live subscription from the closed list `todo-items` and
`weather-forecast`), refresh, parameters, the closed step list, the output, the authored `schema` the steps must produce, and the reads
and nodes that name a flow. The accepted files rebuild Overdue Chores (live), Upcoming Chores and Expired Food with demo entity ids.
They are written by `scripts/generate-pipeline-corpus.ts`; do not edit them by hand.

The `conditions-`, `rules-`, `app-state-` and `home-status-` files (and their `pending-` twins) cover the one expression grammar outside a flow:
the `compare`, `in` and `exists` leaves and reads of any model source (`sh.conditions@1`), the `choose` rule, the `expr` authored string and the
`conditional` look (`sh.rules@1`), the `app-state@1` source (`sh.app-state@1`) and the `count`, `total` and `unavailableCount` fields of a home status
(`sh.home-status-counts@1`). They are written by `scripts/generate-expression-corpus.ts`; do not edit them by hand.

The `enabled-when-`, `tile-look-`, `bound-color-`, `bound-symbol-`, `text-fallback-`, `badge-`, `action-rules-`, `confirm-when-`, `tab-fallback-`, `list-parts-` and `date-format-` files (and their `pending-` twins) cover the lane L-asks ids (`sh.enabled-when@1`, `sh.tile-look@1`, `sh.rules@1` colors and symbols, `sh.badges@1`, `sh.action-rules@1`, `sh.confirm-when@1`, `sh.tab-fallback@1`, `sh.list-parts@1`, and the date format under `sh.pipeline-operands@1`). They are written by `scripts/asks-corpus.ts` through the same generator. Evaluation cases name a subject kind (`operand`, `condition`, `fill`, `symbol`, `text`, `badge`, `enabled`, `faces`, `action`, `asks`) with its answer.

The `text-keep-*` cases cover `sh.text-keep@1` (shipped): `read` and `expr` accept
`whenUnavailable: "fallback" | "keep"`, reject unknown policies and require the
capability when either policy is written. Keep uses the last answered text,
never a fallback as an answer; before any answer it still draws the fallback.
They are written by `scripts/asks-corpus.ts` through the same generator.

The `number-format-`, `text-format-`, `list-read-` and `raw-state-` files (and their `pending-` twins) cover the four grammar additions the climate controls need
(`minimumFractionDigits` and the title-case format under `sh.pipeline-operands@1`, the list reads `sh.list-read@1`, the raw state read `sh.raw-state@1`). They are written
by `scripts/grammar2-corpus.ts` through the same generator. Their evaluation cases add one environment key: `env.raw` maps a source id to what the host's raw state read
gives (`{status: 'value', value: 'unknown'}`); a source not listed has no entity and is unavailable. `env.reads` may hold arrays for a list attribute. `env.viewerPerson` is what the host's `viewerPersonState` gives (a read result); absent, the host has none.

The `text-format-words-` files and the `format-words-case-*` evaluation cases (and their `pending-` twins) cover the `words` text case under `sh.text-case-words@1` (shipped): `{ text: { case: "words" } }`
splits at `_` and at a space, capitalizes an ASCII first letter, keeps empty parts and joins with one space. The `appearance-` files (and their `pending-` twins) cover the light and dark colour pair
`solid-appearance { light, dark }` under `sh.solid-appearance@1` (shipped), in a glyph, a fill, a rule case, a bound colour's fallback, a room card colour and a state style fill. Both are written
by `scripts/grammar2-corpus.ts` through the same generator. Two older refusals (`bound-color-glyph-standard-fallback`, `state-style-fills-fill-standard`) stay plain rejects but were re-pinned: widening a slot to take a pair changed their first issue from `missing_required` at `.../blue` to `unknown_variant` at `.../type` (a native promotion item).

The `fold-sides-` files (22 cases, written by `scripts/generate-fold-sides-corpus.ts`) cover `sh.fold-sides@1`: nine accepted as `accept/fold-sides-*` (the app shipped the id first, so they sit under `accept/`, as the Studio's generator places them once `capabilities.json` lists it), twelve refused as `reject/fold-sides-*`, and `accept/fold-sides-no-fields-needs-no-id.json`, the page with neither field, which needs no id. Twelve `evaluation/fold-sides-*` cases (subject `foldsides`) pin each section's side and width.
The `tile-ink-` files (and their `pending-` twins) cover `sh.tile-ink@1` (TC5, shipped): a state tile's `glyphTint` and `discGlyphTint` (each a `solid-rgb` or a `solid-appearance`
pair, so a pair also declares `sh.solid-appearance@1`) a state tile's `cellFit` (`fill` or `natural`, only a state tile) and a state style rule's `fillInk` (`white` or `soft`, only beside a `fill`, which also needs `sh.state-style@1` and
`sh.state-style-fills@1`). They are written by `scripts/grammar2-corpus.ts` through the same generator; there are no evaluation cases, since the fields only draw. No case encodes the drawing: the tint is ignored on a filled, error or unavailable face (an unavailable tile draws the default grey icon at 50%), and the corpus pins only decode and refusal.

The `surface-orientation-` and `surface-controls-` files cover the shipped `sh.surface-orientation@1` (a vacuum's `orientation`: both flips, written once on the source) and `sh.surface-controls@1`
(the `map` primitive's `controls`: up to four corner groups of up to eight buttons, a row or a column, each button a map action, a source command, a service call or navigation). The compiled cases are a flip, both flips, each corner,
a row of three, a column of two, a mixed set, eight buttons (More-sized) and buttons whose symbol and label follow a rule; the refused ones are two groups in a corner, an empty group, nine buttons, five groups, a repeated id, a
missing or blank label, an unknown corner, axis, map command or source command, Locate twice, `locate` that does not state whether a Locate button is authored, `visibleWhen` or `enabledWhen` on a map action or source command, a replaced
sheet, a power toggle, and a Locate button on a source that is not a vacuum. They are written by `scripts/grammar2-corpus.ts` through the same generator; there are no evaluation cases, since the fields only draw.

`evaluation/*.json` is the expression **evaluation** corpus: an operand or a condition, an environment (`reads` keyed `<source>/<path>`, a
viewer, a clock, an item, parameters, and `flow` for flow mode) and the exact answer (`yes`, `no` or `unknown` for a condition; `value`, `loading`
or `unavailable` for an operand). The Studio runs it in `tests/expression-corpus.test.ts`; the app's evaluator must agree byte for byte.

`pipelines/*.json` is the Data Flow **evaluation** corpus, a new kind: not envelopes but a flow, the data its request returned, a clock, and
the exact answer (`{status: "ok", output}` or `{status: "over-budget"}`, with the step cost where it matters). The Studio runs it in
`tests/pipeline-corpus.test.ts`; the app's evaluator must give the same answers byte for byte. The cases pin the four places JavaScript
and Swift disagree (text order, text equality, number text, rounding) and the step budget. `compiles: false` marks the few cases that run
a step on data the compiler refuses, to pin that evaluation is total; `expectedShape` is the hand-written shape after the steps. Written by
the same generator, with hand-written expectations: do not edit by hand.

The `profile-badges-` files (and their `pending-` twins) cover the four ids of the Profile Icon and badges lane (`sh.shell-profile@1`, `sh.avatar@1`, `sh.badge-spoken@1`, `sh.badge-nodes@1`): the header's `profile` block, the `avatar` node, `spoken` on a value badge and a badge on `action-tile`, `door-tile`, `light-group-tile`, `room-card`,
`room-chip`, `settings-link`, `avatar` and a drawn header `button`. They are written by `scripts/profile-badges-corpus.ts` through `generate-expression-corpus.ts`; do not edit them by hand. Show at Most and Spoken As are the Studio's, never published: the cases hold what they work out into, and a case that leaves `cap` or a
Spoken As line in a badge is refused as an unknown field. The `badge-cap-*` and `badge-spoken-*` evaluation cases pin `resolveBadge`: the answer carries `spoken` (the words, or `null` for the drawn text) only when the badge has a `spoken` operand. `badge-chrome-button` (a drawn header badge) declares `sh.badge-nodes@1` and is pending with them.

The `component-`, `ref-`, `param-` and `body-` files (and their `pending-` twins) cover the lane L-linked id `sh.component-ref@1`: the `componentLibrary`
key, the `component-ref` node, parameters (kinds `entity-id` and `state-id`, `label`, `origin`), bindings, template-owned `sources` and `args`; the `component-example-*` files are the four
template examples (light button, vent tile, humidifier sheet, bed sheet), compiled with placeholder entity ids. They are written by `scripts/generate-component-corpus.ts` through the same generator. The
accepted ones are pending (the app's list refuses them with `unsupported_capability`); the rejected ones name the code the Studio's compiler gives.

The `text-style-`, `rgba-`, `stack-`, `shape-`, `symbol-part-` and `choice-icons-` files cover the four shipped ids of the weather-gen style lane WG-S1: `sh.text-style@1` (the `rgba` colour, which takes
an alpha from 0 to 1, the eleven text styles, and a text's `font`, `ink`, `lines`, `align` and `overflow`), `sh.stack@1` (the `stack` node with its groups, collapse, dividers, surface, tap and accessibility, and the `shape` node),
`sh.symbol-part@1` (the `symbol` node) and `sh.choice-icons@1` (a `symbol` and a `hint` on a local-state choice's option). They are written by `scripts/wgstyle-corpus.ts` through the same generator; do not edit them by hand. Every refusal
records its first issue in the case (hand-written), and the generator fails when the compiler disagrees. The accepted ones live in `accept/`; `rgba` is an ink only in the slots these ids add, and
the slots that existed before refuse it (`rgba-in-a-slot-that-has-no-opacity`, `rgba-in-an-old-pair`). The `stack-reflow-*` evaluation files are a new subject kind, `stack`: `{ props, children: [{ id, width, shrinks? }], width, accessibilitySize }` answers
`{ stack: { collapsed, reason, axis, spacing, groups } }`, the arrangement a stack chooses (`src/shared/composition/stack-layout.ts`); the cases use the numbers of the app's hand-laid weather card header.

The `repeat-`, `records-`, `flow-extras-` and `owned-flow-` files cover the two shipped ids of the weather-gen data lane WG-S2: `sh.repeat@1` (a flow output `records`, the node `repeat` with its paging and
placeholder, the `item` operand in a node slot, the `index` operand, and the Data Flows a saved component owns in `flows`) and `sh.flow-extras@1` (the steps `min`, `max`, `running-sum` and `annotate`, the date styles `hour` and `weekday`, and the `progress` operation
of a `date` operand). They are written by `scripts/wgflow-corpus.ts` through the same generator; do not edit them by hand. A saved component entry's `flows` field is new: native must decode it and
expand each use's copy as `<reference id>~<flow id>`. The evaluation cases are the `date-hour-*`, `date-weekday-*`, `date-progress-*` and `index-*` files in `evaluation/`, and the `min-`, `max-`, `running-sum-`, `annotate-`, `index-` and `records-`
files in `pipelines/`; `evaluation/*.json` environments gain one key, `index` (the position of the item). Their expected values are worked out by hand from `WeatherFormat.swift`, `WeatherDates.swift`, `WeatherRails.swift`,
`WeatherPrecipitationTimeline.swift` and `WeatherPresentation.swift`, cited in each note.
The `chart-` and `linear-gauge-` files (and their `pending-` twins) cover the weather-gen data parts WG-S3 (`sh.chart@1`, `sh.linear-gauge@1`): the `chart` node (bar, line and area marks, a literal series, three kinds of value scale, an axis, thinned labels and the spoken series) and the `linear-gauge` node (a track, an optional span and marker, a gradient).
A chart that reads a `source` series names a records flow (WG-S2) or sits in a repeat's cell: the `chart-source-*` and `pending-chart-source-*` cases pin the accepts and the code each refusal gets (a path the flow does not give, a field of the wrong kind, a flow that is not records, no provider outside a repeat or in its placeholder), and `linear-gauge-in-a-repeat` and `-item-outside-a-repeat` do the same for a gauge in a cell. The evaluation files `chart-source-points-*` (subject `chart`, op `source-points`, answer `{ sourcePoints }`) pin the points a source series draws from records, and `gauge-cell-*` the share a cell's gauge reads from its record. They are written by `scripts/wgchart-corpus.ts` through the same generator; do not edit them by hand. Every refusal records the Studio's first issue by hand. The evaluation cases `chart-*` (subject kind `chart`: an `op` of `domain`, `two-step`, `share`, `labels`, `indices`, `levels`, `bars`, `points`, `spoken` or `source-points`) and `gauge-*` (subject kind `gauge`, and `operand` cases that build a rail's shares with the grammar) are written from the native tests' own numbers.
The `dial-` and `arc-track-` files (and their `pending-` twins) cover the weather-gen gauge parts WG-S4 (`sh.dial@1`, `sh.arc-track@1`): the `dial` node (a sweep, ticks, letters, a flag, a lit-tick or needle pointer, text in the middle) and the `arc-track` node (a curve, a horizon, a marker at progress). They are written by `scripts/wgdial-corpus.ts` through the same generator; do not edit them by hand.
Every refusal records the Studio's first issue by hand. The evaluation cases are two new subject kinds, both written from the native code and tests: `dial` (`{ op: "layout", input, pick }` answers each picked part of the layout, as `ticks.0`, `lit`, `needle`, `labels`, under its own path; `share`, `normalize`, `delta`, `next`) and `arc` (`{ op: "layout", input, pick }`, `progress`, `point`), answered by
`src/shared/composition/dial-math.ts` and `arc-track-math.ts` through `tests/dial-corpus.ts`.
The `dialctl-` and `dial-text-place-` files (and their `pending-` twins) cover the dial control lane SD1/SD2 (`sh.dial-control@1`, `sh.dial-text-place@1`): the `dial-control` node (one or two stoppers on a fixed 270 degree ring, the rule between them, limits, and one call or one per stopper with `control` naming a stopper) and the display dial's `textAt`. They are written by `scripts/dialctl-corpus.ts` through the same generator; do not edit them by hand. The family is `dialctl` so the older `dial-` family does not claim its files.
Evaluation: the subject kind `dialctl` (`{ op, input, ... }` with `op` `state`, `bounds`, `move`, `adjust`, `nearest`, `snap`, `ticks`, `tick-count` or `angle`; a stopper with no value has `value: null`, a gap or a limit side that is authored and cannot be read is `null`, one not authored is absent), answered by `dial-control-math.ts` through `tests/dial-corpus.ts`; `dial` `layout` cases may pick `textCenterY` and pass `textAt`; operand cases for `control` set `env.controlValue` (the one value being sent) or `env.controlValues` (each stopper's, by id).

The `count-operand-` files cover the `count` operand under the shipped `sh.count@1`: how many of up to 32 entries' conditions hold, each entry with an optional `viewer` filter of `person.*` entities. The compiled cases are a sentence over the count, a node that hides at zero, numeric tests, an attribute and an `all` test, a viewer filter, a sum of two counts and the 32-entry maximum; the refused ones are no entries, 33 entries, the 64-node budget, a missing `of` or `test`, a test that is not a condition, an undeclared source, unknown fields on the count, an entry and a viewer, a viewer that is not a `person.*`, an empty viewer list, a count compared as text, a test nested past six levels and a count inside a Data Flow. The evaluation cases (`count-operand-*`) pin zero, one, many and all, the states `unavailable` and `unknown` as text, an entity with no state, loading, entries that cannot be answered (skipped; the whole count is `loading` or `unavailable` only when every entry in play is), the viewer filter (listed, not listed, no person entity, viewer not known yet, filtered out and never read), a sum, a rule over the count and a flow. They are written by `scripts/count-corpus.ts` through `generate-expression-corpus.ts`; do not edit them by hand.
The `count-operand-` evaluation cases also pin every read path of a test (`raw-state`, `last-changed`, `viewer-person`, a viewer not known yet) reporting loading the same way, and the two `count` records: the operand, and the profile node (`sh.profile-count@1`).
