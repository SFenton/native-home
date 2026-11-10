"""``.github/CODEOWNERS`` lists every agent file for the owner (owner decisions D1 and D2, 2026-11-10).

The matcher below is a minimal gitignore-style one, enough for this file: a leading ``/`` anchors to the repository root, a trailing ``/``
means a directory and everything under it, ``*`` and ``?`` do not cross ``/``, ``**`` does, the last matching line wins. Not implemented
(CODEOWNERS here does not use them): ``!`` negation, ``[...]`` classes, escapes, and team or email owners.
"""

import re
import sys
import unittest
from pathlib import Path
from typing import List, Optional, Tuple

TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import lane_land  # noqa: E402

OWNER = "@SFenton"

#: The agent-file globs (audit section 2.3 plus the credential subset and the whole ``.github`` tree, decision D2), as written in CODEOWNERS.
AGENT_FILES = (
    "/.claude/", "/.agents/workflow/", "/.agents/skills/", "/AGENTS.md", "/tools/hooks/", "/.githooks/", "/tools/review/",
    "/tools/review_verdict.py", "/tools/ship.sh", "/tools/ship_guard.sh", "/tools/pr_land.py", "/tools/pr_land.sh", "/tools/lane_*.py",
    "/tools/ruleset_gate.py", "/tools/jev_gate.py", "/tools/triage/", "/contracts/jev/", "/evals/", "/.github/", "/tools/agent_login.py",
    "/tools/release/", "/tools/hass_creds.sh", "/tools/gh_app_token.py", "/tools/devcap.py", "/tools/ci_hygiene.py",
    "/tools/release_closure.py", "/.gitmodules",
)
#: ``DEFAULT_PROTECTED`` entries that are not tracked files, so CODEOWNERS cannot (and need not) own them.
UNTRACKED = {".git/**"}


def pattern_regex(pattern: str) -> "re.Pattern[str]":
    """The regex for one CODEOWNERS pattern (gitignore-style, see the module docstring)."""
    anchored = pattern.startswith("/") or "/" in pattern.rstrip("/")
    directory = pattern.endswith("/")
    body = pattern.strip("/")
    out, i = "", 0
    while i < len(body):
        if body.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif body.startswith("**", i):
            out += ".*"
            i += 2
        elif body[i] == "*":
            out += "[^/]*"
            i += 1
        elif body[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(body[i])
            i += 1
    prefix = "" if anchored else "(?:.*/)?"
    return re.compile(prefix + out + ("/.*" if directory else "(?:/.*)?") + r"\Z")


def parse(text: str) -> List[Tuple[str, List[str]]]:
    """``(pattern, owners)`` for each rule line, comments and blanks dropped."""
    rules = []
    for line in text.splitlines():
        line = line.split(" #", 1)[0].strip()
        if line and not line.startswith("#"):
            pattern, *owners = line.split()
            rules.append((pattern, owners))
    return rules


def owners_of(path: str, rules: List[Tuple[str, List[str]]]) -> Optional[List[str]]:
    """The owners of ``path`` (the last matching rule), or None when no rule matches."""
    found = None
    for pattern, owners in rules:
        if pattern_regex(pattern).match(path):
            found = owners
    return found


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


if __name__ == "__main__":
    unittest.main()
