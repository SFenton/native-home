"""Synthetic side-effect apparatus for retention tests."""
from __future__ import annotations
import contextlib, copy, importlib, json, shutil, subprocess, sys, tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Optional, Tuple
from unittest import mock
custody = importlib.import_module("tools.triage.tests.test_runner_custody")
ht = custody.ht
def private_home(home: Path) -> Path:
    resolved = home.resolve()
    if (not resolved.name.startswith("hass-triage-test-") or
            resolved.parent != Path(tempfile.gettempdir()).resolve()):
        raise AssertionError("fixture: home is not a private temporary directory")
    return resolved
def private_path(home: Path, path: Path, strict: bool = True) -> Path:
    home = private_home(home)
    resolved = Path(path).resolve()
    try:
        relative = resolved.relative_to(home)
    except ValueError as exc:
        raise AssertionError("fixture: path is outside temporary home") from exc
    if strict and not relative.parts:
        raise AssertionError("fixture: path is not below temporary home")
    return resolved
def no_symlinks(home: Path, path: Path) -> Path:
    supplied_home = Path(home).absolute()
    home = private_home(home)
    absolute = Path(path).absolute()
    for root in (supplied_home, home):
        try:
            relative = absolute.relative_to(root)
            break
        except ValueError:
            continue
    else:
        raise AssertionError("fixture: path escapes through a link")
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise AssertionError("fixture: symlinked path is forbidden")
    return Path(path).resolve()
@dataclass(frozen=True)
class GitCall:
    arguments: Tuple[str, ...]
    target: str
    seam: str = field(default="git", compare=False)
    occurrence: int = field(default=0, compare=False)
    def __post_init__(self) -> None:
        object.__setattr__(self, "arguments", tuple(map(str, self.arguments)))
        object.__setattr__(self, "target", str(Path(self.target).resolve()))
@dataclass(frozen=True)
class JournalEvent:
    name: str
    arguments: Tuple[str, ...] = ()
    target: str = ""
class InvocationJournal:
    def __init__(self):
        self.events: List[JournalEvent] = []
    def record(self, name: str, call=None, arguments=(), target="") -> None:
        if call is not None:
            arguments, target = call.arguments, call.target
        self.events.append(JournalEvent(
            name, tuple(map(str, arguments)), str(target)))
    def names(self) -> Tuple[str, ...]:
        return tuple(event.name for event in self.events)
class ClockLimit(BaseException):
    """A separately journaled, always-fatal test clock limit."""
class GitRecorder:
    def __init__(self, expected: Optional[Iterable[GitCall]] = None,
                 journal: Optional[InvocationJournal] = None):
        self.expected = tuple(expected) if expected is not None else None
        self.journal = journal or InvocationJournal()
        self.attempts: List[GitCall] = []
        self.completed: List[GitCall] = []
    @staticmethod
    def command(arguments) -> str:
        args = tuple(str(arg) for arg in arguments)
        return Path(args[0]).name if args else ""
    @classmethod
    def is_git_or_gh(cls, arguments) -> bool:
        return cls.command(arguments) in ("git", "gh")
    @classmethod
    def identity(cls, arguments, cwd: Optional[Path] = None,
                 repository: Optional[Path] = None,
                 seam: str = "git") -> GitCall:
        args = tuple(str(arg) for arg in arguments)
        if seam == "lane_land.git":
            target = repository
        elif "worktree" in args and "remove" in args:
            target = args[-1]
        elif "worktree" in args and "add" in args:
            branch = "-B" if "-B" in args else "-b" if "-b" in args else None
            target = (
                args[args.index(branch) + 2]
                if branch is not None else args[args.index("add") + 1]
            )
        else:
            target = repository or cwd
            if target is None and args[:3] == ("gh", "repo", "clone"):
                target = args[-1]
            elif target is None and "-C" in args:
                target = args[args.index("-C") + 1]
        if target is None:
            raise AssertionError(f"git.target unavailable: {args!r}")
        return GitCall(args, str(target), seam)
    def reject(self, name: str, call: GitCall) -> None:
        self.journal.record(name, call)
        raise AssertionError(f"{name}: call {call.occurrence}: {call!r}")
    def before(self, arguments, cwd: Optional[Path] = None,
               repository: Optional[Path] = None,
               seam: str = "git") -> Optional[GitCall]:
        args = tuple(str(arg) for arg in arguments)
        if seam != "lane_land.git" and not self.is_git_or_gh(args):
            return None
        try:
            call = self.identity(args, cwd, repository, seam)
        except AssertionError:
            self.journal.record("git.target", arguments=args)
            raise
        call = GitCall(call.arguments, call.target, call.seam, len(self.attempts))
        self.attempts.append(call)
        self.validate(call)
        return call
    def validate(self, call: GitCall) -> None:
        if self.expected is None:
            return
        index = call.occurrence
        if index >= len(self.expected):
            self.reject("git.unexpected", call)
        required = self.expected[index]
        if call == required:
            return
        if call in self.expected[index + 1:]:
            self.reject("git.order", call)
        if call.target != required.target:
            self.reject("git.target", call)
        self.reject("git.args", call)
    def after(self, call: Optional[GitCall]) -> None:
        if call is not None:
            self.completed.append(call)
    def assert_complete(self) -> None:
        if self.journal.events:
            event = self.journal.events[0]
            raise AssertionError(f"{event.name}: journaled {event.arguments!r}")
        if self.expected is not None:
            if len(self.completed) < len(self.expected):
                raise AssertionError(
                    f"git.missing: completed {len(self.completed)} "
                    f"expected {len(self.expected)}")
            if len(self.completed) > len(self.expected):
                raise AssertionError("git.unexpected: completed extra call")
