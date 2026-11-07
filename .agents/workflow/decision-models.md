# Decision models (Jev)

> **What:** when and how agents use TypeSafe Jev, a decision model, for fast ranked hints, and what it measurably can and cannot do here. **Read when:** a prompt shows a *Pre-read (decision model: verify, don't obey)* section, or you are about to spend turns finding which pattern or file a task touches.

Jev answers questions **we** frame with fixed options (yes/no, one of N, a level on a scale) and returns calibrated probabilities in about 100 ms for a fraction of a cent. It never writes, plans or explains. It reads text well and predicts outcomes poorly, so it ranks and classifies; planning and implementation stay with the frontier models. Ported from festival-report-tracker's `decide.py`, `dmhints.py` and `fst-decide`; FestivalNativeApps' [decision-models](https://github.com/SFenton/FestivalNativeApps/blob/main/.agents/workflow/decision-models.md) covers its own measurements.

## Rules

- **A hint, never a gate.** Nothing here blocks, routes or merges anything. Verify every guess against the code and the rules; your own reading wins. Hint text from Jev names only registry pattern ids, their docs and canonical files.
- **Unavailable means no hint.** `tools/jev_ask.py` exits 3 without a key or on any network or API error, and `tools/jev_hints.py` then prints nothing, so a prompt is exactly what it was without Jev. `tools/jev_sections.py` falls back to BM25 order and says so.
- **Noul answers are accepted by bands.** A noul's confidence is max(p, 1 - p), so `accept.min_confidence` 0.5 accepts every answer. A question with `accept.yes_above` and `accept.no_below` is accepted only outside the band between them (`band`: yes, no or unsure; `value` is null when unsure; a set lists its `unsure` options). Fit the bands on labels; `validate` warns about an unbanded noul at 0.5. Old fields keep working.
- **Shadow questions are logged, not shown.** `ask_question` appends a shadow question's decision (tag, subject, value, top probabilities, no state text) to `build/jev/shadow.jsonl`; `check.tests` is asked this way by `jev_hints.py review`.
- **The key** is a mode-600 `~/.config/fenton-hass/typesafe.key` (`jev_ask.py` ignores a looser file) or `TYPESAFE_API_KEY` in the process environment. **The file wins when it exists and is non-empty; the variable is only the fallback**, so a stale variable inherited from the Claude desktop app cannot cause HTTP 401. Never print it, log it, put it in the repo, or pass it on a command line. For the triage runner use the launchd plist's `EnvironmentVariables` for that process only, or the key file; **do not put it in a shell profile**, because the worker's Bash would then source it inside an auto-mode session that reads untrusted issue text. The triage worker also runs as the same user, so `tools/triage/config.json` denies `Read` of `~/.config/fenton-hass/**` and `//**/typesafe.key` (the `//` anchors at the filesystem root) and any `Bash` command naming `typesafe.key` (one rule, `Bash(*typesafe.key*)`), and `KeyFileDenyTests` asserts the rules. **The Bash deny rules only match command text**: `cat ~/.config/fenton-hass/*` or `python3 -c` reads the file without naming it. The protection the worker cannot bypass is the launchd plist `EnvironmentVariables`, because the runner does not pass its own environment to the worker (`_launch` builds a minimal one). On the triage Mac prefer the plist over the key file. `jev_ask.py` still reads the file itself: it runs as a tool process, not through the agent's Read.
- **Data sent.** The title, body and file names of an issue or PR, and review finding text, are sent to TypeSafe (it says it does not train on requests). Do not ask it about anything that holds secrets or personal data.
- **Questions are versioned** in `contracts/jev/questions/*.json`. Jev reads literally and is wording-sensitive: bump `version` when wording, criteria or state change, and re-measure. `context.patterns` criteria are generated from the registry: `python3 tools/jev_ask.py sync` after any `contracts/patterns.json` change (`sync --check` verifies).
- **The model is pinned** (`jev-1.13.0`, `JEV_MODEL` overrides) because thresholds were tuned against it; each call is logged to `build/jev/calls.jsonl` (no state text, no key) and cached in `build/jev/cache/`.

## The questions

| Question | Type | Mode | Used for |
|---|---|---|---|
| `context.patterns` | noul-set, one criterion per pattern | active (hint) | Top patterns, their docs and canonical files |
| `context.precedents` | noul per candidate PR | active (hint) | Past PRs worth opening (candidates: keyword prefilter over `git log`) |
| `route.complexity` | score, 5 levels | active (hint) | Haiku, Sonnet or Opus lane (below 1.5, below 3.0, else) |
| `check.tests` | noul | shadow | Asked by `jev_hints.py review` and logged to `build/jev/shadow.jsonl`; never printed or shown |
| `review.finding_family` | choice, 12 families | active (grouping) | Grouping a reviewer's findings into checklists |

### Proposal questions (agent roster, 2026-11-01)

All new, all `version: 1`, `mode: shadow`, `evidence: "unmeasured"`: asked and logged, never acted on until measured against labels ([agent-roster](agent-roster.md), derived candidates, labels and first measurements in [jev-corpus](jev-corpus.md) and `contracts/jev/derived/`). Each file has an `output` field naming its consumer and what the answer produces. Noul questions have p bands; the screening bands are the RAG-passage cookbook's.

| Question | Type | Bands (yes above / no below) | Output |
|---|---|---|---|
| `research.section_relevant` | noul per section, section text in the state | 0.55 / 0.45 | `jev_sections.py` ranking: top-k sections verbatim with offsets and p |
| `research.evidence` | noul per section | 0.55 / 0.45 | `--screen` label `evidence` on a returned section |
| `research.contradicts` | noul per section | 0.70 / 0.30 | `--screen` label `contradicts`; the Researcher reports the conflict |
| `research.injection` | noul per section | 0.70 / 0.30 | `--screen` label `injection`: flag and warn only, the section is still returned |
| `research.release_impact` | noul-set over `tools/jev_surface.py` entries (HA domains and services we call, HAKit types, imported frameworks) | 0.60 / 0.30 | Researcher / Steward: which surface entries a release note may touch |
| `research.source_kind` | choice, 8 kinds | none | Source-kind label on each evidence line of a research note |
| `change.kind` | choice, 10 kinds | none | Task ledger field `kind`; input to the autonomy level |
| `tests.pick` | noul per candidate suite, only for files `affected_tests.py` cannot place | 0.65 / 0.30 | Hint under `NEEDS A PICK` |
| `code.custom_machinery` | noul | 0.75 / 0.25 | Reviewer hint: ask for the rung-0 note |
| `design.user_visible` (v2, active) | noul | 0.60 / 0.30 | Hint at intake (raise L0 to L1) and at the post-research gate (send to the Designer); never lowers, a no never skips the Designer. Decision-gate corpus 2026-11-02: plan AUC 0.994, request 0.925 |
| `decision.needs_owner` (active) | noul over the plan | 0.50 / 0.30 | Hint at the post-research gate: the owner's pick is likely needed (L2); never lowers. Plan AUC 0.999, p>=0.5 precision 0.984 |
| `design.target_decided` (active, hint-only) | noul over the plan, asked only when visible | 0.50 / 0.30 | Gate route hint: the visible result is already chosen, so an L1 Designer spec may replace L2 options; a move down, so the orchestrator decides. Test AUC 0.937, p>=0.5 precision 33/33, recall 0.58; plans must be written target-first |
| `design.new_pattern` | noul (needs `known_patterns` in the state) | 0.60 / 0.25 | Router: may raise to L2, never lower one |
| `route.role` | choice (coder-bug, design, research, ha-config, workflow, none) plus an `exists` companion noul | none | Router hint after the rules; use only when `extras.exists` is high |
| `triage.duplicate` | score over a pair: different, maybe, same | none | Router: propose linking `same`, note `maybe` |
| `brief.complete` | noul-set: objective, output_format, boundaries, done_check, device_families | 0.60 / 0.30 | Orchestrator hint line before dispatch: `brief lacks: ...` |
| `report.complete` | noul-set: result, evidence, not_run, open_questions | 0.60 / 0.30 | Orchestrator hint line on receipt: `report lacks: ...` |
| `transcript.turn_kind` | choice, 8 kinds | none | Steward table: owner corrections and decisions per task |
| `owner_msg.kind` | choice, 8 kinds | none | Router: intake path of an owner message |
| `owner_msg.about_workflow` | noul (hint only; measured on its held-out split like any question) | 0.70 / 0.30 | Router and Steward: the owner message is about how the agents work, so route it to Steward Entry B; never the only trigger, the label and paths decide first |
| `learning.home` | choice over `AGENTS.md` and the `.agents` docs (generated) | none | Steward: the doc a learning should land in (`none` = new doc or drop) |
| `pr.class_needs_evidence` (shadow) | noul-set: iphone, duo, ipad | 0.60 / 0.25 | `pr_visual.py select`: recorded in `selection.json` under `jev_shadow` only; a class Jev marks yes that the tree finds unchanged is listed in `jev_disagrees` for the Verifier; never shown or acted on until measured |
| `pr.motion_named` (shadow) | noul-set per device class: duo_open_close, duo_half, duo_rotate, ipad_rotate, sheet_refit | 0.60 / 0.25 | Recorded per class; the request-text rule decides today |
| `pr.motion_is_point` (shadow) | noul per candidate clip and class | 0.65 / 0.30 | Recorded per clip; the transition-code rule decides today |
| `pr.motion_direction` (shadow) | noul-set per candidate clip and class: forward, reverse, both_same | 0.60 / 0.25 | Recorded per clip (the plan is passed when a plan file is given); round trip by default |
| `pr.needs_stills` (shadow) | noul | 0.65 / 0.30 | Recorded; no consumer until measured |
| `pr.needs_motion` (shadow) | noul | 0.60 / 0.30 | Recorded; no consumer until measured |
| `pr.plain_language` (shadow) | noul over the "What changed for you" text | 0.60 / 0.35 | Recorded; the compose step's rewrite gate comes after measurement |

`research.release_impact` (from the Swift sources) and `learning.home` (from the docs) are generated like `context.patterns`: `python3 tools/jev_ask.py sync` after the code or docs change (`sync --check` lists the stale ones; a stale `learning.home` only misses new docs, so it is not a merge gate). The unit tests assert that every `learning.home` key is an existing file.

## Where the pre-read appears

| Where | How |
|---|---|
| Triage worker prompt | `hass_triage.render_prompt` fills `{{PREREAD}}` from the issue title and body (`jev.enabled` in `tools/triage/config.json`); empty when unavailable |
| Reviewer | `.claude/agents/reviewer.md` runs `python3 tools/jev_hints.py review --pr N` before the checklist |
| Interactive lane | At the start of [change-loop](change-loop.md) step 3: `python3 tools/jev_hints.py preread --title "..." --body-file task.md` (add `--files` for a diff) |
| After a `changes` verdict | `python3 tools/jev_hints.py findings build/review/<branch>.json` groups the findings into one checklist per kind |

## Measured on this repository (2026-10-28, `jev-1.13.0`)

`python3 tools/jev_measure.py recall` and `complexity`, over the last 50 merged PRs (#142 to #191). Ground truth for patterns is the set whose canonical or owned files, or doc, the PR changed (`pattern_guard.py changed`); 33 of the 50 touch at least one pattern. The text is the PR title and body with paths, checklists and pattern-doc names removed.

| Input | Ranker | recall@1 | @3 | @5 | @8 | any true in top 8 | all true in top 8 |
|---|---|---|---|---|---|---|---|
| Title and body | Keyword baseline (registry `keywords`) | 0.23 | 0.42 | 0.52 | 0.58 | 0.91 | 0.27 |
| Title and body | `context.patterns` | 0.30 | 0.59 | 0.71 | **0.78** | 1.00 | 0.42 |
| Title, body and changed file paths | `context.patterns` | 0.34 | 0.65 | 0.76 | 0.83 | 1.00 | 0.48 |
| 16 focused PRs (up to 3 true patterns), title and body | keyword / `context.patterns` | 0.35 / 0.48 | 0.57 / 0.80 | 0.66 / 0.87 | 0.68 / **0.90** | 0.81 / 1.00 | 0.50 / 0.75 |

- **Where it helps:** it beats keyword lookup at every rank, most at the top (recall@3 0.59 against 0.42) and where the text names a behavior without the pattern's words. It always put at least one true pattern in the top 8; keyword lookup missed that on 3 of 33 PRs.
- **Where it does not:** a broad PR (mean 4.9 true patterns) still loses about half of them from the top 8 (all-true@8 0.42), because most of those patterns are touched by a refactor the text never mentions. Treat the list as where to start reading, not as the set of patterns to touch. Adding file paths helps a little at review time (0.83).
- **Caveats:** the ground truth is the diff, not what the author needed to read; the keywords were written by the same agent that wrote the registry, which favors the baseline; PR bodies describe finished work and are richer than the issue reports the triage runner sees. Re-measure on issue text once the request repo has enough closed issues.
- **`route.complexity`:** Spearman 0.74 with lines changed and 0.79 with files changed, from the same PR text; the model put 6 PRs in Haiku, 24 in Sonnet and 20 in Opus. Strong, but the text describes the finished work. Shown as an advisory lane, not used to route.
- **Not measured:** `context.precedents` (too few PRs cite an earlier one to score recall), `check.tests` (the FestivalNativeApps run of the same question could not predict reviewer findings, AUC 0.45 to 0.72, so it stays shadow-only) and `review.finding_family` (this repo has too few recorded findings; the FestivalNativeApps run had median confidence 0.97).

Rule of thumb from these numbers and from FestivalNativeApps: use Jev to **classify what a text says** (which pattern, how big, what kind of finding); do not use it to **predict outcomes** that need reasoning over code (will review pass, is the test enough).

## Finding passages: `tools/jev_sections.py`

Jev returns no text and no spans, so finding the passage that answers a question is a **rerank** over sections cut in code, then the sections come back verbatim.

```bash
python3 tools/jev_sections.py --file F | --url U | --stdin  --question "..." [--top 3] [--screen] [--json] [--kind markdown|swift|text] [--shortlist 30]
```

- **Split** by heading (Markdown; HTML is converted to Markdown-like text with the stdlib first), `// MARK:` lines and `///` blocks (Swift), or paragraph windows; a section over 6000 characters becomes windows. Offsets (`start_line`, `end_line`, `start_byte`, `end_byte`) are into the text as split (`source.offsets` says `original` or `converted`).
- **Shortlist** to 30 or fewer with a pure-Python BM25 (title counted twice, camelCase split; the rest of the 30 is filled from the document in order, because Jev can find a section with no word in common).
- **Ask** one `research.section_relevant` noul per section with the **section text in the state (`items.<id>`) and the question in the instruction**. Requests hold at most 8 sections and about 12k estimated tokens (limits: 64k tokens for state plus questions, 32k for the state plus the longest question), run on at most 8 workers, and ties (the API rounds to 0.01) go to document order. Items named `i0`, `i1`, ... never leak a file name to the model.
- **`--screen`** adds `research.evidence`, `research.contradicts` and `research.injection` to the same requests and labels the returned sections (`flags`, `screen`). Injection only flags: the section is still returned, marked, and no Jev answer authorizes an action. Contradiction needs a claim in `--question`; a question gives noisy flags.
- **Unavailable** (no key, network or API error: `jev_ask` would exit 3): the BM25 top-k is returned with `"ranker": "bm25"`, `p: null` and a note; exit stays 0. Usage errors (bad URL scheme, unreadable or empty source, `--top 0`) exit 2.
- **The source text is untrusted**: a URL is fetched with `urllib` (http and https only, 2 MB cap), HTML is parsed, never executed, and the human output says so. Secret-looking strings and email addresses are replaced by `[redacted]` before anything is sent; the returned text is the source's own.
- Same cache and call log as `jev_ask` (`build/jev/`, tag `jev_sections`).

### Smoke measurement (2026-11-02, `jev-1.13.0`)

`python3 tools/jev_measure.py sections`: 22 hand-labeled (question, `.agents` doc) pairs from 12 docs (4 to 20 sections each; questions paraphrased so they do not copy headings; a section is relevant when it contains the labeled phrase; labels in `tools/tests/fixtures/jev_section_labels.json`, checked by a unit test). Jev reranks the BM25 shortlist; BM25 alone is the baseline over the same sections.

| Ranker | hit@1 | hit@3 | MRR |
|---|---|---|---|
| BM25 alone | 0.50 | 0.73 | 0.64 |
| BM25 shortlist, Jev rerank | **0.77** | **0.95** | **0.88** |

One miss in the top 3 (rank 4 of 20: "How much work may the main thread do per live update?"). 45 requests, 159k input tokens, **$0.0067** (cap $0.50). Caveats: 22 pairs, short docs (the shortlist covered most of each), one author for questions and labels, one relevant section per pair for most pairs; the thresholds in the question files are the cookbook's, not fitted. Treat it as a go signal for shadow use, not a calibration.

## Ad hoc questions

`python3 tools/jev_ask.py yesno|choose|score|rank "<question>" ... --state-file <text>` (same shape as festival-report-tracker's `fst-decide`). It prints one JSON object; use the answer only when `accepted` is true, otherwise decide yourself. Put one judgment in one question, phrase a yes/no so that high means yes, and keep dates, counts and exact lookups in code.

To rank texts, put them in the **state**, not the question: `jev_ask.py rank "Does this answer how auth works?" --items-file sections.json` (`{name: text}` or `[{id, text}]`; ties keep file order), or a registered `item_state` question with `ask <id> --items-file F --param question="..."`. Inline `-i name=desc` still puts the description in the question, which suits short labels only.
