"""``tools/rules_lint.py`` and ``tools/hooks/rules_guard.py``: one passing and one failing fixture per check id, built in a temp dir
(never the real tree), the ratchet that only falls, the write-time hook and ``--stdin-path``."""

import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parent
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "hooks"))
import rules_guard  # noqa: E402
import rules_lint as rl  # noqa: E402

CLEAN = "# Title\n\nAgents state the default for every task of a kind and link to its one home.\n"


class Tree(unittest.TestCase):
    """A temp repo that holds the real contract and whatever files a test writes."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "contracts").mkdir()
        shutil.copy(ROOT / rl.CONTRACT, self.root / rl.CONTRACT)
        self.addCleanup(self.tmp.cleanup)

    def write(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def checks(self, check, **kw):
        s = rl.load_surface(self.root)
        return [f for f in (rl.check_decisions(s, kw.get("base")) if check == "decisions" else rl.CHECKS[check](s))]

    def messages(self, check, **kw):
        return [f.render() for f in self.checks(check, **kw)]


class ForbiddenTests(Tree):
    def test_clean_text_passes(self):
        self.write("AGENTS.md", CLEAN)
        self.assertEqual(self.checks("forbidden"), [])

    def test_each_forbidden_kind_is_found(self):
        for text, kind in (("Decided 2026-11-02.", "date"), ("The rule (owner approved it).", "attribution"),
                           ("See PR #1234 for it.", "reference"), ("Fixed in a1b2c3d4 already.", "sha"),
                           ("The limit (was 5).", "change_was"), ("It previously ran.", "change"), ("It is no longer used.", "change"),
                           ("The gate was unlocked (x).", "change"), ("Phase 2 adds it.", "change"), ("Use it for now.", "change"),
                           ("Since 2026 it runs.", "change"), ("It landed on main.", "change")):
            with self.subTest(text=text):
                self.write("AGENTS.md", f"# T\n\n{text}\n")
                found = self.messages("forbidden")
                self.assertTrue(found, text)
                self.assertTrue(any(f"({kind})" in m for m in found), (text, found))

    def test_code_and_quotes_are_skipped_but_dates_are_not(self):
        self.write("AGENTS.md", "# T\n\nRun `gh pr view #123` or `git show abcdef1` now.\n\n```\nsha deadbee1 #4567 previously\n```\n"
                                'The label says "No longer available".\n')
        self.assertEqual(self.checks("forbidden"), [])
        self.write("AGENTS.md", "# T\n\n```\nsince 2026-11-02\n```\n")
        self.assertEqual(len(self.checks("forbidden")), 1)

    def test_legitimate_uses_are_not_flagged(self):
        """The false-positive classes tuned out: passive 'is used to', lock states, owner in a list, hex-free words, short hashes."""
        self.write("AGENTS.md", "# T\n\nThe flag is used to select a mode. A lock reads unlocked or locked. Users: owner, member.\n"
                                "Colors like #336699 and ids like #1 stay. Words like release9 are not hashes.\n")
        self.assertEqual(self.messages("forbidden"), [])

    def test_state_and_record_layers_allow_dates(self):
        self.write("PROGRESS.md", "# Plan\n\nShipped 2026-11-02 (owner, previously phase 2).\n")
        self.write(".agents/archive/old.md", "# Old\n\n2026-10-01 landed.\n")
        self.assertEqual(self.checks("forbidden"), [])


class BudgetTests(Tree):
    def test_within_budget_passes(self):
        self.write("AGENTS.md", CLEAN)
        self.write("PROGRESS.md", "# P\n" + "\n".join(["line"] * 50) + "\n")
        self.assertEqual(self.checks("budget"), [])

    def test_words_per_line_words_per_file_and_progress_lines_fail(self):
        self.write("AGENTS.md", "# T\n\n" + "word " * 70 + "\n")
        self.assertIn("words on one line", self.messages("budget")[0])
        self.write("AGENTS.md", "# T\n\n" + ("short line here.\n" * 250))
        self.assertTrue(any("words in the file (budget 600)" in m for m in self.messages("budget")))
        self.write("AGENTS.md", CLEAN)
        self.write("PROGRESS.md", "# P\n" + "\n".join(["line"] * 70) + "\n")
        self.assertTrue(any("lines in the file (budget 60)" in m for m in self.messages("budget")))

    def test_the_orchestrator_has_its_own_word_budget(self):
        body = "# O\n\n" + ("a short line of text here.\n" * 90)  # 452 words: over 350, under 600
        self.write(".claude/agents/orchestrator.md", body)
        self.write(".claude/agents/coder.md", body)
        found = self.messages("budget")
        self.assertEqual(len(found), 1)
        self.assertIn("coder.md", found[0])


class RoleLoadTests(Tree):
    def test_a_small_load_passes(self):
        self.write("AGENTS.md", CLEAN)
        self.write(".claude/agents/coder.md", "# Coder\n\n## Read first\n\n[a](../../.agents/workflow/ci.md).\n")
        self.write(".agents/workflow/ci.md", CLEAN)
        self.assertEqual(self.checks("role_load"), [])
        self.assertGreater(rl.role_loads(rl.load_surface(self.root))[".claude/agents/coder.md"], 20)

    def test_a_heavy_read_first_list_fails_and_only_one_level_counts(self):
        self.write("AGENTS.md", CLEAN)
        self.write(".claude/agents/coder.md", "# Coder\n\n## Read first\n\n[a](../../.agents/workflow/ci.md)\n\n## Later\n\n"
                                              "[b](../../.agents/workflow/token-economy.md)\n")
        self.write(".agents/workflow/ci.md", "# Ci\n\n[deep](deep.md)\n" + "word " * 4100 + "\n")
        self.write(".agents/workflow/deep.md", "# Deep\n" + "word " * 9000)
        self.write(".agents/workflow/token-economy.md", "# T\n" + "word " * 9000)
        [found] = self.checks("role_load")
        self.assertIn("coder.md", found.path)
        self.assertIn("budget 4000", found.message)
        self.assertLess(int(found.message.split()[3]), 5000)

    def test_a_prompt_and_the_orchestrator_budget(self):
        self.write("AGENTS.md", CLEAN)
        self.write("tools/triage/prompts/worker.md", "# W\n" + "word " * 4100)
        self.write(".claude/agents/orchestrator.md", "# O\n" + "word " * 4100)
        paths = [f.path for f in self.checks("role_load")]
        self.assertEqual(paths, ["tools/triage/prompts/worker.md"])


class OneHomeTests(Tree):
    SENTENCE = "Every agent finishes by writing its status block as the last thing it prints before it stops working."

    def test_distinct_files_pass(self):
        self.write("AGENTS.md", f"# A\n\n{self.SENTENCE}\n")
        self.write(".agents/workflow/ci.md", "# C\n\nCI runs the checks on every pull request and reports the result to the author.\n")
        self.assertEqual(self.checks("one_home"), [])

    def test_a_repeated_sentence_fails_and_a_short_one_does_not(self):
        self.write("AGENTS.md", f"# A\n\n{self.SENTENCE}\n")
        self.write(".agents/workflow/ci.md", f"# C\n\n- {self.SENTENCE.lower()}\n")
        self.write(".agents/workflow/versioning.md", "# V\n\nSee the status block.\n")
        self.write(".agents/workflow/eval-gate.md", "# V\n\nSee the status block.\n")
        [found] = self.checks("one_home")
        self.assertEqual(found.path, "AGENTS.md")
        self.assertIn(".agents/workflow/ci.md:3", found.message)

    def test_reference_files_are_not_compared(self):
        self.write(".agents/patterns/a.md", f"# A\n\n{self.SENTENCE}\n")
        self.write(".agents/patterns/b.md", f"# B\n\n{self.SENTENCE}\n")
        self.assertEqual(self.checks("one_home"), [])


class LinksTests(Tree):
    def test_good_links_and_paths_pass(self):
        self.write("tools/x.py", "x\n")
        self.write(".agents/workflow/ci.md", "# CI\n\n## Waiting on CI\n")
        self.write("AGENTS.md", "# A\n\nSee [ci](.agents/workflow/ci.md#waiting-on-ci), [web](https://example.com), `tools/x.py:12`, "
                                "`tools/<id>.py`, `tools/*.py`, `build/x.md` and `.claude/worktrees/x`.\n\n```\ntools/missing.py\n```\n")
        self.assertEqual(self.messages("links"), [])

    def test_broken_file_anchor_and_path_fail(self):
        self.write(".agents/workflow/ci.md", "# CI\n\n## Waiting\n")
        self.write("AGENTS.md", "# A\n\n[a](.agents/workflow/none.md) and [b](.agents/workflow/ci.md#nope) and `tools/missing.py --flag`.\n")
        found = self.messages("links")
        self.assertEqual(len(found), 3, found)
        self.assertTrue(any("does not exist" in m for m in found))
        self.assertTrue(any("#nope" in m for m in found))
        self.assertTrue(any("tools/missing.py" in m for m in found))

    def test_a_same_file_anchor_resolves(self):
        self.write("AGENTS.md", "# A\n\n## Own heading\n\n[ok](#own-heading) [bad](#other)\n")
        [found] = self.checks("links")
        self.assertIn("#other", found.message)


class StructureTests(Tree):
    def test_a_clean_tree_passes(self):
        self.write(".agents/README.md", "# Agents\n\n[patterns](patterns/README.md) [workflow](workflow/README.md)\n")
        self.write(".agents/patterns/README.md", "# P\n\n[a](a.md)\n")
        self.write(".agents/patterns/a.md", "# A\n")
        self.write(".agents/workflow/README.md", "# W\n\n[ci](ci.md)\n")
        self.write(".agents/workflow/ci.md", "# C\n")
        self.write(".agents/decisions/README.md", "Anything\n")
        self.write(".claude/agents/coder.md", "---\nname: coder\n---\nbody\n")
        self.assertEqual(self.messages("structure"), [])

    def test_title_router_rules_layer_and_record_links_fail(self):
        self.write("AGENTS.md", "No title here.\n")
        self.write(".agents/patterns/README.md", "# P\n\n[a](a.md)\n")
        self.write(".agents/patterns/a.md", "# A\n")
        self.write(".agents/patterns/b.md", "# B\n")
        self.write(".agents/patterns/sub/inner.md", "# I\n")
        self.write(".agents/workflow/README.md", "# W\n")
        self.write(".agents/workflow/stray.md", "# S\n\nSee [why](../decisions/2026-11-10-x.md) and `.agents/archive/old.md`.\n")
        self.write(".agents/decisions/2026-11-10-x.md", "# X\n")
        found = self.messages("structure")
        joined = "\n".join(found)
        self.assertIn("line 1 must be `# Title`", joined)
        self.assertIn("does not link b.md", joined)
        self.assertIn("does not link the folder sub/", joined)
        self.assertIn("folder has markdown but no README.md", joined)
        self.assertIn("layer rules holds only the files listed", joined)
        self.assertIn("links into decisions/", joined)
        self.assertIn(".agents/archive/old.md", joined)

    def test_docs_conventions_and_routers_may_link_the_record(self):
        self.write(".agents/workflow/README.md", "# W\n\n[dc](docs-conventions.md)\n")
        self.write(".agents/workflow/docs-conventions.md", "# D\n\n[why](../decisions/README.md)\n")
        self.write(".agents/decisions/README.md", "x\n")
        self.assertEqual(self.messages("structure"), [])


class DecisionsTests(Tree):
    GOOD = "# T\n\nDecision: a\nReplaces: none\nRule home: x\n"

    def test_a_well_formed_entry_passes(self):
        self.write(".agents/decisions/README.md", "# D\n")
        self.write(".agents/decisions/2026-11-10-some-thing.md", self.GOOD)
        self.assertEqual(self.checks("decisions"), [])

    def test_a_bad_name_and_missing_front_lines_fail(self):
        self.write(".agents/decisions/notes.md", "# T\n\nDecision: a\n")
        found = self.messages("decisions")
        self.assertTrue(any("YYYY-MM-DD-slug.md" in m for m in found))
        self.assertTrue(any("`Replaces:`" in m for m in found))
        self.assertTrue(any("`Rule home:`" in m for m in found))

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), "-c", "user.email=t@t", "-c", "user.name=t", *args], capture_output=True, text=True, check=True)

    def test_existing_decisions_are_append_only_against_a_base(self):
        self.git("init", "-q", "-b", "main")
        self.write(".agents/decisions/2026-11-01-old.md", self.GOOD)
        self.git("add", "-A")
        self.git("commit", "-qm", "base")
        self.git("checkout", "-qb", "lane")
        self.write(".agents/decisions/2026-11-10-new.md", self.GOOD)
        self.write(".agents/decisions/README.md", "# changed\n")
        self.assertEqual(self.checks("decisions", base="main"), [])
        self.write(".agents/decisions/2026-11-01-old.md", self.GOOD + "edited\n")
        [found] = self.checks("decisions", base="main")
        self.assertIn("append-only", found.message)
        self.assertIn("2026-11-01-old.md", found.path)
        (self.root / ".agents/decisions/2026-11-01-old.md").unlink()
        [found] = self.checks("decisions", base="main")
        self.assertIn("(D against main)", found.message)

    def test_an_unknown_base_is_reported(self):
        self.git("init", "-q", "-b", "main")
        self.git("commit", "-q", "--allow-empty", "-m", "x")
        [found] = self.checks("decisions", base="nope")
        self.assertIn("cannot compare with base", found.message)


class RatchetTests(Tree):
    DIRTY = "# R\n\nDecided 2026-11-02 and again 2026-11-03.\n"

    def ratchet(self, files):
        self.write("contracts/rules-ratchet.json", json.dumps({"files": files}))

    def test_a_listed_file_at_its_entry_passes_and_unlisted_must_be_clean(self):
        self.write(".agents/patterns/a.md", self.DIRTY)
        self.write(".agents/patterns/b.md", "# B\n")
        self.ratchet({".agents/patterns/a.md": {"forbidden": 2}})
        self.assertEqual(self.messages("ratchet"), [])
        self.ratchet({})
        self.assertEqual(len(self.checks("ratchet")), 2)  # unlisted dirty file: each hit is a finding

    def test_exceeding_the_entry_fails_and_a_stale_entry_must_be_lowered(self):
        self.write(".agents/patterns/a.md", self.DIRTY)
        self.ratchet({".agents/patterns/a.md": {"forbidden": 1}})
        [found] = self.checks("ratchet")
        self.assertIn("forbidden is 2, the ratchet allows 1", found.message)
        self.ratchet({".agents/patterns/a.md": {"forbidden": 5}, ".agents/patterns/gone.md": {"forbidden": 1}})
        found = self.messages("ratchet")
        self.assertTrue(any("lower the ratchet" in m for m in found))
        self.assertEqual(len(found), 2)

    def test_mockup_readmes_are_ratcheted_too(self):
        self.write(".agents/design/mockups/x/README.md", self.DIRTY)
        self.write(".agents/design/mockups/x/notes.md", self.DIRTY)  # not a README: not in any layer
        self.ratchet({".agents/design/mockups/x/README.md": {"forbidden": 2}})
        self.assertEqual(self.checks("ratchet"), [])

    def test_write_ratchet_creates_lowers_and_refuses_a_rise(self):
        self.write(".agents/patterns/a.md", self.DIRTY)
        ok, _msg = rl.write_ratchet(rl.load_surface(self.root))
        self.assertTrue(ok)
        data = json.loads((self.root / "contracts/rules-ratchet.json").read_text())
        self.assertEqual(data["files"][".agents/patterns/a.md"], {"forbidden": 2})
        self.write(".agents/patterns/a.md", "# R\n\nDecided 2026-11-02.\n")
        self.assertTrue(rl.write_ratchet(rl.load_surface(self.root))[0])
        self.assertEqual(json.loads((self.root / "contracts/rules-ratchet.json").read_text())["files"][".agents/patterns/a.md"], {"forbidden": 1})
        self.write(".agents/patterns/a.md", self.DIRTY)
        ok, message = rl.write_ratchet(rl.load_surface(self.root))
        self.assertFalse(ok)
        self.assertIn("would rise", message)
        self.write(".agents/patterns/new.md", "# N\n\n2026-11-01\n")  # a new dirty file counts as a rise from zero
        self.write(".agents/patterns/a.md", "# R\n")
        self.assertFalse(rl.write_ratchet(rl.load_surface(self.root))[0])


class CliTests(Tree):
    def run_main(self, *argv, stdin=""):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err), mock.patch.object(sys, "stdin", io.StringIO(stdin)):
            code = rl.main(["--root", str(self.root), *argv])
        return code, out.getvalue(), err.getvalue()

    def test_a_clean_tree_exits_zero_and_a_dirty_one_lists_findings_with_homes(self):
        self.write("AGENTS.md", CLEAN)
        self.assertEqual(self.run_main()[0], 0)
        self.write("AGENTS.md", "# A\n\nDecided 2026-11-02.\n")
        code, out, _err = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("AGENTS.md:3: [forbidden]", out)
        self.assertIn("-> the PR description or .agents/decisions/", out)
        self.assertIn("1 findings in 1 files: forbidden 1", out)

    def test_paths_limits_the_report(self):
        self.write("AGENTS.md", "# A\n\n2026-11-02\n")
        self.write(".claude/agents/coder.md", "# C\n\n2026-11-02\n")
        code, out, _err = self.run_main("--paths", "AGENTS.md")
        self.assertEqual(code, 1)
        self.assertIn("AGENTS.md", out)
        self.assertNotIn("coder.md", out)

    def test_stdin_path_lints_text_as_that_file(self):
        code, out, _err = self.run_main("--stdin-path", "AGENTS.md", stdin="# A\n\nSince 2026-11-02 it landed.\n")
        self.assertEqual(code, 1)
        self.assertIn("AGENTS.md:3", out)
        self.assertEqual(self.run_main("--stdin-path", "AGENTS.md", stdin=CLEAN)[0], 0)
        self.assertEqual(self.run_main("--stdin-path", "PROGRESS.md", stdin="# P\n\n2026-11-02 landed\n")[0], 0)
        self.assertEqual(self.run_main("--stdin-path", "apple/x.md", stdin="2026-11-02")[0], 0)  # not a rule-surface file

    def test_report_gives_words_per_layer_and_role_load(self):
        self.write("AGENTS.md", CLEAN)
        self.write(".claude/agents/coder.md", "# C\n\nbody\n")
        self.write(".agents/decisions/2026-11-10-x.md", "# X\n\nsome words here\n")
        _code, out, _err = self.run_main("--report")
        data = json.loads(out)
        self.assertEqual(data["layers"]["core"]["files"], 1)
        self.assertGreater(data["role_load"][".claude/agents/coder.md"], data["layers"]["agent"]["words"])
        self.assertNotIn(4, [data["layers"]["record"]["files"]])  # the record layer is reported but not in the surface total
        self.assertEqual(data["rule_surface_words"], sum(v["words"] for k, v in data["layers"].items() if k != "record"))

    def test_write_ratchet_flag_and_help(self):
        self.write(".agents/patterns/a.md", "# A\n\n2026-11-02\n")
        code, out, _err = self.run_main("--write-ratchet")
        self.assertEqual(code, 0)
        self.assertIn("rules-ratchet.json", out)
        self.write(".agents/patterns/a.md", "# A\n\n2026-11-02 2026-11-03\n")
        self.assertEqual(self.run_main("--write-ratchet")[0], 1)
        with self.assertRaises(SystemExit), redirect_stdout(io.StringIO()) as help_out:
            rl.main(["--help"])
        self.assertIn("no inline ignore comment", help_out.getvalue())


class HookTests(Tree):
    def payload(self, tool, **tool_input):
        return {"tool_name": tool, "cwd": str(self.root), "tool_input": tool_input}

    def run_hook(self, payload):
        err = io.StringIO()
        with redirect_stderr(err), mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))):
            code = rules_guard.main()
        return code, err.getvalue()

    def test_a_dirtying_write_is_blocked_with_rule_hits_and_home(self):
        self.write("AGENTS.md", CLEAN)
        code, err = self.run_hook(self.payload("Write", file_path=str(self.root / "AGENTS.md"), content="# A\n\nDecided 2026-11-02 (owner, no).\n"))
        self.assertEqual(code, 2)
        self.assertIn("present tense", err)
        self.assertIn("line 3", err)
        self.assertIn("Home for that content: the PR description or .agents/decisions/", err)

    def test_a_clean_write_and_other_files_pass(self):
        self.assertEqual(self.run_hook(self.payload("Write", file_path=str(self.root / "AGENTS.md"), content=CLEAN))[0], 0)
        self.assertEqual(self.run_hook(self.payload("Write", file_path=str(self.root / "apple/x.md"), content="2026-11-02"))[0], 0)
        self.assertEqual(self.run_hook(self.payload("Write", file_path=str(self.root / "tools/x.py"), content="2026-11-02"))[0], 0)
        self.assertEqual(self.run_hook(self.payload("Read", file_path=str(self.root / "AGENTS.md")))[0], 0)
        self.assertEqual(self.run_hook(self.payload("Write", file_path="/elsewhere/AGENTS.md", content="2026-11-02"))[0], 0)

    def test_a_cleaning_edit_is_allowed_and_a_dirtying_one_blocked(self):
        self.write("AGENTS.md", "# A\n\nDecided 2026-11-02 and 2026-11-03 here.\n")
        path = str(self.root / "AGENTS.md")
        code, _err = self.run_hook(self.payload("Edit", file_path=path, old_string="Decided 2026-11-02 and", new_string="Decided"))
        self.assertEqual(code, 0)  # two hits become one: lower
        code, _err = self.run_hook(self.payload("Edit", file_path=path, old_string="here.", new_string="here, 2026-11-04."))
        self.assertEqual(code, 2)
        code, _err = self.run_hook(self.payload("Edit", file_path=path, old_string="here.", new_string="here."))
        self.assertEqual(code, 0)  # equal

    def test_an_edit_that_cannot_apply_is_allowed(self):
        self.write("AGENTS.md", CLEAN)
        path = str(self.root / "AGENTS.md")
        self.assertEqual(self.run_hook(self.payload("Edit", file_path=path, old_string="not in the file", new_string="2026-11-02"))[0], 0)
        self.assertEqual(self.run_hook(self.payload("Edit", file_path=str(self.root / "PROGRESS.md"), old_string="a", new_string="2026-11-02 b"))[0], 0)

    def test_multiedit_applies_edits_in_order_and_replace_all(self):
        self.write("AGENTS.md", "# A\n\nOne.\n\nOne.\n")
        path = str(self.root / "AGENTS.md")
        edits = [{"old_string": "One.", "new_string": "Two.", "replace_all": True}, {"old_string": "Two.", "new_string": "Two 2026-11-02."}]
        self.assertEqual(self.run_hook(self.payload("MultiEdit", file_path=path, edits=edits))[0], 2)
        self.assertEqual(self.run_hook(self.payload("MultiEdit", file_path=path, edits=edits[:1]))[0], 0)

    def test_budget_growth_blocks_but_shrinking_an_oversized_file_passes(self):
        big = "# A\n\n" + ("short line here ok.\n" * 200)  # 800 words, past 600
        self.write("AGENTS.md", big)
        path = str(self.root / "AGENTS.md")
        self.assertEqual(self.run_hook(self.payload("Write", file_path=path, content=big + "more words\n"))[0], 2)
        self.assertEqual(self.run_hook(self.payload("Write", file_path=path, content=big[:-40]))[0], 0)
        wide = "# A\n\n" + "word " * 70 + "\n"
        code, err = self.run_hook(self.payload("Write", file_path=path, content=wide))
        self.assertEqual(code, 2)
        self.assertIn("words on one line", err)

    def test_garbage_input_and_a_crash_fail_open(self):
        with mock.patch.object(sys, "stdin", io.StringIO("not json")):
            self.assertEqual(rules_guard.main(), 0)
        script = TOOLS / "hooks" / "rules_guard.py"
        proc = subprocess.run([sys.executable, str(script)], input=json.dumps(self.payload("Write", file_path=str(self.root / "AGENTS.md"),
                              content="# A\n\n2026-11-02\n")), capture_output=True, text=True, cwd=self.root)
        self.assertEqual(proc.returncode, 2)
        with mock.patch.object(rules_guard, "main", side_effect=RuntimeError("boom")):
            code = subprocess.run([sys.executable, "-c", "import runpy,sys; sys.argv=['x']; "
                                   "import rules_guard as g; g.main=lambda: 1/0; "
                                   f"runpy.run_path({str(script)!r}, run_name='__main__')"], capture_output=True, text=True,
                                  cwd=self.root, env={"PYTHONPATH": str(TOOLS / "hooks")}, input="{}")
        self.assertEqual(code.returncode, 0)


class ContractTests(unittest.TestCase):
    def test_the_contract_is_well_formed(self):
        """Fails if: a layer lacks a field the lint reads, a pattern does not compile, or a refusal has no why or home."""
        contract = json.loads((ROOT / rl.CONTRACT).read_text())
        for name, layer in contract["layers"].items():
            self.assertIn("globs", layer, name)
            self.assertIn("forbidden", layer, name)
        for pattern in contract["forbidden"]:
            rl.re.compile(pattern["regex"])
            self.assertTrue(pattern["why"] and pattern["home"], pattern["id"])
        self.assertEqual(contract["layers"]["reference"]["ratchet"], "contracts/rules-ratchet.json")
        self.assertEqual(contract["role_load"]["orchestrator"], 6000)

    def test_the_real_ratchet_only_lists_ratcheted_layers_and_existing_files(self):
        """Fails if: the ratchet names a file that is gone or a layer without a ratchet (then it should fall, or be deleted)."""
        ratchet = ROOT / "contracts" / "rules-ratchet.json"
        if not ratchet.exists():
            return  # deleted once the reference layer is clean
        contract = rl.load_contract(ROOT)
        for rel in json.loads(ratchet.read_text())["files"]:
            self.assertTrue((ROOT / rel).is_file(), rel)
            self.assertTrue(rl.ratcheted(contract, rl.layer_of(contract, rel)), rel)


if __name__ == "__main__":
    unittest.main()