class RecordingBoundaries(custody.RecordlessBoundaries):
    def __init__(self, home: Path, statuses=None, launcher=None, limit=200,
                 recorder: Optional[GitRecorder] = None,
                 registry: Optional["TemporaryRegistry"] = None,
                 remove_tree: bool = True,
                 redirect_forget: Optional[Path] = None,
                 delegate_forget: bool = True):
        private_home(home)
        super().__init__(home, statuses, launcher, limit)
        self.recorder = recorder or GitRecorder()
        self.registry = registry
        self.remove_tree = remove_tree
        self.redirect_forget = redirect_forget
        self.delegate_forget = delegate_forget
        self.real_forget = ht.t3launch.forget
        self.results = []
    def run(self, runner, args, allow_dry=False, cwd=None, check=True):
        tree = None
        if "worktree" in args:
            if "remove" in args:
                tree = Path(args[-1])
            elif "add" in args:
                branch = "-B" if "-B" in args else "-b" if "-b" in args else None
                tree = Path(
                    args[args.index(branch) + 2]
                    if branch is not None else args[args.index("add") + 1]
                )
        if tree is not None:
            guarded = private_path(self.home, tree)
            no_symlinks(self.home, tree)
            tree = guarded
        call = self.recorder.before(args, cwd)
        result = super().run(runner, args, allow_dry, cwd, check)
        if (result.returncode == 0 and self.remove_tree
                and "worktree" in args and "remove" in args):
            shutil.rmtree(tree, ignore_errors=True)
        self.recorder.after(call)
        self.results.append(result)
        return result
    def land_git(self, repo, *args, **kwargs):
        call = self.recorder.before(args, repository=repo,
                                    seam="lane_land.git")
        result = super().land_git(repo, *args, **kwargs)
        self.recorder.after(call)
        return result
    def forget(self, path, home):
        if self.registry is None:
            return super().forget(path, home)
        self.registry.guard_home(home)
        super().forget(path, home)
        if self.delegate_forget:
            target = self.redirect_forget or path
            self.registry.forget(target, self.real_forget)
class BoundedClock:
    def __init__(self, monotonic: Callable[[], float], deadline: float,
                 call_limit: int,
                 journal: Optional[InvocationJournal] = None):
        self.monotonic = monotonic
        self.deadline = deadline
        self.call_limit = call_limit
        self.calls = 0
        self.journal = journal or InvocationJournal()
    def now(self) -> float:
        self.calls += 1
        value = self.monotonic()
        if self.calls > self.call_limit:
            self.journal.record("clock.call_limit",
                                arguments=(self.calls, self.call_limit))
            raise ClockLimit(f"clock.call_limit: {self.calls} > "
                             f"{self.call_limit}")
        if value >= self.deadline:
            self.journal.record("clock.deadline",
                                arguments=(value, self.deadline))
            raise ClockLimit(f"clock.deadline: {value!r} >= {self.deadline!r}")
        return value
