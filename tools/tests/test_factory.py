"""The factory report is aggregate, fail-closed and strictly read-only."""

from __future__ import annotations

import io
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import factory  # noqa: E402
import factory_lease  # noqa: E402

ENV = {
    "GIT_AUTHOR_NAME": "factory-test",
    "GIT_AUTHOR_EMAIL": "factory@example.invalid",
    "GIT_COMMITTER_NAME": "factory-test",
    "GIT_COMMITTER_EMAIL": "factory@example.invalid",
}


class StaticProcessProvider:
    def __init__(
        self,
        pids: frozenset[int] | None = frozenset(),
        cwds: tuple[Path, ...] | None = (),
        starts: dict[int, str] | None = {},
        pgids: frozenset[int] | None = frozenset(),
        *,
        error: Exception | None = None,
    ) -> None:
        self.value = factory.ProcessObservation(
            pids=pids, cwds=cwds, starts=starts, pgids=pgids
        )
        self.error = error

    def inventory(self) -> factory.ProcessObservation:
        if self.error is not None:
            raise self.error
        return self.value


class StaticResourceProvider:
    def __init__(
        self,
        resource_class: str,
        observations: tuple[factory.ResourceObservation, ...] = (),
        *,
        unreadable: int = 0,
        partial: int = 0,
        error: Exception | None = None,
    ) -> None:
        self.resource_class = resource_class
        self.observations = observations
        self.unreadable = unreadable
        self.partial = partial
        self.error = error
        self.calls = 0

    def inventory(
        self, _processes: factory.ProcessObservation
    ) -> factory.Inventory:
        self.calls += 1
        if self.error is not None:
            raise self.error
        return factory.Inventory(
            self.observations, self.unreadable, self.partial
        )


def observation(
    resource_class: str = "worktrees", **changes
) -> factory.ResourceObservation:
    values = {
        "resource_class": resource_class,
        "owned": True,
        "finished": True,
        "merge_evidence": "not_required",
    }
    values.update(changes)
    return factory.ResourceObservation(**values)


def git(root: Path, *arguments: str) -> str:
    return subprocess.run(
        ["git", "-C", str(root), *arguments],
        check=True,
        capture_output=True,
        text=True,
        env=dict(os.environ, **ENV),
    ).stdout.strip()


def snapshot(root: Path) -> dict[str, tuple[str, int, int, int]]:
    found: dict[str, tuple[str, int, int, int]] = {}
    for base, directories, files in os.walk(root, followlinks=False):
        directories.sort()
        files.sort()
        base_path = Path(base)
        relative_base = str(base_path.relative_to(root))
        base_info = base_path.lstat()
        found[relative_base or "."] = (
            "directory",
            stat.S_IMODE(base_info.st_mode),
            base_info.st_mtime_ns,
            base_info.st_size,
        )
        for name in directories:
            path = base_path / name
            info = path.lstat()
            found[f"{relative_base}/{name}"] = (
                "link" if path.is_symlink() else "directory",
                stat.S_IMODE(info.st_mode),
                info.st_mtime_ns,
                len(os.readlink(path)) if path.is_symlink() else info.st_size,
            )
        for name in files:
            path = base_path / name
            info = path.lstat()
            found[f"{relative_base}/{name}"] = (
                "link" if path.is_symlink() else path.read_bytes().hex(),
                stat.S_IMODE(info.st_mode),
                info.st_mtime_ns,
                info.st_size,
            )
    return found


