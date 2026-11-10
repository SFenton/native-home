"""``tools/hooks/triage_session.py``: the registry of T3-launched triage sessions, its resolver and the SessionStart env export."""

import hashlib
import io
import json
import os
import stat
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "hooks"))
import triage_session as ts  # noqa: E402

ENV = {"FENTON_HEADLESS": "1", "HASS_TRIAGE_ISSUE": "42", "HASS_TRIAGE_PAUSED_FILE": "/p", "HASS_TRIAGE_STATUS_FILE": "/s",
       "HASS_TRIAGE_BIN": "/b", "FENTON_DEVCAP_MAX_WAIT": "1200"}
DENY = ["Bash(gh pr merge*)", "Artifact"]


class Base(unittest.TestCase):
    def setUp(self):
        tmp = TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(os.path.realpath(tmp.name))
        self.root = self.tmp / "t3"
        self.work = self.tmp / "worktrees" / "42"
        self.work.mkdir(parents=True)

    def record(self, **over):
        rec = ts.build_record("request", 42, "orchestrator", self.work, "report/42", ENV, DENY)
        rec.update(over)
        return rec

    def resolve(self, env=None, payload=None, **kw):
        return ts.resolve(env or {}, payload, root=self.root, **kw)


class WriteTests(Base):
    def test_record_has_exactly_the_v1_fields(self):
        """Fails if: the schema drifts from the one the launcher and the hooks agree on."""
        rec = self.record()
        self.assertEqual(set(rec), {"v", "launch_id", "kind", "issue", "role", "worktree", "branch", "thread_id", "state", "started",
                                    "expires", "env", "deny", "hook_sha"})
        self.assertEqual(rec["v"], 1)
        self.assertEqual(rec["state"], "launching")
        self.assertEqual(rec["env"], ENV)
        self.assertEqual(rec["deny"], DENY)

    def test_write_is_private_and_atomic(self):
        """Fails if: the record is readable by others, the folder is not 700, or a temp file is left behind."""
        target = ts.write_record(self.record(), self.root)
        self.assertEqual(target, self.root / "worktrees" / f"{ts.worktree_key(self.work)}.json")
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(target.parent.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(self.root.stat().st_mode), 0o700)
        self.assertEqual([p.name for p in target.parent.iterdir()], [target.name])
        self.assertEqual(json.loads(target.read_text())["worktree"], str(self.work))

    def test_thread_record_is_written_when_the_id_is_known(self):
        """Fails if: the second write (after the handover) does not add the thread key."""
        ts.write_record(self.record(), self.root)
        self.assertFalse((self.root / "threads").exists())
        ts.write_record(self.record(thread_id="thr-1", state="running"), self.root)
        thread = self.root / "threads" / "thr-1.json"
        self.assertEqual(stat.S_IMODE(thread.stat().st_mode), 0o600)
        self.assertEqual(json.loads(thread.read_text())["thread_id"], "thr-1")

    def test_invalid_records_are_refused(self):
        """Fails if: a record the hooks would treat as corrupt can be written."""
        for bad in (self.record(v=2), self.record(kind="other"), self.record(env=[]), self.record(deny="x"), self.record(state="x"),
                    self.record(env={"A": 1}), self.record(worktree=""), self.record(role=None)):
            with self.assertRaises(ValueError):
                ts.write_record(bad, self.root)
        with self.assertRaises(ValueError):
            ts.write_record(self.record(thread_id="../evil"), self.root)
        self.assertFalse(self.root.exists() and any(self.root.rglob("*.json")))

    def test_set_state_marks_ended_but_keeps_the_record(self):
        """Fails if: the end of a session removes the record, so a woken old thread would stop being a triage session."""
        ts.write_record(self.record(thread_id="thr-1"), self.root)
        self.assertTrue(ts.set_state(self.work, "ended", self.root))
        found = self.resolve({"T3CODE_THREAD_ID": "thr-1"})
        self.assertEqual(json.loads((self.root / "worktrees" / f"{ts.worktree_key(self.work)}.json").read_text())["state"], "ended")
        self.assertIsNotNone(found)
        self.assertFalse(ts.set_state(self.tmp / "nowhere", "ended", self.root))
        with self.assertRaises(ValueError):
            ts.set_state(self.work, "gone", self.root)

    def test_forget_removes_both_keys_only_for_that_worktree(self):
        """Fails if: cleanup leaves a record behind or removes another session's."""
        other = self.tmp / "worktrees" / "43"
        other.mkdir()
        ts.write_record(self.record(thread_id="thr-1"), self.root)
        ts.write_record(ts.build_record("request", 43, "orchestrator", other, "report/43", ENV, DENY, thread_id="thr-2"), self.root)
        gone = ts.forget(self.work, self.root)
        self.assertEqual(sorted(p.name for p in gone), sorted([f"{ts.worktree_key(self.work)}.json", "thr-1.json"]))
        self.assertIsNone(self.resolve({"T3CODE_THREAD_ID": "thr-1"}, project_dir=str(self.work)))
        self.assertIsNotNone(self.resolve({"T3CODE_THREAD_ID": "thr-2"}))
        self.assertEqual(ts.forget(self.work, self.root), [])

    def test_hash_hooks_covers_the_guard_files(self):
        """Fails if: the launcher cannot record the bytes of the files that enforce the deny list."""
        repo = Path(__file__).resolve().parents[2]
        hashes = ts.hash_hooks(repo)
        self.assertEqual(sorted(hashes), sorted(ts.GUARD_FILES))
        self.assertEqual(hashes["tools/hooks/deny_rules.py"], hashlib.sha256((repo / "tools/hooks/deny_rules.py").read_bytes()).hexdigest())
        self.assertEqual(ts.hash_hooks(self.tmp), {})