class RawLaunchGuard:
    def __init__(self, journal: InvocationJournal):
        self.journal = journal
        self.run_transport = mock.Mock(
            return_value=subprocess.CompletedProcess([], 0, "", ""))
        self.popen_transport = mock.Mock(return_value=mock.Mock())
        self.opener_transport = mock.Mock(return_value=mock.Mock())
    def launch(self, transport, argv, *args, **kwargs):
        arguments = tuple(str(arg) for arg in argv)
        if GitRecorder.is_git_or_gh(arguments):
            self.journal.record("git.bypass", arguments=arguments)
            raise AssertionError(f"git.bypass: {arguments!r}")
        return transport(arguments, *args, **kwargs)
    def run(self, argv, *args, **kwargs):
        return self.launch(self.run_transport, argv, *args, **kwargs)
    def popen(self, argv, *args, **kwargs):
        return self.launch(self.popen_transport, argv, *args, **kwargs)
    def opener(self, *args, **kwargs):
        self.journal.record("network.bypass")
        raise AssertionError("network.bypass: opener used during recording")
    def signal(self, function: str, process, signum) -> None:
        self.journal.record("signal.undeclared",
                            arguments=(function, process, signum))
        raise AssertionError(f"signal.undeclared: {function}")
    def kill(self, process, signum) -> None:
        self.signal("kill", process, signum)
    def killpg(self, process, signum) -> None:
        self.signal("killpg", process, signum)
@contextlib.contextmanager
def recorded_invocation(recorder: GitRecorder,
                        clock: Optional[BoundedClock] = None):
    guard = RawLaunchGuard(recorder.journal)
    original_init = ht.Runner.__init__
    created = []
    def guarded_init(instance, *args, **kwargs):
        kwargs["run"] = guard.run
        if clock is not None:
            kwargs["clock"] = clock.now
        original_init(instance, *args, **kwargs)
        created.append(instance)
    with mock.patch.object(ht.Runner, "__init__", guarded_init), \
            mock.patch.object(subprocess, "run", side_effect=guard.run), \
            mock.patch.object(subprocess, "Popen", side_effect=guard.popen), \
            mock.patch.object(ht.urllib.request, "build_opener",
                              side_effect=guard.opener), \
            mock.patch.object(ht.os, "kill", side_effect=guard.kill), \
            mock.patch.object(ht.os, "killpg", side_effect=guard.killpg):
        yield guard, created
