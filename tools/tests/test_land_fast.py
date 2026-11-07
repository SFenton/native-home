"""Fast landing (owner, 2026-11-04): right-sized tests, the base moving mid-run, and the reaper after a merge."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "hooks"))
import ci_hygiene  # noqa: E402
import lane_land  # noqa: E402
from test_lane_land import BASE, GENV, Repo, g  # noqa: E402

PASS = "import unittest\n\nclass T(unittest.TestCase):\n    def test_ok(self):\n        self.assertTrue(True)\n"
FAIL = "import unittest\n\nclass T(unittest.TestCase):\n    def test_bad(self):\n        self.fail('new')\n"


def rows(*paths, status="M"):
    return [(status, p, "0" * 40, "1" * 40) for p in paths]


class SelectionTests(unittest.TestCase):
    """``select_land_tests`` over a throwaway repo: a static import scan, nothing executes."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="land-select-")).resolve()
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        subprocess.run(["git", "init", "-q", "-b", "main", str(self.dir)], check=True)
        self.files = {
            "tools/leaf.py": "X = 1\n",
            "tools/mid.py": "import leaf\n",
            "tools/top.py": "import subprocess\nsubprocess.run(['python3', 'tools/mid.py'])\n",
            "tools/lonely.py": "Y = 2\n",
            "tools/shared.py": "Z = 3\n",
            "tools/hooks/shell_parse.py": "S = 1\n",
            "tools/tests/test_core.py": PASS,
            "tools/tests/test_top.py": "import top\n" + PASS,
            "tools/tests/test_lonely.py": PASS,
            "tools/tests/test_other.py": PASS,
            "tools/tests/test_lonely_extra.py": PASS,
            "tools/triage/tests/test_tri.py": "import leaf\n" + PASS,
            "tools/tests/test_loader.py": "def load_tool(n):\n    pass\n\nload_tool('leaf')\n" + PASS,
            "tools/tests/test_words.py": "import subprocess\nsubprocess.run(['git', 'clean', '-n'])\nX = 'lonely'\n" + PASS,
            "tools/tests/test_reads.py": "P = ['contracts', 'test-map.json']\nQ = 'apple/Apps/iOSUITests/MotionJourneyTests.swift'\n" + PASS,
            "tools/tests/test_test_plans.py": PASS,
        }
        for i in range(12):
            self.files[f"tools/tests/test_uses_shared_{i}.py"] = "import shared\n" + PASS
        for rel, text in self.files.items():
            path = self.dir / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        self.git("add", "-A")
        self.git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "x")
        self.sha = self.git("rev-parse", "HEAD").strip()

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.dir), *args], capture_output=True, text=True, check=True).stdout

    def select(self, *changed, status="M", **kw):
        kw.setdefault("core", ["tools/tests/test_core.py"])
        return lane_land.select_land_tests(self.dir, self.sha, rows(*changed, status=status), **kw)

    def test_the_core_set_is_always_selected(self):
        sel = self.select("docs/readme.md")
        self.assertFalse(sel.full)
        self.assertEqual(sel.files, ["tools/tests/test_core.py"])

    def test_the_default_core_names_the_landing_guards(self):
        for name in ("test_lane_land", "test_pr_land", "test_hooks", "test_worktree_guard", "test_kill_guard", "test_signing_guard",
                     "test_jev", "test_jev_gate", "test_bloat", "test_agent_roster", "test_ship_guard_wiring", "test_mockup_lifecycle"):
            self.assertIn(f"tools/tests/{name}.py", lane_land.LAND_CORE_TESTS)

    def test_a_leaf_change_selects_its_importers_transitively_and_nothing_else(self):
        sel = self.select("tools/leaf.py")
        self.assertFalse(sel.full)
        # leaf <- mid <- top (a script start counts) <- test_top, and the triage test that imports leaf
        # (test_loader names the tool by string: load-by-name counts as a reference)
        self.assertEqual(sel.files, ["tools/tests/test_core.py", "tools/tests/test_loader.py", "tools/tests/test_top.py",
                                     "tools/triage/tests/test_tri.py"])
        self.assertNotIn("test_other", " ".join(sel.files))

    def test_a_tool_loaded_by_name_selects_the_test_that_loads_it(self):
        self.assertIn("tools/tests/test_loader.py", self.select("tools/leaf.py").files)
        sel = self.select("tools/mid.py")  # the loader names only leaf
        self.assertNotIn("tools/tests/test_loader.py", sel.files)

    def test_a_bare_word_is_not_a_tool_reference(self):
        # "lonely" (and a git "clean") are words, not tools/ files or a load call's argument
        sel = self.select("tools/lonely.py")
        self.assertNotIn("tools/tests/test_words.py", sel.files)

    def test_a_tools_path_string_is_a_reference(self):
        refs = lane_land.tool_references("P = 'tools/leaf'\nQ = 'leaf'\n", "t.py")
        self.assertIn("leaf", refs)
        self.assertNotIn("leaf", lane_land.tool_references("Q = 'leaf'\n", "t.py"))
        self.assertIn("leaf", lane_land.tool_references("load_tool('leaf')\n", "t.py"))
        self.assertNotIn("leaf", lane_land.tool_references("f('leaf')\n", "t.py"))

    def test_a_change_outside_tools_selects_tests_that_name_it(self):
        sel = self.select("contracts/test-map.json")
        self.assertIn("tools/tests/test_reads.py", sel.files)  # the file name is a literal
        self.assertIn("tools/tests/test_test_plans.py", sel.files)  # the trusted checker map for contracts/
        sel = self.select("apple/Apps/iOSUITests/MotionJourneyTests.swift")
        self.assertIn("tools/tests/test_reads.py", sel.files)  # the full path is a literal
        sel = self.select("apple/Apps/iOSUITests/NewJourneyTests.swift", status="A")
        self.assertIn("tools/tests/test_test_plans.py", sel.files)  # a new journey class: the plans must be regenerated
        self.assertNotIn("tools/tests/test_reads.py", sel.files)
        self.assertFalse(sel.full)

    def test_a_deleted_or_renamed_test_file_forces_the_full_suite_and_is_kept_in_the_command(self):
        sel = lane_land.select_land_tests(self.dir, self.sha, rows("tools/tests/test_other.py", status="D"),
                                          core=["tools/tests/test_core.py"])
        self.assertTrue(sel.full)
        self.assertEqual(sel.removed, ["tools/tests/test_other.py"])
        self.assertIn("test_other.py", sel.command)
        self.assertIn("tools/tests/test_top.py", sel.files)
        fast = lane_land.select_land_tests(self.dir, self.sha, rows("tools/tests/test_other.py", status="D"),
                                           core=["tools/tests/test_core.py"], fast_only=True)
        self.assertFalse(fast.full)
        self.assertIn("tools/tests/test_other.py", fast.files)

    def test_tests_named_for_a_changed_file_and_changed_tests_are_selected(self):
        sel = self.select("tools/lonely.py")
        self.assertEqual(sel.files, ["tools/tests/test_core.py", "tools/tests/test_lonely.py", "tools/tests/test_lonely_extra.py"])
        sel = self.select("tools/tests/test_other.py")
        self.assertEqual(sel.files, ["tools/tests/test_core.py", "tools/tests/test_other.py"])

    def test_a_deleted_file_still_selects_the_tests_that_name_it(self):
        sel = lane_land.select_land_tests(self.dir, self.sha, rows("tools/gone.py", status="D"), core=["tools/tests/test_core.py"])
        self.assertEqual(sel.files, ["tools/tests/test_core.py"])
        (self.dir / "tools/tests/test_gone.py").write_text(PASS)
        self.git("add", "-A")
        self.git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "y")
        sha = self.git("rev-parse", "HEAD").strip()
        sel = lane_land.select_land_tests(self.dir, sha, rows("tools/gone.py", status="D"), core=["tools/tests/test_core.py"])
        self.assertIn("tools/tests/test_gone.py", sel.files)

    def test_a_shared_module_selects_the_full_suite(self):
        sel = self.select("tools/shared.py")
        self.assertTrue(sel.full)
        self.assertIn("tools/tests/test_other.py", sel.files)
        self.assertIn("reached by 12", sel.why)

    def test_the_trigger_list_selects_the_full_suite_and_the_config_only_adds(self):
        self.assertTrue(self.select("tools/hooks/shell_parse.py", full_triggers=[]).full)
        self.assertFalse(self.select("tools/lonely.py", full_triggers=[]).full)
        sel = self.select("tools/lonely.py", full_triggers=["tools/lonely.py"])
        self.assertTrue(sel.full)
        self.assertIn("tools/hooks/shell_parse.py", lane_land.LAND_FULL_SUITE_TRIGGERS)
        for name in ("tools/tasks.py", "tools/run_tool_tests.sh", "tools/redact.py"):
            self.assertIn(name, lane_land.LAND_FULL_SUITE_TRIGGERS)

    def test_the_rerun_after_a_base_move_never_widens_to_the_full_suite(self):
        sel = self.select("tools/shared.py", fast_only=True)
        self.assertFalse(sel.full)
        self.assertEqual(len(sel.files), 13)  # core + the 12 importers

    def test_a_custom_test_command_is_used_as_given(self):
        sel = self.select("tools/shared.py", tests="true")
        self.assertEqual((sel.full, sel.command), (True, "true"))

    def test_the_command_runs_the_selected_files_and_skips_missing_ones(self):
        command = lane_land.suite_command(["tools/tests/test_core.py", "tools/tests/test_missing.py", "tools/tests/test_other.py"])
        proc = subprocess.run(command, shell=True, cwd=self.dir, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(lane_land.test_stats(proc.stderr)[:2], (2, 2))
        (self.dir / "tools/tests/test_core.py").write_text(FAIL)
        proc = subprocess.run(command, shell=True, cwd=self.dir, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(lane_land.test_stats(proc.stderr)[:2], (2, 2))

    def test_release_tests_run_as_modules(self):
        self.assertIn("python3 -m unittest -v tools.release.tests.test_x", lane_land.suite_command(["tools/release/tests/test_x.py"]))


class SelectedLandTests(Repo):
    """The subset rule on the selected set, through ``land``."""

    def test_a_new_failing_test_in_the_selected_set_blocks(self):
        sha = self.push_lane("agents/bad", {"tools/tests/test_new.py": FAIL})
        msg = self.refused("tests", lane="agents/bad", tests=lane_land.DEFAULT_TESTS, launch=lambda *a: self.said(sha))
        self.assertIn("new failures", msg)
        self.assertEqual(g(self.origin, "rev-list", "--count", "--merges", BASE), "0")

    def test_a_passing_selected_test_lands(self):
        sha = self.push_lane("agents/good", {"tools/tests/test_new.py": PASS})
        result = self.land(lane="agents/good", tests=lane_land.DEFAULT_TESTS, launch=lambda *a: self.said(sha))
        self.assertEqual(result["sha"], sha)


class RemovedAndMovedTests(Repo):
    """Per-test-id comparison, the base moving during the review, and the per-file base cache."""

    def test_a_base_that_gains_a_case_during_the_review_is_tested_against_the_new_base(self):
        self.seed_base({"tools/tests/test_extra.py": PASS})
        sha = self.push_lane("agents/late", {"c.txt": "c\n"})

        def review(lane, head, base, diff):
            self.seed_base({"tools/tests/test_extra.py": PASS + "    def test_two(self):\n        self.assertTrue(True)\n"})
            return self.said(head)

        result = self.land(lane="agents/late", tests=lane_land.DEFAULT_TESTS, core_tests=["tools/tests/test_extra.py"], launch=review)
        self.assertEqual(result["sha"], sha)
        self.assertEqual(result["parent"], g(self.origin, "rev-parse", f"{BASE}^1"))

    FOO_TEST = ("import sys\nsys.path.insert(0, 'tools')\nimport foo\nimport unittest\n\n\nclass T(unittest.TestCase):\n"
                "    def test_value(self):\n        self.assertEqual(foo.value(), 1)\n")

    def seed_foo(self):
        self.seed_base({"tools/foo.py": "def value():\n    return 1\n", "tools/tests/test_foo.py": self.FOO_TEST,
                        "tools/tests/test_bar.py": "import sys\nsys.path.insert(0, 'tools')\nimport foo\n" + PASS})

    def test_breaking_a_tool_and_deleting_its_test_is_refused(self):
        self.seed_foo()
        sha = self.push_lane("agents/del", {"tools/foo.py": "def value():\n    return 2\n"}, delete=["tools/tests/test_foo.py"])
        msg = self.refused("tests", lane="agents/del", tests=lane_land.DEFAULT_TESTS, launch=lambda *a: self.said(sha))
        self.assertIn("vanished", msg)
        self.assertIn("test_value (", msg)
        self.assertEqual(g(self.origin, "rev-list", "--count", "--merges", BASE), "0")

    def test_a_renamed_test_file_lands(self):
        self.seed_foo()
        sha = self.push_lane("agents/ren", {"tools/tests/test_foo2.py": self.FOO_TEST}, delete=["tools/tests/test_foo.py"])
        self.assertEqual(self.land(lane="agents/ren", tests=lane_land.DEFAULT_TESTS, launch=lambda *a: self.said(sha))["sha"], sha)

    def test_a_test_retired_with_every_tool_it_covers_lands(self):
        self.seed_base({"tools/solo.py": "X = 1\n", "tools/tests/test_solo.py": "import sys\nsys.path.insert(0, 'tools')\nimport solo\n" + PASS})
        sha = self.push_lane("agents/retire", {}, delete=["tools/solo.py", "tools/tests/test_solo.py"])
        self.assertEqual(self.land(lane="agents/retire", tests=lane_land.DEFAULT_TESTS, launch=lambda *a: self.said(sha))["sha"], sha)

    def test_a_swapped_case_is_refused_naming_the_ids(self):
        two = PASS + "    def test_two(self):\n        self.assertTrue(True)\n"
        self.seed_base({"tools/tests/test_kept.py": two})
        sha = self.push_lane("agents/drop", {"tools/tests/test_kept.py": PASS + "    def test_three(self):\n        self.assertTrue(True)\n"})
        msg = self.refused("tests", lane="agents/drop", tests=lane_land.DEFAULT_TESTS, launch=lambda *a: self.said(sha),
                           core_tests=["tools/tests/test_kept.py"])
        self.assertIn("vanished", msg)

    def test_the_base_side_is_cached_per_file_and_shared_across_selections(self):
        counts = {}
        self.seed_base({"tools/tests/test_a.py": PASS, "tools/tests/test_b.py": PASS})
        sha = self.push_lane("agents/one", {"tools/tests/test_a.py": PASS + "\n# x\n"})
        self.land(lane="agents/one", tests=lane_land.DEFAULT_TESTS, launch=lambda *a: self.said(sha), base_counts=counts, dry_run=True)
        keys = [k for k in counts if "|file|" in k]
        self.assertEqual(len(keys), 1)
        sha = self.push_lane("agents/two", {"tools/tests/test_a.py": PASS + "\n# y\n", "tools/tests/test_b.py": PASS + "\n# z\n"})
        before = dict(counts)
        self.land(lane="agents/two", tests=lane_land.DEFAULT_TESTS, launch=lambda *a: self.said(sha), base_counts=counts, dry_run=True)
        for k in keys:
            self.assertEqual(counts[k], before[k])  # reused, not rerun
        self.assertEqual(len([k for k in counts if "|file|" in k]), 2)


class MergedTreeTests(Repo):
    """The tests run on the lane merged into the current base, not on the lane SHA alone."""

    def test_a_lane_cut_before_the_base_gained_a_test_file_is_not_undercounted(self):
        # self.sha was cut from the initial base; the base then gains a core test the lane does not have
        self.seed_base({"tools/tests/test_extra.py": PASS})
        sha = self.sha
        result = self.land(tests=lane_land.DEFAULT_TESTS, core_tests=["tools/tests/test_extra.py"], launch=lambda *a: self.said(sha))
        self.assertEqual(result["sha"], sha)

    def test_a_conflicting_lane_is_refused_before_any_test_runs(self):
        self.seed_base({"b.txt": "other\n"})  # the lane adds b.txt "b"
        sha = self.sha
        with self.assertRaises(lane_land.LandFailed) as cm:
            self.land(tests="touch ran.marker", launch=lambda *a: self.said(sha))
        self.assertEqual(cm.exception.kind, "conflict")
        self.assertIn("does not merge cleanly", str(cm.exception))
        self.assertFalse((self.clone / "ran.marker").exists())
        self.assertEqual(g(self.origin, "rev-list", "--count", "--merges", BASE), "0")


class BaseMovedTests(Repo):
    """The base moving during the review and tests: rerun the fast sets once, or refuse."""

    def mover(self, name, once=True, text="o\n"):
        marker = self.dir / f"{name}.done"
        script = self.dir / f"{name}.sh"
        guard = f"[ -f {marker} ] && exit 0; touch {marker}; " if once else ""
        script.write_text(f"#!/bin/sh\n{guard}cd {self.dev} && git checkout -q {BASE} && git pull -q origin {BASE} && "
                          f"echo '{text}'$$ > {name}.txt && git add -A && git commit -qm moved-{name} && git push -q origin {BASE}\nexit 0\n")
        script.chmod(0o755)
        return script

    def test_one_move_reruns_and_lands_on_the_new_base(self):
        script = self.mover("once")
        sha = self.sha
        result = self.land(launch=lambda *a: self.said(sha), tests=f"sh {script}")
        self.assertEqual(g(self.origin, "log", "-1", "--format=%s", f"{BASE}^2"), "work on agents/x")
        self.assertEqual(result["parent"], g(self.origin, "rev-parse", f"{BASE}^1"))
        self.assertEqual(g(self.origin, "log", "-1", "--format=%s", f"{BASE}^1"), "moved-once")

    def test_a_second_move_refuses(self):
        script = self.mover("again", once=False)
        sha = self.sha
        msg = self.refused("base", launch=lambda *a: self.said(sha), tests=f"sh {script}")
        self.assertIn("moved", msg)
        self.assertEqual(g(self.origin, "rev-list", "--count", "--merges", BASE), "0")

    def test_a_move_that_conflicts_with_the_lane_refuses(self):
        script = self.mover("b", text="different")  # the lane adds b.txt "b"
        sha = self.sha
        msg = self.refused("base", launch=lambda *a: self.said(sha), tests=f"sh {script}")
        self.assertIn("no longer merges cleanly", msg)
        self.assertEqual(g(self.origin, "rev-list", "--count", "--merges", BASE), "0")

    def test_the_rerun_checks_the_new_changed_paths(self):
        sha = self.sha
        calls = []
        real = lane_land.select_land_tests

        def spy(*a, **kw):
            calls.append(kw.get("fast_only", False))
            return real(*a, **kw)

        script = self.mover("spy")
        with mock.patch.object(lane_land, "select_land_tests", spy):
            self.land(launch=lambda *a: self.said(sha), tests=f"sh {script}")
        self.assertEqual(calls, [False, True])


class ReaperTests(unittest.TestCase):
    """``ci_hygiene.reap_merged_branch``: only a clean, unlocked, fully pushed, unused lane worktree goes."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="reaper-")).resolve()
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.main = self.dir / "main"
        self.main.mkdir()
        self.env = {**os.environ, **GENV}
        self.run_git(self.main, "init", "-q", "-b", "main")
        self.run_git(self.main, "commit", "-q", "--allow-empty", "-m", "i")
        self.wt = self.dir / "lane"
        self.run_git(self.main, "worktree", "add", "-q", "-b", "agents/x", str(self.wt))
        self.sha = self.run_git(self.wt, "rev-parse", "HEAD").strip()

    def run_git(self, cwd, *args):
        return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, check=True, env=self.env).stdout

    def reap(self, held=(), live=(), here=None):
        return ci_hygiene.reap_merged_branch(self.main, "agents/x", self.sha, here=here or self.main, held=list(held), live=list(live))

    def branches(self):
        return self.run_git(self.main, "branch", "--list", "agents/x").strip()

    def test_a_clean_merged_worktree_and_its_branch_are_removed(self):
        lines = self.reap()
        self.assertFalse(self.wt.exists())
        self.assertEqual(self.branches(), "")
        self.assertTrue(any(l.startswith("removed worktree") for l in lines))
        self.assertIn("deleted local branch agents/x", lines)

    def kept(self, reason):
        lines = self.reap()
        self.assertTrue(self.wt.exists(), lines)
        self.assertIn("agents/x", self.branches())
        self.assertTrue(any(reason in l for l in lines), lines)

    def test_a_dirty_worktree_stays(self):
        (self.wt / "wip.txt").write_text("x")
        self.kept("uncommitted or untracked")

    def test_a_modified_tracked_file_stays(self):
        (self.wt / "t.txt").write_text("x")
        self.run_git(self.wt, "add", "t.txt")
        self.run_git(self.wt, "commit", "-qm", "t")
        self.sha_before = self.sha
        (self.wt / "t.txt").write_text("y")
        self.kept("uncommitted")

    def test_a_locked_worktree_stays(self):
        self.run_git(self.main, "worktree", "lock", str(self.wt))
        self.kept("locked")

    def test_a_worktree_with_unpushed_commits_stays(self):
        self.run_git(self.wt, "commit", "-q", "--allow-empty", "-m", "unpushed")
        self.kept("not in the merged")

    def test_a_devcap_hold_or_a_live_cwd_keeps_it(self):
        lines = self.reap(held=[str(self.wt / "sub")])
        self.assertTrue(self.wt.exists())
        self.assertTrue(any("devcap hold" in l for l in lines), lines)
        lines = self.reap(live=[str(self.wt)])
        self.assertTrue(self.wt.exists())
        self.assertTrue(any("live process" in l for l in lines), lines)
        lines = self.reap(here=self.wt)
        self.assertTrue(any("caller is inside" in l for l in lines), lines)

    def test_a_real_process_inside_the_worktree_is_seen_by_lsof(self):
        proc = subprocess.Popen(["sleep", "30"], cwd=self.wt)
        self.addCleanup(proc.wait)
        self.addCleanup(proc.kill)
        cwds = ci_hygiene.live_process_cwds()
        self.assertTrue(any(ci_hygiene._under(c, str(self.wt)) for c in cwds))
        lines = ci_hygiene.reap_merged_branch(self.main, "agents/x", self.sha, here=self.main, held=[])
        self.assertTrue(self.wt.exists(), lines)

    def test_a_handoff_note_keeps_it(self):
        (self.wt / "build" / "handoff").mkdir(parents=True)
        (self.wt / "build" / "handoff" / "t.md").write_text("x")
        self.kept("hand-off")

    def test_the_branch_in_the_primary_clone_is_left_alone(self):
        self.run_git(self.main, "worktree", "remove", "--force", str(self.wt))
        self.run_git(self.main, "checkout", "-q", "agents/x")
        lines = ci_hygiene.reap_merged_branch(self.main, "agents/x", self.sha, here=self.dir)
        self.assertIn("primary clone", lines[0])


class LandReaperTests(Repo):
    """``land`` with a reaper: the remote branch goes, and a failing reaper never changes the result."""

    def setUp(self):
        super().setUp()
        # never the owner's real primary clone
        patch = mock.patch.object(ci_hygiene, "resolve_primary_repo", return_value=(None, "no primary clone configured: test"))
        patch.start()
        self.addCleanup(patch.stop)

    def test_the_remote_lane_branch_is_deleted_after_the_push(self):
        sha = self.sha
        result = self.land(launch=lambda *a: self.said(sha), reaper=lane_land.reap_merged_lane)
        self.assertIn("deleted remote branch agents/x", result["reaper"])
        self.assertEqual(g(self.origin, "branch", "--list", "agents/x"), "")
        self.assertTrue(any("kept worktree and local branch" in l for l in result["reaper"]))

    def test_a_lane_that_moved_keeps_its_remote_branch(self):
        sha = self.sha
        calls = []

        def reaper(lane, merged, clone):
            self.push_lane("agents/x", {"c.txt": "c\n"})
            calls.append(lane_land.reap_merged_lane(lane, merged, clone))
            return calls[0]

        self.land(launch=lambda *a: self.said(sha), reaper=reaper)
        self.assertTrue(any(l.startswith("kept remote branch") for l in calls[0]), calls)
        self.assertIn("agents/x", g(self.origin, "branch", "--list", "agents/x"))

    def test_a_raising_reaper_changes_nothing(self):
        sha = self.sha

        def boom(lane, merged, clone):
            raise RuntimeError("disk on fire")

        result = self.land(launch=lambda *a: self.said(sha), reaper=boom)
        self.assertEqual(result["sha"], sha)
        self.assertIn("RuntimeError", result["reaper"][0])
        self.assertEqual(g(self.origin, "rev-list", "--count", "--merges", BASE), "1")

    def test_a_reaper_is_not_run_when_the_landing_is_refused(self):
        called = []
        self.refused("review", reaper=lambda *a: called.append(1) or [])
        self.assertEqual(called, [])


if __name__ == "__main__":
    unittest.main()
