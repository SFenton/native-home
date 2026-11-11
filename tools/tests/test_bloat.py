"""Bloat controls: the rule surface passes ``tools/rules_lint.py`` (budgets, forbidden patterns, one home, links, structure), and a
deterministic contradiction check runs across the agent files and the roster. Budgets live in ``contracts/rules-surface.json``;
this file holds no numbers."""

import re
import sys
import unittest
from pathlib import Path
from typing import Dict, List, Tuple

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import rules_lint  # noqa: E402


class RuleSurfaceLintTests(unittest.TestCase):
    def test_the_tree_passes_the_lint(self):
        """Fails if: any rule-surface file carries a date, attribution, reference, change word, an over-long line, a repeated
        sentence, a broken link or path, a missing router entry, or is over its budget (the findings are listed)."""
        found = rules_lint.run(ROOT)
        self.assertEqual([f.render() for f in found[:40]], [], rules_lint.summary(found) if found else "")


# MARK: - Contradiction check

#: Facts the docs state in several places, each as regexes whose group 1 is the value. Two values for one fact is a contradiction.
ROUND_FACTS: Dict[str, Tuple[str, ...]] = {
    "design round cap": (r"design(?: verdict| rounds?)?[^.;\n]{0,12}?(?:at most|≤|exceed|>)\s*(\d)",
                         r"numbered changes \(at most (\d) rounds"),
    "review round cap": (r"reviewer \((?:at most|≤) ?(\d)", r"review round (\d)"),
}
#: Every kill-switch path the docs may name; any other `~/...PAUSED` is a contradiction.
KILL_SWITCHES = {"~/.config/hass-triage/PAUSED", "~/.local/state/hass-triage/PAUSED"}
#: The L3 fixed-set items by keyword. A doc listing an item the roster's fixed set does not has contradicted the roster.
L3_ITEMS = {"credentials": r"credential", "signing": r"signing", "physical devices": r"physical", "live HA writes": r"live (?:HA|Home Assistant)",
            "merge path": r"merge path", "eval graders": r"grader", "kill switch": r"kill switch"}


def doc_files() -> Dict[str, str]:
    paths = sorted((ROOT / ".claude" / "agents").glob("*.md")) + [ROOT / ".agents" / "workflow" / "agent-roster.md"]
    return {str(p.relative_to(ROOT)): p.read_text(encoding="utf-8") for p in paths}


def fixed_set_items(text: str) -> set:
    return {name for name, pattern in L3_ITEMS.items() if re.search(pattern, text, re.I)}


def contradictions(docs: Dict[str, str]) -> List[str]:
    """Pairs of lines in ``docs`` ({path: text}) that state different values for the same fixed fact."""
    found: List[str] = []
    for fact, patterns in ROUND_FACTS.items():
        values: Dict[str, List[str]] = {}
        for path, text in docs.items():
            for number, line in enumerate(text.splitlines(), 1):
                for pattern in patterns:
                    for match in re.finditer(pattern, line, re.I):
                        values.setdefault(match.group(1), []).append(f"{path}:{number}")
        if len(values) > 1:
            found.append(f"{fact}: " + "; ".join(f"{v} at {', '.join(where[:3])}" for v, where in sorted(values.items())))
    for path, text in docs.items():
        for number, line in enumerate(text.splitlines(), 1):
            for token in re.findall(r"~/[\w./-]*PAUSED\w*", line):
                if token not in KILL_SWITCHES:
                    found.append(f"kill-switch path {token} at {path}:{number} is not one of {sorted(KILL_SWITCHES)}")
            if re.search(r"\bagents?\b[^.\n]*\b(?:may|can) merge\b", line, re.I) and not re.search(r"\b(?:not|never|cannot|no)\b", line, re.I):
                found.append(f"agents may merge at {path}:{number}")
            if re.search(r"self-change|\blane\b", line, re.I) and re.search(r"pr_land", line) and not re.search(
                    r"\b(?:product|not|never|keeps|only|PR|pull request)\b", line, re.I):
                found.append(f"a self-change lane lands through pr_land.sh at {path}:{number}")
    roster = docs.get(".agents/workflow/agent-roster.md", "")
    section = re.search(r"\*\*The fixed set.*?(?=\n\nEverything else)", roster, re.S)
    allowed = fixed_set_items(section.group(0)) if section else set()
    for path, text in docs.items():
        for number, line in enumerate(text.splitlines(), 1):
            if re.search(r"L3 is the fixed set|may not change the fixed set", line):
                extra = fixed_set_items(line) - allowed
                if extra:
                    found.append(f"fixed set at {path}:{number} lists {sorted(extra)} that the roster does not")
                if re.search(r"ack[-_]verified", line):  # agent sessions may run it (owner, 2026-11-10): it is not in the fixed set
                    found.append(f"fixed set at {path}:{number} lists ack-verified, which agent sessions may run")
    return found


