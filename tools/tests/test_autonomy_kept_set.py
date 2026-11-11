"""The owner-kept set stays owner-only on every route after the autonomy unlock (owner, 2026-11-07; round-1 review of PR #382).

Credentials, signing, the release pipeline (every file its jobs run) and the review recorder are enforced, not just listed: ``pr_land`` and
``lane_land`` refuse a change to them, the release closure and the import closure of the kept set are derived and checked, going public needs
``tools/go_public.sh``, interactive ``lane_land`` is pinned to the base copy, and a review verdict needs the reviewer's identity.
"""

import io
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parent
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "hooks"))
sys.path.insert(0, str(TOOLS / "review"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import lane_land  # noqa: E402
import merge_guard  # noqa: E402
import pr_land  # noqa: E402
import record  # noqa: E402
import release_closure  # noqa: E402
import review_guard  # noqa: E402
import review_verdict  # noqa: E402
import test_lane_land as tll  # noqa: E402

BASE, g = tll.BASE, tll.g

CONFIG = json.loads((TOOLS / "triage" / "config.json").read_text())
STATIC_KEPT = [*lane_land.DEFAULT_PROTECTED, *CONFIG["protected_paths"]]
#: One example of every kind of path in the kept set.
KEPT_EXAMPLES = (
    "tools/release/x.sh", "tools/release/versioning.py", ".github/workflows/ios-release.yml", ".github/workflows/ios-release-extra.yml",
    "tools/review/record.py", "tools/review/other.py", "tools/review_verdict.py", ".claude/agents/reviewer.md", "tools/hass_creds.sh", "tools/gh_app_token.py",
    "tools/devcap.py", "tools/ci_hygiene.py", "tools/release_closure.py", "tools/hooks/review_guard.py", ".githooks/pre-commit", ".gitmodules",
)


class OneListTests(unittest.TestCase):
    def test_the_config_never_drops_a_built_in_entry_it_overlaps(self):
        for example in KEPT_EXAMPLES:
            with self.subTest(path=example):
                self.assertTrue(lane_land.matches(example, STATIC_KEPT), example)

    def test_protected_set_is_the_one_list_both_routes_use(self):
        merged = lane_land.protected_set(ROOT, {"protected_paths": ["extra/**"]})
        self.assertTrue(set(lane_land.DEFAULT_PROTECTED) <= set(merged))
        self.assertIn("extra/**", merged)
        for rel in release_closure.release_files(ROOT):
            self.assertTrue(lane_land.matches(rel, merged), rel)


class PrLandRouteTests(tll.PrGateTests):
    """Blocker 1: ``pr_land`` (through ``lane_land.pr_gate``, run from the base copy) refuses a pull request that touches the kept set,
    with a pass verdict and every other gate green. The lane route refuses the same paths (``ProtectedPathTests``)."""

    def test_a_pr_touching_each_kind_of_kept_path_is_refused(self):
        for number, rel in enumerate(KEPT_EXAMPLES, start=20):
            with self.subTest(path=rel):
                refused = self.refuses(self.pr({rel: "x\n"}, number=number), "paths", number=str(number))
                self.assertIn("owner-only set", refused)
                self.assertIn(rel, refused)
                self.assertIn(lane_land.OWNER_ONLY_HINT, refused)
        self.assertEqual(self.calls, [])

    def test_a_delete_or_a_rename_away_of_a_kept_file_is_refused_from_the_real_diff(self):
        self.seed_base({"tools/release/x.sh": "x\n", "tools/other.txt": "y\n"})
        sha = self.push_lane("pr/del", {}, delete=["tools/release/x.sh"])
        g(self.dev, "push", "-q", "-f", "origin", f"{sha}:refs/pull/31/head")
        # the file list the API reports for a delete, and for a rename it names only the new path (the old one is the diff's to catch)
        for listed in ("tools/release/x.sh", "tools/other-name.txt"):
            info = {"baseRefName": BASE, "headRefOid": sha, "files": [{"path": listed}], "body": "", "title": "t", "author": {"login": "SFenton"}}
            with self.subTest(listed=listed):
                self.assertIn("tools/release/x.sh", self.refuses(info, "paths", number="31"))

    def test_config_additions_are_enforced_and_the_unlocked_paths_still_pass(self):
        cfg = {**self.CFG, "protected_paths": ["extra/**"]}
        self.assertIn("extra/y", self.refuses(self.pr({"extra/y": "x\n"}, number=40), "paths", number="40", cfg=cfg))
        for number, rel in enumerate(("tools/pr_land.py", "tools/lane_land.py", "tools/hooks/merge_guard.py", ".claude/settings.json",
                                      "tools/triage/config.json", "tools/agent_eval.py"), start=50):
            with self.subTest(path=rel):
                self.assertEqual(self.gate(self.pr({rel: "x\n"}, number=number), number=str(number)), "no app UI changed")

    def test_the_release_closure_is_derived_from_the_trusted_workflow_not_listed_by_hand(self):
        """A file the base's release workflow starts becomes owner-only without a list entry (here a tool the static list does not know)."""
        self.seed_base({".github/workflows/ios-release-extra.yml": "jobs:\n  a:\n    steps:\n      - run: python3 tools/brand_new_step.py\n",
                        "tools/brand_new_step.py": "print(1)\n"})
        with mock.patch.object(lane_land, "own_checkout", return_value=self.dev):
            refused = self.refuses(self.pr({"tools/brand_new_step.py": "evil\n"}, number=60), "paths", number="60")
        self.assertIn("tools/brand_new_step.py", refused)


for _name in [n for n in dir(tll.PrGateTests) if n.startswith("test_") and n not in PrLandRouteTests.__dict__]:
    setattr(PrLandRouteTests, _name, None)  # the inherited tests run in test_lane_land; only the ones above run here


class ReleaseClosureTests(unittest.TestCase):
    """Blocker 2: everything the ``ios-release*`` jobs run or import is in the kept set, derived from the workflow steps."""

    def test_every_file_a_release_step_runs_or_imports_is_protected(self):
        files = release_closure.release_files(ROOT)
        for expected in ("tools/devcap.py", "tools/release/ExportOptions-testflight.plist",
                         "tools/release/ios_ipa_build.sh", "tools/release/versioning.py"):
            self.assertIn(expected, files)
        unprotected = [f for f in files if not lane_land.matches(f, STATIC_KEPT)]
        self.assertEqual(unprotected, [], "a release step runs a file that is not in DEFAULT_PROTECTED / protected_paths")

    def test_an_unprotected_step_is_caught(self):
        with TemporaryDirectory() as name:
            root = Path(name)
            (root / ".github" / "workflows").mkdir(parents=True)
            (root / "tools").mkdir()
            (root / ".github" / "workflows" / "ios-release.yml").write_text(
                "steps:\n  # python3 tools/commented.py\n  - run: python3 tools/helper.py --x\n  - run: bash tools/step.sh\n")
            (root / "tools" / "helper.py").write_text("import sibling\n")
            (root / "tools" / "sibling.py").write_text("X = 1\n")
            (root / "tools" / "step.sh").write_text("#!/bin/sh\npython3 \"$ROOT/tools/via_shell.py\"\n")
            (root / "tools" / "via_shell.py").write_text("import subprocess\nsubprocess.run(['python3', 'tools/launched.py'])\n")
            (root / "tools" / "launched.py").write_text("X = 1\n")
            (root / "tools" / "commented.py").write_text("X = 1\n")
            files = release_closure.release_files(root)
            self.assertEqual(files, ["tools/helper.py", "tools/launched.py", "tools/sibling.py", "tools/step.sh", "tools/via_shell.py"])
            self.assertEqual([f for f in files if not lane_land.matches(f, STATIC_KEPT)], files)  # all of them would fail the real test


class ImportClosureOfTheKeptSetTests(unittest.TestCase):
    """Blocker 2, second half: the recorder, the release tools and the guards they load are protected (so ``record.py`` cannot load a file a
    lane may edit). ``record.py`` used to import ``pr_land.py``; it no longer imports any repository module."""

    STARTS = ("tools/review/record.py", "tools/hooks/review_guard.py", "tools/hass_creds.sh", "tools/gh_app_token.py")

    def starts(self):
        paths = [ROOT / s for s in self.STARTS if (ROOT / s).is_file()]
        paths += sorted((ROOT / "tools" / "release").glob("*.py")) + sorted((ROOT / "tools" / "release").glob("*.sh"))
        return paths + [ROOT / f for f in release_closure.release_files(ROOT)]

    def test_everything_the_kept_set_loads_or_launches_is_protected(self):
        closure = release_closure.closure(ROOT, self.starts())
        unprotected = [f for f in closure if not lane_land.matches(f, STATIC_KEPT)]
        self.assertEqual(unprotected, [], "loaded or launched by the owner-only set but not in it (protect it or break the import)")

    def test_the_recorder_imports_no_landing_tool(self):
        text = (ROOT / "tools" / "review" / "record.py").read_text()
        for name in ("pr_land", "lane_land", "house_scan", "devcap"):
            self.assertNotIn(f"import {name}", text)
            self.assertNotIn(f"from {name} import", text)
        self.assertIn("import gh_app_token", text)  # the one tool the recorder may load: it posts the ai-review check
        self.assertEqual(record.review_file_name("claude/pr-lifecycle"), pr_land.review_file_name("claude/pr-lifecycle"))

    def test_the_review_guard_is_self_contained(self):
        closure = release_closure.closure(ROOT, [ROOT / "tools" / "hooks" / "review_guard.py"])
        self.assertNotIn("tools/hooks/shell_parse.py", closure)
        self.assertEqual([f for f in closure if not lane_land.matches(f, STATIC_KEPT)], [])

    def test_a_new_unprotected_import_would_be_caught(self):
        with TemporaryDirectory() as name:
            root = Path(name)
            (root / "tools" / "review").mkdir(parents=True)
            (root / "tools" / "pr_land.py").write_text("X = 1\n")
            (root / "tools" / "review" / "record.py").write_text("from pr_land import X\n")
            closure = release_closure.closure(root, [root / "tools" / "review" / "record.py"])
            self.assertEqual(closure, ["tools/pr_land.py", "tools/review/record.py"])
            self.assertFalse(lane_land.matches("tools/pr_land.py", STATIC_KEPT))


class ReviewerIdentityTests(unittest.TestCase):
    """Major 2: a verdict needs the reviewer's identity; a forged file does not land, and only the reviewer can write one."""

    ID = {"reviewer": {"agent_type": "reviewer", "session_id": "s-1"}}

    HEAD = "a" * 40

    def store(self, tmp, record):
        folder = Path(tmp)
        (folder / f"agents__x-{self.HEAD[:12]}.json").write_text(json.dumps(record))
        return folder

    def test_the_arm_refuses_a_forged_verdict_in_the_store(self):
        """Fails if: review_verdict.has_pass (the check pr_land arms on) accepts a store file without a valid reviewer identity."""
        forged = {"verdict": "pass", "head": self.HEAD, "findings": []}
        with TemporaryDirectory() as tmp:
            self.assertFalse(review_verdict.has_pass(self.HEAD, self.store(tmp, forged)))
            for bad in ({"agent_type": "coder", "session_id": "s"}, {"agent_type": "reviewer", "session_id": ""}, {"agent_type": "reviewer"},
                        "reviewer", None, ["reviewer"]):
                with self.subTest(identity=bad):
                    self.assertFalse(review_verdict.has_pass(self.HEAD, self.store(tmp, {**forged, "reviewer": bad})))
            self.assertTrue(review_verdict.has_pass(self.HEAD, self.store(tmp, {**forged, **self.ID})))

    def test_a_runner_marker_does_not_stand_in_for_an_identity_on_the_pr_route(self):
        """Fails if: a `recorded_by: runner` marker counts as a reviewer identity in the store pr_land reads."""
        with TemporaryDirectory() as tmp:
            self.assertFalse(review_verdict.has_pass(self.HEAD, self.store(tmp, {"verdict": "pass", "head": self.HEAD, "recorded_by": "runner"})))

    def test_the_store_the_arm_trusts_is_the_one_review_guard_protects(self):
        """Fails if: the verdict store moves or review_guard stops covering it, which would let an agent write its own pass (D2 pin)."""
        store = review_verdict.reviews_dir()
        self.assertEqual(store.parts[-2:], ("hass-agents", "reviews"))
        self.assertTrue(review_guard.REVIEW_PATH.search(str(store / "agents__x-0123456789ab.json")))
        target = str(store / "agents__x-0123456789ab.json")
        for payload in ({"tool_name": "Write", "tool_input": {"file_path": target, "content": "{}"}},
                        {"tool_name": "Edit", "tool_input": {"file_path": target}},
                        {"tool_name": "Bash", "tool_input": {"command": f"echo '{{}}' > {target}"}},
                        {"tool_name": "Bash", "tool_input": {"command": f"cp /tmp/v.json {store}/"}}):
            with self.subTest(tool=payload["tool_name"], command=str(payload["tool_input"])[:40]):
                self.assertIsNotNone(review_guard.reason({**payload, "cwd": str(ROOT), "agent_type": "coder"}))

    def test_interactive_lane_land_refuses_a_forged_verdict_file(self):
        with TemporaryDirectory() as name:
            path = Path(name) / "v.json"
            path.write_text(json.dumps({"verdict": "pass", "head": "a" * 40}))
            with self.assertRaises(lane_land.Refused) as cm:
                lane_land.check_review(path, "a" * 40)
            self.assertIn("no reviewer identity", str(cm.exception))
            path.write_text(json.dumps({"verdict": "pass", "head": "a" * 40, **self.ID}))
            self.assertEqual(lane_land.check_review(path, "a" * 40)["verdict"], "pass")

    def test_record_stamps_the_identity_the_hook_left_and_refuses_without_it(self):
        with TemporaryDirectory() as name:
            stamp = Path(name) / "ident.json"
            now = time.time()
            self.assertIsNone(record.reviewer_identity(stamp, now))
            stamp.write_text(json.dumps({"agent_type": "reviewer", "session_id": "s-7", "cwd": name, "at": now}))
            self.assertEqual(record.reviewer_identity(stamp, now, cwd=name)["session_id"], "s-7")
            for change in ({"agent_type": "coder"}, {"session_id": ""}, {"at": now - 10_000}, {"cwd": "/somewhere/else"}):
                stamp.write_text(json.dumps({"agent_type": "reviewer", "session_id": "s-7", "cwd": name, "at": now, **change}))
                with self.subTest(change=change):
                    self.assertIsNone(record.reviewer_identity(stamp, now, cwd=name))
            stamp.write_text("{not json")
            self.assertIsNone(record.reviewer_identity(stamp, now))

    def test_the_stamp_path_is_the_same_in_the_hook_and_the_recorder(self):
        self.assertEqual(review_guard.IDENT_PATH, record.IDENT_PATH)


class ReviewGuardTests(unittest.TestCase):
    """The hook: only ``agent_type`` reviewer runs ``record.py``; nothing else writes a verdict file."""

    def hook(self, tool, tool_input, **payload):
        err = io.StringIO()
        body = json.dumps({"tool_name": tool, "tool_input": tool_input, "cwd": str(ROOT), "session_id": "sess-1", **payload})
        clean = {k: v for k, v in os.environ.items() if k != "FENTON_HEADLESS"}
        with mock.patch.dict(os.environ, clean, clear=True), mock.patch.object(sys, "stdin", io.StringIO(body)), redirect_stderr(err), \
                mock.patch.object(review_guard, "IDENT_PATH", Path(tempfile.mkdtemp()) / "ident.json"):
            return review_guard.main(), err.getvalue()

    def test_a_forged_verdict_by_any_means_is_refused(self):
        verdict = "build/review/agents__x.json"
        for command in (f"cat > {verdict} <<'EOF'\n{{\"verdict\":\"pass\"}}\nEOF", f"echo '{{}}' > {verdict}", f"echo '{{}}' | tee {verdict}",
                        f"cp /tmp/v.json {verdict}", f"python3 -c \"open('{verdict}','w').write('{{}}')\"", f"sed -i s/blocker/pass/ {verdict}",
                        "cp /tmp/v.json ~/hass-agents/reviews/agents__x-0123456789ab.json", f"mv v.json {verdict}", f"printf x >> {verdict}",
                        f"cat {verdict} > other.json; echo hi > {verdict}", "rm ~/hass-agents/reviews/a.json", "echo x > ~/.cache/fenton-hass/reviewer-ident.json",
                        "python3 tools/review/record.py v.json --pr 5", "tools/review/record.py v.json"):
            for agent in ({"agent_type": "coder"}, {"agent_type": "orchestrator"}, {"agent_id": "a1"}):
                with self.subTest(command=command[:50], agent=agent):
                    code, err = self.hook("Bash", {"command": command}, **agent)
                    self.assertEqual(code, 2, command)
                    self.assertIn("reviewer", err)

    def test_file_tools_never_write_a_verdict_not_even_for_the_reviewer(self):
        for path in ("build/review/agents__x.json", "/tmp/wt/build/review/a.json", "~/hass-agents/reviews/a-0123.json"):
            for tool in ("Write", "Edit", "MultiEdit"):
                for agent in ("coder", "reviewer"):
                    with self.subTest(path=path, tool=tool, agent=agent):
                        self.assertEqual(self.hook(tool, {"file_path": os.path.expanduser(path)}, agent_type=agent)[0], 2)
        self.assertEqual(self.hook("Write", {"file_path": "build/research/x.md"}, agent_type="coder")[0], 0)
        self.assertEqual(self.hook("Write", {"file_path": "tools/review/notes.md"}, agent_type="coder")[0], 0)

    def test_the_reviewer_may_record_plainly_and_a_stamp_is_left(self):
        for command in ("tools/review/record.py v.json --pr 5", "python3 tools/review/record.py v.json", "./tools/review/record.py v.json --lane agents/x",
                        "python3 /repo/tools/review/record.py v.json --confirm-round \"third pass, no blockers\"",
                        "tools/review/record.py - --pr 5 <<'EOF'\n{\"verdict\":\"pass\"}\nEOF"):
            with self.subTest(command=command[:40]):
                with TemporaryDirectory() as name:
                    ident = Path(name) / "ident.json"
                    err = io.StringIO()
                    body = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(ROOT), "session_id": "sess-9",
                                       "agent_type": "reviewer"})
                    with mock.patch.object(sys, "stdin", io.StringIO(body)), redirect_stderr(err), mock.patch.object(review_guard, "IDENT_PATH", ident):
                        self.assertEqual(review_guard.main(), 0, err.getvalue())
                    saved = json.loads(ident.read_text())
                    self.assertEqual((saved["agent_type"], saved["session_id"]), ("reviewer", "sess-9"))

    def test_the_reviewer_may_record_for_a_worktree_from_any_cwd_and_the_stamp_names_it(self):
        with TemporaryDirectory() as name:
            wt = Path(name).resolve() / "wt"
            wt.mkdir()
            cases = {f"cd {wt} && python3 tools/review/record.py v.json --pr 5": wt,
                     f"python3 tools/review/record.py v.json --pr 5 --root {wt}": wt,
                     f"cd {name} && python3 tools/review/record.py v.json --root wt": wt,
                     f"python3 tools/review/record.py --root={wt} - <<'EOF'\n{{}}\nEOF": wt}
            for command, where in cases.items():
                with self.subTest(command=command[:60]):
                    ident = Path(name) / "ident.json"
                    err = io.StringIO()
                    body = json.dumps({"tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(ROOT), "session_id": "s", "agent_type": "reviewer"})
                    with mock.patch.object(sys, "stdin", io.StringIO(body)), redirect_stderr(err), mock.patch.object(review_guard, "IDENT_PATH", ident):
                        self.assertEqual(review_guard.main(), 0, err.getvalue())
                    self.assertEqual(json.loads(ident.read_text())["cwd"], str(where))
            for command in (f"cd {wt} && cd /tmp && tools/review/record.py v.json", f"cd {wt}; tools/review/record.py v.json", "cd $HOME && tools/review/record.py v.json",
                            f"cd {wt} && tools/review/record.py v.json && echo x"):
                with self.subTest(command=command[:60]):
                    self.assertEqual(self.hook("Bash", {"command": command}, agent_type="reviewer")[0], 2)

    def test_the_primary_checkout_cannot_stamp_a_pr_on_another_branch(self):
        """The coordinator sits in the primary checkout (branch main): the stamp it can get names that directory, and record.py refuses a PR whose head
        branch is another one, so no verdict lands on the wrong branch."""
        with TemporaryDirectory() as name:
            repo = Path(name) / "primary"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
            g(repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "x")
            verdict = Path(name) / "v.json"
            verdict.write_text(json.dumps({"verdict": "pass", "findings": []}))
            stamp = Path(name) / "ident.json"
            stamp.write_text(json.dumps({"agent_type": "reviewer", "session_id": "s", "cwd": str(repo), "at": time.time()}))
            gh = subprocess.CompletedProcess([], 0, stdout=json.dumps({"headRefName": "agents/other"}), stderr="")
            err = io.StringIO()
            real_run = subprocess.run
            with mock.patch.object(record, "IDENT_PATH", stamp), mock.patch.object(record.subprocess, "run", side_effect=lambda cmd, **kw: gh if cmd[0] == "gh" else real_run(cmd, **kw)), \
                    redirect_stderr(err):
                code = record.main([str(verdict), "--pr", "7", "--root", str(repo)])
            self.assertEqual(code, 2)
            self.assertIn("agents/other", err.getvalue())
            self.assertFalse((repo / "build" / "review").exists())

    def test_a_mention_of_a_review_path_in_a_message_add_or_body_is_not_a_write(self):
        for command in ("git commit -m 'review guard now covers build/review verdicts'", "git add build/review/agents__x.json",
                        "gh pr create --title t --body 'the verdict goes in build/review/x.json'", "gh issue comment 5 --body \"see ~/hass-agents/reviews\"",
                        "git commit -F - <<'EOF'\nmentions build/review/a.json\nEOF", "gh pr create --body-file - <<'EOF'\nbuild/review/a.json\nEOF",
                        "gh pr create --body \"$(cat <<'EOF'\nbuild/review/a.json\nEOF\n)\""):
            with self.subTest(command=command[:50]):
                self.assertEqual(self.hook("Bash", {"command": command}, agent_type="coder")[0], 0, command)

    def test_reads_that_only_name_record_py_are_not_running_it(self):
        for command in ("cat tools/review/record.py", "grep -n round tools/review/record.py", "git add tools/review/record.py",
                        "git show abc1234:tools/review/record.py", "git diff origin/main -- tools/review/record.py", "head -20 tools/review/record.py",
                        "wc -l tools/review/record.py"):
            for agent in ("coder", "reviewer"):
                with self.subTest(command=command, agent=agent):
                    self.assertEqual(self.hook("Bash", {"command": command}, agent_type=agent)[0], 0, command)
        self.assertEqual(self.hook("Bash", {"command": "python3 tools/review/record.py v.json"}, agent_type="coder")[0], 2)
        self.assertEqual(self.hook("Bash", {"command": "bash tools/review/record.py v.json"}, agent_type="coder")[0], 2)

    def test_an_interpreter_heredoc_that_writes_a_verdict_is_refused(self):
        verdict = "build/review/agents__x.json"
        for command in (f"python3 - <<'EOF'\nopen('{verdict}','w').write('{{}}')\nEOF", f"python3 <<EOF\nimport pathlib\npathlib.Path('{verdict}').write_text('x')\nEOF",
                        f"node - <<'EOF'\nrequire('fs').writeFileSync('{verdict}','{{}}')\nEOF", f"bash <<'EOF'\necho x > ~/hass-agents/reviews/a.json\nEOF",
                        f"cd wt && python3 - <<'EOF'\nopen('{verdict}','w')\nEOF"):
            with self.subTest(command=command[:40]):
                self.assertEqual(self.hook("Bash", {"command": command}, agent_type="coder")[0], 2, command)
        self.assertEqual(self.hook("Bash", {"command": "python3 - <<'EOF'\nprint(1)\nEOF"}, agent_type="coder")[0], 0)

    def test_the_reviewer_may_not_chain_or_redirect_around_record(self):
        for command in ("tools/review/record.py v.json; rm -rf build", "tools/review/record.py v.json && echo '{}' > build/review/a.json",
                        "tools/review/record.py v.json > build/review/a.json", "cat v.json | tools/review/record.py -",
                        "tools/review/record.py $(cat args)", "tools/review/record.py - <<'EOF'\n{}\nEOF\nrm -rf x"):
            with self.subTest(command=command[:40]):
                self.assertEqual(self.hook("Bash", {"command": command}, agent_type="reviewer")[0], 2)

    def test_plain_reads_and_ordinary_work_pass_and_the_owner_is_never_blocked(self):
        for command in ("cat build/review/agents__x.json", "ls build/review", "jq .verdict build/review/a.json", "grep -r verdict build/review",
                        "tools/pr_land.sh 5 --dry-run --review build/review/a.json", "git status", "python3 tools/jev_hints.py review --pr 5"):
            with self.subTest(command=command):
                self.assertEqual(self.hook("Bash", {"command": command}, agent_type="coder")[0], 0, command)
        code, _ = self.hook("Bash", {"command": "echo x > build/review/a.json"})  # a plain owner session
        self.assertEqual(code, 0)

    def test_the_hook_is_wired_for_bash_and_the_file_tools(self):
        settings = json.loads((ROOT / ".claude" / "settings.json").read_text())
        for matcher in ("Bash", "Edit|Write|MultiEdit|NotebookEdit"):
            entry = next(m for m in settings["hooks"]["PreToolUse"] if m["matcher"] == matcher)
            self.assertTrue(any("review_guard.py" in h["command"] for h in entry["hooks"]), matcher)


class LaneLandPinTests(unittest.TestCase):
    """Major 3: an agent runs the lander only from a checkout whose ``lane_land.py`` (and what it loads, and the config) equal the base's."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="lane-pin-")).resolve()
        self.addCleanup(__import__("shutil").rmtree, self.dir, ignore_errors=True)
        self.repo = self.dir / "repo"
        (self.repo / "tools" / "triage").mkdir(parents=True)
        subprocess.run(["git", "init", "-q", "-b", "main", str(self.repo)], check=True)
        for name in ("lane_land.py", "release_closure.py", "agent_eval_measure.py", "request_repo.py", "agent_login.py", "go_public.sh", "go_public_gate.py", "house_scan.py", "pr_land.sh", "pr_land.py"):
            (self.repo / "tools" / name).write_text(f"# {name}\n")
        (self.repo / "tools" / "triage" / "config.json").write_text("{}\n")
        g(self.repo, "add", "-A")
        g(self.repo, "commit", "-qm", "base")
        g(self.repo, "update-ref", "refs/remotes/origin/main", "HEAD")
        for patch in (mock.patch.dict(os.environ, {"FENTON_HEADLESS": "0"}), mock.patch.object(merge_guard, "base_refs", return_value=["main"])):
            patch.start()
            self.addCleanup(patch.stop)

    def why(self, command, agent=True):
        return merge_guard.reason(command, str(self.repo), agent=agent)

    def test_a_matching_copy_runs_and_an_edited_one_is_refused(self):
        command = "python3 tools/lane_land.py agents/x --into main --dry-run"
        self.assertIsNone(self.why(command))
        for name in ("lane_land.py", "release_closure.py", "agent_eval_measure.py", "request_repo.py", "agent_login.py", "triage/config.json"):
            with self.subTest(name=name):
                path = self.repo / "tools" / name
                original = path.read_text()
                path.write_text(original + "# edited\n")
                self.assertIn("differs from origin", self.why(command) or "")
                self.assertIsNone(self.why(command, agent=False), "the owner's plain session is not checked")
                path.write_text(original)
                self.assertIsNone(self.why(command))

    def test_every_way_to_start_it_is_checked(self):
        (self.repo / "tools" / "lane_land.py").write_text("# edited\n")
        for command in ("python3 tools/lane_land.py agents/x --into main", "python3 ./tools/lane_land.py agents/x --into main", "tools/lane_land.py agents/x --into main",
                        f"python3 {self.repo}/tools/lane_land.py agents/x --into main", "cd tools && python3 lane_land.py agents/x --into main",
                        "env X=1 python3 tools/lane_land.py agents/x --into main"):
            with self.subTest(command=command):
                self.assertIn("differs from origin", self.why(command) or "")
        self.assertIsNone(self.why("grep lane_land tools/pr_land.py"))
        self.assertIsNone(self.why("git commit -m 'edit lane_land.py'"))


class GoPublicGuardTests(unittest.TestCase):
    """Blocker 3: every way of going public except ``tools/go_public.sh SNAPSHOT OWNER/REPO`` is refused."""

    def why(self, command, cwd=None, agent=False):
        return merge_guard.reason(command, str(cwd) if cwd else None, agent=agent)

    def test_each_way_the_reviewer_found_is_refused(self):
        for command in ("gh repo create SFenton/pub --public --source . --push", "gh repo create pub --public", "gh repo create pub --internal",
                        "gh repo edit SFenton/pub --visibility public", "gh repo edit --visibility=public --accept-visibility-change-consequences",
                        "gh repo edit --visibility internal", "gh repo edit pub --visibility",
                        "gh api -X PATCH repos/SFenton/pub -f private=false", "gh api repos/SFenton/pub --method PATCH -f visibility=public",
                        "gh api repos/SFenton/pub -X PATCH --input body.json -F private=false",
                        "gh api graphql -f query='mutation { updateRepository(input:{repositoryId:\"X\", visibility: PUBLIC}) { clientMutationId } }'",
                        "echo ok; gh repo edit pub --visibility public", "bash -c 'gh repo edit pub --visibility public'"):
            with self.subTest(command=command):
                self.assertIn("going public", self.why(command) or "")

    def test_reads_private_creates_and_unrelated_work_pass(self):
        for command in ("gh repo create pub --private --source . --push", "gh repo edit pub --visibility private", "gh repo view SFenton/pub --json visibility",
                        "gh api repos/SFenton/pub --jq .visibility", "gh api graphql -f query='query { viewer { login } }'", "gh repo list",
                        "git commit -m 'gh repo create x --public in prose'"):
            with self.subTest(command=command):
                self.assertNotIn("going public", self.why(command) or "")

    def test_a_push_to_another_remote_is_refused(self):
        with TemporaryDirectory() as name:
            repo = Path(name) / "repo"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
            g(repo, "remote", "add", "origin", "git@github.com:SFenton/native-home.git")
            g(repo, "remote", "add", "pub", "https://github.com/SFenton/pub.git")
            g(repo, "remote", "add", "web", "https://github.com/owner/private-app")
            for command in ("git push pub HEAD:agents/x", "git push pub --all", "git push --mirror pub", "git push https://github.com/SFenton/pub.git HEAD",
                            "git push git@github.com:SFenton/pub.git HEAD:agents/x", "git push --repo=pub", "git push --repo pub", "git push git@github.com:owner/private-app.git HEAD", "git push /tmp/elsewhere.git HEAD",
                            "git -C ../other push origin HEAD", "git push '$R' HEAD", "git push web agents/z"):
                cwd = repo
                if command.startswith("git -C ../other"):
                    other = Path(name) / "other"
                    other.mkdir()
                    subprocess.run(["git", "init", "-q", "-b", "main", str(other)], check=True)
                    g(other, "remote", "add", "origin", "https://github.com/SFenton/pub.git")
                    cwd = repo
                    command = f"git -C {other} push origin HEAD"
                with self.subTest(command=command):
                    self.assertIn("going public", self.why(command, cwd) or "", command)
            for command in ("git push origin agents/x", "git push", "git push -u origin HEAD:agents/y", "git fetch pub",
                            "git push --dry-run origin agents/x", "git push --force-with-lease origin agents/x"):
                with self.subTest(command=command):
                    self.assertNotIn("going public", self.why(command, repo) or "", command)

    def test_remote_rewrites_and_public_gists_are_refused_as_a_whole_command(self):
        for command in ("git remote add pub https://github.com/SFenton/x.git && git push pub --all", "git remote set-url origin https://github.com/o/x.git && git push origin agents/x",
                        "git remote rename origin old", "git -c remote" + ".origin.url=https://github.com/o/x.git push origin agents/x",
                        "git -c url.https://github.com/o/.insteadOf=https://github.com/SFenton/ push origin agents/x",
                        "git config remote\x2eorigin.url https://github.com/o/x.git && git push origin agents/x",
                        "git config remote\x2eorigin.pushurl https://github.com/o/x.git; git push",
                        "git config --local 'remote\x2eorigin.url' https://github.com/o/x.git && git push origin agents/x",
                        "git config url.https://github.com/o/.insteadOf https://github.com/SFenton/ && git push origin agents/x",
                        "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote\x2eorigin.url GIT_CONFIG_VALUE_0=https://github.com/o/x.git git push origin agents/x",
                        "GIT_CONFIG_PARAMETERS=\"'remote\x2eorigin.url=https://github.com/o/x.git'\" git push origin agents/x",
                        "export GIT_CONFIG_KEY_0=remote\x2eorigin.pushurl && git push origin agents/x",
                        "gh gist create --public FILE", "gh gist create -p FILE", "gh gist edit abc123 --public"):
            with self.subTest(command=command):
                self.assertIn("going public", self.why(command) or "", command)
        self.assertNotIn("going public", self.why("gh gist create FILE") or "")
        self.assertNotIn("going public", self.why("git remote -v") or "")
        for read in ("git config --get remote\x2eorigin.url", "git config remote\x2eorigin.url", "git config --list", "git config user.name x"):
            with self.subTest(read=read):
                self.assertNotIn("going public: git config", self.why(read) or "", read)

    def test_a_push_when_origin_does_not_resolve_is_refused(self):
        with TemporaryDirectory() as name:
            repo = Path(name) / "repo"
            repo.mkdir()
            subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
            self.assertIn("going public", self.why("git push origin agents/x", repo) or "")

    def test_go_public_runs_only_in_its_exact_form_and_from_the_base_copy(self):
        with TemporaryDirectory() as name:
            repo = Path(name) / "repo"
            (repo / "tools" / "triage").mkdir(parents=True)
            subprocess.run(["git", "init", "-q", "-b", "main", str(repo)], check=True)
            for rel in ("go_public.sh", "go_public_gate.py", "house_scan.py"):
                (repo / "tools" / rel).write_text(f"# {rel}\n")
            (repo / "tools" / "triage" / "config.json").write_text("{}\n")
            g(repo, "add", "-A")
            g(repo, "commit", "-qm", "base")
            g(repo, "update-ref", "refs/remotes/origin/main", "HEAD")
            with mock.patch.object(merge_guard, "base_refs", return_value=["main"]), mock.patch.dict(os.environ, {"FENTON_HEADLESS": "0"}):
                self.assertIsNone(self.why("tools/go_public.sh /tmp/snap SFenton/pub", repo, agent=True))
                self.assertIsNone(self.why(f"{repo}/tools/go_public.sh /tmp/snap SFenton/pub", repo, agent=True))
                for command in ("tools/go_public.sh /tmp/snap SFenton/pub --skip-gate", "tools/go_public.sh", "tools/go_public.sh /tmp/snap",
                                "tools/go_public.sh /tmp/snap SFenton/pub; echo", "bash tools/go_public.sh /tmp/snap SFenton/pub",
                                "env X=1 tools/go_public.sh /tmp/snap SFenton/pub", "tools/go_public.sh $(pwd) SFenton/pub"):
                    with self.subTest(command=command):
                        self.assertIn("going public", self.why(command, repo, agent=True) or "")
                for rel in ("go_public.sh", "go_public_gate.py", "house_scan.py", "triage/config.json"):
                    path = repo / "tools" / rel
                    original = path.read_text()
                    path.write_text(original + "# edited\n")
                    with self.subTest(edited=rel):
                        self.assertIn("differs from origin", self.why("tools/go_public.sh /tmp/snap SFenton/pub", repo, agent=True) or "")
                    path.write_text(original)

    def test_the_script_runs_the_gate_before_it_creates_pushes_or_publishes(self):
        text = (TOOLS / "go_public.sh").read_text()
        order = [text.index(marker) for marker in ("go_public_gate.py", "gh repo create", "push \"https://github.com", "--visibility public")]
        self.assertEqual(order, sorted(order))
        self.assertIn("set -euo pipefail", text)
        self.assertIn("--private", text.split("gh repo create", 1)[1].split("\n", 1)[0])
        self.assertNotIn("--public", text.split("gh repo create", 1)[1].split("\n", 1)[0])

    def test_the_script_refuses_bad_targets_before_anything_runs(self):
        with TemporaryDirectory() as name:
            snap = Path(name) / "snap"
            snap.mkdir()
            origin = subprocess.run(["git", "-C", str(ROOT), "remote", "get-url", "origin"], capture_output=True, text=True).stdout
            own = origin.strip().split("github.com", 1)[-1].lstrip(":/").removesuffix(".git") or "owner/own-repo"
            for target in ("not-a-slug", own, "Owner/Private-Requests", "a/b/c"):
                proc = subprocess.run(["bash", str(TOOLS / "go_public.sh"), str(snap), target], capture_output=True, text=True,
                                      env=dict(os.environ, FENTON_REQUEST_REPO="owner/private-requests"))
                with self.subTest(target=target):
                    self.assertEqual(proc.returncode, 2, proc.stderr)


class RealSettingsTests(unittest.TestCase):
    def test_the_gate_hooks_are_still_registered(self):
        settings = json.loads((ROOT / ".claude" / "settings.json").read_text())
        bash = next(m for m in settings["hooks"]["PreToolUse"] if m["matcher"] == "Bash")
        names = " ".join(h["command"] for h in bash["hooks"])
        for hook in ("merge_guard.py", "signing_guard.py", "review_guard.py"):
            self.assertIn(hook, names)


if __name__ == "__main__":
    unittest.main()
