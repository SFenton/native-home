"""``tools/studio_land.py`` (stubbed ``gh``), the merge guard's one Studio allow-shape, and the recorded pass a Studio head needs."""

import io
import json
import os
import subprocess
import sys
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / "hooks"))
sys.path.insert(0, str(TOOLS / "review"))
import merge_guard  # noqa: E402
import pr_land  # noqa: E402
import record  # noqa: E402
import review_verdict  # noqa: E402
import studio_land  # noqa: E402

HEAD = "a" * 40
REPO = "SFenton/ha-native-home-app"
GREEN = [{"name": "checks", "status": "completed", "conclusion": "success"},
         {"name": "e2e (1/8)", "status": "completed", "conclusion": "success"},
         {"name": "container", "status": "completed", "conclusion": "skipped"},
         {"name": "studio", "status": "completed", "conclusion": "success"}]
ENV = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
       "GIT_COMMITTER_EMAIL": "t@t", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null"}


def view(**changes):
    info = {"state": "OPEN", "isDraft": False, "headRefName": "agents/x", "headRefOid": HEAD, "mergeable": "MERGEABLE", "baseRefName": "main",
            "labels": [], "author": {"login": "SFenton"}, "isCrossRepository": False}
    info.update(changes)
    return info


class Stub:
    """A stand-in for ``studio_land.run``: records every argv and answers the ``gh`` reads the tool makes."""

    def __init__(self, info=None, files=("Sources/A.swift",), runs=GREEN, merged=True, merge_code=0):
        self.info, self.files, self.runs, self.merged, self.merge_code = info or view(), list(files), runs, merged, merge_code
        self.calls = []

    def __call__(self, args, check=True):
        self.calls.append(list(args))
        out = ""
        if args[:3] == ["gh", "pr", "view"]:
            out = json.dumps(view(state="MERGED") if args[-1] == "state" and self.merged and self.merged_called() else self.info)
        elif args[:2] == ["gh", "api"]:
            out = "\n".join(self.files) if "/files" in args[2] else "\n".join(json.dumps(r) for r in self.runs)
        code = self.merge_code if args[:3] == ["gh", "pr", "merge"] else 0
        return subprocess.CompletedProcess(args, code, out, "boom" if code else "")

    def merged_called(self):
        return any(c[:3] == ["gh", "pr", "merge"] for c in self.calls)

    def merges(self):
        return [c for c in self.calls if c[:3] == ["gh", "pr", "merge"]]


