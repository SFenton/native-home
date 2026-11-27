"""Synthetic side-effect apparatus for retention tests."""
from __future__ import annotations

import copy
import importlib
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, List, Optional, Tuple
from unittest import mock


custody = importlib.import_module(
    "tools.triage.tests.test_runner_custody"
)
ht = custody.ht


def private_home(home: Path) -> Path:
    resolved = home.resolve()
    if (
        not resolved.name.startswith("hass-triage-test-")
        or resolved.parent != Path(tempfile.gettempdir()).resolve()
    ):
        raise AssertionError("fixture: home is not a private temporary directory")
    return resolved


def private_path(home: Path, path: Path) -> Path:
    resolved = path.resolve()
    try:
        resolved.relative_to(home)
    except ValueError as exc:
        raise AssertionError("fixture: path is outside temporary home") from exc
    return resolved


@dataclass(frozen=True)
class GitCall:
    arguments: Tuple[str, ...]
    target: str

    def __post_init__(self) -> None:
        object.__setattr__(self, "arguments", tuple(
            str(argument) for argument in self.arguments
        ))
        object.__setattr__(self, "target", str(Path(self.target).resolve()))


class BoundaryInterrupted(Exception):
    """A controlled interruption at one exact command boundary."""


class ControlledInterruption:
    def __init__(self, boundary: GitCall):
        self.boundary = boundary
        self.fired = False

    def before(self, call: GitCall) -> None:
        if not self.fired and call == self.boundary:
            self.fired = True
            raise BoundaryInterrupted(
                f"interrupted at {call.arguments!r} on {call.target}"
            )


class GitRecorder:
    def __init__(
        self,
        expected: Optional[Tuple[GitCall, ...]] = None,
        interruption: Optional[ControlledInterruption] = None,
    ):
        self.expected = expected
        self.interruption = interruption
        self.completed: List[GitCall] = []

    @staticmethod
    def identity(
        arguments,
        cwd: Optional[Path] = None,
        repository: Optional[Path] = None,
    ) -> GitCall:
        args = tuple(str(argument) for argument in arguments)
        target = repository or cwd
        if "worktree" in args and "remove" in args:
            target = args[-1]
        elif "worktree" in args and "add" in args:
            branch = "-B" if "-B" in args else "-b" if "-b" in args else None
            target = (
                args[args.index(branch) + 2]
                if branch is not None else args[args.index("add") + 1]
            )
        elif target is None and args[:2] == ("gh", "repo"):
            target = args[-1]
        elif target is None and "-C" in args:
            target = args[args.index("-C") + 1]
        if target is None:
            raise AssertionError(f"git.target unavailable: {args!r}")
        return GitCall(args, str(target))

    def before(
        self,
        arguments,
        cwd: Optional[Path] = None,
        repository: Optional[Path] = None,
    ) -> GitCall:
        call = self.identity(arguments, cwd, repository)
        if self.interruption is not None:
            self.interruption.before(call)
        if self.expected is not None:
            index = len(self.completed)
            if index >= len(self.expected):
                raise AssertionError(
                    f"git.complete: unexpected call {index}: {call!r}"
                )
            self.assert_call(index, call, self.expected[index])
        return call

    def after(self, call: GitCall) -> None:
        self.completed.append(call)

    def assert_complete(
        self,
        actual: Tuple[GitCall, ...],
        expected: Optional[Tuple[GitCall, ...]] = None,
    ) -> None:
        wanted = tuple(actual if expected is None else expected)
        actual = tuple(actual)
        if len(actual) != len(wanted):
            raise AssertionError(
                f"git.complete: actual {len(actual)} expected {len(wanted)}"
            )
        for index, (observed, required) in enumerate(zip(actual, wanted)):
            self.assert_call(index, observed, required)

    @staticmethod
    def assert_call(index: int, observed: GitCall, required: GitCall) -> None:
        if observed.arguments != required.arguments:
            raise AssertionError(
                f"git.order: call {index}: {observed.arguments!r}"
            )
        if observed.target != required.target:
            raise AssertionError(
                f"git.target: call {index}: {observed.target!r}"
            )


