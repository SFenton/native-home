"""Bloat controls (plan section 9): line and word budgets for the agent files, the Steward, the pattern docs and AGENTS.md, and a
deterministic contradiction check across the agent files and the roster. Each budget is the current maximum of its group
rounded up (lines to the next 5, words to the next 50), so the tests pass today and fail when a file grows: shrink or split a
file before raising a budget. Words matter because AGENTS.md and some pattern docs are written as long paragraphs."""

import re
import tempfile
import unittest
from pathlib import Path
from typing import Dict, List, Tuple

ROOT = Path(__file__).resolve().parents[2]

#: Line budgets (``len(text.splitlines())``); current maxima: agent files 55 (reviewer), steward 48, pattern docs 121, AGENTS.md 48.
AGENT_FILE_BUDGET = 55
STEWARD_BUDGET = 50
PATTERN_BUDGET = 125
AGENTS_MD_BUDGET = 50
#: Word budgets (``len(text.split())``); current maxima: agent files 1119 (orchestrator), steward 680, pattern docs 6404
#: (modal-sheet), AGENTS.md 1821.
AGENT_FILE_WORDS = 1150
STEWARD_WORDS = 700
PATTERN_WORDS = 6450
AGENTS_MD_WORDS = 1850


def lines_of(path: Path) -> int:
    return len(path.read_text(encoding="utf-8").splitlines())


def words_of(path: Path) -> int:
    return len(path.read_text(encoding="utf-8").split())


def over(paths, line_budget: int, word_budget: int) -> List[str]:
    """The files in ``paths`` past the line or the word budget, each as one message."""
    found: List[str] = []
    for p in sorted(paths):
        rel = p.relative_to(ROOT) if ROOT in p.parents else p
        if lines_of(p) > line_budget:
            found.append(f"{rel}: {lines_of(p)} lines (budget {line_budget})")
        if words_of(p) > word_budget:
            found.append(f"{rel}: {words_of(p)} words (budget {word_budget})")
    return found


class LineBudgetTests(unittest.TestCase):
    def test_agent_files(self):
        files = [p for p in (ROOT / ".claude" / "agents").glob("*.md") if p.name != "steward.md"]
        self.assertTrue(files)
        self.assertEqual(over(files, AGENT_FILE_BUDGET, AGENT_FILE_WORDS), [])

    def test_the_steward(self):
        self.assertEqual(over([ROOT / ".claude" / "agents" / "steward.md"], STEWARD_BUDGET, STEWARD_WORDS), [])

    def test_pattern_docs(self):
        files = list((ROOT / ".agents" / "patterns").glob("*.md"))
        self.assertTrue(files)
        self.assertEqual(over(files, PATTERN_BUDGET, PATTERN_WORDS), [])

    def test_agents_md(self):
        self.assertEqual(over([ROOT / "AGENTS.md"], AGENTS_MD_BUDGET, AGENTS_MD_WORDS), [])

    def test_the_budgets_are_tight(self):
        """A budget far above the largest file it covers is no budget: within 10% (and the rounding) of the maximum."""
        groups = [([p for p in (ROOT / ".claude" / "agents").glob("*.md") if p.name != "steward.md"], AGENT_FILE_BUDGET,
                   AGENT_FILE_WORDS),
                  ([ROOT / ".claude" / "agents" / "steward.md"], STEWARD_BUDGET, STEWARD_WORDS),
                  (list((ROOT / ".agents" / "patterns").glob("*.md")), PATTERN_BUDGET, PATTERN_WORDS),
                  ([ROOT / "AGENTS.md"], AGENTS_MD_BUDGET, AGENTS_MD_WORDS)]
        for files, line_budget, word_budget in groups:
            with self.subTest(files=str(files[0].name)):
                self.assertLess(line_budget, max(lines_of(p) for p in files) + 5)
                self.assertLess(word_budget, max(words_of(p) for p in files) + 50)

    def test_over_catches_a_longer_file_and_a_wordier_one(self):
        with tempfile.TemporaryDirectory() as tmp:
            long_file, wide_file, fine = Path(tmp) / "long.md", Path(tmp) / "wide.md", Path(tmp) / "fine.md"
            long_file.write_text("line\n" * 5)
            wide_file.write_text("word " * 30 + "\n")
            fine.write_text("a b c\n")
            self.assertEqual(lines_of(long_file), 5)
            self.assertEqual(words_of(wide_file), 30)
            [message] = over([long_file], 4, 100)
            self.assertIn("5 lines (budget 4)", message)
            [message] = over([wide_file], 4, 20)
            self.assertIn("30 words (budget 20)", message)
            self.assertEqual(over([fine, long_file], 5, 100), [])
            self.assertEqual(len(over([long_file, wide_file], 4, 20)), 2)


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