class LandTests(unittest.TestCase):
    def land(self, stub, passed=True, paused=None, dry_run=False, cfg=None):
        with mock.patch.object(studio_land, "run", stub), mock.patch.object(studio_land, "kill_switch", return_value=paused), \
                mock.patch.object(review_verdict, "has_pass", return_value=passed) as has_pass, \
                mock.patch.object(pr_land, "load_config", return_value=cfg or {}):
            result = studio_land.land("7", dry_run)
        self.has_pass = has_pass
        return result

    def assert_blocked(self, stub, text, **kwargs):
        code, line = self.land(stub, **kwargs)
        self.assertEqual(code, 1, line)
        self.assertTrue(line.startswith("blocked #7"), line)
        self.assertIn(text, line)
        self.assertEqual(stub.merges(), [], "a blocked pull request must not reach gh pr merge")

    def test_green_pull_request_is_squash_merged_pinned_to_the_verified_head(self):
        """Fails if: the merge argv gains --auto, --admin or --delete-branch, loses the pin, or is not squash."""
        stub = Stub()
        code, line = self.land(stub)
        self.assertEqual((code, line), (0, f"merged #7 at {HEAD[:8]}"))
        self.assertEqual(stub.merges(), [["gh", "pr", "merge", "7", "-R", REPO, "--squash", "--match-head-commit", HEAD]])
        self.has_pass.assert_called_once_with(HEAD)

    def test_dry_run_merges_nothing(self):
        """Fails if: --dry-run reaches gh pr merge or gh pr ready."""
        stub = Stub(info=view(isDraft=True))
        code, line = self.land(stub, dry_run=True)
        self.assertEqual((code, line), (0, f"would merge #7 at {HEAD[:8]}"))
        self.assertEqual([c for c in stub.calls if c[:3] in (["gh", "pr", "merge"], ["gh", "pr", "ready"])], [])

    def test_a_draft_is_marked_ready_first(self):
        """Fails if: a draft is merged without being marked ready, or ready runs after the merge."""
        stub = Stub(info=view(isDraft=True))
        self.assertEqual(self.land(stub)[0], 0)
        kinds = [c[2] for c in stub.calls if c[:2] == ["gh", "pr"] and c[2] in ("ready", "merge")]
        self.assertEqual(kinds, ["ready", "merge"])

    def test_every_merge_is_pinned_to_a_head_read_from_this_pull_request(self):
        """Fails if: the merge uses a head other than the one the pass and the checks were read for."""
        other = "b" * 40
        stub = Stub(info=view(headRefOid=other))
        self.land(stub)
        self.has_pass.assert_called_once_with(other)
        self.assertEqual(stub.merges()[0][-1], other)
        self.assertIn(f"commits/{other}/check-runs", " ".join(stub.calls[-3]))

    def test_kill_switch(self):
        self.assert_blocked(Stub(), "landing paused (/x/NO_LAND)", paused="/x/NO_LAND")

    def test_not_open_foreign_author_fork_base_conflict_label(self):
        for info, text in ((view(state="MERGED"), "merged"), (view(state="CLOSED"), "closed"),
                           (view(author={"login": "mallory"}), "author 'mallory'"), (view(author=None), "author None"),
                           (view(isCrossRepository=True), "fork"), (view(isCrossRepository=None), "fork"),
                           (view(baseRefName="release"), "the base is release"), (view(mergeable="CONFLICTING"), "conflicts"),
                           (view(labels=[{"name": "Needs Decision"}]), "Needs Decision")):
            with self.subTest(text=text):
                self.assert_blocked(Stub(info=info), text)

    def test_an_owner_path_blocks_the_merge(self):
        """Fails if: a change to the release pipeline or its inputs (a directory entry, an exact file, or a rename away from one) can be merged by the agent."""
        for path in (".github/workflows/ci.yml", "Dockerfile", "scripts/release.ts", "scripts/next-version.ts", "CHANGELOG.md", "config.yaml",
                     "package.json", "package-lock.json"):
            with self.subTest(path=path):
                self.assert_blocked(Stub(files=["Sources/A.swift", path]), path)
        self.assert_blocked(Stub(files=["Sources/B.swift", ".github/workflows/old.yml"]), ".github/workflows/old.yml")

    def test_owner_paths_match_directories_by_prefix_and_files_exactly(self):
        """Fails if: a file merely named like an owner file (a nested package.json, Dockerfile.dev) blocks, or a .github/ file does not."""
        owned = studio_land.owner_paths({})
        self.assertEqual(studio_land.owner_hits(["src/package.json", "Dockerfile.dev", "docs/CHANGELOG.md", "scripts/other.ts", ".githubx/a"], owned), [])
        self.assertEqual(studio_land.owner_hits([".github/a/b.yml", "Dockerfile"], owned), [".github/a/b.yml", "Dockerfile"])
        self.assertEqual(studio_land.owner_paths({"studio_owner_paths": ["x/", "y.txt"]}), ["x/", "y.txt"])
        for bad in ("x", [], [""], [1]):
            self.assertEqual(studio_land.owner_paths({"studio_owner_paths": bad}), studio_land.DEFAULT_OWNER_PATHS)
        self.assertEqual(studio_land.owner_paths(), studio_land.DEFAULT_OWNER_PATHS)  # the real config has no such key: the defaults apply
        self.assertEqual(studio_land.DEFAULT_OWNER_PATHS, [".github/", "Dockerfile", "scripts/release.ts", "scripts/next-version.ts", "CHANGELOG.md",
                                                           "config.yaml", "package.json", "package-lock.json"])

    def test_the_allow_entries_match_pr_land(self):
        """Fails if: studio_land.py loses the settings allow entries pr_land.sh has, so the route stops running unattended."""
        allow = json.loads((TOOLS.parent / ".claude/settings.json").read_text())["permissions"]["allow"]
        for entry in ("Bash(tools/studio_land.py:*)", "Bash(./tools/studio_land.py:*)"):
            self.assertIn(entry, allow)

    def test_the_refusal_message_names_both_landers(self):
        """Fails if: a refused merge still points a Studio pull request at pr_land.sh only."""
        self.assertIn("tools/studio_land.py N", merge_guard.MESSAGE)
        self.assertIn("tools/pr_land.sh N", merge_guard.MESSAGE)

    def test_no_pass_stale_head_or_a_pass_for_another_sha(self):
        """Fails if: a missing pass, a pass for an earlier head (the head moved after it) or one for another sha lets the merge through."""
        self.assert_blocked(Stub(), "no independent pass for " + HEAD[:12], passed=False)
        with TemporaryDirectory() as tmp:  # the real reader: a record for another sha does not count for this head
            (Path(tmp) / f"agents__x-{'c' * 12}.json").write_text(json.dumps({"verdict": "pass", "head": "c" * 40, "findings": [],
                                                                               "reviewer": {"agent_type": "reviewer", "session_id": "s"}}))
            stub = Stub()
            with mock.patch.object(studio_land, "run", stub), mock.patch.object(studio_land, "kill_switch", return_value=None), \
                    mock.patch.object(review_verdict, "reviews_dir", return_value=Path(tmp)):
                code, line = studio_land.land("7", False)
            self.assertEqual(code, 1, line)
            self.assertIn("no independent pass", line)
            self.assertEqual(stub.merges(), [])

    def test_failing_pending_or_absent_checks(self):
        """Fails if: one e2e shard failing or pending, a cancelled run, or a missing ``studio`` run lets the merge through."""
        shard = {"name": "e2e (3/8)"}
        cases = (({**shard, "status": "completed", "conclusion": "failure"}, "e2e (3/8) (failure)"),
                 ({**shard, "status": "in_progress", "conclusion": None}, "e2e (3/8) (in_progress)"),
                 ({**shard, "status": "queued", "conclusion": None}, "e2e (3/8) (queued)"),
                 ({**shard, "status": "completed", "conclusion": "cancelled"}, "e2e (3/8) (cancelled)"),
                 ({**shard, "status": "completed", "conclusion": "timed_out"}, "e2e (3/8) (timed_out)"))
        for bad, text in cases:
            with self.subTest(text=text):
                self.assert_blocked(Stub(runs=GREEN + [bad]), text)
        self.assert_blocked(Stub(runs=[r for r in GREEN if r["name"] != "studio"]), "absent on this head: studio")
        self.assert_blocked(Stub(runs=[]), "absent on this head: studio")

    def test_neutral_and_skipped_hold_nothing(self):
        stub = Stub(runs=GREEN + [{"name": "lint", "status": "completed", "conclusion": "neutral"}])
        self.assertEqual(self.land(stub)[0], 0)

    def test_required_checks_come_from_the_config_and_default_to_studio(self):
        """Fails if: studio_required_checks is ignored, or a malformed value empties the requirement."""
        self.assertEqual(studio_land.required_checks({}), ["studio"])
        for bad in ("studio", [], [""], [1], None):
            self.assertEqual(studio_land.required_checks({"studio_required_checks": bad}), ["studio"], bad)
        self.assertEqual(studio_land.required_checks({"studio_required_checks": ["studio", "e2e (1/8)"]}), ["studio", "e2e (1/8)"])
        self.assertEqual(studio_land.required_checks(), ["studio"])  # the real config has no such key: the default applies
        self.assert_blocked(Stub(), "absent on this head: extra", cfg={"studio_required_checks": ["studio", "extra"]})

    def test_a_refused_merge_fails_and_an_unmerged_pull_request_fails(self):
        code, line = self.land(Stub(merge_code=1))
        self.assertEqual(code, 2)
        self.assertTrue(line.startswith("failed #7: GitHub refused: boom"), line)
        code, line = self.land(Stub(merged=False))
        self.assertEqual(code, 2)
        self.assertIn("not merged", line)

    def test_main_prints_one_line_and_maps_errors_to_failed(self):
        out = io.StringIO()
        with mock.patch.object(studio_land, "land", return_value=(1, "blocked #7: x")), redirect_stdout(out):
            self.assertEqual(studio_land.main(["#7", "--dry-run"]), 1)
        self.assertEqual(out.getvalue(), "blocked #7: x\n")
        out = io.StringIO()
        with mock.patch.object(studio_land, "land", side_effect=RuntimeError("gh down")), redirect_stdout(out):
            self.assertEqual(studio_land.main(["7"]), 2)
        self.assertEqual(out.getvalue(), "failed #7: gh down\n")
        with redirect_stdout(out):
            self.assertEqual(studio_land.main(["7; true"]), 2)

    def test_the_repository_is_fixed_and_pr_land_is_the_shared_source(self):
        """Fails if: the tool can be pointed at another repository, or copies the helpers instead of importing them."""
        self.assertEqual(studio_land.STUDIO_REPO, REPO)
        self.assertIs(studio_land.run, pr_land.run)
        self.assertIs(studio_land.kill_switch, pr_land.kill_switch)
        self.assertIs(studio_land.author_ok, pr_land.author_ok)
        self.assertNotIn("--auto", studio_land.merge_command("7", HEAD))
        self.assertNotIn("--admin", studio_land.merge_command("7", HEAD))
        self.assertNotIn("--delete-branch", studio_land.merge_command("7", HEAD))

    def test_the_real_helpers_read_all_pages(self):
        """Fails if: file or check-run lookups stop paginating (a 101st file under .github/ would then go unseen)."""
        stub = Stub()
        with mock.patch.object(studio_land, "run", stub):
            studio_land.changed_files("7")
            studio_land.check_runs(HEAD)
        self.assertTrue(all("--paginate" in c for c in stub.calls))


