"""``tools/lane_land.py`` (the runner's landing library and the interactive CLI) in temp repos with a local bare origin, and
the headless allow-list of ``tools/hooks/merge_guard.py``. No network, no claude."""
import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "hooks"))
import lane_land  # noqa: E402
import merge_guard  # noqa: E402

GENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
        "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}
BASE = "claude/uikit-port"


def g(cwd, *args):
    return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, check=True,
                          env={**os.environ, **GENV}).stdout.strip()


class Repo(unittest.TestCase):
    """A bare origin with the base, a dev clone that pushes lanes, and the runner's land clone."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="lane-land-")).resolve()
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.home = self.dir / "home"
        self.home.mkdir()
        env = mock.patch.dict(os.environ, {**GENV, "HOME": str(self.home)})
        env.start()
        self.addCleanup(env.stop)
        for key in ("HASS_TRIAGE_PAUSED_FILE", "FENTON_HEADLESS"):
            os.environ.pop(key, None)
        self.origin = self.dir / "origin.git"
        subprocess.run(["git", "init", "-q", "--bare", str(self.origin)], check=True)
        self.dev = self.dir / "dev"
        subprocess.run(["git", "init", "-q", "-b", BASE, str(self.dev)], check=True)
        (self.dev / "a.txt").write_text("a\n")
        g(self.dev, "add", "-A")
        g(self.dev, "commit", "-qm", "init")
        g(self.dev, "remote", "add", "origin", str(self.origin))
        g(self.dev, "push", "-q", "origin", BASE)
        self.root = self.dir / "root"
        self.clone = lane_land.land_clone(self.root, str(self.origin), "repo")
        self.reviews = self.root / "reviews"
        self.lane = "agents/x"
        self.sha = self.push_lane(self.lane, {"b.txt": "b\n"})

    def push_lane(self, lane, files, base=BASE, delete=()):
        """Commit ``files`` on a new branch from ``origin/base`` in dev and push it; returns the tip."""
        g(self.dev, "fetch", "-q", "origin")
        g(self.dev, "checkout", "-q", "-B", lane.replace("/", "_"), f"origin/{base}")
        for rel, text in files.items():
            path = self.dev / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        for rel in delete:
            (self.dev / rel).unlink()
        g(self.dev, "add", "-A")
        g(self.dev, "commit", "-qm", f"work on {lane}")
        g(self.dev, "push", "-q", "-f", "origin", f"HEAD:refs/heads/{lane}")
        return g(self.dev, "rev-parse", "HEAD")

    def seed_base(self, files):
        """Commit ``files`` straight onto the base on origin (existing protected or append-only content)."""
        g(self.dev, "checkout", "-q", BASE)
        g(self.dev, "pull", "-q", "origin", BASE)
        for rel, text in files.items():
            path = self.dev / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        g(self.dev, "add", "-A")
        g(self.dev, "commit", "-qm", "seed")
        g(self.dev, "push", "-q", "origin", BASE)

    def verdict(self, lane=None, sha=None, verdict="pass", head=None, rnd=2):
        lane, sha = lane or self.lane, sha or self.sha
        path = lane_land.review_path(self.reviews, lane, sha)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"verdict": verdict, "head": head or sha, "round": rnd,
                                    "reviewer": {"agent_type": "reviewer", "session_id": "s-1"}}))
        return path

    @staticmethod
    def said(sha, verdict="pass", findings=(), head=None):
        """A reviewer's final message: prose, then the one fenced json verdict block."""
        body = {"verdict": verdict, "head": head or sha, "round": 1, "findings": list(findings)}
        return "Reviewed.\n\n```json\n" + json.dumps(body) + "\n```"

    def land(self, lane=None, launch=None, **kw):
        kw.setdefault("tests", "true")
        kw.setdefault("reviews_dir", self.reviews)
        return lane_land.land(lane or self.lane, BASE, clone=self.clone, home=self.home, launch_review=launch, **kw)

    def refused(self, kind=None, **kw):
        with self.assertRaises(lane_land.Refused) as cm:
            self.land(**kw)
        if kind:
            self.assertEqual(cm.exception.kind, kind, str(cm.exception))
        return str(cm.exception)

    def origin_base(self):
        return g(self.origin, "rev-parse", BASE)


class LandTests(Repo):
    def test_lands_merges_pushes_and_cites_the_verdict(self):
        self.verdict()
        result = self.land()
        self.assertEqual(result["sha"], self.sha)
        self.assertEqual(self.origin_base(), result["merge"])
        parents = g(self.origin, "log", "-1", "--format=%P", BASE).split()
        self.assertEqual(len(parents), 2)  # --no-ff
        self.assertEqual(parents[1], self.sha)
        message = g(self.origin, "log", "-1", "--format=%B", BASE)
        for part in (lane_land.review_file_name(self.lane, self.sha), "round 2", "Release-Note: none",
                     "Co-Authored-By: Claude Opus 5.5"):
            self.assertIn(part, message)

    def test_expected_sha_lands_exactly_that_commit(self):
        self.verdict()
        result = self.land(expected_sha=self.sha)
        self.assertEqual(result["sha"], self.sha)
        self.assertEqual(g(self.origin, "log", "-1", "--format=%P", BASE).split()[1], self.sha)

    def test_a_lane_that_is_not_at_the_expected_sha_is_refused_before_anything_runs(self):
        self.verdict()
        newer = self.push_lane(self.lane, {"b.txt": "other\n"})  # pushed after the caller recorded self.sha
        self.assertIn("not the expected", self.refused("lane", expected_sha=self.sha))
        self.assertNotEqual(newer, self.sha)
        self.assertEqual(self.origin_base(), g(self.dev, "rev-parse", f"origin/{BASE}"))

    def test_a_push_to_the_lane_after_the_check_and_before_the_merge_does_not_change_what_merges(self):
        self.verdict()
        pushed = []
        real = lane_land.git

        def racing(repo, *args, **kw):
            if args and args[0] == "merge" and "--no-ff" in args and not pushed:  # the lane moves after every check, as the merge starts
                pushed.append(self.push_lane(self.lane, {"evil.txt": "evil\n"}))
            return real(repo, *args, **kw)
        with mock.patch.object(lane_land, "git", racing):
            result = self.land(expected_sha=self.sha)
        self.assertTrue(pushed and pushed[0] != self.sha)
        self.assertEqual(g(self.origin, "log", "-1", "--format=%P", BASE).split()[1], self.sha)  # the SHA object, not the branch
        self.assertEqual(g(self.origin, "rev-parse", f"refs/heads/{self.lane}"), pushed[0])
        self.assertEqual(result["sha"], self.sha)
        with self.assertRaises(subprocess.CalledProcessError):
            g(self.origin, "show", f"{BASE}:evil.txt")

    def test_a_push_to_the_lane_after_the_review_and_before_the_final_check_is_refused(self):
        self.verdict()
        moved = []

        def reviewer_then_push(lane, sha, base, diff):
            moved.append(self.push_lane(self.lane, {"evil.txt": "evil\n"}))
            return self.said(sha)
        self.assertIn("moved", self.refused("review", launch=reviewer_then_push, expected_sha=self.sha))
        self.assertNotIn("evil.txt", g(self.origin, "ls-tree", "--name-only", BASE))

    def test_the_review_path_is_per_lane_and_sha(self):
        self.assertEqual(lane_land.review_path(self.reviews, "agents/a/b", "0123456789abcdef").name,
                         "agents__a__b-0123456789ab.json")

    def test_a_stale_local_base_is_refreshed_before_the_merge(self):
        self.seed_base({"c.txt": "c\n"})
        self.verdict()
        self.land()
        self.assertEqual(g(self.origin, "show", f"{BASE}:c.txt"), "c")
        self.assertEqual(g(self.origin, "show", f"{BASE}:b.txt"), "b")

    def test_review_gates(self):
        self.assertIn("no review verdict", self.refused("review"))
        self.verdict(verdict="blocker")
        self.assertIn("blocker", self.refused("review"))
        self.verdict(head="0" * 40)
        self.assertIn("is not the tip", self.refused("review"))
        self.assertEqual(self.origin_base(), g(self.origin, "rev-parse", BASE))

    def test_a_verdict_for_another_sha_does_not_count(self):
        other = self.push_lane("agents/y", {"y.txt": "y\n"})
        self.verdict(lane="agents/y", sha=other)  # verdict path embeds the sha, so x has none
        self.assertIn("no review verdict", self.refused("review"))

    def test_the_runner_takes_the_verdict_from_the_reviewers_final_message_and_records_it(self):
        planted = self.verdict()  # a file at the record path is never an input for a runner launch
        seen = []

        def lazy_reviewer(lane, sha, base, diff):  # says nothing useful
            seen.append((lane, sha, base, diff.is_file(), planted.exists()))
            return "I looked and it seems fine."

        self.assertIn("no fenced json verdict", self.refused("review", launch=lazy_reviewer))
        self.assertEqual(seen, [(self.lane, self.sha, BASE, True, False)])
        self.assertFalse(seen[0][3] and (self.reviews / "diffs" / (planted.stem + ".diff")).exists())  # temp diff removed

        def reviewer(lane, sha, base, diff):
            self.assertIn("b.txt", diff.read_text())
            self.assertNotIn(str(self.clone), str(diff))  # outside any clone
            return self.said(sha)

        self.assertEqual(self.land(launch=reviewer)["sha"], self.sha)
        record = json.loads(planted.read_text())
        self.assertEqual((record["head"], record["verdict"], record["recorded_by"]), (self.sha, "pass", "runner"))

    def test_verdict_parsing(self):
        sha = self.sha
        self.assertEqual(lane_land.parse_verdict(self.said(sha), sha)["head"], sha)
        last_wins = "```json\n" + json.dumps({"verdict": "pass", "head": sha}) + "\n```\n\n" + self.said(sha, "changes")
        self.assertIn("changes", self._refused_text(last_wins, sha))
        self.assertIn("no fenced json", self._refused_text("pass", sha))
        self.assertIn("not valid JSON", self._refused_text("```json\n{nope\n```", sha))
        self.assertIn("not the tip", self._refused_text(self.said(sha, head="0" * 40), sha))
        self.assertIn("major or blocker", self._refused_text(self.said(sha, findings=[{"severity": "major"}]), sha))
        self.assertIn("not an object", self._refused_text("```json\n[1]\n```", sha))
        self.assertIn("blocker", self._refused_text(self.said(sha, "blocker"), sha))

    def _refused_text(self, text, sha):
        with self.assertRaises(lane_land.Refused) as cm:
            lane_land.parse_verdict(text, sha)
        return str(cm.exception)

    def test_final_message_reads_the_last_result_event_of_stream_json(self):
        raw = "\n".join([json.dumps({"type": "assistant", "message": "x"}), "garbage",
                         json.dumps({"type": "result", "result": "first"}), json.dumps({"type": "result", "result": "last"})])
        self.assertEqual(lane_land.final_message(raw), "last")
        self.assertEqual(lane_land.final_message("plain text"), "plain text")

    def test_the_review_prompt_names_the_format_the_diff_and_the_trusted_checkout(self):
        prompt = lane_land.review_prompt(self.lane, self.sha, BASE, Path("/x/y.diff"))
        for part in (self.lane, self.sha, "/x/y.diff", f"origin/{BASE}", "git show", "```json", "pass|changes|blocker",
                     "opus-ok: final review"):
            self.assertIn(part, prompt)

    def test_a_kill_switch_set_during_the_review_stops_the_merge(self):
        switch = self.home / ".local/state/hass-triage/SELF_CHANGE_PAUSED"

        def reviewer(lane, sha, base, diff):
            switch.parent.mkdir(parents=True, exist_ok=True)
            switch.write_text("x")
            return self.said(sha)

        before = self.origin_base()
        self.assertIn("kill switch", self.refused("paused", launch=reviewer))
        self.assertEqual(self.origin_base(), before)

    def test_each_kill_switch_refuses_and_clears(self):
        self.verdict()
        for where in (self.home / ".config/hass-triage/PAUSED", self.home / ".local/state/hass-triage/PAUSED",
                      self.home / ".local/state/hass-triage/SELF_CHANGE_PAUSED", self.clone / "build/retro/PAUSED"):
            where.parent.mkdir(parents=True, exist_ok=True)
            where.write_text("x")
            self.assertIn("kill switch", self.refused("paused"), str(where))
            where.unlink()
        paused = self.dir / "paused-env"
        paused.write_text("x")
        with mock.patch.dict(os.environ, {"HASS_TRIAGE_PAUSED_FILE": str(paused)}):
            self.assertIn("kill switch", self.refused("paused"))
        self.land()

    def test_failing_fixed_tests_refuse(self):
        self.verdict()
        self.assertIn("tests failed", self.refused("tests", tests="false"))

    def test_the_fixed_test_command_runs_in_the_land_clone_at_the_sha(self):
        self.verdict()
        marker = self.dir / "ran-in"
        self.land(tests=f"pwd >> {marker} && test -f b.txt")
        lines = marker.read_text().splitlines()
        self.assertEqual(Path(lines[0]).name, "repo")
        self.assertEqual(Path(lines[0]).parent.name, "trusted")  # the trusted base runs first
        self.assertEqual(Path(lines[-1]).resolve(), self.clone.resolve())

    def test_agent_eval_runs_when_the_lane_has_it(self):
        self.seed_base({"tools/agent_eval.py": "import sys; sys.exit(1)\n"})
        sha = self.push_lane(self.lane, {"c.txt": "c\n"})
        self.verdict(sha=sha)
        self.assertIn("agent_eval", self.refused("tests"))

    def test_a_conflict_aborts_leaves_the_base_alone_and_the_clone_clean(self):
        self.seed_base({"b.txt": "other\n"})
        self.verdict()
        before = self.origin_base()
        with self.assertRaises(lane_land.LandFailed) as cm:
            self.land()
        self.assertEqual(cm.exception.kind, "conflict")
        self.assertEqual(self.origin_base(), before)
        self.assertEqual(g(self.clone, "status", "--porcelain"), "")

    def test_a_rejected_push_fails_cleanly(self):
        self.verdict()
        hook = self.origin / "hooks" / "pre-receive"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)
        before = self.origin_base()
        with self.assertRaises(lane_land.LandFailed) as cm:
            self.land()
        self.assertEqual(cm.exception.kind, "push")
        self.assertEqual(self.origin_base(), before)

    def test_a_lane_that_moves_after_the_review_is_refused(self):
        def reviewer(lane, sha, base, diff):
            self.push_lane(self.lane, {"evil.txt": "e\n"})
            return self.said(sha)

        before = self.origin_base()
        self.assertIn("moved", self.refused("review", launch=reviewer))
        self.assertEqual(self.origin_base(), before)

    def test_dry_run_merges_nothing(self):
        self.verdict()
        before = self.origin_base()
        with mock.patch("sys.stdout", new=io.StringIO()):
            self.assertEqual(self.land(dry_run=True)["merge"], "")
        self.assertEqual(self.origin_base(), before)

    def test_bad_lanes_and_missing_lane_and_missing_base(self):
        for lane in (BASE, "main", "agents/../claude/x", "agents/", "agents/a.lock", "agents/a b", "--all"):
            with self.assertRaises(lane_land.Refused, msg=lane) as cm:
                self.land(lane=lane)
            self.assertEqual(cm.exception.kind, "lane", lane)
        self.assertIn("not on origin", self.refused("lane", lane="agents/none"))
        with self.assertRaises(lane_land.Refused) as cm:
            lane_land.land(self.lane, "no/such-base", clone=self.clone, home=self.home, reviews_dir=self.reviews,
                           tests="true")
        self.assertEqual(cm.exception.kind, "base")

    def test_a_headless_session_cannot_land(self):
        self.verdict()
        with mock.patch.dict(os.environ, {"FENTON_HEADLESS": "1"}):
            self.assertIn("runner", self.refused("headless"))
        self.assertEqual(self.origin_base(), g(self.dev, "rev-parse", f"origin/{BASE}"))