class TemporaryRegistry:
    def __init__(self, home: Path):
        self.home = private_home(home)
        lexical = self.home / "hass-agents" / "t3"
        self.root = ht.t3launch.registry_root(self.home)
        if self.root != lexical:
            raise AssertionError("registry: not the launcher registry root")
        no_symlinks(self.home, self.root)
        self.session = ht.t3launch.session_module()
    def guard_home(self, home: Path) -> Path:
        if private_home(Path(home)) != self.home:
            raise AssertionError("registry: foreign test home")
        return self.root
    def guard_worktree(self, worktree: Path) -> Path:
        return private_path(self.home, worktree)
    def guarded_root(self) -> Path:
        return Path(no_symlinks(self.home, self.root))
    def files(self) -> List[Path]:
        root = self.guarded_root()
        if not root.exists():
            return []
        paths = sorted(root.rglob("*"))
        for path in paths:
            if path.is_symlink():
                raise AssertionError("registry: symlinked entry is forbidden")
        return [path for path in paths if path.is_file()]
    def seed(self, worktree: Path, thread: str, issue: int) -> None:
        worktree = self.guard_worktree(worktree)
        root = self.guarded_root()
        self.files()
        record = self.session.build_record(
            "request", issue, "coder", worktree, "agents/synthetic",
            {"FENTON_HEADLESS": "1"}, [], thread_id=thread)
        self.session.write_record(record, root)
    def snapshot(self) -> Dict[str, bytes]:
        return {str(path.relative_to(self.home)): path.read_bytes() for path in
                self.files()}
    def forget(self, worktree: Path, launcher_forget) -> None:
        self.guard_home(self.home)
        worktree = self.guard_worktree(worktree)
        self.files()
        launcher_forget(worktree, self.home)
    def records(self, worktree: Path, thread: str) -> Tuple[Path, Path]:
        root = self.guarded_root()
        return (self.session.path_record(worktree, root),
                self.session.thread_record(thread, root))
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
    def capture(home: Path, stores: Dict[str, Path],
                registry: TemporaryRegistry) -> "RetentionSnapshot":
        home = private_home(home)
        files = {}
        for path in sorted(home.rglob("*")):
            no_symlinks(home, path)
            if path.is_file():
                files[str(path.relative_to(home))] = path.read_bytes()
        loaded = {}
        for name, path in stores.items():
            path = private_path(home, path)
            state = ht.State(path)
            loaded[name] = StoreSnapshot(
                name, path.read_bytes(), copy.deepcopy(state.data),
                copy.deepcopy(state.read_result),
                tuple(copy.deepcopy(state.load_faults)))
        return RetentionSnapshot(files, loaded, registry.snapshot())
    def registry_changes(self, before: "RetentionSnapshot") -> Dict[str, str]:
        return {
            key: ("added" if key not in before.registry else
                  "removed" if key not in self.registry else "changed")
            for key in sorted(set(before.registry) | set(self.registry))
            if before.registry.get(key) != self.registry.get(key)
        }