class ReportContractTests(unittest.TestCase):
    def test_every_reason_is_exact_and_an_eligible_fixture_is_attested(self):
        held = tuple(
            observation(
                **(
                    {"merge_evidence": "attested", **values}
                )
            )
            for values in (
                {"active_hold": True},
                {"booted": True},
                {"dirty": True},
                {"owned": False},
                {"fresh_at_main": True},
                {"ignored": True},
                {"merge_evidence": "unknown"},
                {"live_process": True},
                {"locked": True},
                {"finished": False},
                {"partial": True},
                {"recent": True},
                {"owner_current": False},
                {"owned": None},
                {"merge_evidence": "unmerged"},
                {"unreadable": True},
                {"untracked": True},
            )
        )
        # This eligible fixture carries explicit provider attestation, not Git ancestry.
        eligible_attestation = observation(
            "worktrees",
            owned=True,
            finished=True,
            merge_evidence="attested",
        )
        providers = [
            StaticResourceProvider(
                resource_class,
                (*held, eligible_attestation)
                if resource_class == "worktrees"
                else (
                    observation(
                        resource_class,
                        merge_evidence=(
                            "attested"
                            if resource_class == "branches"
                            else "not_required"
                        ),
                    ),
                ),
            )
            for resource_class in factory.RESOURCE_CLASSES
        ]

        report = factory.build_report(providers, StaticProcessProvider())
        worktrees = report["worktrees"]
        self.assertEqual(
            (worktrees["total"], worktrees["eligible"], worktrees["held"]),
            (18, 1, 17),
        )
        self.assertEqual(
            worktrees["hold_reasons"],
            {reason: 1 for reason in factory.HOLD_REASONS},
        )
        for resource_class in factory.RESOURCE_CLASSES:
            if resource_class == "worktrees":
                continue
            aggregate = report[resource_class]
            self.assertEqual(
                (aggregate["total"], aggregate["eligible"], aggregate["held"]),
                (1, 1, 0),
            )
            self.assertTrue(
                all(n == 0 for n in aggregate["hold_reasons"].values())
            )
        self.assertTrue(all(provider.calls == 1 for provider in providers))

    def test_text_and_json_hide_raw_provider_errors(self):
        private = "/synthetic/raw-name pid-123 udid-456 sensitive detail"
        failed = StaticResourceProvider(
            "worktrees", error=factory.ProviderError(private)
        )
        providers = [
            failed,
            *(
                StaticResourceProvider(resource_class)
                for resource_class in factory.RESOURCE_CLASSES
                if resource_class != "worktrees"
            ),
        ]
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            report = factory.build_report(providers, StaticProcessProvider())
            sys.stdout.write(factory.render_text(report))
        rendered = out.getvalue()
        encoded = json.dumps(report, sort_keys=True)
        self.assertEqual(err.getvalue(), "")
        self.assertNotIn(private, rendered + encoded)
        self.assertEqual(report["worktrees"]["hold_reasons"]["unreadable"], 1)
        self.assertIn("worktrees.unknown_owner=0", rendered)
        self.assertIn("simulators total=0", rendered)

    def test_unexpected_provider_errors_are_unreadable_without_stderr(self):
        private = "/synthetic/provider-private-path"
        failures = (
            PermissionError(13, "synthetic denied", private),
            UnicodeDecodeError(
                "utf-8", b"\xff", 0, 1, "synthetic decode failure"
            ),
        )
        for failure in failures:
            with self.subTest(failure=type(failure).__name__):
                providers = [
                    StaticResourceProvider(
                        resource_class,
                        error=failure
                        if resource_class == "worktrees"
                        else None,
                    )
                    for resource_class in factory.RESOURCE_CLASSES
                ]
                out, err = io.StringIO(), io.StringIO()
                with redirect_stdout(out), redirect_stderr(err):
                    report = factory.build_report(
                        providers, StaticProcessProvider()
                    )
                self.assertEqual(err.getvalue(), "")
                self.assertEqual(out.getvalue(), "")
                self.assertEqual(
                    report["worktrees"]["hold_reasons"]["unreadable"], 1
                )

    def test_process_provider_error_supplies_a_none_snapshot(self):
        private = "/synthetic/process-private-path"

        class RecordingProvider(StaticResourceProvider):
            snapshot = None

            def inventory(
                self, processes: factory.ProcessObservation
            ) -> factory.Inventory:
                self.snapshot = processes
                return factory.Inventory()

        recording = RecordingProvider("worktrees")
        processes = StaticProcessProvider(
            error=OSError(13, "synthetic denied", private)
        )
        with redirect_stderr(io.StringIO()) as err:
            factory.build_report((recording,), processes)
        self.assertEqual(err.getvalue(), "")
        self.assertEqual(
            recording.snapshot,
            factory.ProcessObservation(pids=None, cwds=None),
        )

    def test_provider_wide_incomplete_counts_are_reported(self):
        providers = [
            StaticResourceProvider(
                resource_class,
                unreadable=int(resource_class == "branches"),
                partial=int(resource_class == "scratch"),
            )
            for resource_class in factory.RESOURCE_CLASSES
        ]
        report = factory.build_report(providers, StaticProcessProvider())
        self.assertEqual(report["branches"]["hold_reasons"]["unreadable"], 1)
        self.assertEqual(
            report["scratch"]["hold_reasons"]["partial_observation"], 1
        )
        self.assertEqual(report["branches"]["total"], 0)
        self.assertEqual(report["scratch"]["total"], 0)

    def test_cli_report_supports_json_and_prints_nothing_else(self):
        providers = tuple(
            StaticResourceProvider(resource_class)
            for resource_class in factory.RESOURCE_CLASSES
        )
        processes = StaticProcessProvider()
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(
            factory,
            "default_providers",
            return_value=(providers, processes),
        ), redirect_stdout(out), redirect_stderr(err):
            self.assertEqual(
                factory.main(["report", "--json", "--repo", "/synthetic/repo"]),
                0,
            )
        self.assertEqual(err.getvalue(), "")
        result = json.loads(out.getvalue())
        self.assertEqual(set(result), set(factory.RESOURCE_CLASSES))
        self.assertTrue(
            all(result[name]["total"] == 0 for name in factory.RESOURCE_CLASSES)
        )

    def test_cli_reports_one_fixed_error_without_private_exception_text(self):
        private = "/synthetic/cli-private-path"
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(
            factory,
            "default_providers",
            side_effect=PermissionError(13, "synthetic denied", private),
        ), redirect_stdout(out), redirect_stderr(err):
            result = factory.main(["report"])
        self.assertEqual(result, 1)
        self.assertEqual(out.getvalue(), "")
        self.assertEqual(err.getvalue(), "factory report failed\n")
        self.assertNotIn(private, err.getvalue())

    def test_not_required_and_attested_have_class_specific_effects(self):
        worktree = observation(
            "worktrees",
            finished=True,
            merge_evidence="not_required",
        )
        self.assertIn(
            "insufficient_merge_evidence", factory.classify(worktree)
        )
        simulator = observation(
            "simulators",
            finished=True,
            merge_evidence="attested",
        )
        self.assertIn(
            "insufficient_merge_evidence", factory.classify(simulator)
        )
        attested = observation(
            "worktrees",
            finished=True,
            merge_evidence="attested",
        )
        self.assertEqual(factory.classify(attested), frozenset())
        ancestor = observation(
            "worktrees",
            finished=True,
            merge_evidence="ancestor",
        )
        self.assertEqual(
            factory.classify(ancestor),
            frozenset(("insufficient_merge_evidence",)),
        )

    def test_holder_start_and_missing_inventory_are_exact_hold_facts(self):
        record = {"holder": {"pid": 71, "start": "synthetic-start"}}
        complete = factory.ProcessObservation(
            pids=frozenset({71}),
            cwds=(),
            starts={71: "synthetic-start"},
            pgids=frozenset(),
        )
        reused = factory.ProcessObservation(
            pids=frozenset({71}),
            cwds=(),
            starts={71: "different-start"},
            pgids=frozenset(),
        )
        missing = factory.ProcessObservation(
            pids=None, cwds=None, starts=None, pgids=None
        )
        self.assertEqual(factory.holder_status(record, complete), (True, False))
        self.assertEqual(factory.holder_status(record, reused), (False, False))
        self.assertEqual(factory.holder_status(record, missing), (False, True))