class RecordingBoundaries(custody.RecordlessBoundaries):
    def __init__(
        self,
        home: Path,
        statuses=None,
        launcher=None,
        limit=200,
        recorder: Optional[GitRecorder] = None,
        registry: Optional["TemporaryRegistry"] = None,
    ):
        private_home(home)
        super().__init__(home, statuses, launcher, limit)
        self.recorder = recorder or GitRecorder()
        self.registry = registry

    def run(self, runner, args, allow_dry=False, cwd=None, check=True):
        call = self.recorder.before(args, cwd)
        result = super().run(runner, args, allow_dry, cwd, check)
        self.recorder.after(call)
        return result

    def land_git(self, repo, *args, **kwargs):
        call = self.recorder.before(args, repository=repo)
        result = super().land_git(repo, *args, **kwargs)
        self.recorder.after(call)
        return result

    def forget(self, path, home):
        super().forget(path, home)
        if self.registry is not None:
            if Path(home).resolve() != self.registry.home.resolve():
                raise AssertionError("registry: foreign test home")
            self.registry.forget(path)


class BoundedClock:
    def __init__(
        self,
        monotonic: Callable[[], float],
        deadline: float,
        call_limit: int,
    ):
        self.monotonic = monotonic
        self.deadline = deadline
        self.call_limit = call_limit
        self.calls = 0

    def now(self) -> float:
        self.calls += 1
        if self.calls > self.call_limit:
            raise AssertionError(
                f"clock.call_limit: {self.calls} > {self.call_limit}"
            )
        value = self.monotonic()
        if value >= self.deadline:
            raise AssertionError(
                f"clock.deadline: {value!r} >= {self.deadline!r}"
            )
        return value


class TemporaryRegistry:
    def __init__(self, home: Path):
        self.home = private_home(home)
        self.root = self.home / "test-registry"
        try:
            self.root.relative_to(self.home)
        except ValueError as exc:
            raise AssertionError("registry: outside temporary home") from exc
        self.session = ht.t3launch.session_module()

    def seed(self, worktree: Path, thread: str, issue: int) -> None:
        worktree = private_path(self.home, worktree)
        record = self.session.build_record(
            "request",
            issue,
            "coder",
            worktree,
            "agents/synthetic",
            {"FENTON_HEADLESS": "1"},
            [],
            thread_id=thread,
        )
        self.session.write_record(record, self.root)

    def snapshot(self) -> Dict[str, bytes]:
        if not self.root.exists():
            return {}
        return {
            str(path.relative_to(self.home)): path.read_bytes()
            for path in sorted(self.root.rglob("*"))
            if path.is_file()
        }

    def forget(self, worktree: Path) -> None:
        self.session.forget(private_path(self.home, worktree), self.root)


@dataclass(frozen=True)
class StoreSnapshot:
    name: str
    raw: Optional[bytes]
    data: Dict[str, object]
    read_result: Dict[str, object]
    load_faults: Tuple[Dict[str, object], ...]


@dataclass(frozen=True)
class RetentionSnapshot:
    files: Dict[str, bytes]
    stores: Dict[str, StoreSnapshot]
    registry: Dict[str, bytes]

    @staticmethod
    def capture(
        home: Path,
        stores: Dict[str, Path],
        registry: TemporaryRegistry,
    ) -> "RetentionSnapshot":
        home = private_home(home)
        files = {
            str(path.relative_to(home)): path.read_bytes()
            for path in sorted(home.rglob("*"))
            if path.is_file()
        }
        loaded = {}
        for name, path in stores.items():
            path = private_path(home, path)
            state = ht.State(path)
            loaded[name] = StoreSnapshot(
                name,
                path.read_bytes() if path.exists() else None,
                copy.deepcopy(state.data),
                copy.deepcopy(state.read_result),
                tuple(copy.deepcopy(state.load_faults)),
            )
        return RetentionSnapshot(files, loaded, registry.snapshot())

    def registry_changes(
        self, before: "RetentionSnapshot"
    ) -> Dict[str, str]:
        return {
            key: "added" if key not in before.registry else
            "removed" if key not in self.registry else "changed"
            for key in sorted(set(before.registry) | set(self.registry))
            if before.registry.get(key) != self.registry.get(key)
        }