class RetentionRecorderTests(custody.StoreTestBase):
    def golden_trace(self) -> Tuple[GitCall, ...]:
        clone = str(self.paths.clone)
        base = self.cfg["product_base"]
        return (
            GitCall(("gh", "repo", "clone", self.cfg["product_repo"], clone), clone),
            GitCall(("git", "-C", clone, "fetch", "-q", "origin", base), clone),
            GitCall(("git", "-C", clone, "fetch", "-q", "origin", base), clone),
        )
    def run_golden(self, expected: Tuple[GitCall, ...], failure: str = ""):
        journal = InvocationJournal()
        recorder = GitRecorder(expected, journal=journal)
        clock = BoundedClock(lambda: 1.0, 100.0, 20, journal)
        instrumented = []
        def boundary(home, statuses=None, launcher=None, limit=200):
            instrumented.append(RecordingBoundaries(
                home, statuses, launcher, limit, recorder=recorder))
            return instrumented[-1]
        golden = custody.StatusAndGoldenTests.\
            test_recordless_both_admissions_choose_priority_and_keep_fixed_bytes
        with mock.patch.object(custody, "RecordlessBoundaries",
                               side_effect=boundary), \
                recorded_invocation(recorder, clock) as (guard, created):
            if failure:
                try:
                    golden(self)
                except AssertionError as exc:
                    self.assertRegex(str(exc), failure)
                with self.assertRaisesRegex(AssertionError, failure):
                    recorder.assert_complete()
            else:
                golden(self)
                recorder.assert_complete()
        self.assertEqual(len(instrumented), 1)
        self.assertTrue(len(created) >= 1 if failure else len(created) == 2)
        self.assertTrue(all(getattr(runner.clock, "__self__", None) is clock
                            for runner in created))
        guard.run_transport.assert_not_called()
        guard.popen_transport.assert_not_called()
        guard.opener_transport.assert_not_called()
        return recorder
    def test_real_golden_control_preserves_transcript(self):
        """Fails if: the recorder changes #213's accepted golden transcript."""
        recorder = self.run_golden(self.golden_trace())
        self.assertEqual(len(recorder.completed), 3)
    def test_real_golden_rejects_wrong_target(self):
        """Fails if: a real last-fetch target change escapes comparison."""
        trace = self.golden_trace()
        other = self.home / "wrong-target"
        changed = list(trace[-1].arguments)
        changed[2] = str(other)
        expected = trace[:2] + (GitCall(tuple(changed), other),)
        self.run_golden(expected, r"git\.target")
    def test_real_golden_rejects_wrong_order(self):
        """Fails if: clone and first fetch may be swapped unnoticed."""
        trace = self.golden_trace()
        self.run_golden((trace[1], trace[0], trace[2]), r"git\.order")
    def test_real_golden_rejects_changed_arguments(self):
        """Fails if: the last fetch argument change is hidden by target."""
        trace = self.golden_trace()
        changed = list(trace[-1].arguments)
        changed[4] = "--quiet"
        expected = trace[:2] + (GitCall(tuple(changed), trace[-1].target),)
        self.run_golden(expected, r"git\.args")
    def test_real_golden_rejects_missing_call(self):
        """Fails if: an installed final call may disappear."""
        trace = self.golden_trace()
        extra = GitCall(("git", "-C", str(self.paths.clone), "status"),
                        self.paths.clone)
        self.run_golden(trace + (extra,), r"git\.missing")
    def test_real_golden_rejects_unexpected_call(self):
        """Fails if: the third real call is silently accepted."""
        self.run_golden(self.golden_trace()[:2], r"git\.unexpected")
    def test_remove_order_on_distinct_trees_precedes_delegation(self):
        """Fails if: distinct-tree remove order is called a target mismatch."""
        first = self.home / "remove-a"
        second = self.home / "remove-b"
        first_call = GitCall(("git", "worktree", "remove", "--force",
                              str(first)), first)
        second_call = GitCall(("git", "worktree", "remove", "--force",
                               str(second)), second)
        expected = (first_call, second_call)
        control = GitRecorder(expected)
        control.after(control.before(first_call.arguments))
        control.after(control.before(second_call.arguments))
        control.assert_complete()
        replay = GitRecorder(expected)
        with self.assertRaisesRegex(AssertionError, r"git\.order"):
            replay.before(second_call.arguments)
        self.assertEqual(len(replay.attempts), 1)
        self.assertEqual(replay.attempts[0].occurrence, 0)
        self.assertEqual(replay.completed, [])
    def test_swallowed_rejection_still_fails_outer_check(self):
        """Fails if: a best-effort catch hides an extra call rejection."""
        expected = GitCall(("git", "status"), self.home / "clone")
        extra = GitCall(("git", "fetch"), self.home / "clone")
        recorder = GitRecorder((expected,))
        recorder.after(recorder.before(expected.arguments, expected.target))
        caught = False
        try:
            recorder.before(extra.arguments, extra.target)
        except Exception:
            caught = True
        self.assertTrue(caught)
        with self.assertRaisesRegex(AssertionError, r"git\.unexpected"):
            recorder.assert_complete()
        targetless = GitRecorder()
        try:
            targetless.before(("git", "status"))
        except Exception:
            pass
        with self.assertRaisesRegex(AssertionError, r"git\.target"):
            targetless.assert_complete()
    def test_land_git_keeps_repository_and_full_arguments(self):
        """Fails if: the land command seam loses args or repository identity."""
        repository = self.home / "repository"
        call = GitCall(("status", "--short"), repository)
        recorder = GitRecorder((call,))
        boundaries = RecordingBoundaries(self.home, recorder=recorder)
        result = boundaries.land_git(repository, "status", "--short")
        self.assertEqual(result.returncode, 0)
        recorder.assert_complete()
        self.assertEqual(recorder.completed, [call])
    def assert_worktree_guard(self, operation):
        regular = self.home / f"{operation}-control"
        if operation == "remove":
            regular.mkdir()
        arguments = ["git", "-C", str(self.paths.clone), "worktree", operation]
        arguments += (["--force", str(regular)] if operation == "remove" else
                      ["-B", "agents/control", str(regular)])
        boundaries = RecordingBoundaries(self.home)
        runner = self.runner(custody.FakeGitHub([]))
        result = boundaries.run(runner, arguments)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(regular.exists(), operation == "add")
        boundaries.recorder.assert_complete()
        actual = self.home / f"{operation}-actual"
        linked = self.home / f"{operation}-linked"
        actual.mkdir()
        linked.symlink_to(actual, target_is_directory=True)
        with tempfile.TemporaryDirectory(prefix="hass-triage-test-") \
                as outside_name:
            outside = Path(outside_name) / "tree"
            if operation == "remove":
                outside.mkdir()
                (actual / "tree").mkdir()
            for target, failure in (
                (outside, r"outside"),
                (linked / "tree", r"symlinked path"),
            ):
                was_present = target.exists()
                rejected = arguments[:-1] + [str(target)]
                with self.assertRaisesRegex(AssertionError, failure):
                    boundaries.run(runner, rejected)
                self.assertEqual(target.exists(), was_present)
        self.assertEqual(len(boundaries.recorder.attempts), 1)
    def test_worktree_remove_guards_original_operand_with_control(self):
        """Fails if: the fake remove follows or escapes the private home."""
        self.assert_worktree_guard("remove")
    def test_worktree_add_guards_target_before_creation_with_control(self):
        """Fails if: the inherited fake creates an unguarded add target."""
        self.assert_worktree_guard("add")
    def test_raw_launch_and_http_backstop_reject_before_transport(self):
        """Fails if: raw Git, GitHub, Popen or HTTP reaches a real transport."""
        clone = self.home / "clone"
        recorder = GitRecorder((GitCall(
            ("git", "-C", str(clone), "status"), clone),))
        with recorded_invocation(recorder) as (guard, created):
            boundaries = RecordingBoundaries(self.home, recorder=recorder)
            runner = ht.Runner(self.cfg, self.paths, custody.FakeGitHub([]))
            result = boundaries.run(runner, recorder.expected[0].arguments)
            self.assertEqual(result.returncode, 0)
            for launch in (
                lambda: ht.lane_land.land_clone(self.home,
                                                str(self.home / "source"), "direct"),
                lambda: subprocess.Popen(
                    ["/usr/bin/gh", "api", "repos/example/private"]),
                lambda: ht.lane_land._blobs(self.home / "clone",
                                            "a" * 40, ("file",)),
                lambda: ht.GitHub(dry_run=False)._gh(["api", "user"]),
                lambda: ht.ruleset_gate.fetch_rules("example/private", "main"),
                lambda: runner.run(["gh", "api", "repos/example/private"]),
                lambda: ht.download("https://example.invalid/attachment",
                                    self.home / "media", "synthetic"),
            ):
                with self.assertRaisesRegex(
                        AssertionError, r"(git\.bypass|network\.bypass)"):
                    launch()
            with self.assertRaisesRegex(AssertionError, r"git\.bypass"):
                recorder.assert_complete()
        self.assertEqual(len(created), 1)
        self.assertEqual(recorder.journal.names(),
                         ("git.bypass",) * 6 + ("network.bypass",))
        guard.run_transport.assert_not_called()
        guard.popen_transport.assert_not_called()
        guard.opener_transport.assert_not_called()
    def registry_fixture(self, remove_tree=True, redirect=None, delegate=True):
        registry = TemporaryRegistry(self.home)
        old = self.paths.worktree(63)
        foreign = self.paths.worktree(64)
        old.mkdir(parents=True, exist_ok=True)
        registry.seed(old, "thread-old", 63)
        registry.seed(foreign, "thread-foreign", 64)
        expected = GitCall(("git", "-C", str(self.paths.clone), "worktree",
                            "remove", "--force", str(old)), old)
        boundaries = RecordingBoundaries(
            self.home, recorder=GitRecorder((expected,)),
            registry=registry, remove_tree=remove_tree,
            redirect_forget=redirect, delegate_forget=delegate)
        return registry, old, foreign, boundaries
    def run_cleanup(self, boundaries, expected=True):
        runner = self.runner(custody.FakeGitHub([]))
        with mock.patch.object(runner, "archive_before_change",
                               return_value=True), \
                mock.patch.object(
                    runner, "_run",
                    side_effect=lambda args, *a, **kw: boundaries.run(
                        runner, args, *a, **kw)), \
                mock.patch.object(ht.t3launch, "forget",
                                  side_effect=boundaries.forget), \
                recorded_invocation(boundaries.recorder):
            result = runner.cleanup(63)
        self.assertEqual(result, expected)
        boundaries.recorder.assert_complete()
    def test_cleanup_records_remove_and_real_forget_at_owned_registry(self):
        """Fails if: cleanup omits removal or uses the wrong registry root."""
        registry, old, foreign, boundaries = self.registry_fixture()
        before = RetentionSnapshot.capture(self.home, {}, registry)
        old_records = registry.records(old, "thread-old")
        foreign_records = registry.records(foreign, "thread-foreign")
        foreign_bytes = tuple(
            before.registry[str(path.relative_to(registry.home))]
            for path in foreign_records)
        self.run_cleanup(boundaries)
        after = RetentionSnapshot.capture(self.home, {}, registry)
        self.assertFalse(old.exists())
        self.assertTrue(all(not path.exists() for path in old_records))
        self.assertTrue(all(path.exists() for path in foreign_records))
        self.assertEqual(tuple(path.read_bytes() for path in foreign_records),
                         foreign_bytes)
        self.assertEqual(after.registry_changes(before), {
            str(path.relative_to(registry.home)): "removed"
            for path in old_records})
        self.assertEqual(registry.root.resolve(),
                         ht.t3launch.registry_root(self.home).resolve())
    def test_cleanup_without_forget_fails_registry_observation(self):
        """Fails if: a recorded remove is mistaken for registry teardown."""
        registry, old, _foreign, boundaries = self.registry_fixture(delegate=False)
        self.run_cleanup(boundaries)
        self.assertFalse(old.exists())
        records = registry.records(old, "thread-old")
        with self.assertRaises(AssertionError):
            self.assertTrue(all(not path.exists() for path in records))
    def test_cleanup_redirected_forget_fails_old_record_observation(self):
        """Fails if: forgetting a different owned worktree counts as success."""
        registry, old, foreign, boundaries = self.registry_fixture(
            redirect=self.paths.worktree(64))
        self.run_cleanup(boundaries)
        old_records = registry.records(old, "thread-old")
        foreign_records = registry.records(foreign, "thread-foreign")
        with self.assertRaises(AssertionError):
            self.assertTrue(all(not path.exists() for path in old_records))
        with self.assertRaises(AssertionError):
            self.assertTrue(all(path.exists() for path in foreign_records))
    def test_registry_guards_reject_foreign_home_and_escaping_worktree(self):
        """Fails if: registry teardown delegates outside this test's home."""
        registry, old, _foreign, boundaries = self.registry_fixture()
        delegated = mock.Mock()
        boundaries.real_forget = delegated
        with tempfile.TemporaryDirectory(prefix="hass-triage-test-") \
                as other_name:
            foreign_home = Path(other_name)
            with self.assertRaisesRegex(AssertionError, r"foreign test home"):
                boundaries.forget(old, foreign_home)
            escaping = self.home / "escape"
            escaping.symlink_to(foreign_home, target_is_directory=True)
            with self.assertRaisesRegex(AssertionError, r"outside"):
                boundaries.forget(escaping, self.home)
        delegated.assert_not_called()
    def test_registry_rejects_symlinked_root_and_entries_before_read(self):
        """Fails if: a registry link can read or remove a synthetic escape."""
        with tempfile.TemporaryDirectory(prefix="hass-triage-test-") \
                as other_name:
            outside = Path(other_name) / "t3"
            outside.mkdir()
            component = self.home / "hass-agents"
            component.symlink_to(outside.parent, target_is_directory=True)
            with self.assertRaisesRegex(AssertionError, r"symlinked path"):
                TemporaryRegistry(self.home)
            component.unlink()
        registry = TemporaryRegistry(self.home)
        registry.root.mkdir(parents=True, exist_ok=True)
        linked = registry.root / "escape.json"
        linked.symlink_to(self.paths.state)
        with self.assertRaisesRegex(AssertionError, r"symlinked entry"):
            registry.snapshot()
    def test_zero_remove_return_does_not_prove_tree_vanished(self):
        """Fails if: return code zero collapses path and registry observations."""
        registry, old, foreign, boundaries = self.registry_fixture(remove_tree=False)
        before = registry.snapshot()
        self.run_cleanup(boundaries)
        self.assertEqual(boundaries.results[-1].returncode, 0)
        self.assertTrue(old.exists())
        self.assertTrue(old.is_dir())
        self.assertTrue(all(not path.exists()
                            for path in registry.records(old, "thread-old")))
        foreign_record = registry.records(foreign, "thread-foreign")[0]
        self.assertEqual(foreign_record.read_bytes(),
                         before[str(foreign_record.relative_to(registry.home))])
    def test_fresh_disk_snapshot_uses_independent_store_values(self):
        """Fails if: fresh stores or raw bytes are taken from live run objects."""
        cfg = dict(self.cfg)
        cfg["nightly"] = None
        cfg["schedules"] = {}
        retro = ht.Paths(cfg, self.home, "retro-").state
        primary_data = self.legacy(marker={"primary": True})
        retro_data = self.legacy(queue=[], marker={"retro": True})
        primary_raw = self.saved_bytes(primary_data)
        retro_raw = json.dumps(retro_data).encode()
        self.paths.state.parent.mkdir(parents=True, exist_ok=True)
        self.write_raw(self.paths.state, json.dumps(primary_data))
        retro.parent.mkdir(parents=True, exist_ok=True)
        self.write_raw(retro, json.dumps(retro_data))
        registry = TemporaryRegistry(self.home)
        boundaries = RecordingBoundaries(self.home, registry=registry)
        stores = {"primary": self.paths.state, "retro": retro}
        with recorded_invocation(boundaries.recorder):
            result = self.main_golden(["tick", "--max-items", "0"], cfg,
                                       custody.FakeGitHub([]), boundaries)
        self.assertEqual(result, (0, "", ""))
        boundaries.recorder.assert_complete()
        after = RetentionSnapshot.capture(self.home, stores, registry)
        for name, data, raw in (
            ("primary", primary_data, primary_raw),
            ("retro", retro_data, retro_raw),
        ):
            self.assertEqual(after.stores[name].data, data)
            self.assertEqual(after.stores[name].raw, raw)
            self.assertEqual(after.stores[name].read_result["kind"], "loaded")
        self.assertIn(str(self.paths.state.relative_to(self.home)), after.files)
        self.assertIn(str(retro.relative_to(self.home)), after.files)
    def test_clock_limits_survive_broad_exception_catches(self):
        """Fails if: deadline or call-cap limits become catchable domain errors."""
        journal = InvocationJournal()
        control = BoundedClock(lambda: 1.0, 2.0, 2, journal)
        self.assertEqual(control.now(), 1.0)
        caught = []
        for clock in (
            BoundedClock(lambda: 2.0, 2.0, 2, journal),
            BoundedClock(lambda: 1.0, 10.0, 0, journal),
        ):
            try:
                try:
                    clock.now()
                except Exception as exc:
                    caught.append(exc)
            except ClockLimit:
                pass
        self.assertEqual(caught, [])
        self.assertEqual(journal.names(), ("clock.deadline", "clock.call_limit"))
        with self.assertRaisesRegex(AssertionError, r"clock\.deadline"):
            GitRecorder(journal=journal).assert_complete()
    def assert_signal_guard(self, name):
        control = GitRecorder()
        with recorded_invocation(control):
            control.assert_complete()
        recorder = GitRecorder()
        with recorded_invocation(recorder):
            try:
                getattr(ht.os, name)(id(recorder), 0)
            except Exception:
                pass
            with self.assertRaisesRegex(AssertionError, r"signal\.undeclared"):
                recorder.assert_complete()
        self.assertEqual(recorder.journal.names(), ("signal.undeclared",))
    def test_kill_attempt_is_journaled_after_broad_catch(self):
        """Fails if: a swallowed process-kill attempt passes finalization."""
        self.assert_signal_guard("kill")
    def test_killpg_attempt_is_journaled_after_broad_catch(self):
        """Fails if: a swallowed process-group kill passes finalization."""
        self.assert_signal_guard("killpg")
    def test_non_git_digest_helper_stays_on_its_fake(self):
        """Fails if: a cwd-less helper is misreported as a Git target error."""
        boundaries = RecordingBoundaries(self.home)
        argv = (sys.executable, str(ht.HERE.parent / "retro_digest.py"),
                "--task", "synthetic", "--archive", str(self.home / "archive"))
        result = boundaries.run(self.runner(custody.FakeGitHub([])),
                                argv, check=False)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(boundaries.recorder.attempts, [])
        boundaries.recorder.assert_complete()
