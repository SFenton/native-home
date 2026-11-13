# Pull request form

> **What:** the form of a pull request title, description and step comment. **Read when:** writing or posting any of them.

## Title and description

- The title is one plain sentence of at most 70 characters, with no area prefix, file name or internal label.
- The description has `## Summary` and `## Tests` only. It shows no step list, no status line, no review block and no generated-by footer. An `## Evidence` section appears only when it holds its own picture.
- A fix made in another repository or pull request is named with the repository (`owner/repo`) or a link, the files, what changes there and its state (merged, open, not pushed, not installed).
- Words are plain and short: no banned words, no passive voice, no file path in the first sentence.
- `tools/pr_text.py` composes and checks the description (`title-check`, `compose`, `body-check --strict`); the word lists are in `tools/pr_text_words.json`. `tools/ship.sh` adds nothing to it.

## Step comments

- Each role posts one comment per step, written as `## <Role>`, `### Actions Taken`, `### Result` and `### Next Steps`, each a bullet list. The comment shows no step number, round, head or time.
- The body file holds the three headings. `python3 tools/pr_note.py post KIND --task T --round N --body-file F --as ROLE` posts it; `--step N` is optional and `--now` sends a step ahead of a missing one.
- `tools/pr_note.py` refuses a comment that breaks the form or sends the reader elsewhere without naming the place.
- Pictures are scaled down, shown for iPhone, iPhone Duo and iPad only where that family's layout differs, and never repeated; a repeat reads `Same as` the first.

## Linked pull requests

- A description that links another pull request, in this repository or another, states that pull request's state beside the link. Each of the two names the other.
- When the state changes (opened, review changes the behavior, merged, released, installed, closed without merging), the session that caused or saw it updates the state line in every description that links it.
- That session also posts one step comment on each linked pull request. It says what changed, what it means for this pull request, and for the person who uses the app: what works now, what still waits, what they must do.