class ReadOnlyBoundaryTests(unittest.TestCase):
    def test_only_allowlisted_read_commands_reach_the_runner(self):
        calls = []

        def run(command, **values):
            calls.append((command, values))
            return subprocess.CompletedProcess(command, 0, "output\n", "")

        runner = factory.ReadOnlyRunner(run)
        with mock.patch.dict(
            os.environ,
            {"GIT_INDEX_FILE": "/synthetic/index", "GIT_OPTIONAL_LOCKS": "1"},
        ):
            runner.run(["git", "-C", "/repo", "rev-parse", "HEAD"])
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][1]["env"]["GIT_OPTIONAL_LOCKS"], "0")
        self.assertNotIn("GIT_INDEX_FILE", calls[0][1]["env"])

        before = len(calls)
        for command in (
            ["git", "-C", "/repo", "clean", "-fd"],
            ["git", "-C", "/repo", "merge-tree", "--write-tree", "a", "b"],
            ["git", "-C", "/repo", "fetch", "origin"],
            ["xcrun", "simctl", "delete", "UDID"],
            ["xcrun", "simctl", "list", "devices", "-j", "extra"],
            ["kill", "123"],
        ):
            with self.assertRaises(factory.MutatingProviderCall):
                runner.run(command)
        self.assertEqual(len(calls), before)

    def test_refused_provider_command_becomes_unreadable_without_stderr(self):
        calls = []

        def run(command, **values):
            calls.append((command, values))
            return subprocess.CompletedProcess(command, 0, b"", b"")

        class RefusingProvider:
            resource_class = "worktrees"

            def __init__(self) -> None:
                self.runner = factory.ReadOnlyRunner(run)

            def inventory(
                self, _processes: factory.ProcessObservation
            ) -> factory.Inventory:
                self.runner.run(
                    ["git", "-C", "/synthetic/repo", "clean", "-fd"]
                )
                return factory.Inventory()

        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            report = factory.build_report(
                (RefusingProvider(),), StaticProcessProvider()
            )
        self.assertEqual(err.getvalue(), "")
        self.assertEqual(out.getvalue(), "")
        self.assertEqual(calls, [])
        self.assertEqual(
            report["worktrees"]["hold_reasons"]["unreadable"], 1
        )

    def test_process_provider_uses_read_only_commands_and_handles_empty_ps(self):
        commands = []

        def run(command, **_values):
            commands.append(command)
            if command[:1] == ["ps"]:
                return subprocess.CompletedProcess(
                    command, 0, b"\n7\n\xff\n", b""
                )
            return subprocess.CompletedProcess(
                command, 0, b"n/synthetic/path\n", b""
            )

        provider = factory.ReadOnlyProcessProvider(factory.ReadOnlyRunner(run))
        result = provider.inventory()
        self.assertEqual(result.pids, frozenset({7}))
        self.assertEqual(result.cwds, (Path("/synthetic/path"),))
        self.assertEqual(
            commands[0], ["ps", "-axo", "pid=,lstart=,pgid="]
        )

    def test_process_provider_normalizes_a_padded_day_from_real_ps_shape(self):
        raw_start = "Sat Nov  7 09:26:17 2026"

        def run(command, **_values):
            if command[:1] == ["ps"]:
                return subprocess.CompletedProcess(
                    command,
                    0,
                    b"  73  " + raw_start.encode("ascii") + b"  91\n",
                    b"",
                )
            return subprocess.CompletedProcess(command, 0, b"", b"")

        provider = factory.ReadOnlyProcessProvider(factory.ReadOnlyRunner(run))
        result = provider.inventory()
        self.assertEqual(
            result.starts,
            {73: "Sat Nov 7 09:26:17 2026"},
        )
        self.assertEqual(result.pgids, frozenset({91}))