class ProtectedPathTests(Repo):
    """The fixed set: a lane that touches any of it is refused (kind ``paths``) even with a pass verdict."""

    PROTECTED = (".claude/agents/reviewer.md", ".gitmodules", ".githooks/pre-commit", ".gitconfig",
                 "tools/review/record.py", "tools/release/versioning.py", "tools/release/tests/x.py", "tools/hass_creds.sh",
                 "tools/gh_app_token.py", ".github/workflows/ios-release.yml", ".github/workflows/ios-release-extra.yml")
    #: Unlocked by the owner on 2026-11-07 (end-to-end autonomy): the merge path, guard hooks, eval graders and thresholds, kill-switch code.
    UNLOCKED = (".claude/settings.json", "tools/hooks/merge_guard.py", "tools/hooks/worktree_guard.py", "tools/hooks/kill_guard.py",
                "tools/hooks/orchestrator_guard.py", "tools/hooks/signing_guard.py", "tools/hooks/shell_parse.py",
                "tools/lane_land.py", "tools/pr_land.sh", "tools/pr_land.py", "tools/triage/config.json", "tools/triage/hass_triage.py",
                "tools/run_tool_tests.sh", "tools/agent_eval.py", "evals/jev/grade_labels.py", "evals/grade.py",
                "evals/agents/design-defects/run.py", "contracts/jev/derived/measure.py", "tools/jev_ask.py", "tools/jev_gate.py",
                "tools/ship_guard.sh", "tools/hooks/commit_guard.py", "tools/tests/test_ship_guard_wiring.py", "tools/redact.py",
                ".github/workflows/ci.yml")

    def try_lane(self, files, delete=()):
        sha = self.push_lane(self.lane, files, delete=delete)
        self.verdict(sha=sha)
        return self.refused("paths")

    def test_every_protected_path_is_refused_new_or_modified(self):
        for rel in self.PROTECTED:
            with self.subTest(path=rel, kind="add"):
                self.assertIn(rel, self.try_lane({rel: "x\n"}))
        self.seed_base({rel: "old\n" for rel in self.PROTECTED})
        for rel in self.PROTECTED:
            with self.subTest(path=rel, kind="modify"):
                self.assertIn(rel, self.try_lane({rel: "new\n"}))
            with self.subTest(path=rel, kind="delete"):
                self.assertIn(rel, self.try_lane({}, delete=[rel]))

    def test_the_unlocked_set_lands_but_the_owner_set_cannot_be_removed_by_config(self):
        for rel in self.UNLOCKED:
            self.assertFalse(lane_land.matches(rel, lane_land.DEFAULT_PROTECTED), rel)
        landable = [r for r in self.UNLOCKED if not r.startswith(("tools/hooks/", ".claude/", "evals/", "contracts/", "tools/jev_", "tools/agent_eval"))]
        sha = self.push_lane(self.lane, {rel: "x\n" for rel in landable})
        self.verdict(sha=sha)
        self.assertEqual(self.land()["sha"], sha)

    def test_config_can_add_protected_paths_never_remove_them(self):
        self.assertIn("extra/x", self.try_lane_with(["extra/**"], {"extra/x": "x\n"}))
        sha = self.push_lane(self.lane, {"tools/hass_creds.sh": "x\n"})
        self.verdict(sha=sha)
        self.assertIn("protected", self.refused("paths", protected=["only/this"]))

    def try_lane_with(self, protected, files):
        sha = self.push_lane(self.lane, files)
        self.verdict(sha=sha)
        return self.refused("paths", protected=protected)

    def test_unprotected_paths_land(self):
        sha = self.push_lane(self.lane, {".agents/workflow/note.md": "n\n", "tools/other.py": "p\n",
                                         "tools/hooks/new_guard.py": "g\n"})
        self.verdict(sha=sha)
        self.assertEqual(self.land()["sha"], sha)

    def test_behaviour_and_evaluation_never_change_in_the_same_lane(self):
        for behaviour in (".claude/agents/coder.md", "tools/hooks/new_guard.py", ".agents/skills/x/SKILL.md",
                          "contracts/jev/questions/new.json"):
            for evals in ("evals/jev/cases/c9.json", "contracts/jev/derived/labels/l9.json"):
                with self.subTest(behaviour=behaviour, evals=evals):
                    sha = self.push_lane(self.lane, {behaviour: "{}\n", evals: "{}\n"})
                    self.verdict(sha=sha)
                    self.assertIn("split it into two lanes", self.refused("paths"))
        sha = self.push_lane(self.lane, {"evals/jev/cases/c9.json": "{}\n"})
        self.verdict(sha=sha)
        self.assertEqual(self.land()["sha"], sha)


class DesignRecordTests(Repo):
    """App UI lands only with a design decision record (owner, 2026-11-03) or a cited existing one."""

    VIEW = "apple/Sources/HassUI/Chip.swift"
    RECORD = ".agents/design/chip.md"
    GOOD = ("# Chip\n\nDecision: 2026-11-03, judged Option A, B and C from screenshots; picked B.\n"
            "Gate: app_wide=no\n")

    def lane_with(self, files, message=None):
        sha = self.push_lane(self.lane, files)
        if message:
            g(self.dev, "commit", "-q", "--amend", "-m", message)
            g(self.dev, "push", "-q", "-f", "origin", f"HEAD:refs/heads/{self.lane}")
            sha = g(self.dev, "rev-parse", "HEAD")
        self.verdict(sha=sha)
        return sha

    def test_ui_without_a_record_is_refused(self):
        for ui in (self.VIEW, "apple/Sources/HassDesign/Tokens.swift", ".agents/design/mockups/chip.html"):
            with self.subTest(ui=ui):
                self.lane_with({ui: "x\n"})
                self.assertIn("design decision record", self.refused("design"))

    def jev(self, p_yes, calls=None, marker=None):
        """A fake Jev: records ``(question, text)`` and whether lane code (the test command) had run yet."""
        def ask(trusted, qid, text):
            if calls is not None:
                calls.append((qid, text, marker is not None and marker.exists()))
            return p_yes
        return ask

    def test_ui_with_a_dated_decision_naming_options_lands(self):
        sha = self.lane_with({self.VIEW: "x\n", self.RECORD: self.GOOD})
        self.assertEqual(self.land(jev_ask=self.jev(0.1))["sha"], sha)

    def test_agent_initiated_work_lands_only_on_a_confident_no(self):
        for p_yes, ok in ((0.1, True), (0.29, True), (0.3, False), (0.5, False), (0.9, False), (None, False)):
            with self.subTest(p_yes=p_yes):
                sha = self.lane_with({self.VIEW: "x\n", self.RECORD: self.GOOD})
                if ok:
                    self.assertEqual(self.land(jev_ask=self.jev(p_yes))["sha"], sha)
                    g(self.origin, "update-ref", f"refs/heads/{BASE}", g(self.origin, "rev-parse", f"{BASE}^1"))
                else:
                    self.refused("gate", jev_ask=self.jev(p_yes))

    def test_unavailable_jev_refuses_with_kind_gate(self):
        self.lane_with({self.VIEW: "x\n", self.RECORD: self.GOOD})
        self.assertIn("unavailable", self.refused("gate", jev_ask=self.jev(None)))

    def test_an_owner_request_lane_lands_only_on_a_yes_and_asks_matches_request(self):
        message = "Bigger chips\n\nOwner-Request: 12\n"
        record = "# Chip\n\nDecision: 2026-11-03, judged Option A, B and C; picked B.\nGate: matches_request=yes\n"
        for p_yes, ok in ((0.95, True), (0.8, True), (0.79, False), (0.5, False), (0.1, False)):
            with self.subTest(p_yes=p_yes):
                sha = self.lane_with({self.VIEW: "x\n", self.RECORD: record}, message)
                calls = []
                kw = dict(jev_ask=self.jev(p_yes, calls), request_reader=lambda t, ref: f"Make chips bigger ({ref})")
                if ok:
                    self.assertEqual(self.land(**kw)["sha"], sha)
                    g(self.origin, "update-ref", f"refs/heads/{BASE}", g(self.origin, "rev-parse", f"{BASE}^1"))
                else:
                    self.refused("gate", **kw)
                self.assertEqual([c[0] for c in calls], ["design.matches_request"])
                self.assertIn("Request: Make chips bigger (12)\nChange: ", calls[0][1])
                self.assertIn("Decision: 2026-11-03", calls[0][1])
                self.assertIn("Diff stat:", calls[0][1])
                self.assertIn(self.VIEW, calls[0][1])

    def test_a_request_the_runner_does_not_vouch_for_is_ignored_and_app_wide_is_asked(self):
        """A ref the reader returns nothing for (another issue, an edited or agent-filed one) never reaches matches_request."""
        self.lane_with({self.VIEW: "x\n", self.RECORD: self.GOOD}, "Chips\n\nOwner-Request: 99\n")
        calls = []
        self.refused("gate", jev_ask=self.jev(0.99, calls), request_reader=lambda t, ref: None)
        self.assertEqual([c[0] for c in calls], ["design.app_wide"])
        calls.clear()
        sha = self.lane_with({self.VIEW: "x\n", self.RECORD: self.GOOD}, "Chips\n\nOwner-Request: 99\n")
        self.assertEqual(self.land(jev_ask=self.jev(0.05, calls), request_reader=lambda t, ref: None)["sha"], sha)
        self.assertEqual([c[0] for c in calls], ["design.app_wide"])

    def test_read_config_never_vouches_for_the_agent_login(self):
        """Fails if: an unset agent_login changes authors, or a configured one stays in authors so a request it filed counts as the owner's."""
        repo = Path(self.dir) / "cfgrepo"
        (repo / "tools" / "triage").mkdir(parents=True)
        config = repo / "tools" / "triage" / "config.json"
        config.write_text(json.dumps({"authors": ["SFenton", "sh-agent"], "agent_login": ""}))
        entry = {"title": "T", "body": "Bigger", "author": "sh-agent", "labels": []}
        with mock.patch.dict(os.environ, {"FENTON_AGENT_LOGIN": "SFenton"}):  # a process setting changes nothing
            self.assertEqual(lane_land.read_config(repo)["authors"], ["SFenton", "sh-agent"])
        config.write_text(json.dumps({"authors": ["SFenton", "sh-agent"], "agent_login": "sh-agent"}))  # read from the repo's config
        loaded = lane_land.read_config(repo)
        authors = loaded["authors"]
        self.assertEqual(authors, ["SFenton"])
        self.assertIsNone(lane_land.vouched_request(entry, authors))
        self.assertEqual(lane_land.vouched_request({**entry, "author": "SFenton"}, authors), "T\nBigger")

    def test_the_first_vouched_request_among_several_refs_is_used(self):
        self.lane_with({self.VIEW: "x\n", self.RECORD: self.GOOD}, "Chips\n\nOwner-Request: 98\nOwner-Request: 12\n")
        calls = []
        self.land(jev_ask=self.jev(0.9, calls), request_reader=lambda t, ref: "Bigger chips" if ref == "12" else None)
        self.assertEqual([c[0] for c in calls], ["design.matches_request"])
        self.assertIn("Request: Bigger chips", calls[0][1])

    def test_without_a_reader_every_lane_is_asked_app_wide(self):
        self.lane_with({self.VIEW: "x\n", self.RECORD: self.GOOD}, "Chips\n\nOwner-Request: 12\n")
        calls = []
        self.land(jev_ask=self.jev(0.05, calls))
        self.assertEqual([c[0] for c in calls], ["design.app_wide"])
        self.assertIsNone(lane_land.no_request(self.dir, "12"))

    def test_a_forged_gate_line_that_contradicts_jev_is_refused(self):
        self.lane_with({self.VIEW: "x\n", self.RECORD: self.GOOD})  # claims app_wide=no
        # Jev says unsure: refused as an unconfirmed gate; a lane that claims `no` while Jev says `no` agrees.
        self.refused("gate", jev_ask=self.jev(0.5))
        record = "# Chip\n\nDecision: 2026-11-03, judged Option A, B and C; picked B.\nGate: matches_request=no\n"
        self.lane_with({self.VIEW: "x\n", self.RECORD: record}, "Chips\n\nOwner-Request: 12\n")
        self.assertIn("must agree", self.refused("gate", jev_ask=self.jev(0.95), request_reader=lambda t, ref: "chips"))

    def test_the_lane_gate_line_is_documentation_only(self):
        # No line at all, or a line for the other question, still lands when Jev confirms.
        for gate in ("", "Gate: matches_request=yes\n"):
            with self.subTest(gate=gate):
                sha = self.lane_with({self.VIEW: "x\n", self.RECORD: "# Chip\n\nDecision: 2026-11-03, judged Option A, B and C.\n" + gate})
                self.assertEqual(self.land(jev_ask=self.jev(0.05))["sha"], sha)
                g(self.origin, "update-ref", f"refs/heads/{BASE}", g(self.origin, "rev-parse", f"{BASE}^1"))

    def test_jev_is_asked_before_any_lane_code_runs(self):
        marker = self.dir / "lane-code-ran"
        self.lane_with({self.VIEW: "x\n", self.RECORD: self.GOOD})
        calls = []
        self.land(jev_ask=self.jev(0.05, calls, marker), tests=f"touch {marker}")
        self.assertEqual(len(calls), 1)
        self.assertFalse(calls[0][2], "Jev was asked after the lane's test command had run")
        self.assertTrue(marker.exists())

    def test_a_refused_gate_never_runs_lane_code(self):
        marker = self.dir / "lane-code-ran"
        self.lane_with({self.VIEW: "x\n", self.RECORD: self.GOOD})
        self.refused("gate", jev_ask=self.jev(0.9), tests=f"touch {marker}")
        self.assertFalse(marker.exists())

    def test_citing_a_base_record_still_asks_jev(self):
        self.seed_base({self.RECORD: self.GOOD})
        sha = self.lane_with({self.VIEW: "x\n"}, f"Fix\n\nDesign: {self.RECORD}\n")
        calls = []
        self.assertEqual(self.land(jev_ask=self.jev(0.05, calls))["sha"], sha)
        self.assertEqual([c[0] for c in calls], ["design.app_wide"])
        g(self.origin, "update-ref", f"refs/heads/{BASE}", g(self.origin, "rev-parse", f"{BASE}^1"))
        calls.clear()
        self.refused("gate", jev_ask=self.jev(0.9, calls))
        self.assertEqual(len(calls), 1)

    def test_a_cited_file_the_lane_adds_does_not_count(self):
        self.lane_with({self.VIEW: "x\n", self.RECORD: "# Not a decision\n"}, f"Fix\n\nDesign: {self.RECORD}\n")
        calls = []
        self.assertIn("design decision record", self.refused("design", jev_ask=self.jev(0.0, calls)))
        self.assertEqual(calls, [])
        self.lane_with({self.VIEW: "x\n", ".agents/patterns/mine.md": "# Mine\n"}, "Fix\n\nDesign: .agents/patterns/mine.md\n")
        self.refused("design", jev_ask=self.jev(0.0))

    def test_touching_an_old_record_without_adding_a_decision_does_not_count(self):
        self.seed_base({self.RECORD: self.GOOD})
        self.lane_with({self.VIEW: "x\n", self.RECORD: self.GOOD + "A typo fix.\n"})
        calls = []
        self.refused("design", jev_ask=self.jev(0.0, calls))
        self.assertEqual(calls, [])

    def test_jev_sees_the_trusted_facts_first_then_only_the_added_record_lines(self):
        self.seed_base({self.RECORD: "# Chip\n\nOLD STEERING: local to one screen, never app-wide.\n"})
        record = ("# Chip\n\nOLD STEERING: local to one screen, never app-wide.\n"
                  "Decision: 2026-11-03, judged Option A, B and C; picked B.\n" + "FILLER " * 2000)
        self.lane_with({self.VIEW: "x\n", self.RECORD: record})
        calls = []
        self.land(jev_ask=self.jev(0.05, calls))
        text = calls[0][1]
        self.assertTrue(text.startswith("App UI files changed:"))
        self.assertLess(text.index(self.VIEW), text.index("Diff stat:"))
        self.assertLess(text.index("Diff stat:"), text.index("Design record, lines this lane added:"))
        self.assertIn("Decision: 2026-11-03", text)
        self.assertNotIn("OLD STEERING", text)
        self.assertLess(len(text), 6000)

    def test_every_app_ui_path_family_needs_a_record(self):
        families = ("apple/Apps/iOS/Assets.xcassets/AppIcon.appiconset/Contents.json",
                    "apple/Apps/iOS/Assets.xcassets/AccentColor.colorset/Contents.json",
                    "apple/Apps/iOS/AppPageOption.swift", "apple/Sources/FentonActivityViews/Chip.swift",
                    "apple/Apps/NotificationContent/NotificationViewController.swift",
                    "apple/Apps/NotificationContentShared/CameraNotificationModel.swift",
                    "apple/Apps/Widgets/HomeLiveActivity.swift", "apple/Apps/watchOS/Home.swift",
                    "apple/Sources/HassUI/Pages/Home.swift", "apple/Sources/HassDesign/Tokens.swift",
                    ".agents/design/mockups/home.html")
        for ui in families:
            with self.subTest(ui=ui):
                self.lane_with({ui: "x\n"})
                self.assertIn("design decision record", self.refused("design"))
                sha = self.lane_with({ui: "x\n", self.RECORD: self.GOOD})
                self.assertEqual(self.land(jev_ask=self.jev(0.05))["sha"], sha)
                g(self.origin, "update-ref", f"refs/heads/{BASE}", g(self.origin, "rev-parse", f"{BASE}^1"))

    def test_test_targets_and_privacy_manifests_are_not_app_ui(self):
        for path in ("apple/Apps/iOSTests/A.swift", "apple/Apps/iOSUITests/B.swift", "apple/Apps/iOS/PrivacyInfo.xcprivacy"):
            with self.subTest(path=path):
                sha = self.lane_with({path: "x\n"})
                self.assertEqual(self.land()["sha"], sha)
                g(self.origin, "update-ref", f"refs/heads/{BASE}", g(self.origin, "rev-parse", f"{BASE}^1"))

    def test_a_record_without_a_date_or_options_does_not_count(self):
        for text in ("Decision: picked B.\n", "Decision: 2026-11-03 picked it.\n", "## Decision\nOption A, B, 2026-11-03\n"):
            with self.subTest(text=text):
                self.lane_with({self.VIEW: "x\n", self.RECORD: text})
                self.refused("design")

    def test_citing_an_existing_record_or_pattern_lands(self):
        self.seed_base({self.RECORD: self.GOOD, ".agents/patterns/chips.md": "# Chips\n"})
        for cite in (self.RECORD, ".agents/patterns/chips.md"):
            with self.subTest(cite=cite):
                sha = self.lane_with({self.VIEW: f"x {cite}\n"}, f"Fix chip clipping\n\nDesign: {cite}\n")
                self.assertEqual(self.land(jev_ask=self.jev(0.05))["sha"], sha)
                g(self.origin, "update-ref", f"refs/heads/{BASE}", g(self.origin, "rev-parse", f"{BASE}^1"))

    def test_citing_a_missing_or_foreign_path_is_refused(self):
        for cite in (".agents/design/nope.md", "README.md", "../x.md"):
            with self.subTest(cite=cite):
                self.lane_with({self.VIEW: "x\n"}, f"Fix\n\nDesign: {cite}\n")
                self.refused("design")

    def test_tests_and_non_view_files_are_not_app_ui(self):
        sha = self.lane_with({"apple/Tests/HassUITests/ChipTests.swift": "x\n", "apple/Sources/HassUI/notes.md": "x\n"})
        self.assertEqual(self.land()["sha"], sha)