class ResolveTests(Base):
    def test_ordinary_session_is_untouched(self):
        """Fails if: an owner session in T3 (a thread id, no record) is treated as a triage session."""
        self.assertIsNone(self.resolve({"T3CODE_THREAD_ID": "owner-thread", "CLAUDE_PROJECT_DIR": str(self.work)}))
        self.assertIsNone(self.resolve({}, {"cwd": str(self.work)}))
        ts.write_record(self.record(), self.root)
        self.assertIsNone(self.resolve({"T3CODE_THREAD_ID": "owner-thread", "CLAUDE_PROJECT_DIR": str(self.tmp)}))

    def test_path_key_resolves_before_the_thread_exists(self):
        """Fails if: the first tool call of a launched thread (no thread id known, none in the registry) escapes the record."""
        ts.write_record(self.record(), self.root)
        found = self.resolve({"CLAUDE_PROJECT_DIR": str(self.work)})
        self.assertEqual((found.via, found.strict, found.env, list(found.deny)), ("path", False, ENV, DENY))
        found = self.resolve({"T3CODE_THREAD_ID": "not-registered-yet", "CLAUDE_PROJECT_DIR": str(self.work)})
        self.assertEqual(found.via, "path")

    def test_cd_elsewhere_still_resolves_by_project_dir(self):
        """Fails if: running `cd /tmp` (the payload cwd moves, the project dir does not) leaves the session unguarded."""
        ts.write_record(self.record(), self.root)
        found = self.resolve({"CLAUDE_PROJECT_DIR": str(self.work)}, {"cwd": "/tmp"})
        self.assertFalse(found.strict)
        self.assertEqual(found.record["issue"], 42)

    def test_cwd_inside_the_worktree_resolves_without_a_project_dir(self):
        """Fails if: a hook whose environment lacks CLAUDE_PROJECT_DIR cannot find the record from a sub-folder."""
        ts.write_record(self.record(), self.root)
        sub = self.work / "tools" / "x"
        sub.mkdir(parents=True)
        self.assertEqual(self.resolve({}, {"cwd": str(sub)}).via, "path")

    def test_symlinked_project_dir_resolves(self):
        """Fails if: the key is computed from the path as written, so a symlink to the worktree misses it."""
        ts.write_record(self.record(), self.root)
        link = self.tmp / "link"
        link.symlink_to(self.work)
        self.assertIsNotNone(self.resolve({"CLAUDE_PROJECT_DIR": str(link)}))

    def test_thread_key_wins_and_resolves_alone(self):
        """Fails if: a thread id that has a record is not honoured, whatever the project dir."""
        ts.write_record(self.record(thread_id="thr-1"), self.root)
        found = self.resolve({"T3CODE_THREAD_ID": "thr-1", "CLAUDE_PROJECT_DIR": "/somewhere/else"})
        self.assertEqual(found.via, "thread")

    def test_bad_thread_ids_are_ignored_not_followed(self):
        """Fails if: a hostile thread id walks out of the threads folder."""
        ts.write_record(self.record(), self.root)
        for bad in ("../worktrees/x", "a/b", "", ".hidden"):
            self.assertIsNone(self.resolve({"T3CODE_THREAD_ID": bad}))

    def corrupt(self, text, key=None):
        path = self.root / "worktrees" / f"{key or ts.worktree_key(self.work)}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def test_a_record_that_cannot_be_trusted_is_strict(self):
        """Fails if: a corrupt, wrong-version or incomplete record turns the session into an ordinary one."""
        good = self.record()
        cases = {"not json": "{oops", "empty": "", "list": "[]", "version": json.dumps({**good, "v": 2}),
                 "no env": json.dumps({k: v for k, v in good.items() if k != "env"}),
                 "no deny": json.dumps({k: v for k, v in good.items() if k != "deny"}),
                 "env values": json.dumps({**good, "env": {"A": 1}}), "deny items": json.dumps({**good, "deny": [1]}),
                 "no worktree": json.dumps({**good, "worktree": ""}),
                 "other worktree": json.dumps({**good, "worktree": str(self.tmp)})}
        for name, text in cases.items():
            with self.subTest(name):
                self.corrupt(text)
                found = self.resolve({"CLAUDE_PROJECT_DIR": str(self.work)})
                self.assertTrue(found and found.strict, name)
                self.assertEqual(found.env["FENTON_HEADLESS"], "1")
                self.assertTrue(found.reason)

    def test_an_unreadable_record_is_strict(self):
        """Fails if: a record that exists but cannot be read is treated as absent."""
        ts.write_record(self.record(), self.root)
        path = self.root / "worktrees" / f"{ts.worktree_key(self.work)}.json"
        os.chmod(path, 0)
        self.addCleanup(os.chmod, path, 0o600)
        if os.access(path, os.R_OK):
            self.skipTest("running as a user that ignores file modes")
        self.assertTrue(self.resolve({"CLAUDE_PROJECT_DIR": str(self.work)}).strict)

    def test_one_bad_key_makes_it_strict_even_if_the_other_is_good(self):
        """Fails if: a good thread record hides a corrupt path record."""
        ts.write_record(self.record(thread_id="thr-1"), self.root)
        self.corrupt("{oops")
        found = self.resolve({"T3CODE_THREAD_ID": "thr-1", "CLAUDE_PROJECT_DIR": str(self.work)})
        self.assertTrue(found.strict)
        self.assertEqual(found.record["issue"], 42)

    def test_an_expired_or_ended_record_still_guards(self):
        """Fails if: a record's age or state switches the guards off."""
        ts.write_record(self.record(expires="2000-01-01T00:00:00Z", state="ended"), self.root)
        self.assertFalse(self.resolve({"CLAUDE_PROJECT_DIR": str(self.work)}).strict)

    def test_apply_overlays_exactly_the_record_env(self):
        """Fails if: the hooks do not see the markers a headless runner session would have had."""
        ts.write_record(self.record(), self.root)
        env = {"CLAUDE_PROJECT_DIR": str(self.work), "KEEP": "1"}
        found = ts.apply({}, env, root=self.root)
        self.assertIsNotNone(found)
        self.assertEqual({k: v for k, v in env.items() if k not in ("CLAUDE_PROJECT_DIR", "KEEP")}, ENV)
        self.assertEqual(env["KEEP"], "1")

    def test_apply_leaves_an_ordinary_session_alone(self):
        """Fails if: a session with no record changes at all (byte-for-byte as today)."""
        env = {"T3CODE_THREAD_ID": "owner", "CLAUDE_PROJECT_DIR": str(self.work), "A": "b"}
        before = dict(env)
        self.assertIsNone(ts.apply({"cwd": str(self.work)}, env, root=self.root))
        self.assertEqual(env, before)

    def test_apply_in_strict_mode_sets_the_headless_marker(self):
        """Fails if: an untrusted record leaves the other hooks in owner mode."""
        self.corrupt("{oops")
        env = {"CLAUDE_PROJECT_DIR": str(self.work)}
        ts.apply({}, env, root=self.root)
        self.assertEqual(env["FENTON_HEADLESS"], "1")

    def test_apply_never_raises(self):
        """Fails if: a lookup error crashes a guard hook."""
        with mock.patch.object(ts, "resolve", side_effect=RuntimeError("boom")):
            self.assertIsNone(ts.apply({}, {}, root=self.root))

    def test_default_registry_root_is_under_home(self):
        """Fails if: the registry moves or an environment variable can redirect it."""
        self.assertEqual(ts.registry_root("/h"), Path("/h/hass-agents/t3"))
        with mock.patch.dict(os.environ, {"HOME": "/h2"}):
            self.assertEqual(ts.registry_root(), Path("/h2/hass-agents/t3"))


