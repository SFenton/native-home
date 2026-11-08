"""tools/ci_hygiene.py: the free-space pre-flight, what it may delete and what it must not."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ci_hygiene as h  # noqa: E402

REAL_STEPS = h.reap_steps

A, B, C, D, E = ("%032X" % i for i in range(1, 6))


def uuid(n):
    s = "%032X" % n
    return "%s-%s-%s-%s-%s" % (s[:8], s[8:12], s[12:16], s[16:20], s[20:])


def sim(udid, name, state="Shutdown"):
    return {"udid": udid, "name": name, "state": state, "runtime": "r"}


class HygieneTests(unittest.TestCase):
    def setUp(self):
        # Pre-flight cleans orphaned DerivedData: never the real one.
        self._derived = tempfile.mkdtemp()
        patcher = mock.patch.dict(os.environ, {"HASS_DERIVED_DATA": self._derived})
        patcher.start()
        self.addCleanup(patcher.stop)
        # Pre-flight reaps worktrees and simulators when short: never the real ones.
        steps = mock.patch.object(h, "reap_steps", return_value=[])
        steps.start()
        self.addCleanup(steps.stop)

    def _derived_folder(self, root, name, workspace=None, plist=True):
        folder = Path(root) / name
        folder.mkdir()
        (folder / "Build").mkdir()
        if plist:
            import plistlib
            data = {} if workspace is None else {"WorkspacePath": str(workspace)}
            (folder / "info.plist").write_bytes(plistlib.dumps(data))
        return folder

    def test_orphaned_derived_data_is_deleted_only_when_its_project_is_gone(self):
        root = Path(tempfile.mkdtemp())
        live = Path(tempfile.mkdtemp()) / "FentonHome.xcodeproj"
        live.mkdir()
        gone = root / "deleted-worktree" / "FentonHome.xcodeproj"
        orphan = self._derived_folder(root, "FentonHome-orphan", gone)
        kept = self._derived_folder(root, "FentonHome-live", live)
        no_plist = self._derived_folder(root, "FentonHome-noplist", plist=False)
        no_path = self._derived_folder(root, "FentonHome-nopath")
        other = self._derived_folder(root, "OtherApp-orphan", gone)
        self.assertEqual(h.orphaned_derived_data(root), [orphan])
        with redirect_stdout(StringIO()):
            self.assertEqual(h.clean_derived_orphans(dry=True, root=root), 1)
            self.assertTrue(orphan.exists())
            self.assertEqual(h.clean_derived_orphans(root=root), 1)
        self.assertFalse(orphan.exists())
        for folder in (kept, no_plist, no_path, other):
            self.assertTrue(folder.exists(), folder.name)

    @unittest.skipUnless(sys.platform == "darwin", "DerivedData path handling is macOS")
    def test_only_a_missing_workspace_is_an_orphan(self):
        root = Path(tempfile.mkdtemp())
        folder = self._derived_folder(root, "FentonHome-denied", root / "FentonHome.xcodeproj")
        with mock.patch.object(h.os, "stat", side_effect=PermissionError(13, "denied")):
            self.assertEqual(h.orphaned_derived_data(root), [])
        with mock.patch.object(h.os, "stat", side_effect=FileNotFoundError(2, "gone")):
            self.assertEqual(h.orphaned_derived_data(root), [folder])

    def test_a_malformed_plist_is_not_an_orphan(self):
        root = Path(tempfile.mkdtemp())
        folder = self._derived_folder(root, "FentonHome-bad", plist=False)
        (folder / "info.plist").write_text("not a plist")
        self.assertEqual(h.orphaned_derived_data(root), [])

    def test_preflight_cleans_orphans_before_checking_space(self):
        orphan = self._derived_folder(self._derived, "FentonHome-orphan", Path(self._derived) / "nope.xcodeproj")
        with mock.patch.dict(os.environ, {"HASS_CI_FREE_GB": "80"}), redirect_stdout(StringIO()):
            self.assertEqual(h.preflight(30), 0)
        self.assertFalse(orphan.exists())

    def test_preflight_fails_below_the_limit_with_a_message(self):
        err = StringIO()
        with mock.patch.dict(os.environ, {"HASS_CI_FREE_GB": "12"}), redirect_stderr(err):
            self.assertEqual(h.preflight(30), 1)
        self.assertIn("only 12 GB free", err.getvalue())
        self.assertIn("simctl delete unavailable", err.getvalue())
        with mock.patch.dict(os.environ, {"HASS_CI_FREE_GB": "80"}), redirect_stdout(StringIO()):
            self.assertEqual(h.preflight(30), 0)

    def test_preflight_runs_the_reap_chain_in_order_and_stops_once_space_is_back(self):
        calls = []
        free = iter([10.0, 18.0, 41.0])
        steps = [(n, (lambda n=n: calls.append(n))) for n in ("prune-worktrees", "clean-sims", "prune-results", "derived-orphans")]
        out = StringIO()
        with mock.patch.object(h, "reap_steps", return_value=steps), mock.patch.object(h, "free_gb", lambda path="/": next(free)), \
                redirect_stdout(out):
            self.assertEqual(h.preflight(30), 0)
        self.assertEqual(calls, ["prune-worktrees", "clean-sims"])
        self.assertIn("reap prune-worktrees: freed 8.0 GB", out.getvalue())
        self.assertIn("reap clean-sims: freed 23.0 GB", out.getvalue())

    def test_preflight_fails_only_after_every_step_and_survives_a_failing_step(self):
        calls = []

        def boom():
            raise RuntimeError("nope")
        steps = [("a", boom), ("b", lambda: calls.append("b"))]
        err = StringIO()
        with mock.patch.object(h, "reap_steps", return_value=steps), mock.patch.dict(os.environ, {"HASS_CI_FREE_GB": "12"}), \
                redirect_stdout(StringIO()), redirect_stderr(err):
            self.assertEqual(h.preflight(30), 1)
        self.assertEqual(calls, ["b"])
        self.assertIn("reap step a failed", err.getvalue())
        self.assertIn("only 12 GB free", err.getvalue())

    def test_preflight_with_enough_space_reaps_nothing(self):
        called = []
        with mock.patch.object(h, "reap_steps", return_value=[("a", lambda: called.append(1))]), \
                mock.patch.dict(os.environ, {"HASS_CI_FREE_GB": "80"}), redirect_stdout(StringIO()):
            self.assertEqual(h.preflight(30), 0)
        self.assertEqual(called, [])

    def test_reap_steps_are_the_four_in_the_owner_approved_order(self):
        self.assertEqual([n for n, _ in REAL_STEPS()], ["prune-worktrees", "clean-sims", "prune-results", "derived-orphans"])

    def test_idle_sims_are_shutdown_unheld_pool_members_devcap_created(self):
        sims = [sim(A, "iPhone (pool 2)", "Booted"), sim(B, "iPad (pool 3)"), sim(C, "iPad (pool 4)"), sim(D, "Duo"),
                sim(E, "iPhone (pool 5)")]
        self.assertEqual([s["udid"] for s in h.idle_sims(sims, {C}, {A, B, C, D})], [B])

    def test_clean_idle_sims_only_deletes_never_erases_and_dry_run_touches_nothing(self):
        sims = [sim(A, "iPhone"), sim(B, "iPhone (pool 2)"), sim(C, "iPad (pool 3)", "Booted"), sim(D, "Duo (pool 2)"),
                sim(E, "Duo (pool 3)")]
        with mock.patch.object(h, "simulators", return_value=sims), mock.patch.object(h, "held_udids", return_value={D}), \
                mock.patch.object(h, "project_members", return_value={A, B, C, D}), \
                mock.patch.object(h.subprocess, "run") as run, redirect_stdout(StringIO()):
            self.assertEqual(h.clean_idle_sims(dry=True), 0)
            run.assert_not_called()
            self.assertEqual(h.clean_idle_sims(dry=False), 0)
        self.assertEqual([c.args[0] for c in run.call_args_list], [["xcrun", "simctl", "delete", B]])

    def test_clean_idle_sims_leaves_untagged_legacy_and_other_projects_members(self):
        sims = [sim(A, "iPhone (pool 2)"), sim(B, "iPad (pool 3)"), sim(C, "Duo (pool 2)")]
        with mock.patch.object(h, "simulators", return_value=sims), mock.patch.object(h, "held_udids", return_value=set()), \
                mock.patch.object(h, "project_members", return_value={B}), \
                mock.patch.object(h.subprocess, "run") as run, redirect_stdout(StringIO()):
            self.assertEqual(h.clean_idle_sims(dry=False), 0)
        self.assertEqual([c.args[0] for c in run.call_args_list], [["xcrun", "simctl", "delete", B]])

    def test_project_members_reads_only_this_projects_tagged_records(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "sims.json").write_text(json.dumps({
                A.lower(): {"kind": "pool", "project": "mine"}, B: {"kind": "pool", "project": "theirs"},
                C: {"kind": "ephemeral", "project": "mine"}, D: {"project": "mine"}}))
            with mock.patch.dict(os.environ, {"DEVCAP_DIR": tmp, "DEVCAP_PROJECT": "mine"}):
                self.assertEqual(h.project_members(), {A, C})
            with mock.patch.dict(os.environ, {"DEVCAP_DIR": tmp, "DEVCAP_PROJECT": "unknown"}):
                self.assertEqual(h.project_members(), set())

    def test_clean_idle_sims_touches_nothing_when_a_fact_is_unreadable(self):
        for failing in ("simulators", "held_udids"):
            patches = {"simulators": mock.Mock(return_value=[sim(A, "iPhone (pool 2)")]), "held_udids": mock.Mock(return_value=set()),
                       "project_members": mock.Mock(return_value={A})}
            patches[failing] = mock.Mock(side_effect=h.HygieneError("unreadable"))
            with mock.patch.multiple(h, **patches), mock.patch.object(h.subprocess, "run") as run, redirect_stderr(StringIO()):
                self.assertEqual(h.clean_idle_sims(dry=False), 1)
            run.assert_not_called()

    def _plist(self, **values):
        path = Path(tempfile.mkdtemp()) / "runner.plist"
        import plistlib
        path.write_bytes(plistlib.dumps(values))
        return path

    def test_session_create_true_warns_only_on_macos_under_actions(self):
        env = {"GITHUB_ACTIONS": "true"}
        plist = self._plist(Label="x", SessionCreate=True)
        warning = h.session_create_warning(plist, "darwin", env)
        self.assertTrue(warning.startswith("::warning"))
        self.assertIn("plutil -replace SessionCreate -bool false", warning)
        self.assertIsNone(h.session_create_warning(plist, "linux", env))
        self.assertIsNone(h.session_create_warning(plist, "darwin", {}))

    def test_runner_plist_follows_the_runner_running_the_job(self):
        agents = Path.home() / "Library" / "LaunchAgents"
        self.assertEqual(h.runner_plist_path({"RUNNER_NAME": "host-mini"}),
                         agents / "actions.runner.SFenton-native-home.host-mini.plist")
        self.assertEqual(h.runner_plist_path({}), agents / "actions.runner.SFenton-native-home.hass-mac.plist")
        self.assertEqual(h.runner_plist_path({"RUNNER_NAME": "host-mini", "HASS_RUNNER_PLIST": "/tmp/x.plist"}),
                         Path("/tmp/x.plist"))

    def test_session_create_false_missing_or_unreadable_is_silent(self):
        env = {"GITHUB_ACTIONS": "true"}
        self.assertIsNone(h.session_create_warning(self._plist(SessionCreate=False), "darwin", env))
        self.assertIsNone(h.session_create_warning(self._plist(Label="x"), "darwin", env))
        self.assertIsNone(h.session_create_warning(Path("/nonexistent/x.plist"), "darwin", env))
        bad = Path(tempfile.mkdtemp()) / "bad.plist"
        bad.write_text("not a plist")
        self.assertIsNone(h.session_create_warning(bad, "darwin", env))

    def test_malformed_xml_and_non_dict_roots_never_raise(self):
        env = {"GITHUB_ACTIONS": "true"}
        d = Path(tempfile.mkdtemp())
        xml = d / "xml.plist"
        xml.write_text("<?xml version='1.0'?><plist><dict><key>SessionCreate</key><true/></plist>")
        self.assertIsNone(h.session_create_warning(xml, "darwin", env))
        arr = d / "arr.plist"
        import plistlib
        arr.write_bytes(plistlib.dumps(["SessionCreate"]))
        self.assertIsNone(h.session_create_warning(arr, "darwin", env))

    def test_preflight_prints_the_warning_but_never_fails_for_it(self):
        plist = self._plist(SessionCreate=True)
        out = StringIO()
        with mock.patch.dict(os.environ, {"HASS_CI_FREE_GB": "80", "GITHUB_ACTIONS": "true", "HASS_RUNNER_PLIST": str(plist)}), \
                mock.patch.object(h.sys, "platform", "darwin"), redirect_stdout(out):
            self.assertEqual(h.preflight(30), 0)
        self.assertIn("::warning", out.getvalue())

    def test_only_attributable_new_shutdown_unheld_pool_simulators_are_deleted(self):
        sims = [sim("A", "iPhone 17 Pro"), sim("B", "iPhone 17 Pro (pool 2)"), sim("C", "iPhone 17 Pro (pool 3)"),
                sim("D", "iPhone 17 Pro (pool 4)", "Booted"), sim("E", "iPhone 17 Pro (pool 5)"),
                sim("F", "iPhone 17 Pro (pool 6)"), sim("G", "Other (Rooms)")]
        removed = h.sims_to_remove(sims, before={"A", "B"}, created={"C", "D", "E", "G"}, mine={"C", "D", "E", "G", "A"},
                                   held={"E"})
        self.assertEqual([s["udid"] for s in removed], ["C"])  # F was created by someone else, G is not a pool member
        self.assertEqual(h.sims_to_remove(sims, set(), {"C"}, set(), set()), [], "not this checkout's: never deleted")

    def test_erase_only_this_checkouts_idle_simulators(self):
        sims = [sim("A", "x"), sim("B", "y", "Booted"), sim("C", "z")]
        self.assertEqual([s["udid"] for s in h.sims_to_erase(sims, {"A", "B"}, set())], ["A"])
        self.assertEqual(h.sims_to_erase(sims, {"A"}, {"A"}), [])

    def test_failure_paths_delete_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            snap = Path(tmp) / "snap.json"
            with mock.patch.object(h, "simulators", side_effect=h.HygieneError("boom")), redirect_stderr(StringIO()):
                self.assertEqual(h.snapshot(snap), 1)
            self.assertFalse(snap.exists(), "a failed snapshot writes nothing")
            snap.write_text(json.dumps({"udids": [], "epoch": 0}))
            run = mock.Mock()
            with mock.patch.object(h.subprocess, "run", run), redirect_stderr(StringIO()) as err:
                with mock.patch.object(h, "simulators", return_value=[sim(A, "x (pool 2)")]), \
                        mock.patch.object(h, "held_udids", side_effect=h.HygieneError("no status")):
                    self.assertEqual(h.clean_sims(snap, False, Path(tmp)), 1)
                with mock.patch.object(h, "simulators", side_effect=h.HygieneError("no list")):
                    self.assertEqual(h.clean_sims(snap, False, Path(tmp)), 1)
                self.assertEqual(h.clean_sims(Path(tmp) / "missing.json", False, Path(tmp)), 1)
            run.assert_not_called()
            self.assertIn("not touching any simulator", err.getvalue())

    def registry(self, tmp, records):
        (Path(tmp) / "sims.json").write_text(json.dumps(records))

    def test_created_since_reads_the_registry_not_the_log(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(os.environ, {"DEVCAP_DIR": tmp}):
            (Path(tmp) / "devcap.log").write_text("2026 pid 1 create pool simulator iPad (pool 2) (%s)\n" % uuid(9))
            self.registry(tmp, {
                uuid(1).lower(): {"kind": "pool", "created_epoch": 150.0},
                uuid(2): {"kind": "ephemeral", "created_epoch": 100},
                uuid(3): {"kind": "pool", "created_epoch": 99.9},
                uuid(4): {"kind": "job", "created_epoch": 500},
                uuid(5): {"kind": "pool"},
                uuid(6): {"kind": "pool", "created_epoch": "later"},
                uuid(7): "not a record"})
            self.assertEqual(h.created_since(100), {uuid(1), uuid(2)})
            self.assertEqual(h.created_since(1000), set(), "the log line for uuid(9) names nothing now")

    def test_created_since_missing_registry_attributes_nothing_and_a_bad_one_raises(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(os.environ, {"DEVCAP_DIR": tmp}):
            self.assertEqual(h.created_since(0), set())
            (Path(tmp) / "sims.json").write_text("{not json")
            with self.assertRaises(h.HygieneError):
                h.created_since(0)
            (Path(tmp) / "sims.json").write_text("[1]")
            with self.assertRaises(h.HygieneError):
                h.created_since(0)

    def test_snapshot_records_the_time_and_clean_aborts_on_an_unreadable_registry(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(os.environ, {"DEVCAP_DIR": tmp}):
            snap = Path(tmp) / "snap.json"
            before = time.time()
            with mock.patch.object(h, "simulators", return_value=[sim(A, "x")]), redirect_stdout(StringIO()):
                self.assertEqual(h.snapshot(snap), 0)
            recorded = json.loads(snap.read_text())
            self.assertGreaterEqual(recorded["epoch"], before)
            self.assertNotIn("log_offset", recorded)
            (Path(tmp) / "sims.json").write_text("{not json")
            run = mock.Mock()
            with mock.patch.object(h.subprocess, "run", run), mock.patch.object(h, "simulators", return_value=[sim(A, "x (pool 2)")]), \
                    mock.patch.object(h, "held_udids", return_value=set()), redirect_stderr(StringIO()) as err:
                self.assertEqual(h.clean_sims(snap, False, Path(tmp)), 1)
            run.assert_not_called()
            self.assertIn("not touching any simulator", err.getvalue())

    def test_clean_sims_deletes_only_registry_attributed_new_simulators_of_this_checkout(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(os.environ, {"DEVCAP_DIR": tmp}):
            root = Path(tmp) / "co"
            (root / "apple" / ".build").mkdir(parents=True)
            for n in (1, 2, 3):
                (root / "apple" / ".build" / ("uitest-%d.udid" % n)).write_text(uuid(n) + "\n")
            snap = Path(tmp) / "snap.json"
            snap.write_text(json.dumps({"udids": [uuid(3)], "epoch": 100.0}))
            self.registry(tmp, {uuid(1): {"kind": "pool", "created_epoch": 200}, uuid(3): {"kind": "pool", "created_epoch": 50}})
            sims = [sim(uuid(1), "iPhone (pool 2)"), sim(uuid(2), "iPhone (pool 3)"), sim(uuid(3), "iPhone (pool 4)")]
            run = mock.Mock()
            with mock.patch.object(h.subprocess, "run", run), mock.patch.object(h, "simulators", return_value=sims), \
                    mock.patch.object(h, "held_udids", return_value=set()), redirect_stdout(StringIO()):
                self.assertEqual(h.clean_sims(snap, False, root), 0)
            verbs = [(c.args[0][2], c.args[0][3]) for c in run.call_args_list]
            # uuid(1) was created in the run: deleted. uuid(2) is this checkout's but not in the registry: only erased. uuid(3) pre-existed: erased.
            self.assertEqual(verbs, [("delete", uuid(1)), ("erase", uuid(2)), ("erase", uuid(3))])

    def devcap_dir(self):
        """A fake devcap root: device gate 1 held by this process (flock + holder json), gate 2 idle, a build gate held too."""
        import fcntl
        root = Path(tempfile.mkdtemp(prefix="devcap-"))
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        locks = []
        for gate, held in (("device-%s" % uuid(1), True), ("device-%s" % uuid(2), False), ("build", True)):
            (root / gate).mkdir()
            lock = root / gate / "slot-0.lock"
            lock.write_text("")
            if held:
                handle = open(lock, "rb")
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                locks.append(handle)
                (root / gate / "slot-0.json").write_text(json.dumps({"pid": 1, "cwd": "/a/" + gate[:5]}))
        (root / "bin").mkdir()
        self.addCleanup(lambda: [x.close() for x in locks])
        return root

    def test_held_udids_reads_device_gates_and_fails_closed(self):
        root = self.devcap_dir()
        with mock.patch.dict(os.environ, {"DEVCAP_DIR": str(root)}):
            self.assertEqual(h.held_udids(), {uuid(1)})
            (root / ("device-%s" % uuid(2)) / "queue").mkdir()
            (root / ("device-%s" % uuid(2)) / "queue" / "t").write_text("x")
            self.assertEqual(h.held_udids(), {uuid(1), uuid(2)})
        with mock.patch.dict(os.environ, {"DEVCAP_DIR": str(root / "missing")}):
            with self.assertRaises(h.HygieneError):
                h.held_udids()

    def test_prune_removes_only_old_results(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            build = root / "apple" / ".build"
            build.mkdir(parents=True)
            old, new = build / "uitest-iphone.xcresult", build / "uitest-ipad.xcresult"
            for d in (old, new):
                d.mkdir()
                (d / "x").write_text("x")
            past = time.time() - 10 * 86400
            os.utime(old, (past, past))
            with redirect_stdout(StringIO()):
                h.prune_results(7, False, root)
            self.assertFalse(old.exists())
            self.assertTrue(new.exists())

    def test_rm_dir_only_removes_dd_directories_under_work(self):
        with redirect_stderr(StringIO()):
            self.assertEqual(h.rm_dir("/Users/someone/Library/Developer/Xcode/DerivedData"), 1)
            self.assertEqual(h.rm_dir("/Users/someone/actions-runner-hass/_work"), 1)
            self.assertEqual(h.rm_dir("/Users/someone/actions-runner-hass/_work/Fenton-HASS-Native"), 1)
        with tempfile.TemporaryDirectory() as tmp:
            keep = Path(tmp) / "a" / "_work" / "Fenton-HASS-Native"
            target = Path(tmp) / "a" / "_work" / "Fenton-HASS-Native" / "dd-1-x"
            target.mkdir(parents=True)
            with redirect_stdout(StringIO()):
                self.assertEqual(h.rm_dir(str(target)), 0)
            self.assertFalse(target.exists())
            self.assertTrue(keep.exists())



def git(cwd, *args):
    subprocess.run(["git", "-C", str(cwd), "-c", "user.name=t", "-c", "user.email=t@t", *args], check=True, capture_output=True)


class PruneWorktreeTests(unittest.TestCase):
    devcap_dir = HygieneTests.devcap_dir

    """Temporary repos only: a real repo, simulator or DerivedData is never touched."""

    def setUp(self):
        env = mock.patch.dict(os.environ)
        env.start()
        self.addCleanup(env.stop)
        for key in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"):
            os.environ.pop(key, None)
        base = Path(os.path.realpath(tempfile.mkdtemp()))
        self.addCleanup(shutil.rmtree, base, True)
        origin = base / "origin.git"
        self.repo = base / "primary"
        subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(origin)], check=True)
        subprocess.run(["git", "clone", "-q", str(origin), str(self.repo)], check=True, capture_output=True)
        (self.repo / "f.txt").write_text("1")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-qm", "init")
        git(self.repo, "push", "-q", "origin", "HEAD:main")
        git(self.repo, "push", "-q", "origin", "HEAD:refs/heads/claude/uikit-port")
        git(self.repo, "fetch", "-q", "origin")
        self.base = base
        self.far = Path(os.path.realpath(tempfile.mkdtemp()))  # the "current" worktree stand-in, outside every victim
        self.addCleanup(shutil.rmtree, self.far, True)

    def _tree(self, name, commit=False, merge=False):
        path = self.base / name.replace("/", "-")
        git(self.repo, "worktree", "add", "-q", "-b", name, str(path), "origin/main")
        if commit:
            (path / "x.txt").write_text(name)
            git(path, "add", ".")
            git(path, "commit", "-qm", name)
        if merge:
            git(self.repo, "push", "-q", "origin", "%s:refs/heads/main" % name)
            git(self.repo, "fetch", "-q", "origin")
        return path

    def _prune(self, dry=False, days=0.0, held=None, current=None):
        out = StringIO()
        with mock.patch.object(h, "devcap_cwds", return_value=held or []), redirect_stdout(out):
            code = h.prune_worktrees(days, dry, repo=self.repo, current=current or self.far)
        return code, out.getvalue()

    def test_only_the_merged_clean_unlocked_unheld_worktree_goes(self):
        merged = self._tree("merged", commit=True, merge=True)
        unmerged = self._tree("unmerged", commit=True)
        dirty = self._tree("dirty")
        (dirty / "scratch.txt").write_text("wip")
        locked = self._tree("locked")
        git(self.repo, "worktree", "lock", str(locked))
        held = self._tree("held")
        (held / "apple").mkdir()
        (self.repo / "tools" / "triage").mkdir(parents=True, exist_ok=True)
        (self.repo / "tools" / "triage" / "config.json").write_text(json.dumps({"workflow_base": "claude/uikit-port"}))
        protected = self._tree("claude/uikit-port")
        code, out = self._prune(held=[str(held / "apple")])
        self.assertEqual(code, 0)
        self.assertFalse(merged.exists())
        for kept in (unmerged, dirty, locked, held, protected, self.repo):
            self.assertTrue(kept.exists(), kept)
        self.assertIn("removed 1 worktree(s)", out)

    def test_dry_run_lists_but_removes_nothing(self):
        merged = self._tree("merged", commit=True, merge=True)
        code, out = self._prune(dry=True)
        self.assertEqual(code, 0)
        self.assertTrue(merged.exists())
        self.assertIn("would remove worktree %s" % merged, out)

    def test_the_current_worktree_is_never_removed(self):
        merged = self._tree("merged", commit=True, merge=True)
        (merged / "tools").mkdir()
        self._prune(current=merged / "tools")
        self.assertTrue(merged.exists())

    def test_a_recently_used_worktree_is_kept_until_it_has_been_idle_for_the_days(self):
        merged = self._tree("merged", commit=True, merge=True)
        self._prune(days=3)
        self.assertTrue(merged.exists())

    def test_a_worktree_on_main_is_protected(self):
        main_tree = self.base / "main-tree"
        git(self.repo, "checkout", "-q", "-b", "elsewhere")
        git(self.repo, "worktree", "add", "-q", str(main_tree), "main")
        self.assertEqual(h.list_worktrees(self.repo)[1]["branch"], "main")
        self._prune()
        self.assertTrue(main_tree.exists())

    def test_an_unreadable_devcap_removes_nothing(self):
        merged = self._tree("merged", commit=True, merge=True)
        err = StringIO()
        with mock.patch.object(h, "devcap_cwds", side_effect=h.HygieneError("no devcap")), redirect_stderr(err):
            self.assertEqual(h.prune_worktrees(0, False, repo=self.repo, current=self.far), 1)
        self.assertTrue(merged.exists())
        self.assertIn("not removing any worktree", err.getvalue())

    def test_workflow_base_reads_the_triage_config_and_defaults(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root, True)
        self.assertEqual(h.workflow_base(root), "main")
        (root / "tools" / "triage").mkdir(parents=True)
        (root / "tools" / "triage" / "config.json").write_text(json.dumps({"workflow_base": "claude/other"}))
        self.assertEqual(h.workflow_base(root), "claude/other")

    def test_devcap_cwds_lists_holders_and_fails_closed(self):
        root = self.devcap_dir()
        with mock.patch.dict(os.environ, {"DEVCAP_DIR": str(root)}):
            self.assertEqual(sorted(h.devcap_cwds()), ["/a/build", "/a/devic"])
        with mock.patch.dict(os.environ, {"DEVCAP_DIR": str(root / "missing")}), self.assertRaises(h.HygieneError):
            h.devcap_cwds()

    def test_a_squash_merged_multi_commit_branch_is_merged(self):
        path = self._tree("squashed")
        for n in (1, 2):
            (path / ("s%d.txt" % n)).write_text(str(n))
            git(path, "add", ".")
            git(path, "commit", "-qm", "c%d" % n)
        other = self.base / "squasher"
        git(self.repo, "worktree", "add", "-q", "-b", "squasher", str(other), "origin/main")
        git(other, "merge", "-q", "--squash", "squashed")
        git(other, "commit", "-qm", "squash")
        git(self.repo, "push", "-q", "origin", "squasher:refs/heads/main")
        git(self.repo, "fetch", "-q", "origin")
        code, out = self._prune()
        self.assertEqual(code, 0)
        self.assertFalse(path.exists())

    def test_a_branch_with_a_base_merge_and_new_work_is_not_merged_but_a_fully_landed_one_is(self):
        path = self._tree("work", commit=True)
        git(self.repo, "checkout", "-q", "-b", "other")
        (self.repo / "o.txt").write_text("o")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-qm", "other")
        git(self.repo, "push", "-q", "origin", "other:refs/heads/main")
        git(self.repo, "fetch", "-q", "origin")
        git(path, "merge", "-q", "origin/main", "-m", "merge base")
        self._prune()
        self.assertTrue(path.exists())  # x.txt is not on main
        git(self.repo, "push", "-q", "origin", "work:refs/heads/main")
        git(self.repo, "fetch", "-q", "origin")
        self._prune()
        self.assertFalse(path.exists())

    def test_a_worktree_with_a_handoff_note_is_kept(self):
        merged = self._tree("merged", commit=True, merge=True)
        (merged / "build" / "handoff").mkdir(parents=True)
        (merged / "build" / "handoff" / "topic.md").write_text("todo")
        git(merged, "add", "-f", ".")
        git(merged, "commit", "-qm", "note")
        self._prune()
        self.assertTrue(merged.exists())

    def test_primary_repo_resolution_order_and_validation(self):
        origin = str(self.base / "origin.git")
        config = self.base / "primary_repo"
        none, why = h.resolve_primary_repo(env={}, config=self.base / "absent", expected_origin=origin)
        self.assertIsNone(none)
        self.assertIn("primary_repo", why)
        config.write_text(str(self.repo) + "\n")
        self.assertEqual(h.resolve_primary_repo(env={}, config=config, expected_origin=origin), (self.repo, ""))
        self.assertEqual(h.resolve_primary_repo(env={"FENTON_PRIMARY_REPO": str(self.repo)}, config=self.base / "absent",
                                                expected_origin=origin)[0], self.repo)
        linked = self._tree("linked")
        got, why = h.resolve_primary_repo(str(linked), env={}, config=config, expected_origin=origin)
        self.assertIsNone(got)
        self.assertIn("linked worktree", why)
        got, why = h.resolve_primary_repo(str(self.repo), env={}, config=config, expected_origin="https://github.com/x/y.git")
        self.assertIsNone(got)
        self.assertIn("origin", why)
        got, why = h.resolve_primary_repo(str(self.base / "nope"), env={}, config=config, expected_origin=origin)
        self.assertIn("not a directory", why)

    def test_origin_urls_compare_across_ssh_and_https(self):
        self.assertEqual(h._norm_url("git@github.com:SFenton/Fenton-HASS-Native.git"),
                         h._norm_url("https://github.com/SFenton/Fenton-HASS-Native"))

    def test_prune_worktrees_skips_with_a_message_when_no_primary_is_configured(self):
        out = StringIO()
        with mock.patch.object(h, "resolve_primary_repo", return_value=(None, "set FENTON_PRIMARY_REPO")), redirect_stdout(out):
            self.assertEqual(h.prune_worktrees(3, False), 0)
        self.assertIn("skipped", out.getvalue())

    def test_main_passes_the_repo_flag_and_fails_on_an_invalid_one(self):
        with mock.patch.object(h, "resolve_primary_repo", return_value=(self.repo, "")), \
                mock.patch.object(h, "prune_worktrees", return_value=0) as prune:
            self.assertEqual(h.main(["prune-worktrees", "--repo", str(self.repo)]), 0)
        prune.assert_called_once_with(3.0, False, self.repo)
        with mock.patch.object(h, "resolve_primary_repo", return_value=(None, "bad")), redirect_stderr(StringIO()):
            self.assertEqual(h.main(["prune-worktrees", "--repo", "/x"]), 1)


if __name__ == "__main__":
    unittest.main()