class RecordForAStudioHeadTests(unittest.TestCase):
    """Open check from the spec: ``record.py --lane`` records a pass for a head in another repository and ``has_pass`` reads it."""

    def git(self, cwd, *args):
        return subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, check=True, env=ENV).stdout.strip()

    def test_a_pass_recorded_in_a_studio_checkout_is_read_by_has_pass(self):
        with TemporaryDirectory() as tmp:
            repo, home = Path(tmp) / "studio", Path(tmp) / "home"
            repo.mkdir()
            self.git(repo, "init", "-q", "-b", "agents/studio-x")
            self.git(repo, "remote", "add", "origin", f"https://github.com/{REPO}.git")
            (repo / "a.txt").write_text("x")
            self.git(repo, "add", ".")
            self.git(repo, "commit", "-qm", "c")
            head = self.git(repo, "rev-parse", "HEAD")
            verdict = Path(tmp) / "v.json"
            verdict.write_text(json.dumps({"verdict": "pass", "findings": []}))
            ident = {"agent_type": "reviewer", "session_id": "s1", "agent_id": ""}
            with mock.patch.object(record, "reviewer_identity", return_value=ident), mock.patch.object(Path, "home", return_value=home), \
                    redirect_stdout(io.StringIO()):
                self.assertEqual(record.main([str(verdict), "--lane", "agents/studio-x", "--root", str(repo)]), 0)
            self.assertTrue(review_verdict.has_pass(head, home / "hass-agents" / "reviews"))
            self.assertFalse(review_verdict.has_pass("d" * 40, home / "hass-agents" / "reviews"))


