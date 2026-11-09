# Agent behaviour replay (tier 2, weekly)

A small, **budgeted** replay of agent behaviour through `claude -p` (Sonnet), for `python3 tools/agent_eval.py --tier 2`.
The Steward's weekly job runs it (`tools/triage/prompts/steward.md`, step 8); `lane_land` never does. It costs nothing until a case is switched on.

* `config.json`: `model`, `max_cases` (a hard cap per run), `max_cost_usd` (the run stops starting cases once spent) and
  `timeout_s`.
* `cases/<id>.json`: `{"id", "source", "enabled", "prompt", "expect": {"contains": [regex], "not_contains": [regex]}}`.
  Only cases with `"enabled": true` run. The three shipped examples are disabled.

## Adding a case

1. Put the recorded situation in `prompt` (self-contained: the replay has no repo context beyond the prompt).
2. Say in `expect` what the answer must (`contains`) and must not (`not_contains`) match; keep the patterns loose enough
   for a model's wording and sharp enough to catch the old failure.
3. Leave `"enabled": false`, run it once by hand with the owner's go-ahead, then enable it. Raising `max_cases` or
   `max_cost_usd` is an owner decision.

Replies and cost are not stored; the run prints `suite agent-behaviour: N cases, P passed` and a `spent $x of $y` note.
