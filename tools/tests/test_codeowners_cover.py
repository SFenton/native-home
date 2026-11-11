"""``.github/CODEOWNERS`` lists every agent file for the owner (owner decisions D1 and D2, 2026-11-10).

The matcher is ``tools/pr_blockers.py``'s (the one the landing tools use; no second copy here): gitignore-style, the last matching line
wins. See its docstring for the supported forms.
"""

import sys
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import lane_land  # noqa: E402
from pr_blockers import owners_of, parse  # noqa: E402

OWNER = "@SFenton"

#: The agent-file globs (audit section 2.3 plus the credential subset and the whole ``.github`` tree, decision D2), as written in CODEOWNERS.
AGENT_FILES = (
    "/.claude/", "/.agents/workflow/", "/.agents/skills/", "/AGENTS.md", "/tools/hooks/", "/.githooks/", "/tools/review/",
    "/tools/review_verdict.py", "/tools/ship.sh", "/tools/ship_guard.sh", "/tools/pr_land.py", "/tools/pr_land.sh", "/tools/pr_blockers.py", "/tools/lane_*.py",
    "/tools/ruleset_gate.py", "/tools/jev_gate.py", "/tools/triage/", "/contracts/jev/", "/evals/", "/.github/", "/tools/agent_login.py",
    "/tools/release/", "/tools/hass_creds.sh", "/tools/gh_app_token.py", "/tools/devcap.py", "/tools/ci_hygiene.py",
    "/tools/release_closure.py", "/.gitmodules",
)
#: ``DEFAULT_PROTECTED`` entries that are not tracked files, so CODEOWNERS cannot (and need not) own them.
UNTRACKED = {".git/**"}


def sample(glob: str) -> str:
    """A concrete tracked-looking path that matches a ``DEFAULT_PROTECTED`` style glob."""
    return glob.replace("**", "sub/x.py").replace("*", "x")


RULES = parse((ROOT / ".github" / "CODEOWNERS").read_text(encoding="utf-8"))


class CodeownersCoverTests(unittest.TestCase):
    def test_every_default_protected_entry_is_owned_by_the_owner(self):
        """Fails if: a path the landing gate keeps owner-only has no CODEOWNERS line, or one with another owner."""
        for entry in lane_land.DEFAULT_PROTECTED:
            if entry in UNTRACKED:
                continue
            path = sample(entry)
            self.assertEqual(owners_of(path, RULES), [OWNER], f"{entry} (as {path})")

    def test_every_agent_file_glob_is_owned_by_the_owner(self):
        """Fails if: an agent file from the audit list loses its CODEOWNERS line."""
        for glob in AGENT_FILES:
            path = sample(glob.lstrip("/")) if not glob.endswith("/") else glob.lstrip("/") + "sub/x.py"
            self.assertEqual(owners_of(path, RULES), [OWNER], f"{glob} (as {path})")
            self.assertIn(glob, [pattern for pattern, _ in RULES], glob)

    def test_the_whole_github_tree_is_owned(self):
        """Fails if: a file under .github (workflows, the template, CODEOWNERS itself) is not the owner's (decision D2)."""
        for path in (".github/workflows/pr-checks.yml", ".github/CODEOWNERS", ".github/pull_request_template.md"):
            self.assertEqual(owners_of(path, RULES), [OWNER], path)

    def test_product_code_and_ordinary_tools_are_not_owned(self):
        """Fails if: a catch-all line makes the owner review every change, which would defeat the agent lane."""
        for path in ("apple/HassUI/UIKitPort/HomeViewController.swift", "apple/HassCore/EntityStore.swift", "tools/affected_tests.py",
                     "tools/tests/test_codeowners_cover.py", ".agents/pages/home/spec.md", "PROGRESS.md"):
            self.assertIsNone(owners_of(path, RULES), path)

    def test_every_rule_names_only_the_owner(self):
        """Fails if: a rule lists no owner (which un-owns the path) or someone besides the owner."""
        for pattern, owners in RULES:
            self.assertEqual(owners, [OWNER], pattern)

    def test_the_matcher(self):
        """Fails if: the minimal matcher drifts from gitignore semantics for the forms CODEOWNERS uses."""
        rules = parse("/a/ @o\n/b.py @o\n/c_*.py @o\n*.md @o\n/a/keep.txt @p\n")
        self.assertEqual(owners_of("a/x/y.txt", rules), ["@o"])
        self.assertEqual(owners_of("a/keep.txt", rules), ["@p"])  # the last match wins
        self.assertEqual(owners_of("b.py", rules), ["@o"])
        self.assertIsNone(owners_of("sub/b.py", rules))  # a leading slash anchors to the root
        self.assertEqual(owners_of("c_x.py", rules), ["@o"])
        self.assertIsNone(owners_of("sub/c_x.py", rules))
        self.assertEqual(owners_of("docs/deep/n.md", rules), ["@o"])  # no slash: any depth

    def test_the_last_matching_line_wins_and_an_unowned_override_unowns(self):
        """Fails if: an earlier line beats a later one, or a later owner-less line no longer leaves the file unowned (GitHub's rule)."""
        rules = parse("/tools/ @o\n/tools/free/ \n/tools/free/keep.py @p\n")
        self.assertEqual(owners_of("tools/x.py", rules), ["@o"])
        self.assertEqual(owners_of("tools/free/a.py", rules), [])
        self.assertEqual(owners_of("tools/free/keep.py", rules), ["@p"])
        self.assertIsNone(owners_of("apple/x.swift", rules))


if __name__ == "__main__":
    unittest.main()
