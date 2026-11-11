# Skills

> **What:** repeatable procedures, one task each. **Read when:** a task matches one.

| Skill | Use for |
|---|---|
| [add-control](add-control/SKILL.md) | A new reusable control |
| [design-decision](design-decision/SKILL.md) | A design choice the owner has not made, and its decision record |
| [fix-reported-issue](fix-reported-issue/SKILL.md) | A bug or feature from the request repo |
| [land-pr](land-pr/SKILL.md) | Shipping a branch: pull request, review, verdict, arming the merge, waiting on CI |
| [mockup-hub](mockup-hub/SKILL.md) | Publishing the mockup atlas to the hub Artifact |
| [port-page](port-page/SKILL.md) | Bringing a web page to the UIKit app |
| [pose-matrix](pose-matrix/SKILL.md) | The Verifier's check of a visible change in every device pose, and the evidence pack |
| [research-note](research-note/SKILL.md) | The Researcher's sourced note: rung-0 lookups, precedents, release watches |
| [secret-scan-triage](secret-scan-triage/SKILL.md) | Judging a secret-scan finding and allowing a false positive |
| [self-change-lane](self-change-lane/SKILL.md) | One change to agents, skills, hooks, tools or Jev questions |
| [triage-session](triage-session/SKILL.md) | An unattended request or nightly failure, start to status file |
| [swiftui-pro](../../.claude/skills/swiftui-pro/SKILL.md) | Writing or reviewing SwiftUI (vendored under `.claude/skills`) |

## Adding a skill

1. Create `.agents/skills/<name>/SKILL.md`. This folder is the one source; edit skills here.
2. Start it with frontmatter: `name`, and a `description` in the third person that says what it does and when to use it.
3. Write the procedure as numbered steps for one task. Link the rules it follows; do not restate them.
4. Link it for Claude Code in the same commit: `ln -s ../../.agents/skills/<name> .claude/skills/<name>`. The link makes it invocable (`/<name>`) and preloadable through `skills:` in an agent file.
5. Add its row to the table above.