class RetentionRecorderTests(custody.StoreTestBase):
    def test_git_comparison_rejects_wrong_target_with_passing_control(self):
        """Fails if: a different target passes the argument identity check."""
        actual = GitCall(("git", "status"), self.home / "actual")
        expected = GitCall(actual.arguments, self.home / "expected")
        control = GitRecorder((actual,))
        control.after(control.before(actual.arguments, actual.target))
        with self.assertRaisesRegex(AssertionError, r"git\.target"):
            GitRecorder((expected,)).before(
                actual.arguments, actual.target
            )

    def test_git_comparison_rejects_wrong_order_with_passing_control(self):
        """Fails if: reordered arguments pass the ordered trace check."""
        first = GitCall(("git", "fetch"), self.home / "clone")
        second = GitCall(("git", "prune"), self.home / "clone")
        control = GitRecorder((first, second))
        control.after(control.before(first.arguments, first.target))
        control.after(control.before(second.arguments, second.target))
        with self.assertRaisesRegex(AssertionError, r"git\.order"):
            GitRecorder((second, first)).before(
                first.arguments, first.target
            )

    def test_unexpected_call_is_rejected_at_the_named_boundary(self):
        """Fails if: the recorder silently passes an unlisted side effect."""
        expected = GitCall(("git", "status"), self.home / "clone")
        extra = GitCall(("git", "fetch"), self.home / "clone")
        recorder = GitRecorder((expected,))
        recorder.after(recorder.before(expected.arguments, self.home / "clone"))
        with self.assertRaisesRegex(AssertionError, r"git\.complete"):
            recorder.before(extra.arguments, self.home / "clone")

    def test_land_git_records_repository_identity_and_full_arguments(self):
        """Fails if: the repository command boundary loses args or its target."""
        repository = self.home / "repository"
        boundaries = RecordingBoundaries(self.home)
        result = boundaries.land_git(repository, "status", "--short")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(boundaries.recorder.completed, [
            GitCall(("status", "--short"), repository),
        ])

    def test_recordless_golden_keeps_its_default_transcript_when_recorded(self):
        """Fails if: recorder attachment changes the existing append-only golden."""
        instrumented = []

        def boundary(home, statuses=None, launcher=None, limit=200):
            value = RecordingBoundaries(home, statuses, launcher, limit)
            instrumented.append(value)
            return value

        golden = (
            custody.StatusAndGoldenTests
            .test_recordless_both_admissions_choose_priority_and_keep_fixed_bytes
        )
        with mock.patch.object(
            custody, "RecordlessBoundaries", side_effect=boundary
        ), mock.patch.object(
            ht.os, "kill", side_effect=AssertionError("fake process signaled")
        ):
            golden(self)
        self.assertEqual(len(instrumented), 1)
        calls = tuple(instrumented[0].recorder.completed)
        self.assertEqual(len(calls), 3)
        raw_calls = instrumented[0].git_events
        self.assertEqual(calls, tuple(
            GitRecorder.identity(arguments, cwd or None)
            for arguments, cwd in raw_calls
        ))
        instrumented[0].recorder.assert_complete(calls)

    def test_fresh_disk_snapshot_distinguishes_files_stores_and_registry(self):
        """Fails if: a run is read through live objects or the registry is not private."""
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        retro = ht.Paths(cfg, self.home, "retro-").state
        primary_data = self.legacy(marker={"primary": True})
        retro_data = self.legacy(queue=[], marker={"retro": True})
        self.write_raw(self.paths.state, primary_data)
        self.write_raw(retro, retro_data)
        registry = TemporaryRegistry(self.home)
        old_tree = self.home / "trees" / "old"
        foreign_tree = self.home / "trees" / "foreign"
        registry.seed(old_tree, "thread-old", 1)
        registry.seed(foreign_tree, "thread-foreign", 2)
        stores = {"primary": self.paths.state, "retro": retro}
        boundaries = RecordingBoundaries(self.home, registry=registry)
        before = RetentionSnapshot.capture(self.home, stores, registry)

        with mock.patch.object(
            ht.os, "kill", side_effect=AssertionError("fake process signaled")
        ):
            result = self.main_golden(
                ["tick", "--max-items", "0"],
                cfg,
                custody.FakeGitHub([]),
                boundaries,
            )
        self.assertEqual(result, (0, "", ""))
        boundaries.forget(old_tree, self.home)
        after = RetentionSnapshot.capture(self.home, stores, registry)

        foreign_files = {
            str(registry.session.path_record(
                foreign_tree, registry.root
            ).relative_to(registry.home)),
            str(registry.session.thread_record(
                "thread-foreign", registry.root
            ).relative_to(registry.home)),
        }
        for path in foreign_files:
            self.assertEqual(after.registry[path], before.registry[path])
        old_files = {
            str(registry.session.path_record(
                old_tree, registry.root
            ).relative_to(registry.home)),
            str(registry.session.thread_record(
                "thread-old", registry.root
            ).relative_to(registry.home)),
        }
        self.assertEqual(after.registry_changes(before), {
            path: "removed" for path in old_files
        })
        self.assertEqual(after.stores["primary"].data["marker"],
                         {"primary": True})
        self.assertEqual(after.stores["retro"].data["marker"], {"retro": True})
        self.assertEqual(after.stores["primary"].raw,
                         self.paths.state.read_bytes())
        self.assertEqual(after.stores["retro"].raw,
                         retro.read_bytes())
        self.assertIn(
            str(self.paths.state.relative_to(self.home)), after.files
        )
        self.assertIn(str(retro.relative_to(self.home)), after.files)
        self.assertEqual(set(after.stores), {"primary", "retro"})
        self.assertTrue(boundaries.recorder.completed)

    def test_bounded_clock_rejects_deadline_and_spin_with_controls(self):
        """Fails if: an endless loop can run past a deadline or call cap."""
        self.assertEqual(BoundedClock(lambda: 1.0, 2.0, 2).now(), 1.0)
        with self.assertRaisesRegex(AssertionError, r"clock\.deadline"):
            BoundedClock(lambda: 2.0, 2.0, 2).now()

        spinning = BoundedClock(lambda: 1.0, 10.0, 3)
        with self.assertRaisesRegex(AssertionError, r"clock\.call_limit"):
            while True:
                spinning.now()
        self.assertEqual(spinning.calls, 4)

    def test_controlled_interruption_fires_once_at_exact_boundary(self):
        """Fails if: interruption is broad, repeats, or hides completed calls."""
        first = GitCall(("git", "fetch"), self.home / "clone")
        selected = GitCall(("git", "status"), self.home / "selected")
        control = GitRecorder()
        for call in (first, selected):
            control.after(control.before(call.arguments, call.target))
        self.assertEqual(tuple(control.completed), (first, selected))

        interruption = ControlledInterruption(selected)
        recorder = GitRecorder(interruption=interruption)
        recorder.after(recorder.before(first.arguments, first.target))
        with self.assertRaises(BoundaryInterrupted):
            recorder.before(selected.arguments, selected.target)
        self.assertEqual(tuple(recorder.completed), (first,))
        self.assertTrue(interruption.fired)
        recorder.after(recorder.before(selected.arguments, selected.target))
        self.assertEqual(tuple(recorder.completed), (first, selected))