class ToolShellTests(Base):
    """``session_env`` / ``registered``: what pr_land and lane_land ask from inside a tool shell."""

    def setUp(self):
        super().setUp()
        subprocess.run(["git", "init", "-q", str(self.work)], check=True)

    def test_registered_by_toplevel_from_a_subfolder(self):
        """Fails if: `git rev-parse --show-toplevel` of the working directory does not find the record."""
        ts.write_record(self.record(), self.root)
        sub = self.work / "a"
        sub.mkdir()
        self.assertEqual(ts.session_env({}, cwd=str(sub), root=self.root), ENV)
        self.assertTrue(ts.registered({}, cwd=str(sub), root=self.root))

    def test_not_registered_elsewhere(self):
        """Fails if: an owner checkout is reported as a triage session."""
        ts.write_record(self.record(), self.root)
        other = self.tmp / "owner"
        subprocess.run(["git", "init", "-q", str(other)], check=True)
        self.assertIsNone(ts.session_env({"T3CODE_THREAD_ID": "x"}, cwd=str(other), root=self.root))
        self.assertFalse(ts.registered({}, cwd=str(other), root=self.root))

    def test_a_lookup_failure_counts_as_headless(self):
        """Fails if: an error in the lookup lets a landing tool run as the owner."""
        with mock.patch.object(ts, "resolve", side_effect=OSError("boom")):
            self.assertEqual(ts.session_env({}, root=self.root), {"FENTON_HEADLESS": "1"})


