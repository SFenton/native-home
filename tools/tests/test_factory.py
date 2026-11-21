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
        *,
        error: Exception | None = None,
    ) -> None:
        self.value = factory.ProcessObservation(pids=pids, cwds=cwds)
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
        for name in directories:
            path = base_path / name
            if path.is_symlink():
                found[f"{relative_base}/{name}"] = (
                    "link",
                    stat.S_IMODE(path.lstat().st_mode),
                    path.lstat().st_mtime_ns,
                    len(os.readlink(path)),
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
            observation(**values)
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
            merge_evidence="not_required",
        )
        providers = [
            StaticResourceProvider(
                resource_class,
                (*held, eligible_attestation)
                if resource_class == "worktrees"
                else (observation(resource_class),),
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
        self.assertEqual(commands[0], ["ps", "-axo", "pid="])


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