class SimulatorProviderTests(unittest.TestCase):
    def test_owned_idle_shutdown_simulator_is_eligible_and_holds_are_exact(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            old, recent, foreign, booted, held = (
                "A" * 36,
                "B" * 36,
                "C" * 36,
                "D" * 36,
                "E" * 36,
            )
            now = 2_000_000
            (root / "sims.json").write_text(
                json.dumps(
                    {
                        old: {
                            "kind": "pool",
                            "project": "project",
                            "last_release_epoch": now - 100_000,
                        },
                        recent: {
                            "kind": "pool",
                            "project": "project",
                            "last_release_epoch": now - 10,
                        },
                        foreign: {
                            "kind": "pool",
                            "project": "other",
                            "last_release_epoch": now - 100_000,
                        },
                        booted: {
                            "kind": "ephemeral",
                            "project": "project",
                            "last_release_epoch": now - 100_000,
                        },
                        held: {
                            "kind": "pool",
                            "project": "project",
                            "last_release_epoch": now - 100_000,
                        },
                    }
                )
            )
            gate = root / f"device-{held}"
            gate.mkdir()
            (gate / "slot-1.json").write_text('{"pid": 123}')
            listing = {
                "devices": {
                    "runtime": [
                        {"udid": old, "state": "Shutdown"},
                        {"udid": recent, "state": "Shutdown"},
                        {"udid": foreign, "state": "Shutdown"},
                        {"udid": booted, "state": "Booted"},
                        {"udid": held, "state": "Shutdown"},
                    ]
                }
            }

            def run(command, **_values):
                return subprocess.CompletedProcess(
                    command, 0, json.dumps(listing), ""
                )

            reader = mock.Mock()
            reader.project_name.return_value = "project"
            provider = factory.SimulatorResourceProvider(
                Path("."),
                factory.ReadOnlyRunner(run),
                reader,
                devcap_root=root,
                now=now,
            )
            before = snapshot(root)
            with mock.patch.dict(
                os.environ, {"DEVCAP_PROJECT": "project"}, clear=False
            ):
                first = provider.inventory(StaticProcessProvider().inventory())
                second = provider.inventory(StaticProcessProvider().inventory())
            self.assertEqual(first, second)
            self.assertEqual(snapshot(root), before)
            report = factory.empty_report()
            factory.add_inventory(report, "simulators", first)
            aggregate = report["simulators"]
            self.assertEqual(
                (
                    aggregate["total"],
                    aggregate["eligible"],
                    aggregate["held"],
                ),
                (5, 1, 4),
            )
            expected = {
                reason: 1
                if reason
                in {
                    "active_hold",
                    "booted",
                    "foreign",
                    "not_finished",
                    "recent",
                }
                else 0
                for reason in factory.HOLD_REASONS
            }
            expected["not_finished"] = 2
            self.assertEqual(aggregate["hold_reasons"], expected)

    def test_unreadable_simulator_input_becomes_an_enum_count(self):
        def fail(command, **_values):
            return subprocess.CompletedProcess(command, 1, "", "private error")

        provider = factory.SimulatorResourceProvider(
            Path("."),
            factory.ReadOnlyRunner(fail),
            mock.Mock(project_name=mock.Mock(return_value=None)),
            devcap_root=Path("/not-present"),
        )
        inventory = provider.inventory(StaticProcessProvider().inventory())
        self.assertEqual(inventory.unreadable, 1)
        self.assertEqual(inventory.observations, ())

    def test_malformed_registry_partial_state_does_not_leak(self):
        with tempfile.TemporaryDirectory() as raw:
            (Path(raw) / "sims.json").write_text("synthetic malformed")
            listing = {
                "devices": {
                    "runtime": [{"udid": "A" * 36, "state": "Shutdown"}]
                }
            }

            def run(command, **_values):
                return subprocess.CompletedProcess(
                    command, 0, json.dumps(listing), ""
                )

            provider = factory.SimulatorResourceProvider(
                Path("."),
                factory.ReadOnlyRunner(run),
                mock.Mock(project_name=mock.Mock(return_value="project")),
                devcap_root=Path(raw),
            )
            inventory = provider.inventory(
                StaticProcessProvider().inventory()
            )
            report = factory.empty_report()
            factory.add_inventory(report, "simulators", inventory)
            self.assertEqual(
                report["simulators"]["hold_reasons"]["partial_observation"],
                1,
            )
            self.assertNotIn("synthetic malformed", factory.render_text(report))


class GitProviderProofTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self._temporary.cleanup)
        self.root = Path(self._temporary.name)
        self.repo = self.root / "repository"
        self.lane = self.root / "lane"
        git(self.root, "init", "-q", "-b", "main", str(self.repo))
        git(self.repo, "config", "user.name", "factory-test")
        git(self.repo, "config", "user.email", "factory@example.invalid")
        (self.repo / ".gitignore").write_text(
            "ignored.txt\napple/.build/\napple/build/\nbuild/\n"
        )
        (self.repo / "tracked.txt").write_text("base\n")
        (self.repo / "apple").mkdir()
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "base")
        old_main = git(self.repo, "rev-parse", "HEAD")
        git(
            self.repo,
            "worktree",
            "add",
            "-q",
            "-b",
            "agents/lane",
            str(self.lane),
            "main",
        )
        (self.lane / "tracked.txt").write_text("base plus lane\n")
        git(self.lane, "add", "tracked.txt")
        git(self.lane, "commit", "-qm", "lane")
        (self.lane / "tracked.txt").write_text("dirty lane\n")
        (self.lane / "untracked.txt").write_text("synthetic untracked")
        (self.lane / "ignored.txt").write_text("synthetic ignored")
        (self.lane / "apple" / ".build").mkdir(parents=True)
        (self.lane / "apple" / ".build" / "product").write_text("artifact")
        (self.lane / "build" / "tmp").mkdir(parents=True)
        (self.lane / "build" / "tmp" / "scratch").write_text("artifact")
        (self.lane / "build" / "runs").mkdir()
        (self.lane / "build" / "runs" / "left.running").write_text(
            json.dumps({"pid": 4242, "cwd": "/synthetic/raw-cwd"})
        )
        git(self.repo, "branch", "agents/older", old_main)
        (self.repo / "main-only.txt").write_text("new main\n")
        git(self.repo, "add", "main-only.txt")
        git(self.repo, "commit", "-qm", "advance main")
        git(
            self.repo,
            "update-ref",
            "refs/remotes/origin/main",
            "HEAD",
        )
        git(self.repo, "branch", "agents/fresh", "main")

        runner = factory.ReadOnlyRunner()
        reader = factory.GitReader(self.repo, runner)
        self.providers = tuple(
            factory.GitResourceProvider(resource_class, self.repo, reader)
            for resource_class in (
                "worktrees",
                "branches",
                "build_output",
                "scratch",
                "run_markers",
            )
        ) + (StaticResourceProvider("simulators"),)
        self.processes = StaticProcessProvider(
            pids=frozenset({4242}), cwds=()
        )

    def test_repeated_reports_preserve_files_ignored_files_and_git_state(self):
        before_repo = snapshot(self.repo)
        before_lane = snapshot(self.lane)
        first = factory.build_report(self.providers, self.processes)
        second = factory.build_report(self.providers, self.processes)
        self.assertEqual(first, second)
        self.assertEqual(snapshot(self.repo), before_repo)
        self.assertEqual(snapshot(self.lane), before_lane)

        reasons = first["worktrees"]["hold_reasons"]
        self.assertEqual(
            (reasons["dirty"], reasons["untracked"], reasons["ignored"]),
            (1, 1, 1),
        )
        self.assertEqual(reasons["unknown_owner"], 1)
        self.assertEqual(reasons["unmerged"], 1)
        self.assertEqual(first["worktrees"]["held"], 1)

        branches = first["branches"]["hold_reasons"]
        self.assertEqual(first["branches"]["total"], 3)
        self.assertEqual(branches["fresh_at_main"], 1)
        self.assertEqual(branches["insufficient_merge_evidence"], 1)
        self.assertEqual(branches["unmerged"], 1)
        self.assertEqual(branches["active_hold"], 1)
        self.assertEqual(branches["unknown_owner"], 3)
        self.assertEqual(first["branches"]["held"], 3)

        self.assertEqual(first["build_output"]["total"], 1)
        self.assertEqual(first["scratch"]["total"], 1)
        self.assertEqual(first["run_markers"]["total"], 1)
        self.assertEqual(
            first["run_markers"]["hold_reasons"]["live_process"], 1
        )
        rendered = json.dumps(first, sort_keys=True) + factory.render_text(first)
        self.assertNotIn(str(self.repo), rendered)
        self.assertNotIn(str(self.lane), rendered)
        self.assertNotIn("4242", rendered)
        self.assertNotIn("/synthetic/", rendered)

    def test_cwd_inside_lane_holds_real_worktree_for_live_process(self):
        report = factory.build_report(
            self.providers,
            StaticProcessProvider(
                pids=frozenset({4242}), cwds=(self.lane / "apple",)
            ),
        )
        reasons = report["worktrees"]["hold_reasons"]
        self.assertEqual(reasons["active_hold"], 1)
        self.assertEqual(reasons["live_process"], 1)
        self.assertEqual(report["worktrees"]["held"], 1)

    def test_locked_second_lane_holds_real_worktree(self):
        locked = self.root / "locked-lane"
        git(
            self.repo,
            "worktree",
            "add",
            "-q",
            "-b",
            "agents/locked",
            str(locked),
            "main",
        )
        git(
            self.repo,
            "worktree",
            "lock",
            "--reason",
            "synthetic lock",
            str(locked),
        )
        report = factory.build_report(self.providers, self.processes)
        self.assertEqual(report["worktrees"]["hold_reasons"]["locked"], 1)

    def test_removed_lane_directory_holds_for_failed_real_git_status(self):
        shutil.rmtree(self.lane)
        report = factory.build_report(self.providers, self.processes)
        self.assertEqual(
            report["worktrees"]["hold_reasons"]["unreadable"], 1
        )
        self.assertEqual(report["worktrees"]["held"], 1)

    def test_missing_cwd_snapshot_holds_real_worktree_as_partial(self):
        report = factory.build_report(
            self.providers,
            StaticProcessProvider(pids=frozenset({4242}), cwds=None),
        )
        self.assertEqual(
            report["worktrees"]["hold_reasons"]["partial_observation"], 1
        )
        self.assertEqual(report["worktrees"]["held"], 1)

    def test_malformed_marker_is_an_unreadable_count_without_raw_error(self):
        (self.lane / "build" / "runs" / "broken.running").write_text("no json")
        inventory = self.providers[-2].inventory(
            StaticProcessProvider().inventory()
        )
        report = factory.empty_report()
        factory.add_inventory(report, "run_markers", inventory)
        self.assertEqual(report["run_markers"]["total"], 2)
        self.assertEqual(
            report["run_markers"]["hold_reasons"]["unreadable"], 1
        )
        self.assertNotIn("no json", factory.render_text(report))

    def leased_providers(self, store, now):
        records, invalid = store.__class__(store.identity, now=now).read_records()
        self.assertEqual(invalid, 0)
        snapshot = factory.LeaseSnapshot(
            identity=store.identity, records=tuple(records), invalid=invalid
        )
        reader = factory.GitReader(self.repo, factory.ReadOnlyRunner())
        return tuple(
            factory.GitResourceProvider(
                resource_class, self.repo, reader, snapshot, now=now
            )
            for resource_class in (
                "worktrees",
                "branches",
                "build_output",
                "scratch",
                "run_markers",
            )
        )

    def attest_lane(self, store, worktree_id=None, branch_id=None):
        if worktree_id is None or branch_id is None:
            worktree_id, branch_id = store.create_worktree(
                self.lane,
                "lane_new",
                task="proof",
                branch_created="agents/lane",
            )
        head = git(self.lane, "rev-parse", "HEAD")

        class Pulls(factory_lease.PullRequestProvider):
            repository = "example/project"

            def list_for_branch(inner, repository, branch):
                return (
                    factory_lease.PullRequestEvidence(
                        80,
                        repository,
                        "main",
                        branch,
                        "MERGED",
                        head,
                        int(store.now()),
                    ),
                )

        store.reconcile(branch_id, provider=Pulls())
        return worktree_id, branch_id, head

    def clean_lane(self):
        commit_text = self.git_result(
            self.lane, "show", "HEAD:tracked.txt"
        ).rstrip("\n") + "\n"
        (self.lane / "tracked.txt").write_text(commit_text)
        for name in ("untracked.txt", "ignored.txt"):
            path = self.lane / name
            if path.exists():
                path.unlink()
        for relative in ("apple/.build", "apple/build", "build"):
            path = self.lane / relative
            if path.exists():
                shutil.rmtree(path)

    def git_result(self, cwd, *arguments):
        return subprocess.run(
            ["git", "-C", str(cwd), *arguments],
            capture_output=True,
            text=True,
            check=True,
            env=dict(os.environ, **ENV),
        ).stdout

    def test_production_git_provider_admits_only_expired_attested_lease(self):
        self.clean_lane()
        store = factory_lease.LeaseStore.for_repo(self.lane)
        _worktree_id, branch_id = store.create_worktree(
            self.lane,
            "lane_new",
            task="proof",
            branch_created="agents/lane",
        )
        head = git(self.lane, "rev-parse", "HEAD")

        class Pulls(factory_lease.PullRequestProvider):
            repository = "example/project"

            def list_for_branch(self, repository, branch):
                return (
                    factory_lease.PullRequestEvidence(
                        71,
                        repository,
                        "main",
                        branch,
                        "MERGED",
                        head,
                        int(store.now()),
                    ),
                )

        store.reconcile(branch_id, provider=Pulls())
        records, _invalid = store.read_records()
        expiry = max(record["expires"] for record in records)
        providers = self.leased_providers(store, expiry + 1)
        processes = StaticProcessProvider(
            pids=frozenset(), cwds=(), starts={}, pgids=frozenset()
        )
        report = factory.build_report(providers, processes)
        self.assertEqual(
            (
                report["worktrees"]["total"],
                report["worktrees"]["eligible"],
                report["worktrees"]["held"],
            ),
            (1, 1, 0),
        )
        self.assertEqual(
            report["worktrees"]["hold_reasons"]["insufficient_merge_evidence"],
            0,
        )
        (self.lane / "tracked.txt").write_text("later commit candidate\n")
        changed = factory.build_report(providers, processes)
        self.assertEqual(changed["worktrees"]["eligible"], 0)
        self.assertEqual(changed["worktrees"]["hold_reasons"]["dirty"], 1)

    def test_invalid_reconciliation_ancestry_and_fresh_branch_stay_held(self):
        self.clean_lane()
        store = factory_lease.LeaseStore.for_repo(self.lane)
        worktree_id, branch_id = store.create_worktree(
            self.lane,
            "lane_new",
            task="proof",
            branch_created="agents/lane",
        )
        head = git(self.lane, "rev-parse", "HEAD")

        class Pulls(factory_lease.PullRequestProvider):
            repository = "example/project"

            def __init__(self, evidence):
                self.evidence = tuple(evidence)

            def list_for_branch(self, repository, branch):
                return self.evidence

        def pull(**changes):
            values = {
                "number": 81,
                "repository": Pulls.repository,
                "base": "main",
                "branch": "agents/lane",
                "state": "MERGED",
                "head_oid": head,
                "created_at": int(store.now()),
            }
            values.update(changes)
            return factory_lease.PullRequestEvidence(**values)

        invalid = (
            pull(repository="example/other"),
            pull(base="other"),
            pull(branch="agents/other"),
            pull(created_at=int(store.now()) - 1),
            pull(created_at=None),
            pull(state="CLOSED"),
        )
        for item in invalid:
            with self.subTest(item=item):
                with self.assertRaises(factory_lease.InvalidLease):
                    store.reconcile(
                        branch_id, provider=Pulls((item,))
                    )
        with self.assertRaises(factory_lease.InvalidLease):
            store.reconcile(branch_id, provider=Pulls(()))

        class Broken(factory_lease.PullRequestProvider):
            def list_for_branch(self, repository, branch):
                raise factory_lease.LeaseError("provider unavailable")

        with self.assertRaises(factory_lease.LeaseError):
            store.reconcile(branch_id, provider=Broken())

        records = store.read_records()[0]
        branch_record = [
            record for record in records if record["lease_id"] == branch_id
        ][0]
        changed_branch = dict(branch_record)
        changed_branch["subject"] = dict(branch_record["subject"])
        changed_branch["subject"]["parent_generation"] += 1
        store._write_record(changed_branch)
        with self.assertRaises(factory_lease.InvalidLease):
            store.reconcile(branch_id, provider=Pulls((pull(),)))
        store._write_record(branch_record)

        records, _invalid = store.read_records()
        expiry = max(record["expires"] for record in records)
        unresolved = factory.build_report(
            (self.leased_providers(store, expiry + 1)[0],),
            StaticProcessProvider(),
        )["worktrees"]
        self.assertEqual(unresolved["eligible"], 0)
        self.assertEqual(
            {
                reason
                for reason, count in unresolved["hold_reasons"].items()
                if count
            },
            {"not_finished", "unmerged"},
        )

        git(self.repo, "merge", "--no-ff", "-qm", "fixture merge", "agents/lane")
        git(self.repo, "update-ref", "refs/remotes/origin/main", "HEAD")
        git(self.repo, "branch", "-f", "agents/fresh", "main")
        fresh = self.root / "fresh-lane"
        git(
            self.repo,
            "worktree",
            "add",
            "-q",
            str(fresh),
            "agents/fresh",
        )
        store.create_worktree(
            fresh, "lane_new", task="fresh", branch_created=None
        )
        refreshed_records, _invalid = store.read_records()
        refreshed_expiry = max(
            record["expires"] for record in refreshed_records
        )
        report = factory.build_report(
            (self.leased_providers(store, refreshed_expiry + 1)[0],),
            StaticProcessProvider(),
        )["worktrees"]
        self.assertEqual(
            (report["total"], report["eligible"], report["held"]),
            (2, 0, 2),
        )
        self.assertEqual(report["hold_reasons"]["fresh_at_main"], 1)
        self.assertEqual(
            report["hold_reasons"]["insufficient_merge_evidence"], 1
        )
        self.assertEqual(report["hold_reasons"]["not_finished"], 2)

    def test_unreconciled_owned_git_resources_remain_held(self):
        store = factory_lease.LeaseStore.for_repo(self.lane)
        store.create_worktree(
            self.lane,
            "lane_new",
            task="proof",
            branch_created="agents/lane",
        )
        records, _invalid = store.read_records()
        future = max(record["expires"] for record in records) + 1
        report = factory.build_report(
            self.leased_providers(store, future),
            StaticProcessProvider(),
        )
        self.assertEqual(report["worktrees"]["eligible"], 0)
        self.assertEqual(
            report["worktrees"]["hold_reasons"]["insufficient_merge_evidence"],
            0,
        )
        self.assertEqual(report["worktrees"]["hold_reasons"]["unmerged"], 1)
        self.assertEqual(report["worktrees"]["hold_reasons"]["not_finished"], 1)

    def test_wrong_repo_class_and_nonce_are_exact_unknown_owners(self):
        self.clean_lane()
        store = factory_lease.LeaseStore.for_repo(self.lane)
        worktree_id, _branch_id = store.create_worktree(
            self.lane,
            "lane_new",
            task="proof",
            branch_created="agents/lane",
        )
        record_path = (
            store.identity.common_dir
            / "factory"
            / "leases"
            / "worktree"
            / (worktree_id + ".json")
        )
        original = json.loads(record_path.read_text())
        mutations = (
            (
                "wrong_repo",
                {
                    **original,
                    "repo": {
                        "common_dir": str(self.root / "foreign"),
                        "root_commit": original["repo"]["root_commit"],
                    },
                },
            ),
            ("wrong_class", {**original, "class": "branch"}),
        )
        for label, value in mutations:
            with self.subTest(label=label):
                record_path.write_text(json.dumps(value) + "\n")
                records, invalid = store.read_records()
                snapshot = factory.LeaseSnapshot(
                    identity=store.identity,
                    records=tuple(records),
                    invalid=invalid,
                )
                provider = factory.GitResourceProvider(
                    "worktrees",
                    self.repo,
                    factory.GitReader(self.repo, factory.ReadOnlyRunner()),
                    snapshot,
                    now=store.now(),
                )
                report = factory.build_report(
                    (provider,), StaticProcessProvider()
                )["worktrees"]
                self.assertEqual(report["eligible"], 0)
                self.assertEqual(
                    {
                        reason
                        for reason, count in report["hold_reasons"].items()
                        if count
                    },
                    {
                        "partial_observation",
                        "unknown_owner",
                        "unmerged",
                    },
                )
                record_path.write_text(json.dumps(original) + "\n")

        nonce_path = Path(original["subject"]["nonce_path"])
        original_nonce = nonce_path.read_text()
        nonce_path.write_text("f" * 32 + "\n")
        report = factory.build_report(
            (self.leased_providers(store, store.now())[0],),
            StaticProcessProvider(),
        )["worktrees"]
        self.assertEqual(report["eligible"], 0)
        self.assertEqual(
            {
                reason
                for reason, count in report["hold_reasons"].items()
                if count
            },
            {"unknown_owner", "unmerged"},
        )
        nonce_path.write_text(original_nonce)

    def test_report_preserves_store_and_directory_state_when_present(self):
        store = factory_lease.LeaseStore.for_repo(self.lane)
        store.create_worktree(
            self.lane,
            "lane_new",
            task="proof",
            branch_created="agents/lane",
        )
        store_root = store.identity.common_dir / "factory"
        before_store = snapshot(store_root)
        before_lane = snapshot(self.lane)
        processes = StaticProcessProvider()
        providers = self.leased_providers(store, store.now())
        with mock.patch.object(
            factory_lease.fcntl,
            "flock",
            side_effect=AssertionError("report took the writer lock"),
        ):
            first = factory.build_report(providers, processes)
            second = factory.build_report(providers, processes)
        self.assertEqual(first, second)
        self.assertEqual(snapshot(store_root), before_store)
        self.assertEqual(snapshot(self.lane), before_lane)

    def test_marker_start_and_group_inventory_are_independent_holds(self):
        self.clean_lane()
        store = factory_lease.LeaseStore.for_repo(self.lane)
        store.create_worktree(
            self.lane,
            "lane_new",
            task="proof",
            branch_created="agents/lane",
        )
        marker = self.lane / "build" / "runs" / "proof.running"
        marker.parent.mkdir(parents=True, exist_ok=True)
        lease_id = store.begin_run(
            self.lane, marker.resolve(), "proof", os.getpid()
        )
        self.assertIsNotNone(lease_id)
        store.end_run(lease_id)
        wrapper_pid = 200001
        wrapper_start = "synthetic wrapper start"
        group = 200002
        marker.write_text(
            json.dumps(
                {
                    "v": 1,
                    "pid": wrapper_pid,
                    "label": "proof",
                    "started": 1,
                    "cwd": str(self.lane),
                    "lease_id": lease_id,
                    "start": wrapper_start,
                    "pgid": group,
                }
            )
        )
        records, _invalid = store.read_records()
        future = max(record["expires"] for record in records) + 1
        provider = [
            value
            for value in self.leased_providers(store, future)
            if value.resource_class == "run_markers"
        ][0]

        cases = (
            (
                factory.ProcessObservation(
                    pids=frozenset({wrapper_pid}),
                    cwds=(),
                    starts={wrapper_pid: wrapper_start},
                    pgids=frozenset(),
                ),
                frozenset(("active_hold", "live_process")),
                0,
            ),
            (
                factory.ProcessObservation(
                    pids=frozenset({wrapper_pid}),
                    cwds=(),
                    starts={wrapper_pid: "synthetic reused start"},
                    pgids=frozenset(),
                ),
                frozenset(),
                1,
            ),
            (
                factory.ProcessObservation(
                    pids=frozenset(),
                    cwds=(),
                    starts={},
                    pgids=frozenset({group}),
                ),
                frozenset(("active_hold", "live_process")),
                0,
            ),
            (
                factory.ProcessObservation(
                    pids=None, cwds=None, starts=None, pgids=None
                ),
                frozenset(("not_finished", "partial_observation")),
                0,
            ),
        )
        for processes, expected, eligible in cases:
            with self.subTest(expected=expected):
                inventory = provider.inventory(processes)
                self.assertEqual(
                    factory.classify(inventory.observations[0]), expected
                )
                report = factory.build_report(
                    (provider,),
                    StaticProcessProvider(
                        pids=processes.pids,
                        cwds=processes.cwds,
                        starts=processes.starts,
                        pgids=processes.pgids,
                    ),
                )
                self.assertEqual(report["run_markers"]["eligible"], eligible)
        marker_value = json.loads(marker.read_text())
        marker_value["start"] = ""
        marker.write_text(json.dumps(marker_value))
        missing_start = factory.ProcessObservation(
            pids=frozenset({wrapper_pid}),
            cwds=(),
            starts={wrapper_pid: wrapper_start},
            pgids=frozenset(),
        )
        inventory = provider.inventory(missing_start)
        self.assertEqual(
            factory.classify(inventory.observations[0]),
            frozenset(
                (
                    "active_hold",
                    "live_process",
                    "not_finished",
                    "partial_observation",
                )
            ),
        )
        self.assertEqual(
            factory.build_report(
                (provider,),
                StaticProcessProvider(
                    pids=missing_start.pids,
                    cwds=missing_start.cwds,
                    starts=missing_start.starts,
                    pgids=missing_start.pgids,
                ),
            )["run_markers"]["eligible"],
            0,
        )

    def test_reused_pid_with_cwd_holds_worktree_even_after_holder_reuse(self):
        self.clean_lane()
        store = factory_lease.LeaseStore.for_repo(self.lane)
        worktree_id, branch_id = store.create_worktree(
            self.lane,
            "lane_new",
            task="proof",
            branch_created="agents/lane",
        )
        records, _invalid = store.read_records()
        worktree = [
            record for record in records if record["lease_id"] == worktree_id
        ][0]
        holder = {"pid": 71, "start": "synthetic start"}
        worktree = dict(worktree)
        worktree["holder"] = holder
        store._write_record(worktree)
        self.attest_lane(store, worktree_id, branch_id)
        records, _invalid = store.read_records()
        expiry = max(record["expires"] for record in records)
        processes = factory.ProcessObservation(
            pids=frozenset({71}),
            starts={71: "different start"},
            pgids=frozenset(),
            cwds=(self.root / "outside",),
        )
        providers = self.leased_providers(store, expiry + 1)
        reused = factory.build_report(
            (providers[0],),
            StaticProcessProvider(
                pids=processes.pids,
                starts=processes.starts,
                pgids=processes.pgids,
                cwds=processes.cwds,
            ),
        )["worktrees"]
        self.assertEqual(reused["eligible"], 1)
        with_cwd = factory.build_report(
            (providers[0],),
            StaticProcessProvider(
                pids=processes.pids,
                starts=processes.starts,
                pgids=processes.pgids,
                cwds=(self.lane / "apple",),
            ),
        )["worktrees"]
        self.assertEqual(with_cwd["eligible"], 0)
        self.assertEqual(
            with_cwd["hold_reasons"],
            {
                reason: int(reason in {"active_hold", "live_process"})
                for reason in factory.HOLD_REASONS
            },
        )
        self.assertFalse(factory.holder_status(worktree, processes)[0])

    def test_missing_holder_start_empty_cwd_and_partial_table_hold_exactly(self):
        self.clean_lane()
        store = factory_lease.LeaseStore.for_repo(self.lane)
        worktree_id, branch_id = store.create_worktree(
            self.lane,
            "lane_new",
            task="proof",
            branch_created="agents/lane",
        )
        records, _invalid = store.read_records()
        worktree = [
            record for record in records if record["lease_id"] == worktree_id
        ][0]
        worktree = dict(worktree)
        worktree["holder"] = {"pid": 91, "start": "synthetic holder"}
        store._write_record(worktree)
        self.attest_lane(store, worktree_id, branch_id)
        records, _invalid = store.read_records()
        expiry = max(record["expires"] for record in records)
        provider = self.leased_providers(store, expiry + 1)[0]
        cases = (
            (
                StaticProcessProvider(
                    pids=frozenset({91}),
                    cwds=(self.root / "outside",),
                    starts={},
                ),
                frozenset(("partial_observation",)),
            ),
            (
                StaticProcessProvider(
                    pids=frozenset({999}),
                    cwds=(),
                    starts={999: "synthetic"},
                ),
                frozenset(("partial_observation",)),
            ),
            (
                StaticProcessProvider(
                    pids=frozenset({91}),
                    cwds=None,
                    starts={91: "synthetic holder"},
                ),
                frozenset(
                    ("active_hold", "live_process", "partial_observation")
                ),
            ),
            (
                StaticProcessProvider(
                    pids=None,
                    cwds=(self.root / "outside",),
                    starts=None,
                ),
                frozenset(("partial_observation",)),
            ),
        )
        for processes, expected in cases:
            with self.subTest(expected=expected):
                observation = provider.inventory(
                    processes.inventory()
                ).observations[0]
                self.assertEqual(factory.classify(observation), expected)
                report = factory.build_report((provider,), processes)
                self.assertEqual(report["worktrees"]["eligible"], 0)
                self.assertEqual(
                    report["worktrees"]["hold_reasons"][
                        "partial_observation"
                    ],
                    1,
                )

    def test_unexpired_release_future_expiry_and_unreleased_lease_hold(self):
        self.clean_lane()
        store = factory_lease.LeaseStore.for_repo(self.lane)
        worktree_id, branch_id = store.create_worktree(
            self.lane,
            "lane_new",
            task="proof",
            branch_created="agents/lane",
        )
        records, _invalid = store.read_records()
        expiry = max(record["expires"] for record in records)
        active = factory.build_report(
            (self.leased_providers(store, store.now())[0],),
            StaticProcessProvider(),
        )["worktrees"]
        self.assertEqual(active["eligible"], 0)
        self.assertEqual(
            {
                reason
                for reason, count in active["hold_reasons"].items()
                if count
            },
            {"active_hold", "not_finished", "unmerged"},
        )
        store.release(worktree_id, "ended")
        store.release(branch_id, "ended", "branch")
        released = factory.build_report(
            (self.leased_providers(store, expiry - 1)[0],),
            StaticProcessProvider(),
        )["worktrees"]
        self.assertEqual(released["eligible"], 0)
        self.assertEqual(
            {
                reason
                for reason, count in released["hold_reasons"].items()
                if count
            },
            {"active_hold", "not_finished", "unmerged"},
        )
        expired_unreleased_store = factory_lease.LeaseStore.for_repo(self.lane)
        expired = factory.build_report(
            (
                self.leased_providers(
                    expired_unreleased_store, expiry + 1
                )[0],
            ),
            StaticProcessProvider(),
        )["worktrees"]
        self.assertEqual(expired["eligible"], 0)
        self.assertEqual(
            {
                reason
                for reason, count in expired["hold_reasons"].items()
                if count
            },
            {"unmerged"},
        )
        expired_unreleased_store.renew_worktree(self.lane, "agents/lane")
        renewed_records, _invalid = expired_unreleased_store.read_records()
        renewed_expiry = max(
            record["expires"] for record in renewed_records
        )
        unreleased = factory.build_report(
            (
                self.leased_providers(
                    expired_unreleased_store, renewed_expiry + 1
                )[0],
            ),
            StaticProcessProvider(),
        )["worktrees"]
        self.assertEqual(unreleased["eligible"], 0)
        self.assertEqual(
            {
                reason
                for reason, count in unreleased["hold_reasons"].items()
                if count
            },
            {"not_finished", "unmerged"},
        )

    def test_owned_finished_build_plans_is_explicitly_held_not_ignored(self):
        self.clean_lane()
        ignore = self.lane / ".gitignore"
        ignore.write_text(
            ignore.read_text().replace("build/\n", "")
        )
        self.git_result(self.lane, "add", ".gitignore")
        self.git_result(self.lane, "commit", "-qm", "track build")
        plans = self.lane / "build" / "plans"
        plans.mkdir(parents=True)
        (plans / "plan.md").write_text("fixture")
        self.git_result(self.lane, "add", "build/plans/plan.md")
        self.git_result(self.lane, "commit", "-qm", "track plan")
        store = factory_lease.LeaseStore.for_repo(self.lane)
        self.attest_lane(store)
        records, _invalid = store.read_records()
        expiry = max(record["expires"] for record in records)
        provider = self.leased_providers(store, expiry + 1)[3]
        inventory = provider.inventory(StaticProcessProvider().inventory())
        self.assertEqual(
            factory.classify(inventory.observations[0]),
            frozenset(("insufficient_merge_evidence",)),
        )
        report = factory.build_report(
            (provider,), StaticProcessProvider()
        )
        self.assertEqual(report["scratch"]["eligible"], 0)
        self.assertEqual(
            report["scratch"]["hold_reasons"][
                "insufficient_merge_evidence"
            ],
            1,
        )
        self.assertEqual(report["scratch"]["hold_reasons"]["ignored"], 0)

    def test_checked_out_branch_and_child_of_held_parent_are_held(self):
        self.clean_lane()
        (self.lane / "build" / "plans").mkdir(parents=True)
        store = factory_lease.LeaseStore.for_repo(self.lane)
        self.attest_lane(store)
        providers = self.leased_providers(store, store.now())
        report = factory.build_report(providers, StaticProcessProvider())
        branch = report["branches"]
        self.assertEqual(branch["eligible"], 0)
        self.assertEqual(branch["hold_reasons"]["active_hold"], 1)
        scratch = report["scratch"]
        self.assertEqual(scratch["eligible"], 0)
        self.assertGreater(scratch["hold_reasons"]["active_hold"], 0)


class MissingProviderTests(unittest.TestCase):
    def test_missing_class_is_reported_as_unreadable(self):
        report = factory.build_report(
            (StaticResourceProvider("worktrees"),), StaticProcessProvider()
        )
        self.assertEqual(
            {
                resource_class
                for resource_class in factory.RESOURCE_CLASSES
                if report[resource_class]["hold_reasons"]["unreadable"]
            },
            set(factory.RESOURCE_CLASSES) - {"worktrees"},
        )


if __name__ == "__main__":
    unittest.main()
