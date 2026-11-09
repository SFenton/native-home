# Skills

> **What:** repeatable procedures. **Read when:** a task matches one.

| Skill | Use for |
|---|---|
| [port-page](port-page/SKILL.md) | Bringing a web page to native |
| [add-control](add-control/SKILL.md) | A new reusable control |
| [mockup-hub](mockup-hub/SKILL.md) | Publishing the mockup atlas to the one in-app hub Artifact |
| [design-decision](design-decision/SKILL.md) | A design choice the owner hasn't made (build up to 3 options, judge, record, per [propose-first](../workflow/propose-first.md)) |
| [fix-reported-issue](fix-reported-issue/SKILL.md) | A bug or feature from the request repo |
| [pose-matrix](pose-matrix/SKILL.md) | The Verifier's check of a visible change in every device pose, ending in the evidence pack ([agent-roster](../workflow/agent-roster.md)) |
| [research-note](research-note/SKILL.md) | The Researcher's sourced note: rung-0 system-API lookups, precedents, release-notes watch |
| [swiftui-pro](../../.claude/skills/swiftui-pro/SKILL.md) | Writing or reviewing any SwiftUI (third-party, vendored under `.claude/skills`; see [workflow/swiftui-pro.md](../workflow/swiftui-pro.md)) |

## Claude Code links

Every skill here is invocable (`/pose-matrix`) and preloadable into an agent (`skills:` in `.claude/agents/*.md`) through a relative symlink `.claude/skills/<name>` -> `../../.agents/skills/<name>`. Claude Code reads `SKILL.md` through symlinked skill folders ([skills docs](https://code.claude.com/docs/en/skills), "Symlinked folders"). The `.agents/skills/` folder stays the one source; edit there. A new skill adds its link in the same commit (`ln -s ../../.agents/skills/<name> .claude/skills/<name>`). `swiftui-pro`, `apple-hig` and `app-designer-pro` are real folders under `.claude/skills` (vendored or git-ignored), not links.

Start a skill with frontmatter (`name`, `description`: what it does and when to use it, third person) so Claude Code can choose it; without it the description is the first line of the file. `pose-matrix` and `research-note` have it; the older skills do not yet.