class ContradictionTests(unittest.TestCase):
    def test_the_docs_do_not_contradict_each_other(self):
        self.assertEqual(contradictions(doc_files()), [])

    def test_the_facts_are_still_found_so_the_check_cannot_go_quiet(self):
        docs = doc_files()
        for fact, patterns in ROUND_FACTS.items():
            hits = [m for text in docs.values() for p in patterns for m in re.finditer(p, text, re.I)]
            self.assertGreaterEqual(len(hits), 2, fact)
        self.assertIn("~/.config/hass-triage/PAUSED", "\n".join(docs.values()))
        self.assertTrue(fixed_set_items(docs[".agents/workflow/agent-roster.md"]))

    def test_two_round_caps_are_flagged(self):
        docs = {"a.md": "design verdict (at most 3 rounds)", "b.md": "Stop when design rounds exceed 4"}
        [found] = contradictions(docs)
        self.assertIn("design round cap", found)
        self.assertIn("a.md:1", found)
        self.assertEqual(contradictions({"a.md": "design verdict (≤ 3 rounds)", "b.md": "design rounds > 3"}), [])

    def test_review_round_caps_are_compared(self):
        self.assertEqual(contradictions({"a.md": "Reviewer (at most 2)", "b.md": "survives review round 2"}), [])
        self.assertTrue(contradictions({"a.md": "Reviewer (at most 2)", "b.md": "survives review round 3"}))

    def test_an_unknown_kill_switch_path_is_flagged(self):
        [found] = contradictions({"a.md": "stop with ~/.config/hass-triage/PAUSE and ~/.local/state/other/PAUSED"})
        self.assertIn("~/.local/state/other/PAUSED", found)
        self.assertEqual(contradictions({"a.md": "~/.config/hass-triage/PAUSED, ~/.local/state/hass-triage/PAUSED"}), [])

    def test_merge_path_contradictions(self):
        self.assertTrue(contradictions({"a.md": "Agents can merge a lane themselves."}))
        self.assertEqual(contradictions({"a.md": "Agents can not merge; the runner does."}), [])
        self.assertTrue(contradictions({"a.md": "Each self-change is landed through tools/pr_land.sh."}))
        self.assertEqual(contradictions({"a.md": "Product work lands only through tools/pr_land.sh; self-change lanes use the runner."}), [])

    def test_listing_ack_verified_under_the_fixed_set_is_flagged(self):
        """Fails if: a doc can call ack-verified (agent-runnable) part of the owner's fixed set without the check noticing."""
        roster = ("**The fixed set (owner).** L3 is only this:\n\n- credentials;\n- `ack-base <sha>` (`ack-verified` is agents').\n\nEverything else is autonomous.")
        [found] = contradictions({".agents/workflow/agent-roster.md": roster, "o.md": "L3 is the fixed set (credentials, ack-verified)"})
        self.assertIn("ack-verified", found)
        self.assertEqual(contradictions({".agents/workflow/agent-roster.md": roster, "o.md": "L3 is the fixed set (credentials, ack-base)"}), [])

    def test_an_l3_item_the_roster_lacks_is_flagged(self):
        roster = ("**The fixed set (owner).** L3 is only this:\n\n- credentials;\n- signing and release;\n\nEverything else is autonomous.")
        docs = {".agents/workflow/agent-roster.md": roster, "o.md": "L3 is the fixed set (credentials, signing, physical devices)"}
        [found] = contradictions(docs)
        self.assertIn("physical devices", found)
        docs["o.md"] = "L3 is the fixed set (credentials, signing)"
        self.assertEqual(contradictions(docs), [])


if __name__ == "__main__":
    unittest.main()