class AppendOnlyTests(Repo):
    TREES = ("contracts/jev/derived/labels/a.json", "contracts/jev/derived/scenarios/s1/case.yaml",
             "contracts/jev/derived/results/r1.json", "evals/jev/cases/c1.json")

    def setUp(self):
        super().setUp()
        self.seed_base({rel: "old\n" for rel in self.TREES})

    def lane_refused(self, files, delete=()):
        sha = self.push_lane(self.lane, files, delete=delete)
        self.verdict(sha=sha)
        return self.refused("paths")

    def test_adding_files_is_allowed(self):
        sha = self.push_lane(self.lane, {"contracts/jev/derived/labels/new.json": "n\n", "scenarios/s2/x.yaml": "n\n",
                                         "results/r2.json": "n\n", "evals/jev/cases/c2.json": "n\n"})
        self.verdict(sha=sha)
        self.assertEqual(self.land()["sha"], sha)

    def test_modify_and_delete_are_refused_in_every_tree(self):
        for rel in self.TREES:
            with self.subTest(path=rel):
                self.assertIn(rel, self.lane_refused({rel: "changed\n"}))
                self.assertIn(rel, self.lane_refused({}, delete=[rel]))

    def retire(self, rel, reason=None, content="old\n", extra=None):
        head, name = os.path.split(rel)
        files = {f"{head}/retired/{name}": content, **(extra or {})}
        if reason is not None:
            files[f"{head}/retired/{name}.reason.json"] = json.dumps(reason)
        return self.lane_refused(files, delete=[rel])

    def test_a_move_into_retired_needs_a_reason_and_is_otherwise_unchanged(self):
        reason = {"kind": "owner_rule", "date": "2026-11-02", "quote": "retire it"}
        for rel in self.TREES:
            head, name = os.path.split(rel)
            sha = self.push_lane(self.lane, {f"{head}/retired/{name}": "old\n", f"{head}/retired/{name}.reason.json":
                                             json.dumps(reason)}, delete=[rel])
            self.verdict(sha=sha)
            self.assertEqual(self.land()["sha"], sha, rel)
            self.seed_base({rel: "old\n"})
        rel = self.TREES[0]
        head, name = os.path.split(rel)
        self.assertIn(rel, self.lane_refused({f"{head}/retired/{name}": "different\n"}, delete=[rel]))
        self.assertIn(rel, self.lane_refused({f"{head}/elsewhere/{name}": "old\n"}, delete=[rel]))

    def test_a_move_without_a_reason_file_or_with_a_bad_kind_is_refused(self):
        rel = self.TREES[3]
        self.assertIn("reason.json", self.retire(rel))
        self.assertIn("kind must be one of", self.retire(rel, {"kind": "tired"}))
        self.assertIn("not valid JSON", self.lane_refused({"evals/jev/cases/retired/c1.json": "old\n",
                                                          "evals/jev/cases/retired/c1.json.reason.json": "{nope"},
                                                         delete=[rel]))

    def test_owner_rule_needs_a_date_and_a_quote(self):
        rel = self.TREES[3]
        for reason in ({"kind": "owner_rule", "quote": "q"}, {"kind": "owner_rule", "date": "2026-11-02", "quote": " "},
                       {"kind": "owner_rule", "date": "yesterday", "quote": "q"}):
            self.assertIn("owner_rule needs", self.retire(rel, reason))

    def test_target_removed_needs_a_path_that_is_gone_at_the_lane_sha(self):
        rel = self.TREES[3]
        self.seed_base({"app/Thing.swift": "x\n"})
        self.assertIn("target_removed needs", self.retire(rel, {"kind": "target_removed", "path": "app/Thing.swift"}))
        self.assertIn("target_removed needs", self.retire(rel, {"kind": "target_removed"}))
        sha = self.push_lane(self.lane, {"evals/jev/cases/retired/c1.json": "old\n",
                                         "evals/jev/cases/retired/c1.json.reason.json":
                                         json.dumps({"kind": "target_removed", "path": "app/Thing.swift"})},
                             delete=[rel, "app/Thing.swift"])
        self.verdict(sha=sha)
        self.assertEqual(self.land()["sha"], sha)

    def test_duplicate_needs_an_existing_survivor(self):
        rel = self.TREES[3]
        for survivor in ("evals/jev/cases/c9.json", rel, "", "../x"):
            self.assertIn("duplicate needs", self.retire(rel, {"kind": "duplicate", "survivor": survivor}))

    def test_duplicate_of_an_identical_case_lands(self):
        rel = self.TREES[3]
        self.seed_base({"evals/jev/cases/c2.json": "old\n"})
        sha = self.push_lane(self.lane, {"evals/jev/cases/retired/c1.json": "old\n",
                                         "evals/jev/cases/retired/c1.json.reason.json":
                                         json.dumps({"kind": "duplicate", "survivor": "evals/jev/cases/c2.json"})},
                             delete=[rel])
        self.verdict(sha=sha)
        self.assertEqual(self.land()["sha"], sha)

    def test_duplicate_below_threshold_is_refused(self):
        rel = self.TREES[3]
        self.seed_base({"evals/jev/cases/c2.json": "completely different text, nothing in common\n"})
        self.assertIn("only", self.retire(rel, {"kind": "duplicate", "survivor": "evals/jev/cases/c2.json"}))

    def test_mislabel_needs_a_blind_relabel_file_in_the_lane(self):
        rel = self.TREES[0]
        self.assertIn("mislabel needs", self.retire(rel, {"kind": "mislabel", "relabel": "contracts/jev/derived/labels/r.json"}))
        self.assertIn("mislabel needs", self.retire(rel, {"kind": "mislabel", "relabel": "a.txt"}))  # exists but not added here
        head, name = os.path.split(rel)
        sha = self.push_lane(self.lane, {f"{head}/retired/{name}": "old\n",
                                         f"{head}/retired/{name}.reason.json":
                                         json.dumps({"kind": "mislabel", "relabel": f"{head}/blind-relabel.json"}),
                                         f"{head}/blind-relabel.json": "{}\n"}, delete=[rel])
        self.verdict(sha=sha)
        self.assertEqual(self.land()["sha"], sha)

    def test_a_lane_that_retires_a_case_may_not_change_the_question_or_runner_that_uses_it(self):
        reason = {"kind": "owner_rule", "date": "2026-11-02", "quote": "q"}
        rel = self.TREES[3]
        self.seed_base({"tools/jev_other.py": "old\n"})
        for runner in ("tools/jev_other.py",):
            with self.subTest(runner=runner):
                self.assertIn("retire in a lane of its own", self.retire(rel, reason, extra={runner: "new\n"}))


class GlobTests(unittest.TestCase):
    def test_globs(self):
        m = lane_land.matches
        self.assertTrue(m("tools/pr_land.sh", ["tools/pr_land.*"]))
        self.assertFalse(m("tools/pr_land_extra/x", ["tools/pr_land.*"]))
        self.assertTrue(m("evals/grade.py", ["evals/**/grade*"]))
        self.assertTrue(m("evals/a/b/grader.py", ["evals/**/grade*"]))
        self.assertFalse(m("evals/a/cases/c.json", ["evals/**/grade*"]))
        self.assertTrue(m("scenarios/a/b/c", ["scenarios/**"]))
        self.assertFalse(m("tools/triage/prompts/worker.md", lane_land.DEFAULT_PROTECTED))  # prompts are autonomous (decision 1)
        self.assertFalse(m("scenarios", ["scenarios/**"]))
        for path in (".git/hooks/post-commit", ".git/config"):
            self.assertTrue(m(path, lane_land.DEFAULT_PROTECTED), path)
        self.assertFalse(m(".claude/settings.local.json", lane_land.DEFAULT_PROTECTED))  # hook wiring is unlocked (2026-11-07)
        self.assertFalse(m(".claude/agents/coder.md", lane_land.DEFAULT_PROTECTED))
        for path in ("tools/hass_creds.sh", "tools/gh_app_token.py", "tools/release/versioning.py", ".claude/agents/reviewer.md",
                     "tools/review/record.py", ".github/workflows/ios-release-extra.yml"):
            self.assertTrue(m(path, lane_land.DEFAULT_PROTECTED), path)


class FixedSetRealPathTests(unittest.TestCase):
    """A dead glob protects nothing: every protected pattern matches a real tracked file, every append-only root exists."""
    ROOT = Path(__file__).resolve().parents[2]
    #: Defensive patterns for files this repo does not have (yet).
    DEFENSIVE = {".gitmodules", ".gitconfig", ".git/**", ".githooks/**", "tools/agent_eval.py"}

    def tracked(self):
        out = subprocess.run(["git", "-C", str(self.ROOT), "ls-files"], capture_output=True, text=True).stdout.split()
        return out or [str(p.relative_to(self.ROOT)) for p in self.ROOT.rglob("*") if p.is_file() and ".git/" not in str(p)]

    def test_every_protected_glob_matches_a_real_file(self):
        files = self.tracked()
        cfg = json.loads((self.ROOT / "tools/triage/config.json").read_text())
        for pattern in [*lane_land.DEFAULT_PROTECTED, *cfg["protected_paths"]]:
            if pattern in self.DEFENSIVE:
                continue
            with self.subTest(pattern=pattern):
                self.assertTrue(any(lane_land.matches(f, [pattern]) for f in files), f"{pattern} matches no file")

    def test_graders_and_thresholds_are_unlocked_but_still_real_files(self):
        """Owner, 2026-11-07: the graders and measure code left the fixed set; the append-only case trees stay append-only."""
        for path in ("evals/agents/design-defects/run.py", "contracts/jev/derived/measure.py", "tools/jev_ask.py",
                     "tools/jev_gate.py", "tools/retro_weekly.py", "tools/agent_eval_case.py", "evals/agents/agent-behaviour/config.json"):
            with self.subTest(path=path):
                self.assertFalse(lane_land.matches(path, lane_land.DEFAULT_PROTECTED), path)
                self.assertTrue((self.ROOT / path).is_file(), path)

    def test_the_owner_set_stays_protected_in_code_and_config(self):
        cfg = json.loads((self.ROOT / "tools/triage/config.json").read_text())
        for path in ("tools/review/**", "tools/hooks/review_guard.py", "tools/release/**", "tools/hass_creds.sh", "tools/gh_app_token.py",
                     ".github/workflows/ios-release*.yml", "tools/devcap.py", "tools/ci_hygiene.py", "tools/release_closure.py"):
            self.assertIn(path, lane_land.DEFAULT_PROTECTED)
            self.assertIn(path, cfg["protected_paths"])

    def test_append_only_roots_exist(self):
        cfg = json.loads((self.ROOT / "tools/triage/config.json").read_text())
        for pattern in [*lane_land.DEFAULT_APPEND_ONLY, *cfg["append_only_paths"]]:
            with self.subTest(pattern=pattern):
                self.assertTrue((self.ROOT / pattern.split("**")[0]).is_dir(), pattern)
        self.assertEqual(set(cfg["append_only_paths"]) - set(lane_land.DEFAULT_APPEND_ONLY), set())