class GuardTests(unittest.TestCase):
    """``merge_guard`` allows exactly ``tools/studio_land.py ARGS``; every other merge stays refused."""

    ALLOWED = ("tools/studio_land.py 7", "./tools/studio_land.py 7 --dry-run", f"{merge_guard.REPO}/tools/studio_land.py #7")
    #: Not the exact form, and refused in any session (a merge hidden behind it, or any other merge route).
    REFUSED = (
        "tools/studio_land.py 7 && gh pr merge 9", "tools/studio_land.py 7; gh pr merge 9", "bash -c 'gh pr merge 7 -R SFenton/ha-native-home-app'",
        "gh pr merge 7 -R SFenton/ha-native-home-app", "gh pr merge 7 -R SFenton/ha-native-home-app --squash --match-head-commit abc",
        "gh pr merge 7 -R SFenton/ha-native-home-app --admin", "gh pr merge 7 --auto --squash",
        "gh api -X PUT repos/SFenton/ha-native-home-app/pulls/7/merge", "gh api repos/SFenton/ha-native-home-app/pulls/7/merge --method PUT",
        "gh api repos/SFenton/ha-native-home-app/merges -f base=main -f head=x",
        "gh api graphql -f query='mutation { mergePullRequest(input: {}) { clientMutationId } }'",
    )
    #: Not the exact form: never sanctioned, and an agent session refuses them as a landing (the owner option is spelled out in pieces).
    WRAPPED = (
        "tools/studio_land.py 7; true", "tools/studio_land.py 7 | cat", "tools/studio_land.py $(id)", "FOO=1 tools/studio_land.py 7",
        "env tools/studio_land.py 7", "python3 tools/studio_land.py 7", "bash tools/studio_land.py 7", "bash -c 'tools/studio_land.py 7'",
        "script -q /dev/null tools/studio_land.py 7", "/tmp/evil/tools/studio_land.py 7", "tools/studio_land.py 7 --owner" + "-ack",
    )

    def test_exact_form_is_allowed_everything_else_refused(self):
        for command in self.ALLOWED:
            with self.subTest(command=command):
                self.assertTrue(merge_guard.is_sanctioned(command))
                self.assertIsNone(merge_guard.raw_reason(command))
        for command in self.REFUSED:
            with self.subTest(command=command):
                self.assertFalse(merge_guard.is_sanctioned(command))
                self.assertIsNotNone(merge_guard.raw_reason(command))
        for command in self.WRAPPED:
            with self.subTest(command=command):
                if "--owner" not in command:  # that option is refused by the agent-session check below, as for pr_land
                    self.assertFalse(merge_guard.is_sanctioned(command))

    def test_pr_land_stays_sanctioned(self):
        self.assertTrue(merge_guard.is_sanctioned("tools/pr_land.sh 5"))
        self.assertTrue(merge_guard.is_sanctioned("./tools/pr_land.sh 5 --dry-run"))

    def test_an_agent_session_runs_it_only_from_a_checkout_matching_the_base(self):
        """Fails if: an edited studio_land.py (or one the base does not have) is runnable by an agent, or a wrapper or pty gets around the pin."""
        command = "tools/studio_land.py 7"
        with mock.patch.object(merge_guard, "agent_session", return_value=True):
            with mock.patch.object(merge_guard, "pr_land_matches_base", return_value=True) as matches:
                self.assertIsNone(merge_guard.raw_reason(command))
                self.assertEqual(matches.call_args.args[0], command)
            with mock.patch.object(merge_guard, "pr_land_matches_base", return_value=False):
                self.assertIn("differs from origin/", merge_guard.raw_reason(command) or "")
            with mock.patch.object(merge_guard, "pr_land_matches_base", return_value=True):
                for wrapped in self.WRAPPED:
                    with self.subTest(command=wrapped):
                        self.assertTrue((merge_guard.raw_reason(wrapped) or "").startswith(("landing:", "owner-ack:")))

    def test_the_script_is_pinned_with_what_it_imports(self):
        """Fails if: the hash the guard compares leaves out a file studio_land imports (a changed pr_land would then not be noticed)."""
        pinned = merge_guard.PINNED_WITH["studio_land.py"]
        for name in ("studio_land.py", "pr_land.py", "review_verdict.py", "agent_login.py"):
            self.assertIn(name, pinned)

    def test_the_hook_blocks_with_its_message(self):
        err = io.StringIO()
        payload = {"tool_name": "Bash", "tool_input": {"command": "gh pr merge 7 -R SFenton/ha-native-home-app --squash"}}
        with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(payload))), redirect_stderr(err):
            self.assertEqual(merge_guard.main(), 2)
        self.assertIn("matched: gh pr merge", err.getvalue())


if __name__ == "__main__":
    unittest.main()