class SessionStartTests(Base):
    def test_env_file_exports_the_record_and_scrubs(self):
        """Fails if: the tool shells of a registered session lack the markers, or keep the tokens a headless runner session scrubs."""
        ts.write_record(self.record(env={**ENV, "PATH": "/usr/bin:/bin", "WEIRD": "it's a 'quote'"}), self.root)
        target = self.tmp / "envfile"
        env = {"CLAUDE_PROJECT_DIR": str(self.work), "CLAUDE_ENV_FILE": str(target)}
        self.assertEqual(ts.session_start({}, env, root=self.root), 0)
        text = target.read_text()
        lines = text.splitlines()
        self.assertIn("export FENTON_HEADLESS=1", lines)
        self.assertIn("export HASS_TRIAGE_ISSUE=42", lines)
        self.assertIn("export PATH=/usr/bin:/bin", lines)
        self.assertIn("export WEIRD='it'\"'\"'s a '\"'\"'quote'\"'\"''", lines)
        self.assertEqual(lines[-1], "unset " + " ".join(ts.SCRUB_ENV))
        for name in ("GH_TOKEN", "GITHUB_TOKEN", "GH_CONFIG_DIR", "XDG_CONFIG_HOME", "TYPESAFE_API_KEY", "FENTON_HASS_TOKEN",
                     "FENTON_HASS_PASSWORD", "FENTON_HASS_USERNAME"):
            self.assertIn(name, lines[-1].split())
        # the exported file really sets the shell up
        out = subprocess.run(["bash", "-c", f'GH_TOKEN=x; . "{target}"; echo "$FENTON_HEADLESS:$HASS_TRIAGE_ISSUE:${{GH_TOKEN-unset}}"'],
                             capture_output=True, text=True)
        self.assertEqual(out.stdout.strip(), "1:42:unset")

    def test_names_that_are_not_variables_are_not_exported(self):
        """Fails if: a record can inject shell text through an env name."""
        ts.write_record(self.record(env={**ENV, "A;rm -rf /": "x"}), self.root)
        target = self.tmp / "envfile"
        ts.session_start({}, {"CLAUDE_PROJECT_DIR": str(self.work), "CLAUDE_ENV_FILE": str(target)}, root=self.root)
        self.assertNotIn("rm -rf", target.read_text())

    def test_nothing_is_written_for_an_ordinary_session(self):
        """Fails if: an owner session's env file is touched."""
        target = self.tmp / "envfile"
        ts.session_start({}, {"CLAUDE_PROJECT_DIR": str(self.work), "CLAUDE_ENV_FILE": str(target)}, root=self.root)
        self.assertFalse(target.exists())

    def test_strict_session_still_exports_the_marker(self):
        """Fails if: a corrupt record leaves tool shells without FENTON_HEADLESS."""
        path = self.root / "worktrees" / f"{ts.worktree_key(self.work)}.json"
        path.parent.mkdir(parents=True)
        path.write_text("{oops")
        target = self.tmp / "envfile"
        ts.session_start({}, {"CLAUDE_PROJECT_DIR": str(self.work), "CLAUDE_ENV_FILE": str(target)}, root=self.root)
        self.assertIn("export FENTON_HEADLESS=1", target.read_text())

    def test_a_missing_env_file_variable_or_failure_never_fails_the_hook(self):
        """Fails if: SessionStart can stop a session."""
        ts.write_record(self.record(), self.root)
        self.assertEqual(ts.session_start({}, {"CLAUDE_PROJECT_DIR": str(self.work)}, root=self.root), 0)
        self.assertEqual(ts.session_start({}, {"CLAUDE_PROJECT_DIR": str(self.work), "CLAUDE_ENV_FILE": "/nonexistent/dir/f"},
                                          root=self.root), 0)

    def test_main_reads_the_payload_and_needs_the_flag(self):
        """Fails if: the command line entry point misparses its input."""
        with mock.patch.object(sys, "stdin", io.StringIO("not json")), mock.patch.object(ts, "session_start", return_value=0) as start:
            self.assertEqual(ts.main(["--session-start"]), 0)
            start.assert_called_once_with({})
        with mock.patch.object(sys, "stdin", io.StringIO('{"cwd": "/x"}')), mock.patch.object(ts, "session_start", return_value=0) as start:
            ts.main(["--session-start"])
            start.assert_called_once_with({"cwd": "/x"})
        with mock.patch.object(sys, "stderr", io.StringIO()):
            self.assertEqual(ts.main([]), 2)


if __name__ == "__main__":
    unittest.main()