class JevThresholdTests(Repo):
    PATH = "contracts/jev/questions/q.json"

    def doc(self, **over):
        base = {"id": "q", "mode": "shadow", "accept": {"min_confidence": 0.5, "yes_above": 0.6, "no_below": 0.3},
                "target": {"precision": 0.8}, "evidence": "unmeasured", "instructions": "a"}
        for key, value in over.items():
            if "." in key:
                outer, inner = key.split(".")
                base[outer] = {**base[outer], inner: value}
            else:
                base[key] = value
        return json.dumps(base, indent=1) + "\n"

    def setUp(self):
        super().setUp()
        self.seed_base({self.PATH: self.doc()})

    def attempt(self, text):
        sha = self.push_lane(self.lane, {self.PATH: text})
        self.verdict(sha=sha)
        return sha

    def test_tightening_lands(self):
        sha = self.attempt(self.doc(**{"accept.yes_above": 0.7, "accept.no_below": 0.2, "target.precision": 0.9,
                                       "accept.min_confidence": 0.6, "instructions": "b"}))
        self.assertEqual(self.land()["sha"], sha)

    def test_every_loosening_is_refused(self):
        for key, value in (("accept.yes_above", 0.5), ("accept.no_below", 0.4), ("target.precision", 0.7),
                           ("accept.min_confidence", 0.4)):
            with self.subTest(key=key):
                self.attempt(self.doc(**{key: value}))
                self.assertIn(key, self.refused("paths"))

    def test_removing_a_threshold_or_making_it_a_string_is_refused(self):
        text = json.loads(self.doc())
        del text["accept"]["yes_above"]
        self.attempt(json.dumps(text))
        self.assertIn("accept.yes_above", self.refused("paths"))
        self.attempt(self.doc(**{"accept.yes_above": "0.9"}))
        self.assertIn("accept.yes_above", self.refused("paths"))

    def test_mode_active_to_shadow_is_fine_and_shadow_to_active_needs_new_evidence(self):
        self.attempt(self.doc(mode="active"))
        self.assertIn("mode", self.refused("paths"))
        self.attempt(self.doc(mode="active", evidence="measured 2026-11-02: precision 0.91 on 40 cases"))
        self.assertEqual(self.land()["sha"], self.sha_of(self.lane))
        self.seed_base({self.PATH: self.doc(mode="active")})
        sha = self.attempt(self.doc(mode="shadow"))
        self.assertEqual(self.land()["sha"], sha)

    def sha_of(self, lane):
        return g(self.origin, "rev-parse", lane)

    def test_new_questions_start_in_shadow_and_deletions_are_refused(self):
        sha = self.push_lane(self.lane, {"contracts/jev/questions/new.json": self.doc(mode="active")})
        self.verdict(sha=sha)
        self.assertIn("starts in shadow", self.refused("paths"))
        sha = self.push_lane(self.lane, {"contracts/jev/questions/new.json": self.doc()})
        self.verdict(sha=sha)
        self.assertEqual(self.land()["sha"], sha)
        sha = self.push_lane("agents/del", {}, delete=[self.PATH])
        self.verdict(lane="agents/del", sha=sha)
        self.assertIn("deleted", self.refused("paths", lane="agents/del"))

    def test_invalid_json_is_refused(self):
        self.attempt("{nope")
        self.assertIn("not valid JSON", self.refused("paths"))


class ProcessGroupTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="lane-pg-")).resolve()
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)

    def alive(self, pid):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        return True

    def test_a_grandchild_that_outlives_its_parent_is_killed(self):
        pidfile = self.dir / "pid"
        code, out, gone = lane_land.run_group(f"(nohup sleep 300 >/dev/null 2>&1 & echo $! > {pidfile}); echo done", cwd=self.dir,
                                              shell=True)
        pid = int(pidfile.read_text())
        self.assertEqual((code, out.strip(), gone), (0, "done", True))
        self.assertFalse(self.alive(pid))

    def test_a_timeout_kills_the_whole_group(self):
        pidfile = self.dir / "pid"
        with mock.patch.object(lane_land.subprocess, "TimeoutExpired", subprocess.TimeoutExpired):
            code, _out, gone = lane_land.run_group(f"sleep 300 & echo $! > {pidfile}; wait", cwd=self.dir, shell=True, timeout=0.5)
        self.assertEqual((code, gone), (-9, True))
        self.assertFalse(self.alive(int(pidfile.read_text())))

    def test_a_survivor_is_reported(self):
        proc = subprocess.Popen(["sleep", "300"], start_new_session=True)
        self.addCleanup(lambda: (proc.kill(), proc.wait()))
        self.assertTrue(lane_land.group_alive(proc.pid))
        with mock.patch.object(lane_land.os, "killpg", side_effect=lambda pg, sig: None):
            self.assertFalse(lane_land.reap_group(proc.pid, wait=0.2))

    def test_the_fixed_tests_run_in_a_group_and_survivors_refuse_the_landing(self):
        pidfile = self.dir / "pid"
        lane_land.run_tests(self.dir, f"(nohup sleep 300 >/dev/null 2>&1 & echo $! > {pidfile})")
        self.assertFalse(self.alive(int(pidfile.read_text())))
        with mock.patch.object(lane_land, "reap_group", return_value=False):
            with self.assertRaises(lane_land.Refused) as cm:
                lane_land.run_tests(self.dir, "true")
        self.assertEqual(cm.exception.kind, "processes")

    def test_git_calls_ignore_hooks_and_fsmonitor_in_the_clone_config(self):
        repo = self.dir / "r"
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        marker = self.dir / "ran"
        subprocess.run(["git", "-C", str(repo), "config", "core.fsmonitor", f"touch {marker}; echo"], check=True)
        hooks = repo / ".git" / "hooks"
        (hooks / "post-checkout").write_text(f"#!/bin/sh\ntouch {marker}\n")
        (hooks / "post-checkout").chmod(0o755)
        lane_land.git(repo, "status")
        lane_land.git(repo, "checkout", "-q", "--detach")
        self.assertFalse(marker.exists())

    def test_scrub_clone_removes_ignored_files_and_hook_scripts(self):
        repo = self.dir / "r"
        subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
        (repo / ".gitignore").write_text("junk\n")
        (repo / "a").write_text("a")
        for args in (["add", "-A"], ["commit", "-qm", "x"]):
            subprocess.run(["git", "-C", str(repo), *args], check=True, env={**os.environ, **GENV})
        (repo / "junk").write_text("planted")
        (repo / ".git" / "hooks" / "pre-commit").write_text("#!/bin/sh\n")
        lane_land.scrub_clone(repo)
        self.assertFalse((repo / "junk").exists())
        self.assertFalse((repo / ".git" / "hooks" / "pre-commit").exists())


class BaseComparisonTests(unittest.TestCase):
    """``run_tests`` compares failing ids and counts with the trusted base run of the same command."""

    CMD = "cat out.txt; exit $(cat code)"

    def tree(self, name, *, ran=5, fails=(), summary=True, code=None):
        d = self.root / name
        d.mkdir()
        lines = [f"FAIL: {f}" for f in fails]
        if summary:
            lines += [f"Ran {ran} tests in 0.1s", "", f"FAILED (failures={len(fails)})" if fails else "OK"]
        (d / "out.txt").write_text("\n".join(lines) + "\n")
        (d / "code").write_text(str(1 if fails else 0) if code is None else str(code))
        return d

    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root, True)
        self.counts = {}

    def run_it(self, lane, base):
        lane_land.run_tests(lane, self.CMD, base_clone=base, base_key="sha", base_counts=self.counts)

    def test_the_same_pre_existing_failure_is_accepted_and_cached(self):
        base = self.tree("b", fails=["test_a (m.C)"])
        self.run_it(self.tree("l", fails=["test_a (m.C)"]), base)
        self.assertEqual(self.counts[f"sha|{self.CMD}"], [1, 5, ["test_a (m.C)"]])
        (base / "code").write_text("0")  # the cache is used, the base is not run again
        self.run_it(self.tree("l2", fails=["test_a (m.C)"]), base)

    def test_a_new_failure_is_refused_and_named(self):
        base = self.tree("b", fails=["test_a (m.C)"])
        with self.assertRaises(lane_land.Refused) as cm:
            self.run_it(self.tree("l", fails=["test_a (m.C)", "test_new (m.D)"]), base)
        self.assertEqual(cm.exception.kind, "tests")
        self.assertIn("test_new (m.D)", str(cm.exception))
        self.assertNotIn("test_a (m.C)", str(cm.exception))

    def test_a_lane_that_fixes_a_base_failure_is_accepted(self):
        self.run_it(self.tree("l", ran=6), self.tree("b", fails=["test_a (m.C)"]))

    def test_an_import_time_exit_is_refused(self):
        base = self.tree("b")
        with self.assertRaises(lane_land.Refused):
            self.run_it(self.tree("l", summary=False, code=0), base)
        with self.assertRaises(lane_land.Refused):
            self.run_it(self.tree("l2", ran=2), base)

    def test_a_failing_exit_with_no_ids_is_refused(self):
        with self.assertRaises(lane_land.Refused):
            self.run_it(self.tree("l", code=1), self.tree("b"))


class CliTests(Repo):
    def setUp(self):
        super().setUp()
        (self.dev / "tools" / "triage").mkdir(parents=True, exist_ok=True)  # untracked: the CLI reads land_tests from it
        (self.dev / "tools" / "triage" / "config.json").write_text(json.dumps({"land_tests": "true"}))

    def run_cli(self, *args):
        cwd = os.getcwd()
        self.addCleanup(os.chdir, cwd)
        os.chdir(self.dev)
        err = io.StringIO()
        with redirect_stderr(err), mock.patch("sys.stdout", new=io.StringIO()):
            code = lane_land.main([*args, "--root", str(self.root)])
        return code, err.getvalue()

    def test_exit_codes_refused_dry_run_and_landed(self):
        code, err = self.run_cli(self.lane, "--into", BASE)
        self.assertEqual(code, 2)
        self.assertIn("no review verdict", err)
        self.verdict()
        before = self.origin_base()
        self.assertEqual(self.run_cli(self.lane, "--into", BASE, "--dry-run")[0], 0)
        self.assertEqual(self.origin_base(), before)
        self.assertEqual(self.run_cli(self.lane, "--into", BASE)[0], 0)
        self.assertNotEqual(self.origin_base(), before)

    def test_tests_flag_is_gone(self):
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            lane_land.main([self.lane, "--into", BASE, "--tests", "true"])

    def test_exit_1_on_conflict(self):
        self.seed_base({"b.txt": "other\n"})
        self.verdict()
        self.assertEqual(self.run_cli(self.lane, "--into", BASE)[0], 1)


class BaseMoveTests(Repo):
    """The base moving on origin while a landing is in flight: nothing is merged or pushed over it."""

    def owner_push(self, name="o.txt"):
        g(self.dev, "checkout", "-q", BASE)
        g(self.dev, "pull", "-q", "origin", BASE)
        (self.dev / name).write_text("o\n")
        g(self.dev, "add", "-A")
        g(self.dev, "commit", "-qm", "owner")
        g(self.dev, "push", "-q", "origin", BASE)
        return g(self.dev, "rev-parse", "HEAD")

    def test_a_push_during_the_review_reruns_the_fast_sets_and_lands(self):
        moved = []

        def review(lane, sha, base, diff):
            moved.append(self.owner_push())
            return self.said(sha)

        result = self.land(launch=review)
        self.assertEqual(result["parent"], moved[0])
        self.assertEqual(g(self.origin, "rev-parse", f"{BASE}^1"), moved[0])
        self.assertEqual(g(self.origin, "rev-list", "--count", "--merges", BASE), "1")

    def test_a_second_push_during_the_rerun_aborts(self):
        def review(lane, sha, base, diff):
            self.owner_push("first.txt")
            return self.said(sha)

        script = self.dir / "moves.sh"
        script.write_text(f"#!/bin/sh\ncd {self.dev} && git checkout -q {BASE} && git pull -q origin {BASE} && echo $$ > t$$.txt && "
                          f"git add -A && git commit -qm mid && git push -q origin {BASE}\nexit 0\n")
        script.chmod(0o755)
        msg = self.refused("base", launch=review, tests=f"sh {script}")
        self.assertIn("moved", msg)
        self.assertEqual(g(self.origin, "log", "-1", "--format=%s", BASE), "mid")
        self.assertEqual(g(self.origin, "rev-list", "--count", "--merges", BASE), "0")

    def test_a_move_between_the_last_check_and_the_push_aborts(self):
        sha = self.sha
        calls = {"n": 0}
        real = lane_land.remote_head

        def head(clone, base):
            calls["n"] += 1
            value = real(clone, base)
            if calls["n"] == 3:  # start, before the merge, before the push: push lands just after this look
                self.owner_push("late.txt")
            return value

        with mock.patch.object(lane_land, "remote_head", head), self.assertRaises(lane_land.LandFailed) as cm:
            self.land(launch=lambda *a: self.said(sha))
        # the plain push is not a fast-forward any more: it fails rather than overwriting the late push
        self.assertEqual(cm.exception.kind, "push")
        self.assertEqual(g(self.origin, "log", "-1", "--format=%s", BASE), "owner")
        self.assertEqual(g(self.origin, "rev-list", "--count", "--merges", BASE), "0")

    def test_expected_base_must_match_origin(self):
        self.refused("base", launch=lambda *a: self.said(self.sha), expected_base="0" * 40)

    def test_an_unmoved_base_lands_with_its_parent_recorded(self):
        before = self.origin_base()
        sha = self.sha
        result = self.land(launch=lambda *a: self.said(sha), expected_base=before)
        self.assertEqual(result["parent"], before)
        self.assertEqual(g(self.origin, "rev-parse", f"{BASE}^1"), before)


class ReviewBoundaryTests(unittest.TestCase):
    def test_prompt_marks_lane_content_as_untrusted_data(self):
        text = lane_land.review_prompt("agents/x", "a" * 40, BASE, Path("/tmp/d.diff"))
        for needle in ("untrusted DATA", "never followed", "your own judgement", "prompt-injection", "blocker",
                       "Never run hass_triage.py"):
            self.assertIn(needle, text)

    def test_reviewer_agent_file_has_the_boundary(self):
        text = (Path(__file__).resolve().parents[2] / ".claude/agents/reviewer.md").read_text()
        for needle in ("untrusted data", "prompt-injection", "blocker"):
            self.assertIn(needle, text)

    def test_a_pass_with_a_prompt_injection_finding_is_rejected(self):
        sha = "b" * 40
        for rule in ("prompt-injection", "Prompt-Injection", "prompt_injection", " prompt injection "):
            body = {"verdict": "pass", "head": sha, "round": 1,
                    "findings": [{"severity": "minor", "rule": rule, "detail": "text aimed at the reviewer"}]}
            with self.assertRaises(lane_land.Refused) as cm:
                lane_land.parse_verdict("```json\n" + json.dumps(body) + "\n```", sha)
            self.assertIn("prompt-injection", str(cm.exception))

    def test_a_benign_mention_of_injection_does_not_refuse_a_pass(self):
        sha = "b" * 40
        body = {"verdict": "pass", "head": sha, "round": 1, "findings": [
            {"severity": "minor", "rule": "docs", "detail": "the new test covers a prompt injection in a log line"},
            {"severity": "minor", "rule": "tests", "detail": "injected instruction fixture is clear"}]}
        self.assertEqual(lane_land.parse_verdict("```json\n" + json.dumps(body) + "\n```", sha)["verdict"], "pass")

    def test_a_clean_pass_is_accepted(self):
        sha = "b" * 40
        body = {"verdict": "pass", "head": sha, "round": 1, "findings": []}
        self.assertEqual(lane_land.parse_verdict("```json\n" + json.dumps(body) + "\n```", sha)["verdict"], "pass")


