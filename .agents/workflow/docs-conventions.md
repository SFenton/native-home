# Docs conventions

> **What:** the rule model: what a rule is, where everything that is not a rule goes, and what keeps the rule surface small. **Read when:** before editing `AGENTS.md`, any `.agents` file, an agent file, a skill or a headless prompt.

## Layers

| Layer | Files | Holds |
|---|---|---|
| core | `AGENTS.md` | Product and architecture invariants, roles, the router |
| rules | `.agents/workflow/` | Process rules, one home each |
| agent | `.claude/agents/` | A role's scope, writes, nevers, inputs and ending |
| prompt | `tools/triage/prompts/` | A headless job, its inputs and status file |
| procedure | `.agents/skills/` | Steps for one task; no policy |
| reference | The other `.agents` folders | Surface, platform and test rules |
| state | `PROGRESS.md` | What is being built and what is next |
| record | `.agents/decisions/`, `.agents/archive/` | Why and when; append-only; never required reading |

Word budgets per file, per line and per role's spawn load are in `contracts/rules-surface.json`. The owner approves growing one.

## What a rule is

- A rule is a present-tense statement of what agents or tools do by default for every task of a kind.
- Rule text holds no date, no decider, no reference to a pull request, issue or commit, no incident, run or measurement, no word of change and no status of work. The pattern list is in `contracts/rules-surface.json`.
- A rule states the default and, where needed, its classes. A class is geometric or categorical, never a named instance.
- An example appears only where the rule is ambiguous without one, and is generic.
- A rule that a hook or tool enforces is one sentence plus the enforcer's path; its `--help` and refusal message carry the detail.
- Each rule lives in one file; every other file links to it and never paraphrases it.
- Every claim about a tool, hook, workflow or path is true of the code today.

## Homes

| Event | Home |
|---|---|
| Broad behavior changes | Rewrite the rule in place and delete the old wording in the same change; one entry in `.agents/decisions/` |
| An exception that names an instance | The enforcing tool's configuration or allow-list, with a reason. With no enforcing tool it is not kept |
| An incident, bug or flake | A test or one eval case per class; the pull-request description |
| Why and when | `.agents/decisions/` and the pull-request description |
| Status, plans, lanes, backlog | `PROGRESS.md`; issues |
| Numbers and names a tool reads | `contracts/` or the tool; prose names the file |
| How a tool works | The tool's `--help` and refusal messages |
| A step list for one task | A skill, with `name` and `description` frontmatter |
| Finished specs, plans and measurements | Deleted, or `.agents/archive/` when needed for why |

- A recurring failure is fixed in a hook, tool or test before any prose.
- A rule change is net-neutral or shrinking in words and names the text it deletes.

## Scope test

- Text is an **exception** when it names an instance or carves a case out of an unchanged default: deleting it would change behavior only for the thing it names.
- Text is **broad** when deleting it would change behavior on tasks its author never saw.
- Two exceptions of one kind are rewritten as a class in the rule.

## File conventions

- Line 1 is `# Title`; the next non-empty line is `> **What:** … **Read when:** …`.
- Every folder has a `README.md` that links every child.
- `spec.md` is platform-neutral; form-factor detail goes in the platform file beside it.
- An unknown is written `TODO(orchestrator): …`, never guessed.
- Moving or removing a file fixes its links in the same change.

## Enforcement

`tools/rules_lint.py` checks these rules in `pr-checks` and the tool tests; `tools/hooks/rules_guard.py` applies them at write time. Exemptions are by layer, never inline; every markdown file is in a layer or the contract's `unchecked` list. The lint is the floor: the Reviewer judges paraphrase the patterns miss.