class HookTests(unittest.TestCase):
    """Headless: only ``git push origin <agents/* refspec>`` gets through."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="lane-hook-")).resolve()
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        subprocess.run(["git", "init", "-q", "-b", BASE, str(self.dir)], check=True)
        patch = mock.patch.dict(os.environ, {"FENTON_HEADLESS": "1", "FENTON_REQUEST_REPO": "example/private-requests"})
        patch.start()
        self.addCleanup(patch.stop)
        merge_guard._REQUEST_REPO.clear()
        self.addCleanup(merge_guard._REQUEST_REPO.clear)
        os.environ.pop("LANE_LAND", None)
        real = merge_guard.git_out  # origin resolves to this repository (the push-remote rule); everything else is real git
        origin = mock.patch.object(merge_guard, "git_out", side_effect=lambda top, *a: "git@github.com:SFenton/native-home.git"
                                   if a[:2] == ("remote", "get-url") else real(top, *a))
        origin.start()
        self.addCleanup(origin.stop)

    def why(self, command):
        return merge_guard.reason(command, str(self.dir))

    def test_ack_base_is_blocked_headless_only(self):
        for cmd in ("python3 tools/triage/hass_triage.py ack-base abc", "$HASS_TRIAGE_BIN ack-base abc",
                    "cd x && hass_triage.py ack-base 1"):
            self.assertIn("ack-base", self.why(cmd) or "", cmd)
        with mock.patch.dict(os.environ, {"FENTON_HEADLESS": "0"}):
            self.assertIsNone(self.why("python3 tools/triage/hass_triage.py ack-base abc"))

    def test_ack_verified_is_blocked_headless_and_allowed_interactive_in_its_exact_form(self):
        """Fails if: a headless session can run ack-verified, or an interactive one is blocked from its exact form or allowed a wrapped one."""
        exact = ("python3 tools/triage/hass_triage.py ack-verified", "python3 /Users/x/repo/tools/triage/hass_triage.py ack-verified")
        for cmd in (*exact, "$HASS_TRIAGE_BIN ack-verified", "cd x && hass_triage.py ack-verified"):
            self.assertIn("ack-verified", self.why(cmd) or "", cmd)  # headless: every form is blocked
        self.assertIn("headless", self.why(exact[0]))
        with mock.patch.dict(os.environ, {"FENTON_HEADLESS": "0"}), mock.patch.object(merge_guard, "pr_land_matches_base", return_value=True):
            for cmd in exact:
                self.assertIsNone(self.why(cmd), cmd)
            for cmd in ("python3 tools/triage/hass_triage.py ack-verified && echo ok", "python3 tools/triage/hass_triage.py ack-verified | tee out",
                        "cd x && python3 tools/triage/hass_triage.py ack-verified", "$HASS_TRIAGE_BIN ack-verified",
                        "python3 tools/triage/hass_triage.py ack-verified; true", "env python3 tools/triage/hass_triage.py ack-verified",
                        "script -q /dev/null python3 tools/triage/hass_triage.py ack-verified"):
                self.assertIn("ack-verified", self.why(cmd) or "", cmd)
            self.assertIsNone(self.why("grep -n ack-verified tools/triage/hass_triage.py"))  # a search is not a run

    def test_ack_verified_is_refused_from_a_stale_copy_of_the_verifier(self):
        """Fails if: an interactive session can run an edited hass_triage.py or ruleset_gate.py (a copy that differs from origin/<base>'s)."""
        cmd = "python3 tools/triage/hass_triage.py ack-verified"
        with mock.patch.dict(os.environ, {"FENTON_HEADLESS": "0"}):
            with mock.patch.object(merge_guard, "pr_land_matches_base", return_value=False) as pinned:
                self.assertIn("differs from origin/", self.why(cmd) or "")
                pinned.assert_called_once_with(cmd, "tools/triage/hass_triage.py")
            with mock.patch.object(merge_guard, "pr_land_matches_base", return_value=True):
                self.assertIsNone(self.why(cmd))

    def test_allowed_lane_pushes(self):
        for cmd in ("git push origin agents/x", "git push origin HEAD:agents/x", "git push origin HEAD:refs/heads/agents/x",
                    "git push -u origin agents/retro-r-1-261102", "git push --set-upstream origin agents/a/b",
                    "git push origin agents/x agents/y", "git -C /tmp/w push origin agents/x",
                    "cd /tmp/w && git push origin HEAD:agents/x", "git push --no-verify origin agents/x",
                    "git status && git push -q origin agents/x && echo ok", "git push origin refs/heads/agents/x:refs/heads/agents/x"):
            self.assertIsNone(self.why(cmd), cmd)

    def test_every_bypass_form_is_blocked(self):
        for cmd in (
                "git push", "git push origin", "git push origin HEAD", "git push origin HEAD:claude/uikit-port",
                "git push origin claude/uikit-port", "git push origin HEAD:refs/heads/claude/uikit-port",
                "git push origin +agents/x", "git push origin +HEAD:agents/x", "git push origin +x:claude/uikit-port",
                "git push --force origin agents/x", "git push -f origin agents/x", "git push --force-with-lease origin agents/x",
                "git push --force-with-lease=agents/x origin agents/x", "git push --force-if-includes origin agents/x",
                "git push -uf origin agents/x", "git push --all origin", "git push --all", "git push origin --all",
                "git push --mirror origin", "git push --tags origin", "git push origin --tags", "git push --follow-tags origin agents/x",
                "git push --delete origin agents/x", "git push -d origin agents/x", "git push origin :agents/x",
                "git push origin ':refs/heads/agents/x'", "git push origin 'refs/heads/*:refs/heads/*'",
                "git push origin refs/heads/*:refs/heads/*", "git push origin agents/x claude/uikit-port",
                "git push origin agents/x HEAD:main", "git push origin main", "git push origin HEAD:main",
                "git push upstream agents/x", "git push https://example.com/r.git agents/x", "git push ../other agents/x",
                "git push --repo=https://x/y agents/x", "git push --receive-pack=evil origin agents/x",
                "git push -o foo origin agents/x", "git push origin agents/x:claude/uikit-port",
                "git push origin agents/x:agents/../claude/uikit-port", "git push origin refs/tags/v1",
                "git push origin HEAD:refs/heads/agent/x", "git push origin agentsx", "git push origin refs/heads/agents",
                "git -C /tmp/w push origin HEAD", "git -C /tmp/w push --all origin",
                "git -c push.default=matching push origin", "git -c alias.p=push p --all origin",
                "git -c alias.m=merge m x", "git --config-env=alias.p=ALIAS p", "git config alias.p push",
                "git config --global alias.p 'push --all'", "git send-pack origin --all", "git http-push origin x",
                "git checkout claude/uikit-port && git push origin HEAD",
                "git checkout claude/uikit-port; git push", "git push --all origin && echo done",
                "echo hi | git push origin HEAD", "(git push --all origin)", "{ git push --all origin; }",
                "true || git push --mirror origin", "if true; then git push --all origin; fi",
                "bash -c 'git push --all origin'", "sh -c \"git push origin HEAD:claude/uikit-port\"",
                "eval 'git push --all'", "env git push --all origin", "command git push origin +x:y",
                "nohup git push --all &", "time git push --all", "sudo git push --all", "/usr/bin/git push --all origin",
                "\\git push --all", "'git' push --all", "g''it push --all", "xargs git push origin", "echo --all | xargs git push origin",
                "timeout 30 git push --all origin", "nice git push --all origin", "find . -exec git push --all \;",
                "watch git push --all", "$(echo git) push --all", "`echo git` push --all", "G=git; $G push --all",
                "git ${X} push --all", "git push origin $BR", "git push origin \"$(git rev-parse HEAD):claude/uikit-port\"",
                "git push 'origin", "echo 'x; git push --all origin"):
            self.assertIsNotNone(self.why(cmd), cmd)

    def test_the_gh_api_write_paths_and_lane_land_are_blocked(self):
        for cmd in ("gh api -X POST repos/o/r/git/refs -f ref=refs/heads/claude/uikit-port -f sha=abc",
                    "gh api repos/o/r/git/refs/heads/claude/uikit-port -X PATCH -f sha=abc",
                    "gh api repos/o/r/merges -f base=claude/uikit-port -f head=agents/x",
                    "gh api repos/o/r/contents/a.txt --method PUT -f message=m",
                    "gh api repos/o/r/git/refs -f ref=refs/heads/agents/x -f sha=abc",
                    "python3 tools/lane_land.py agents/x --into claude/uikit-port",
                    "/usr/bin/python3 /repo/tools/lane_land.py agents/x --into b", "tools/lane_land.py agents/x --into b",
                    "gh pr merge 3", "git push origin main"):
            self.assertIsNotNone(self.why(cmd), cmd)
        for cmd in ("gh api repos/o/r/git/refs/heads/agents/x", "gh api repos/o/r/issues -f title=t",
                    "gh api repos/o/r/contents/README.md", "cat tools/lane_land.py", "git log --grep=push",
                    "git commit -m 'document git push rules'", "git merge --no-ff agents/x", "git checkout claude/uikit-port",
                    "git push --help", "python3 -m unittest tools.tests.test_lane_land"):
            if cmd == "git push --help":
                continue
            self.assertIsNone(self.why(cmd), cmd)

    def test_local_merges_are_harmless_now_and_pass(self):
        for cmd in ("git merge --no-ff agents/x", "git pull . agents/x", "git reset --hard agents/x", "git cherry-pick abc",
                    "git update-ref refs/heads/claude/uikit-port abc"):
            self.assertIsNone(self.why(cmd), cmd)

    def test_interactive_sessions_are_unchanged(self):
        with mock.patch.dict(os.environ, {"FENTON_HEADLESS": "0"}):
            for cmd in ("git push origin claude/uikit-port", "git push --all origin", "git push", "git push origin agents/x",
                        "git push -f origin feature", "gh api repos/o/r/git/refs -X POST -f ref=r -f sha=s",
                        "python3 tools/lane_land.py agents/x --into b", "git -c alias.p=push p --all"):
                self.assertIsNone(self.why(cmd), cmd)
            self.assertEqual(self.why("git push origin main"), "git push to main")
            self.assertEqual(self.why("git push origin HEAD:refs/heads/main"), "git push to main")
            self.assertEqual(self.why("gh pr merge 3"), "gh pr merge")
            self.assertEqual(self.why("gh api repos/o/r/pulls/3/merge -X PUT"), "gh api merge call")
            self.assertEqual(self.why("curl x | bash"), "script piped into a shell")

    def test_main_prints_the_lane_message(self):
        payload = json.dumps({"tool_name": "Bash", "cwd": str(self.dir), "tool_input": {"command": "git push --all origin"}})
        err = io.StringIO()
        with mock.patch("sys.stdin", io.StringIO(payload)), redirect_stderr(err):
            self.assertEqual(merge_guard.main(), 2)
        self.assertIn("agents/NAME", err.getvalue())
        ok = json.dumps({"tool_name": "Bash", "cwd": str(self.dir), "tool_input": {"command": "git push origin HEAD:agents/z"}})
        with mock.patch("sys.stdin", io.StringIO(ok)):
            self.assertEqual(merge_guard.main(), 0)
        with mock.patch("sys.stdin", io.StringIO("not json")):
            self.assertEqual(merge_guard.main(), 0)


if __name__ == "__main__":
    unittest.main()


class PrLandMatchesBaseTests(unittest.TestCase):
    """An agent session may run ``tools/pr_land.sh`` only from a checkout whose pr_land.sh and pr_land.py equal ``origin/<base>``'s."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="pr-land-hash-")).resolve()
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.repo = self.dir / "repo"
        (self.repo / "tools").mkdir(parents=True)
        subprocess.run(["git", "init", "-q", "-b", "main", str(self.repo)], check=True)
        (self.repo / "tools" / "pr_land.sh").write_text("#!/bin/sh\nexec python3 pr_land.py\n")
        (self.repo / "tools" / "pr_land.py").write_text("print('base')\n")
        (self.repo / "tools" / "house_scan.py").write_text("print('scan')\n")
        (self.repo / "tools" / "agent_login.py").write_text("print('login')\n")
        for name in ("pr_blockers", "review_verdict", "ruleset_gate", "request_repo"):
            (self.repo / "tools" / f"{name}.py").write_text(f"print('{name}')\n")
        (self.repo / "tools" / "triage").mkdir()
        (self.repo / "tools" / "triage" / "config.json").write_text("{}\n")
        g(self.repo, "add", "-A")
        g(self.repo, "commit", "-qm", "base")
        g(self.repo, "update-ref", "refs/remotes/origin/main", "HEAD")
        env = mock.patch.dict(os.environ, {"FENTON_HEADLESS": "1"})
        env.start()
        self.addCleanup(env.stop)
        bases = mock.patch.object(merge_guard, "base_refs", return_value=["main", "claude/uikit-port"])
        bases.start()
        self.addCleanup(bases.stop)

    def why(self, command="tools/pr_land.sh 5", cwd=None, **kw):
        return merge_guard.reason(command, str(cwd or self.repo), **kw)

    def test_a_matching_copy_runs_headless_and_for_agent_sessions(self):
        self.assertIsNone(self.why())
        self.assertIsNone(self.why("./tools/pr_land.sh 5 --dry-run"))
        with mock.patch.dict(os.environ, {"FENTON_HEADLESS": "0"}):
            self.assertIsNone(self.why(agent=True))

    def test_an_edited_copy_is_refused_whichever_file_changed(self):
        for name in ("pr_land.py", "pr_land.sh", "house_scan.py", "agent_login.py", "pr_blockers.py", "review_verdict.py", "ruleset_gate.py", "request_repo.py", "triage/config.json"):
            with self.subTest(name=name):
                path = self.repo / "tools" / name
                original = path.read_text()
                path.write_text(original + "# edited\n")
                self.assertIn("differs from origin", self.why() or "")
                with mock.patch.dict(os.environ, {"FENTON_HEADLESS": "0"}):
                    self.assertIn("differs from origin", self.why(agent=True) or "")
                    self.assertIsNone(self.why(agent=False), "the owner's plain session is not checked")
                path.write_text(original)
                self.assertIsNone(self.why())

    def test_a_committed_edit_that_is_not_on_the_base_is_refused(self):
        (self.repo / "tools" / "pr_land.py").write_text("print('lane')\n")
        g(self.repo, "commit", "-qam", "lane edit")
        self.assertIn("differs from origin", self.why() or "")
        g(self.repo, "update-ref", "refs/remotes/origin/claude/uikit-port", "HEAD")  # the workflow base counts too
        self.assertIsNone(self.why())

    def test_git_failing_or_a_missing_base_refuses(self):
        self.assertIsNotNone(self.why(cwd=self.dir))  # not a repository
        g(self.repo, "update-ref", "-d", "refs/remotes/origin/main")
        self.assertIsNotNone(self.why())  # no origin/<base> to compare with
        g(self.repo, "update-ref", "refs/remotes/origin/main", "HEAD")
        with mock.patch.object(merge_guard, "git_out", side_effect=OSError("boom")):
            self.assertIn("differs from origin", self.why() or "")
        with mock.patch.object(merge_guard.subprocess, "run", side_effect=OSError("no git")):
            self.assertIsNotNone(self.why())

    def test_the_bases_come_from_the_triage_config(self):
        cfg = json.loads((TOOLS / "triage" / "config.json").read_text())
        self.addCleanup(mock.patch.stopall)
        mock.patch.stopall()
        self.assertEqual(merge_guard.base_refs(), list(dict.fromkeys([cfg["product_base"], cfg["workflow_base"]])))


class RequestRepoGuardTests(unittest.TestCase):
    """Headless sessions never edit the request repository's issues and create there only with the ``Workflow`` label
    (owner, 2026-11-03); an interactive owner session is unaffected."""

    R = "example/private-requests"

    def setUp(self):
        # the real name is local configuration: pin the environment variable and drop the cached value
        patch = mock.patch.dict(os.environ, {"FENTON_HEADLESS": "1", "FENTON_REQUEST_REPO": self.R})
        patch.start()
        self.addCleanup(patch.stop)
        merge_guard._REQUEST_REPO.clear()
        self.addCleanup(merge_guard._REQUEST_REPO.clear)
        base = mock.patch.object(merge_guard, "pr_land_matches_base", return_value=True)  # the hash check has its own tests
        base.start()
        self.addCleanup(base.stop)

    def why(self, command, **kw):
        return merge_guard.reason(command, **kw)

    def test_the_request_repo_comes_from_local_configuration(self):
        self.assertEqual(merge_guard.request_repo(), self.R.lower())

    def test_with_no_request_repo_configured_every_guarded_write_is_refused_against_any_repo(self):
        with tempfile.TemporaryDirectory() as home, mock.patch.dict(os.environ, {"HOME": home}):
            os.environ.pop("FENTON_REQUEST_REPO", None)  # an empty HOME: no local file either
            merge_guard._REQUEST_REPO.clear()
            self.assertEqual(merge_guard.request_repo(), "")
            for cmd in ("gh issue edit 5 -R other/repo --title x", "gh issue close 5 -R other/repo", "gh issue comment 5 --body x",
                        "gh issue edit 5 --add-label X", "GH_REPO=other/repo gh issue edit 5", "gh label create X -R other/repo",
                        "gh api -X PATCH repos/other/repo/issues/5 -f state=closed"):
                with self.subTest(command=cmd):
                    self.assertIsNotNone(self.why(cmd))
            for cmd in ("gh issue view 5 -R other/repo", "gh api repos/other/repo/issues/5", "git status"):
                with self.subTest(command=cmd):
                    self.assertIsNone(self.why(cmd))

    def test_issue_edit_of_the_request_repo_is_blocked_in_every_spelling(self):
        for cmd in (f"gh issue edit 5 --repo {self.R} --add-label X", f"gh issue edit 5 -R {self.R} --title x",
                    f"gh issue edit 5 --repo={self.R}", f"gh issue edit 5 -R{self.R}", f"gh issue edit 5 -R={self.R}",
                    f"gh issue edit 5 --repo {self.R.upper()}", f"gh issue edit 5 -R https://github.com/{self.R}",
                    f"gh issue edit 5 -R 'github.com/{self.R}.git'", f"gh issue edit 5 --repo '{self.R}'",
                    f'gh issue edit 5 -R "{self.R}"', f"gh issue edit https://github.com/{self.R}/issues/5 --body x",
                    f"GH_REPO={self.R} gh issue edit 5", f"env GH_REPO={self.R} gh issue edit 5",
                    f"gh --version; gh issue edit 5 -R {self.R}", f"true && gh issue edit 5 -R {self.R} --body-file b.md",
                    f"bash -c 'gh issue edit 5 -R {self.R}'", f"eval \"gh issue edit 5 -R {self.R}\"",
                    f"echo $(gh issue edit 5 -R {self.R})", f"/opt/homebrew/bin/gh issue edit 5 -R {self.R}",
                    f"gh issue edit 5 --title 'a; (b)' -R {self.R}", f"timeout 5 gh issue edit 5 -R {self.R}",
                    f"xargs -n1 gh issue edit -R {self.R}", f"nohup gh issue edit 5 -R {self.R}"):
            with self.subTest(cmd=cmd):
                self.assertTrue((self.why(cmd) or "").startswith("request-repo"), cmd)

    def test_issue_edit_elsewhere_is_untouched(self):
        for cmd in ("gh issue edit 5 --title x", "gh issue edit 5 -R SFenton/native-home --title x",
                    f"gh issue edit 5 -R SFenton/native-home --body 'see {self.R}#3'",
                    f"gh issue edit 5 --title 'about {self.R}'", f"GH_REPO=SFenton/native-home gh issue edit 5 --body x",
                    f"gh issue edit 5 -R other/repo --repo {self.R}x", "echo gh issue edit 5"):
            with self.subTest(cmd=cmd):
                # -R other/repo with a later --repo of the request repo is the last word in gh; the guard reads all -R/--repo values
                if "other/repo" in cmd:
                    continue
                self.assertIsNone(self.why(cmd), cmd)

    def test_issue_create_needs_the_workflow_label(self):
        base = f"gh issue create -R {self.R} --title 'x (y); z' --body 'b'"
        self.assertTrue((self.why(base) or "").startswith("request-repo"))
        for tail in ("", " --label Bug", " -l Bug,Feature", " --label=Bug", " -lBug", " --label 'Workflows'",
                     " --body 'pass --label Workflow'", " --title 'use -l Workflow'", " --label-file Workflow", " --labels Workflow"):
            with self.subTest(tail=tail):
                self.assertTrue((self.why(f"gh issue create -R {self.R}" + (tail if tail.startswith((" --body", " --title")) else tail
                                          + " --title t")) or "").startswith("request-repo"), tail)
        for label in ("--label Workflow", "-l Workflow", "--label=Workflow", "-lWorkflow", "-l=Workflow", "--label workflow",
                      "--label 'Bug, Workflow'", "--label Bug,Workflow", "--label Bug --label Workflow", '--label "Workflow"',
                      "-l Bug -l Workflow"):
            with self.subTest(label=label):
                self.assertIsNone(self.why(f"gh issue create -R {self.R} --title 'x (y); z' --body 'b' {label}"), label)
                self.assertIsNone(self.why(f"gh issue create --repo {self.R} {label} --title t"), label)
                self.assertIsNone(self.why(f"GH_REPO={self.R} gh issue create {label} --title t"), label)

    def test_a_title_or_body_that_mentions_the_label_does_not_count(self):
        for text in ("--label Workflow", "-l Workflow"):
            cmd = f"gh issue create -R {self.R} --title t --body '{text}'"
            self.assertTrue((self.why(cmd) or "").startswith("request-repo"), cmd)

    def test_issue_create_elsewhere_and_other_issue_commands_are_untouched(self):
        for cmd in ("gh issue create --title t", "gh issue create -R SFenton/native-home --title t",
                    f"gh issue create --title 'see {self.R}#4' --body b", f"gh issue view 5 -R {self.R}",
                    f"gh issue list -R {self.R}", f"gh issue status -R {self.R}", f"gh repo view {self.R}",
                    f"gh api repos/{self.R}/issues/5", f"gh api repos/{self.R}/issues", f"gh api -X GET repos/{self.R}/issues/5/labels",
                    "gh issue comment 5 --body hi", "gh issue close 5", "gh label list", "gh label create x",
                    "gh issue comment 5 -R SFenton/native-home --body x", "gh api repos/SFenton/native-home/issues/5 -X PATCH -f state=closed"):
            with self.subTest(cmd=cmd):
                self.assertIsNone(self.why(cmd), cmd)

    def test_the_gh_api_route_is_closed_the_same_way(self):
        for cmd in (f"gh api -X PATCH repos/{self.R}/issues/5 -f state=closed", f"gh api --method=PATCH repos/{self.R}/issues/5",
                    f"gh api -XPATCH repos/{self.R}/issues/5 -f title=x", f"gh api repos/{self.R}/issues -f title=x",
                    f"gh api repos/{self.R}/issues -f title=x -f 'labels[]=Bug'", f"gh api repos/{self.R}/issues --input body.json",
                    f"gh api -X POST repos/{self.R}/issues/5 -f x=y", f"gh api -X DELETE repos/{self.R}/issues/5"):
            with self.subTest(cmd=cmd):
                self.assertTrue((self.why(cmd) or "").startswith("request-repo"), cmd)
        self.assertIsNone(self.why(f"gh api repos/{self.R}/issues -f title=x -f 'labels[]=Workflow'"))
        self.assertIsNotNone(self.why(f"gh api repos/{self.R}/issues/5/comments -f body=hi"))  # every non-GET write is closed

    def test_every_other_write_against_the_request_repo_is_blocked(self):
        R = self.R
        for cmd in (f"gh api -X DELETE repos/{R}/issues/5/labels/Workflow", f"gh api -X PUT repos/{R}/issues/5/labels -f 'labels[]=x'",
                    f"gh api -X POST repos/{R}/issues/5/labels -f 'labels[]=x'", f"gh api --method PATCH repos/{R}/labels/Workflow -f name=x",
                    f"gh api -X DELETE repos/{R}/labels/Workflow", f"gh api -X PUT repos/{R}", f"gh api repos/{R}/issues/5/lock -X PUT",
                    f"gh label edit Workflow --name X -R {R}", f"gh label delete Workflow -R {R} --yes", f"gh label create x -R {R}",
                    f"gh label clone SFenton/native-home -R {R}",
                    "gh api graphql -f query='mutation { deleteIssue(input: {issueId: \"x\"}) { clientMutationId } }'",
                    "gh api graphql -F query=@q.graphql", "gh api graphql --input q.json",
                    f"gh repo set-default {R} && gh issue edit 5", f"gh repo set-default {R}", "gh repo set-default other/repo",
                    f"gh repo edit {R} --description x", f"gh repo delete {R} --yes", f"gh repo rename x -R {R}",
                    f"export GH_REPO={R}; gh issue edit 5", f"export GH_REPO={R} && gh issue close 5", f"GH_REPO={R} gh label delete x",
                    f"declare -x GH_REPO={R}; gh issue edit 5", "export GH_REPO=$X; gh issue edit 5", "GH_REPO=$(cat r) gh issue edit 5",
                    "gh issue edit 5 -R $R", "gh issue edit 5 --repo $R", "gh issue edit 5 -R $(echo example/private-requests)",
                    "gh issue edit 5 -R \"$(cat repo)\"", "gh issue edit 5 -R `cat repo`", "gh issue edit 5 -R ${REPO}", "gh issue edit 5 -R SFenton/fenton-*",
                    "gh issue edit $URL", "gh issue edit $(cat url)",
                    f"gh issue edit https://github.com/{R}/issues/5 -R other/repo", f"gh issue edit -R other/repo https://github.com/{R}/issues/5",
                    f"gh issue edit 5 -R SFenton/native-home --repo {R}",
                    f"find . -name x -exec gh issue edit 5 -R {R} \\;", "find . -name x -exec gh issue edit {} \\;",
                    f"find . -exec gh issue close 5 -R {R} \\;", f"ls | xargs -I{{}} gh issue edit {{}} -R {R}",
                    f"gh issue close 5 -R {R}", f"gh issue close 5 -R {R} --reason completed", f"gh issue delete 5 -R {R} --yes",
                    f"gh issue transfer 5 SFenton/native-home -R {R}", f"gh issue comment 5 -R {R} --body x",
                    f"gh issue reopen 5 -R {R}", f"gh issue lock 5 -R {R}", f"gh issue pin 5 -R {R}", f"gh issue unpin 5 -R {R}",
                    f"gh issue develop 5 -R {R}", f"gh issue create -R {R} --title t", f"gh issue edit 5 -R {R} --add-label Workflow",
                    f"bash -c 'gh issue delete 5 -R {R}'", f"timeout 9 gh label delete Workflow -R {R}"):
            with self.subTest(cmd=cmd):
                self.assertTrue((self.why(cmd) or "").startswith("request-repo"), cmd)

    def test_reads_and_the_workflow_create_stay_open_against_the_request_repo(self):
        R = self.R
        for cmd in (f"gh issue view 5 -R {R} --json title,body", f"gh issue list -R {R} --label Workflow", f"gh issue status -R {R}",
                    f"gh repo view {R}", f"gh api repos/{R}/issues/5", f"gh api graphql -f query='query {{ viewer {{ login }} }}'",
                    f"gh api repos/{R}/issues --paginate", f"gh issue create -R {R} --title t --label Workflow",
                    f"gh api -X POST repos/{R}/issues -f title=x -f 'labels[]=Workflow'", f"GH_REPO={R} gh issue view 5",
                    f"export GH_REPO={R}; gh issue list", "gh issue view $N", "gh label list", "gh pr list",
                    f"gh label list -R {R}", f"gh label list --repo {R} --json name", f"GH_REPO={R} gh label list", f"gh label view Workflow -R {R}"):
            with self.subTest(cmd=cmd):
                self.assertIsNone(self.why(cmd), cmd)

    def test_other_repositories_keep_working(self):
        for cmd in ("gh issue edit 5 --title x", "gh issue close 5", "gh label create x", "gh issue comment 5 --body x",
                    "gh issue edit 5 -R SFenton/native-home --add-label Bug", "GH_REPO=SFenton/native-home gh issue close 5",
                    "export GH_REPO=SFenton/native-home; gh issue edit 5 --title x",
                    "gh api -X PATCH repos/SFenton/native-home/issues/5 -f state=closed",
                    "gh api graphql -f query='mutation { x }'".replace("mutation { x }", "query { y }")):
            with self.subTest(cmd=cmd):
                self.assertIsNone(self.why(cmd), cmd)

    def test_gh_alias_is_blocked_headless(self):
        self.assertIn("alias", self.why("gh alias set ie 'issue edit'") or "")

    def test_an_interactive_owner_session_is_unaffected(self):
        with mock.patch.dict(os.environ, {"FENTON_HEADLESS": "0"}):
            for cmd in (f"gh issue edit 5 -R {self.R} --add-label X", f"gh issue create -R {self.R} --title t",
                        f"gh api -X PATCH repos/{self.R}/issues/5", "gh alias set a b"):
                self.assertIsNone(merge_guard.reason(cmd), cmd)

    def test_the_hook_blocks_with_the_request_message(self):
        err = io.StringIO()
        payload = json.dumps({"tool_name": "Bash", "tool_input": {"command": f"gh issue edit 5 -R {self.R}"}})
        with mock.patch.object(sys, "stdin", io.StringIO(payload)), redirect_stderr(err):
            self.assertEqual(merge_guard.main(), 2)
        self.assertIn("request repository", err.getvalue())
        self.assertNotIn("lane branches", err.getvalue())

    def test_pr_land_runs_headless_only_in_its_sanctioned_form(self):
        for cmd in ("tools/pr_land.sh 5", "tools/pr_land.sh 5 --dry-run", "./tools/pr_land.sh 12"):
            self.assertIsNone(self.why(cmd), cmd)
        for cmd in ("cd x && tools/pr_land.sh 5", "bash tools/pr_land.sh 5", "sh -c 'tools/pr_land.sh 5'", "python3 tools/pr_land.py 5",
                    "python3 -I tools/pr_land.py 5 --dry-run", "FOO=1 tools/pr_land.sh 5", "tools/pr_land.sh 5; true",
                    "tools/pr_land.sh $(echo 5)", "tools/pr_land.sh 5 | cat", "env tools/pr_land.sh 5", "source tools/pr_land.sh",
                    "time tools/pr_land.sh 5", "nice python3 tools/pr_land.py 5"):
            with self.subTest(cmd=cmd):
                self.assertTrue((self.why(cmd) or "").startswith("landing: pr_land"), f"{cmd}: {self.why(cmd)}")
        for cmd in ("git add tools/pr_land.py", "cat tools/pr_land.sh", "python3 -m unittest tools.tests.test_pr_land",
                    "grep -n owner tools/pr_land.py", "python3 -m unittest tools.tests.test_lane_land.HookTests"):
            with self.subTest(cmd=cmd):
                self.assertIsNone(self.why(cmd), cmd)

    def test_any_owner_option_and_its_abbreviations_are_refused(self):
        for cmd in ("tools/pr_land.sh 5 --owner", "tools/pr_land.sh 5 --owner-a", "tools/pr_land.sh 5 --owner-ack", "tools/pr_land.sh 5 --OWNER-ACK",
                    "tools/pr_land.sh 5 --owner=1", "python3 tools/pr_land.py 5 --owner_ack"):
            with self.subTest(cmd=cmd):
                self.assertIn("owner-ack", self.why(cmd) or "", cmd)

    def test_the_session_markers_cannot_be_taken_away_in_a_command(self):
        for cmd in ("env -u FENTON_HEADLESS tools/pr_land.sh 5", "env -u FENTON_HEADLESS -u HASS_TRIAGE_ISSUE tools/pr_land.sh 5",
                    "env -uFENTON_HEADLESS tools/pr_land.sh 5", "env --unset=FENTON_HEADLESS tools/pr_land.sh 5", "env -i tools/pr_land.sh 5",
                    "env -i PATH=/usr/bin tools/pr_land.sh 5", "env --ignore-environment ls", "env - ls", "env FOO=1 -i ls",
                    "unset FENTON_HEADLESS; ls", "unset HASS_TRIAGE_ISSUE", "unset -v FENTON_HEADLESS HASS_TRIAGE_ISSUE",
                    "FENTON_HEADLESS=0 tools/pr_land.sh 5", "FENTON_HEADLESS= ls", "export FENTON_HEADLESS=0", "HASS_TRIAGE_ISSUE=7 ls",
                    "export HASS_TRIAGE_ISSUE=7", "bash -c 'unset FENTON_HEADLESS; tools/pr_land.sh 5'"):
            with self.subTest(cmd=cmd):
                self.assertIsNotNone(self.why(cmd), cmd)
        for cmd in ("FENTON_HEADLESS=1 python3 -m unittest x", "env FOO=1 grep -i x f", "env -u TERM ls", "echo $FENTON_HEADLESS"):
            with self.subTest(cmd=cmd):
                self.assertIsNone(self.why(cmd), cmd)

    def test_a_pty_wrapper_around_the_landing_tools_is_refused(self):
        for cmd in ("script -q /dev/null tools/pr_land.sh 5", "script -q /dev/null -c 'tools/pr_land.sh 5'", "/usr/bin/script -q /dev/null python3 tools/pr_land.py 5",
                    "expect -c 'spawn tools/pr_land.sh 5; interact'", "unbuffer python3 tools/pr_land.py 5", "unbuffer tools/pr_land.sh 5",
                    "script -q /dev/null python3 tools/lane_land.py x --into y", "script -q /dev/null python3 tools/triage/hass_triage.py ack-base abc",
                    "script -q /dev/null python3 tools/triage/hass_triage.py ack-verified", "unbuffer python3 tools/triage/hass_triage.py ack-verified",
                    "env -u FENTON_HEADLESS -u HASS_TRIAGE_ISSUE script -q /dev/null tools/pr_land.sh 5 --owner", "tmux new 'tools/pr_land.sh 5'"):
            with self.subTest(cmd=cmd):
                self.assertTrue((self.why(cmd) or "") != "", cmd)
        self.assertIsNone(self.why("script -q /dev/null ls"))

    def test_the_reviewers_reproduction_is_refused(self):
        cmd = "env -u FENTON_HEADLESS -u HASS_TRIAGE_ISSUE script -q /dev/null tools/pr_land.sh 12 --owner"
        self.assertIsNotNone(self.why(cmd))
        with mock.patch.dict(os.environ, {"FENTON_HEADLESS": "0"}):
            self.assertIsNone(self.why("tools/pr_land.sh 12"))  # the owner's own session is untouched
            self.assertIsNone(self.why("cd x && python3 tools/pr_land.py 12 --owner-ack"))


    def test_false_positives_stay_open(self):
        for cmd in ('gh issue comment 5 --body "$(cat notes.md)"', 'gh issue comment 5 --body "$(git log -1)" -R SFenton/native-home',
                    "gh search repos --owner SFenton", "gh search issues foo --owner SFenton --limit 5", "gh repo list --owner SFenton"):
            with self.subTest(cmd=cmd):
                self.assertIsNone(self.why(cmd), cmd)
        # an unresolvable target still counts as the request repo; so does a POST to gh's {owner}/{repo} placeholders
        for cmd in ('gh issue comment 5 -R "$(cat repo)" --body x', "gh issue comment $(cat url) --body x", "gh issue edit 5 --body `cat f`",
                    "gh api -X POST repos/{owner}/{repo}", "gh api -X POST repos/{owner}/{repo}/issues -f title=x"):
            with self.subTest(cmd=cmd):
                self.assertTrue((self.why(cmd) or "").startswith("request-repo"), cmd)
        self.assertIn("owner-ack", self.why("tools/pr_land.sh 5 --owner") or "")
        self.assertIsNotNone(self.why("python3 tools/lane_land.py gate --pr 5 --own"))  # lane_land never runs headless

    def test_agent_sessions_without_the_headless_flag_get_the_landing_refusals(self):
        with mock.patch.dict(os.environ, {"FENTON_HEADLESS": "0"}):
            for agent in ("orchestrator", "coder", "general-purpose"):
                for cmd in ("python3 tools/pr_land.py 5 --owner-ack", "tools/pr_land.sh 5 --owner", "env -u FENTON_HEADLESS tools/pr_land.sh 5",
                            "unset FENTON_HEADLESS; ls", "script -q /dev/null tools/pr_land.sh 5", "cd x && tools/pr_land.sh 5",
                            "env -u FENTON_HEADLESS -u HASS_TRIAGE_ISSUE script -q /dev/null tools/pr_land.sh 5 --owner"):
                    with self.subTest(agent=agent, cmd=cmd):
                        self.assertIsNotNone(self.why(cmd, agent=True), cmd)
                        self.assertIsNone(self.why(cmd, agent=False), "the owner's plain session is untouched")
            payload = {"tool_name": "Bash", "tool_input": {"command": "python3 tools/pr_land.py 5 --owner-ack"}}
            for extra in ({"agent_type": "coder"}, {"agent_id": "a1"}):
                err = io.StringIO()
                with mock.patch.object(sys, "stdin", io.StringIO(json.dumps({**payload, **extra}))), redirect_stderr(err):
                    self.assertEqual(merge_guard.main(), 2)
                self.assertIn("owner's path", err.getvalue())
            with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))):
                self.assertEqual(merge_guard.main(), 0)
            # the request-repo rules are the runner's (headless) alone
            self.assertIsNone(self.why(f"gh issue edit 5 -R {self.R}", agent=True))

    def test_owner_ack_is_blocked_headless(self):
        for cmd in ("tools/pr_land.sh 5 --owner-ack", "python3 tools/pr_land.py 5 --owner-ack", "bash tools/pr_land.sh 5 --owner_ack"):
            self.assertIn("owner-ack", self.why(cmd) or "", cmd)
        with mock.patch.dict(os.environ, {"FENTON_HEADLESS": "0"}):
            self.assertIsNone(self.why("python3 tools/pr_land.py 5 --owner-ack"))


class PrGateTests(Repo):
    """``lane_land.pr_gate``: the lander's app-UI check run on a product pull request (what ``tools/pr_land.sh`` calls)."""

    VIEW = "apple/Sources/HassUI/Chip.swift"
    RECORD = ".agents/design/chip.md"
    GOOD = DesignRecordTests.GOOD
    AGENT = {"FENTON_HEADLESS": "1", "HASS_TRIAGE_ISSUE": "99"}
    CFG = {"authors": ["SFenton"], "request_repo": "example/private-requests", "product_repo": "SFenton/native-home"}

    def setUp(self):
        super().setUp()
        for key in ("HASS_TRIAGE_ISSUE", "HASS_TRIAGE_INTAKE"):
            os.environ.pop(key, None)
        self.calls = []

    def pr(self, files, message=None, number=7):
        """Push a commit with ``files`` as ``refs/pull/N/head``; returns the ``gh pr view`` info for it."""
        sha = self.push_lane("pr/x", files)
        if message:
            g(self.dev, "commit", "-q", "--amend", "-m", message)
            sha = g(self.dev, "rev-parse", "HEAD")
        g(self.dev, "push", "-q", "-f", "origin", f"{sha}:refs/pull/{number}/head")
        return {"baseRefName": BASE, "headRefOid": sha, "files": [{"path": p} for p in files], "body": "", "title": "Chips",
                "author": {"login": "SFenton"}}

    def jev(self, p_yes):
        def ask(trusted, qid, text):
            self.calls.append((qid, text))
            return p_yes
        return ask

    def gate(self, info, p_yes=0.05, env=None, gh=None, number="7", cfg=None):
        return lane_land.pr_gate(number, info, root=self.root, cfg=cfg or self.CFG, gh=gh or (lambda a: (_ for _ in ()).throw(RuntimeError("no gh"))),
                                 origin=lambda: str(self.origin), env=env or {}, ask=self.jev(p_yes))

    def refuses(self, info, kind, **kw):
        with self.assertRaises(lane_land.Refused) as cm:
            self.gate(info, **kw)
        self.assertEqual(cm.exception.kind, kind, str(cm.exception))
        return str(cm.exception)

    def test_a_pr_without_app_ui_never_clones_or_asks(self):
        info = {"baseRefName": BASE, "headRefOid": "abc", "files": [{"path": "tools/x.py"}, {"path": "apple/Apps/FentonHomeTests/T.swift"}]}
        self.assertEqual(self.gate(info), "no app UI changed")
        self.assertEqual(self.calls, [])
        self.assertFalse((self.root / "gate").exists())

    def test_a_missing_file_list_fails_closed(self):
        self.assertIn("file list", self.refuses({"baseRefName": BASE, "headRefOid": "a" * 40}, "gate"))

    def test_app_ui_without_a_record_is_refused_like_a_lane(self):
        self.assertIn("design decision record", self.refuses(self.pr({self.VIEW: "x\n"}), "design"))
        self.assertEqual(self.calls, [])

    def test_a_cited_record_on_the_base_works_like_a_lane(self):
        self.seed_base({".agents/design/chip.md": "# Chip\n"})
        info = self.pr({self.VIEW: "x\n"}, "Chip fix\n\nDesign: .agents/design/chip.md\n")
        self.gate(info, 0.05, env=self.AGENT)
        self.assertEqual([c[0] for c in self.calls], ["design.app_wide"])

    def test_agent_initiated_pr_lands_only_on_a_confident_no(self):
        info = self.pr({self.VIEW: "x\n", self.RECORD: self.GOOD}, "Chips\n\nOwner-Request: 12\n")
        for p_yes, ok in ((0.1, True), (0.29, True), (0.3, False), (0.5, False), (0.9, False), (None, False)):
            with self.subTest(p_yes=p_yes):
                self.calls.clear()
                env = {"FENTON_HEADLESS": "1", "HASS_TRIAGE_ISSUE": "99"}  # no snapshot for 12: not vouched
                if ok:
                    self.assertIn("passed", self.gate(info, p_yes, env=env))
                else:
                    self.refuses(info, "gate", p_yes=p_yes, env=env)
                self.assertEqual([c[0] for c in self.calls], ["design.app_wide"])

    def snapshot(self, number, **entry):
        path = self.root / "requests" / f"{number}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"number": number, "title": "Bigger chips", "body": "Make them taller", "author": "SFenton",
                                    "labels": ["Feature"], **entry}))

    def test_a_headless_pr_is_vouched_by_the_pickup_snapshot_and_judged_on_matches_request(self):
        self.snapshot(12)
        info = self.pr({self.VIEW: "x\n", self.RECORD: self.GOOD}, "Chips\n\nOwner-Request: #12\n")
        env = {"FENTON_HEADLESS": "1", "HASS_TRIAGE_ISSUE": "12"}
        for p_yes, ok in ((0.95, True), (0.8, True), (0.79, False), (0.5, False), (0.1, False), (None, False)):
            with self.subTest(p_yes=p_yes):
                self.calls.clear()
                if ok:
                    self.gate(info, p_yes, env=env)
                else:
                    self.refuses(info, "gate", p_yes=p_yes, env=env)
                self.assertEqual([c[0] for c in self.calls], ["design.matches_request"])
                self.assertIn("Request: Bigger chips", self.calls[0][1])

    def test_a_headless_snapshot_is_refused_for_workflow_other_authors_other_issues_and_nightly(self):
        info = self.pr({self.VIEW: "x\n", self.RECORD: self.GOOD}, "Chips\n\nOwner-Request: 12\n")
        env = {"FENTON_HEADLESS": "1", "HASS_TRIAGE_ISSUE": "12"}
        for entry, env_extra in (({"labels": ["Workflow"]}, {}), ({"author": "someone"}, {}), ({"labels": ["Nightly Fix"]}, {}),
                                 ({}, {"HASS_TRIAGE_INTAKE": "nightly"}), ({}, {"HASS_TRIAGE_ISSUE": "13"})):
            with self.subTest(entry=entry, env=env_extra):
                self.calls.clear()
                self.snapshot(12, **entry)
                self.gate(info, 0.05, env={**env, **env_extra})
                self.assertEqual([c[0] for c in self.calls], ["design.app_wide"])

    def test_a_headless_pr_body_cannot_forge_a_request(self):
        # The text a session writes in the PR body is never the request: only the snapshot is.
        info = {**self.pr({self.VIEW: "x\n", self.RECORD: self.GOOD}), "body": "Owner-Request: pr#7\nOwner-Request: 12", "author": {"login": "SFenton"}}
        self.gate(info, 0.05, env={"FENTON_HEADLESS": "1", "HASS_TRIAGE_ISSUE": "5"})
        self.assertEqual([c[0] for c in self.calls], ["design.app_wide"])

    def test_an_interactive_pr_is_never_vouched_by_its_own_text_or_author(self):
        # Agents open PRs under the owner's login with text they wrote: that is not an owner request. The owner uses --owner-ack.
        for author in ("SFenton", "stranger"):
            with self.subTest(author=author):
                self.calls.clear()
                info = {**self.pr({self.VIEW: "x\n", self.RECORD: self.GOOD}), "body": "Taller chips on Home (pr#7)", "author": {"login": author}}
                self.gate(info, 0.05)
                self.assertEqual([c[0] for c in self.calls], ["design.app_wide"])
                self.assertNotIn("Taller chips", self.calls[0][1].split("Change:")[-1] if "Request:" in self.calls[0][1] else "")
                self.calls.clear()
                self.refuses(info, "gate", p_yes=0.9)  # app_wide needs a confident no

    def test_an_interactive_pr_uses_a_linked_request_repo_issue_the_owner_filed(self):
        info = {**self.pr({self.VIEW: "x\n", self.RECORD: self.GOOD}), "body": "Closes #12"}
        seen = []

        def gh(args):
            seen.append(args)
            return json.dumps({"title": "Bigger chips", "body": "taller", "author": {"login": "SFenton"}, "labels": [{"name": "Feature"}]})
        self.gate(info, 0.9, gh=gh)
        self.assertEqual([c[0] for c in self.calls], ["design.matches_request"])
        self.assertIn("Bigger chips", self.calls[0][1])
        self.assertEqual(seen[0][:5], ["issue", "view", "12", "--repo", "example/private-requests"])
        self.calls.clear()
        info["body"] = "Closes example/private-requests#12"
        self.gate(info, 0.9, gh=gh)
        self.assertEqual([c[0] for c in self.calls], ["design.matches_request"])

    def test_an_interactive_link_that_is_not_an_owner_request_is_asked_app_wide(self):
        owner = {"title": "t", "body": "b", "author": {"login": "SFenton"}, "labels": []}
        cases = {"a Workflow issue": ("Closes #12", {**owner, "labels": [{"name": "Workflow"}]}),
                 "a Nightly Fix issue": ("Closes #12", {**owner, "labels": [{"name": "Nightly Fix"}]}),
                 "another author": ("Closes #12", {**owner, "author": {"login": "stranger"}}),
                 "a product-repo slug": ("Closes SFenton/native-home#4", owner),
                 "an unreadable issue": ("Closes #12", None)}
        for name, (body, data) in cases.items():
            with self.subTest(name):
                self.calls.clear()
                seen = []

                def gh(args, data=data):
                    seen.append(args)
                    if data is None:
                        raise RuntimeError("gone")
                    return json.dumps(data)
                self.gate({**self.pr({self.VIEW: "x\n", self.RECORD: self.GOOD}), "body": body}, 0.05, gh=gh)
                self.assertEqual([c[0] for c in self.calls], ["design.app_wide"])
                self.assertFalse([a for a in seen if "private-app" in " ".join(a)], "the product repo is never read")

    def test_jev_unavailable_and_a_moved_head_fail_closed(self):
        info = self.pr({self.VIEW: "x\n", self.RECORD: self.GOOD})
        self.assertIn("unavailable", self.refuses(info, "gate", p_yes=None))
        self.assertIn("moved", self.refuses({**info, "headRefOid": "b" * 40}, "gate"))
        self.assertIn("no readable", self.refuses({**info, "headRefOid": "nothex"}, "gate"))

    CHAT = "Make the Home chips taller, they are hard to hit on the Duo"

    def log_prompt(self, text, days_ago=1):
        stamp = datetime.now(timezone.utc) - timedelta(days=days_ago)
        folder = self.root / "owner-prompts"
        folder.mkdir(parents=True, exist_ok=True)
        with open(folder / f"{stamp:%Y-%m}.jsonl", "a") as handle:
            handle.write(json.dumps({"ts": stamp.strftime("%Y-%m-%dT%H:%M:%SZ"), "prompt": text}) + "\n")

    def chat_pr(self, quote):
        return {**self.pr({self.VIEW: "x\n", self.RECORD: self.GOOD}), "body": f'Taller chips\n\nOwner\'s request: "{quote}"\n'}

    def test_a_chat_request_quoted_in_the_pr_and_logged_is_the_owners_request(self):
        self.log_prompt(f"{self.CHAT}. Thanks!")
        self.gate(self.chat_pr(self.CHAT), 0.9)
        self.assertEqual([c[0] for c in self.calls], ["design.matches_request"])
        self.assertIn("Thanks!", self.calls[0][1])  # Jev sees the logged prompt, not only the agent's quote
        self.calls.clear()
        self.refuses(self.chat_pr(self.CHAT), "gate", p_yes=0.5)  # still needs Jev's yes

    def test_an_unlogged_short_or_old_chat_quote_is_asked_app_wide_as_before(self):
        self.log_prompt(self.CHAT, days_ago=15)
        self.log_prompt("Something else entirely, about the settings page")
        for name, quote in (("unlogged", "Make every tile purple, I love it so much"), ("short", "taller chips"), ("old", self.CHAT)):
            with self.subTest(name):
                self.calls.clear()
                self.gate(self.chat_pr(quote), 0.05)
                self.assertEqual([c[0] for c in self.calls], ["design.app_wide"])
                self.refuses(self.chat_pr(quote), "gate", p_yes=0.9)

    def test_a_headless_session_never_uses_the_chat_log(self):
        self.log_prompt(self.CHAT)
        self.gate(self.chat_pr(self.CHAT), 0.05, env=self.AGENT)
        self.assertEqual([c[0] for c in self.calls], ["design.app_wide"])

    MOCK = ".agents/design/mockups/pages/chores/chores/chores.html"
    PAGE = ("<body>\n<script>Mock.mount({kind: 'page', id: 'c', status: 'shipped',\n  source: ['apple/Sources/HassUI/A.swift'],\n"
            "  states: {d: {title: 'Signed in'}} });</script>\n<!-- cite ha-sfenton-react-dash@abc:A.tsx:1 -->\n</body>\n")

    def test_a_citation_only_mockup_rewrite_is_not_app_ui_but_a_drawn_change_is(self):
        self.seed_base({self.MOCK: self.PAGE, ".agents/design/mockups/README.md": "old\n"})
        cite_only = self.PAGE.replace("A.swift", "UKA.swift").replace("abc:A.tsx:1", "def:A.tsx:7").replace("shipped", "decided")
        info = self.pr({self.MOCK: cite_only, ".agents/design/mockups/README.md": "new\n"})
        self.assertEqual(self.gate(info), "no app UI changed")
        self.assertEqual(self.calls, [])
        drawn = self.PAGE.replace("Signed in", "Signed out")
        info = self.pr({self.MOCK: drawn}, number=8)
        self.assertIn("design decision record", self.refuses(info, "design", number="8"))
        info = self.pr({self.MOCK: drawn, self.RECORD: self.GOOD}, number=9)
        self.assertIn("passed", self.gate(info, 0.05, number="9", env=self.AGENT))
        # One drawn change among the citation rewrites keeps the gate on.
        mixed = self.pr({self.MOCK: cite_only, ".agents/design/mockups/pages/chores/chores/new.html": "<p>new</p>\n"}, number=10)
        self.assertIn("design decision record", self.refuses(mixed, "design", number="10"))

    def git_remote(self, path):
        return subprocess.run(["git", "-C", str(path), "remote", "get-url", "origin"], capture_output=True, text=True).stdout.strip()

    def test_the_gate_clone_is_pinned_to_the_expected_origin_and_rebuilt_once(self):
        info = self.pr({self.VIEW: "x\n", self.RECORD: self.GOOD})
        self.gate(info, 0.05, env=self.AGENT)
        clone = self.root / "gate" / "origin"
        subprocess.run(["git", "-C", str(clone), "remote", "set-url", "origin", str(self.dir / "elsewhere.git")], check=True)
        self.gate(info, 0.05, env=self.AGENT)  # origin is forced back before the fetch
        self.assertEqual(self.git_remote(clone), str(self.origin))
        shutil.rmtree(clone / ".git" / "objects")  # a corrupt clone: one re-clone, then it works
        self.gate(info, 0.05, env=self.AGENT)
        # a fetch that fails twice fails closed
        real_git = lane_land.git

        def failing(repo, *args, **kw):
            if args[:1] == ("fetch",):
                return mock.Mock(returncode=1, stdout="", stderr="no route")
            return real_git(repo, *args, **kw)
        with mock.patch.object(lane_land, "git", failing):
            self.assertIn("could not fetch", self.refuses(info, "gate", env=self.AGENT))

    def test_a_gate_run_from_the_gate_trusted_clone_uses_it_and_never_preps_it(self):
        info = self.pr({self.VIEW: "x\n", self.RECORD: self.GOOD})
        own = (self.root / "gate-trusted" / "origin")
        own.mkdir(parents=True)
        (own / "marker.txt").write_text("the running gate's own files\n")
        seen = []

        def ask(trusted, qid, text):
            seen.append(trusted)
            return 0.05
        with mock.patch.object(lane_land, "own_checkout", return_value=own.resolve()), \
                mock.patch.object(lane_land, "trusted_gate_clone", side_effect=AssertionError("re-prepared the running clone")), \
                mock.patch.object(lane_land, "prepare_trusted", side_effect=AssertionError("re-fetched the running clone")):
            lane_land.pr_gate("7", info, root=self.root, cfg=self.CFG, gh=lambda a: "", origin=lambda: str(self.origin), env=self.AGENT, ask=ask)
        self.assertEqual(seen, [own.resolve()])
        self.assertEqual((own / "marker.txt").read_text(), "the running gate's own files\n")
        # run from anywhere else, the gate prepares the trusted clone itself
        elsewhere = []
        with mock.patch.object(lane_land, "own_checkout", return_value=self.dir / "invoking"), \
                mock.patch.object(lane_land, "trusted_gate_clone", side_effect=lambda r, o, b: elsewhere.append(b) or own):
            lane_land.pr_gate("7", info, root=self.root, cfg=self.CFG, gh=lambda a: "", origin=lambda: str(self.origin), env=self.AGENT, ask=ask)
        self.assertEqual(elsewhere, [BASE])

    def test_a_locked_gate_does_not_take_the_lock_again(self):
        info = self.pr({self.VIEW: "x\n", self.RECORD: self.GOOD})
        with mock.patch.object(lane_land, "gate_lock", side_effect=AssertionError("deadlock: pr_land already holds the lock")):
            note = lane_land.pr_gate("7", info, root=self.root, cfg=self.CFG, gh=lambda a: "", origin=lambda: str(self.origin),
                                     env=self.AGENT, ask=self.jev(0.05), locked=True)
        self.assertIn("passed", note)

    @contextlib.contextmanager
    def parent_holds_lock(self):
        """Stands in for ``pr_land``: holds ``<root>/gate.lock`` (``flock``) while the body runs."""
        import fcntl
        self.root.mkdir(parents=True, exist_ok=True)
        with open(self.root / "gate.lock", "w") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(handle, fcntl.LOCK_UN)

    def test_lock_held_passes_when_a_parent_holds_the_lock_and_refuses_when_nobody_does(self):
        with self.parent_holds_lock():
            lane_land.require_gate_lock_held(self.root)  # held by the parent: fine
        with self.assertRaises(lane_land.Refused):
            lane_land.require_gate_lock_held(self.root)  # nobody holds it: the flag is a lie
        import fcntl
        with open(self.root / "gate.lock", "w") as other:
            fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)  # the probe released what it took
        err = io.StringIO()
        with mock.patch.object(lane_land, "pr_gate", side_effect=AssertionError("gate ran")), redirect_stderr(err):
            self.assertEqual(lane_land.main(["gate", "--pr", "7", "--lock-held", "--root", str(self.root)]), 2)
        self.assertIn("nobody holds gate.lock", err.getvalue())

    def test_the_cli_clones_product_repo_from_the_config_and_takes_lock_held(self):
        got = {}

        def fake_gate(number, info, **kw):
            got.update(kw, origin_url=kw["origin"]())
            return "ok"
        info = {"baseRefName": BASE, "headRefOid": "a" * 40, "files": []}
        with mock.patch.object(lane_land, "pr_gate", fake_gate), mock.patch.object(lane_land.subprocess, "run", return_value=mock.Mock(
                returncode=0, stdout=json.dumps(info), stderr="")), redirect_stdout(io.StringIO()):
            with self.parent_holds_lock():
                self.assertEqual(lane_land.main(["gate", "--pr", "7", "--lock-held", "--root", str(self.root)]), 0)
        cfg = json.loads((TOOLS / "triage" / "config.json").read_text())
        self.assertEqual(got["origin_url"], f"https://github.com/{cfg['product_repo']}.git")  # never `git remote get-url origin`
        self.assertTrue(got["locked"])
        self.assertEqual(lane_land.product_origin({"product_repo": "o/r"}), "https://github.com/o/r.git")
        for bad in ({}, {"product_repo": "x"}, {"product_repo": "a/b/c"}, {"product_repo": "o/r; id"}):
            with self.subTest(bad=bad), self.assertRaises(lane_land.Refused):
                lane_land.product_origin(bad)

    def test_the_gate_takes_a_per_root_lock(self):
        import fcntl
        with lane_land.gate_lock(self.root):
            with open(self.root / "gate.lock", "w") as other:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with open(self.root / "gate.lock", "w") as other:
            fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)  # released

    def test_the_gate_cli_refuses_a_head_that_is_not_the_one_being_landed(self):
        out = io.StringIO()
        info = {"baseRefName": BASE, "headRefOid": "a" * 40, "files": []}
        with mock.patch.object(lane_land.subprocess, "run", return_value=mock.Mock(returncode=0, stdout=json.dumps(info), stderr="")), \
                redirect_stderr(out):
            self.assertEqual(lane_land.main(["gate", "--pr", "7", "--head", "b" * 40]), 2)
        self.assertIn("not the", out.getvalue())

    def test_a_forged_gate_line_still_has_to_agree_with_jev(self):
        info = self.pr({self.VIEW: "x\n", self.RECORD: self.GOOD.replace("app_wide=no", "app_wide=yes")})
        self.assertIn("must agree", self.refuses(info, "gate", p_yes=0.05, env=self.AGENT))

    def test_the_cli_reports_the_exit_code(self):
        out = io.StringIO()
        with mock.patch.object(lane_land, "pr_gate", side_effect=lane_land.Refused("nope", "design")), \
                mock.patch.object(lane_land.subprocess, "run", return_value=mock.Mock(returncode=0, stdout=json.dumps({}), stderr="")), \
                redirect_stderr(out):
            self.assertEqual(lane_land.main(["gate", "--pr", "7"]), 2)
        self.assertIn("refused (design)", out.getvalue())
        with mock.patch.object(lane_land, "pr_gate", return_value="no app UI changed"), \
                mock.patch.object(lane_land.subprocess, "run", return_value=mock.Mock(returncode=0, stdout=json.dumps({}), stderr="")), \
                redirect_stdout(io.StringIO()):
            self.assertEqual(lane_land.main(["gate", "--pr", "7"]), 0)
        with mock.patch.object(lane_land.subprocess, "run", return_value=mock.Mock(returncode=1, stdout="", stderr="boom")), \
                redirect_stderr(out):
            self.assertEqual(lane_land.main(["gate", "--pr", "7"]), 2)
        self.assertIn("failed closed", out.getvalue())
