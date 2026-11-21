#!/usr/bin/env python3
"""Read-only inventory of resources an agent factory can leave behind.

``factory.py report [--json] [--repo PATH]`` prints counts only. Providers
observe resources; the classifier never performs cleanup. All incomplete
observations are holds, and no patch/tree equivalence counts as merge proof.
This lane reports every branch as held: a checked-out branch is an active hold,
and a branch without its worktree has an unknown owner. A branch route belongs
to the later cleanup lane.
"""

from __future__ import annotations

import argparse
import json
import os
import stat
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Mapping, Protocol, Sequence, TypedDict

import factory_lease


RESOURCE_CLASSES = (
    "branches",
    "build_output",
    "run_markers",
    "scratch",
    "simulators",
    "worktrees",
)
HOLD_REASONS = (
    "active_hold",
    "booted",
    "dirty",
    "foreign",
    "fresh_at_main",
    "ignored",
    "insufficient_merge_evidence",
    "live_process",
    "locked",
    "not_finished",
    "partial_observation",
    "recent",
    "stale_owner",
    "unknown_owner",
    "unmerged",
    "unreadable",
    "untracked",
)
PROTECTED_SCRATCH = frozenset(
    ("evidence", "handoff", "review", "research", "runs")
)
REGENERABLE_SCRATCH = frozenset()
BUILD_OUTPUT_PATHS = (Path("apple/.build"), Path("apple/build"))
GIT_ENVIRONMENT_KEYS = (
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
)
SIMULATOR_IDLE_SECONDS = 24 * 60 * 60


class ResourceCounts(TypedDict):
    total: int
    eligible: int
    held: int
    hold_reasons: dict[str, int]


Report = dict[str, ResourceCounts]


class ProviderError(RuntimeError):
    """An expected inventory read failed; it is represented as an enum."""


class MutatingProviderCall(RuntimeError):
    """A provider attempted a command outside the read-only allow-list."""


@dataclass(frozen=True)
class ProcessObservation:
    """Private process facts used by classifiers, never rendered."""

    pids: frozenset[int] | None
    cwds: tuple[Path, ...] | None
    starts: Mapping[int, str] | None = None
    pgids: frozenset[int] | None = None


@dataclass(frozen=True)
class ResourceObservation:
    """One resource and the evidence needed to decide whether it can be held."""

    resource_class: str
    owned: bool | None = None
    owner_current: bool = True
    finished: bool | None = None
    merge_evidence: str = "unknown"
    active_hold: bool = False
    booted: bool = False
    dirty: bool = False
    fresh_at_main: bool = False
    ignored: bool = False
    live_process: bool = False
    locked: bool = False
    partial: bool = False
    recent: bool = False
    unreadable: bool = False
    untracked: bool = False


@dataclass(frozen=True)
class Inventory:
    """One provider's observations plus provider-wide incomplete-read counts."""

    observations: tuple[ResourceObservation, ...] = ()
    unreadable: int = 0
    partial: int = 0


class ProcessProvider(Protocol):
    """Read process facts without signaling or terminating a process."""

    def inventory(self) -> ProcessObservation:
        """Return a process snapshot."""


class ResourceProvider(Protocol):
    """Read one class of reclaimable resources."""

    resource_class: str

    def inventory(self, processes: ProcessObservation) -> Inventory:
        """Return a strictly read-only resource snapshot."""


class ReadOnlyRunner:
    """Allow-list the commands factory providers may execute."""

    def __init__(self, runner=None) -> None:
        self._runner = runner or subprocess.run

    @staticmethod
    def is_read_only(command: Sequence[str]) -> bool:
        if not command:
            return False
        if command[0] == "git" and len(command) > 3 and command[1] == "-C":
            subcommand = command[3]
            rest = command[4:]
            return (
                (subcommand == "worktree" and rest[:1] == ["list"])
                or (subcommand == "for-each-ref")
                or (subcommand == "rev-parse")
                or (subcommand == "rev-list")
                or (subcommand == "merge-base" and "--is-ancestor" in rest)
                or (subcommand == "status")
            )
        return (
            list(command) == ["xcrun", "simctl", "list", "devices", "-j"]
            or list(command) == ["lsof", "-d", "cwd", "-Fn"]
            or list(command) == ["ps", "-axo", "pid="]
            or list(command) == ["ps", "-axo", "pid=,lstart=,pgid="]
        )

    def run(
        self, command: Sequence[str], cwd: Path | None = None
    ) -> subprocess.CompletedProcess[str]:
        args = [str(part) for part in command]
        if not self.is_read_only(args):
            raise MutatingProviderCall("provider command is not read-only")
        environment = os.environ.copy()
        for key in GIT_ENVIRONMENT_KEYS:
            environment.pop(key, None)
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["LC_ALL"] = "C"
        try:
            completed = self._runner(
                args,
                cwd=str(cwd) if cwd is not None else None,
                capture_output=True,
                text=False,
                env=environment,
                timeout=60,
            )
            stdout = completed.stdout
            stderr = completed.stderr
            return subprocess.CompletedProcess(
                args,
                completed.returncode,
                (
                    stdout.decode("utf-8", errors="replace")
                    if isinstance(stdout, bytes)
                    else (stdout or "")
                ),
                (
                    stderr.decode("utf-8", errors="replace")
                    if isinstance(stderr, bytes)
                    else (stderr or "")
                ),
            )
        except (OSError, subprocess.SubprocessError, UnicodeError) as error:
            raise ProviderError("read command failed") from error


class ReadOnlyProcessProvider:
    """A private, read-only snapshot of process ids and working directories."""

    def __init__(self, runner: ReadOnlyRunner) -> None:
        self._runner = runner

    def inventory(self) -> ProcessObservation:
        try:
            ps = self._runner.run(["ps", "-axo", "pid=,lstart=,pgid="])
            pids: frozenset[int] | None
            starts: dict[int, str] | None
            pgids: set[int] | None
            if ps.returncode == 0:
                values = set()
                started: dict[int, str] = {}
                groups: set[int] = set()
                for line in ps.stdout.splitlines():
                    parts = line.split()
                    if not parts or not parts[0].isdigit():
                        continue
                    pid = int(parts[0])
                    values.add(pid)
                    if len(parts) >= 6 and parts[-1].isdigit():
                        normalized = factory_lease.normalize_process_start(
                            " ".join(parts[1:-1])
                        )
                        if normalized is not None:
                            started[pid] = normalized
                        groups.add(int(parts[-1]))
                pids = frozenset(values)
                starts = started
                pgids = groups
            else:
                pids = starts = pgids = None
        except Exception:
            pids = None
            starts = None
            pgids = None
        try:
            lsof = self._runner.run(["lsof", "-d", "cwd", "-Fn"])
            if lsof.returncode == 0:
                found = tuple(
                    Path(line[1:])
                    for line in lsof.stdout.splitlines()
                    if line.startswith("n/")
                )
                cwds = found if found else None
            else:
                cwds = None
        except Exception:
            cwds = None
        return ProcessObservation(
            pids=pids, cwds=cwds, starts=starts, pgids=frozenset(pgids) if pgids is not None else None
        )


class GitReader:
    """Read-only Git facts with the index locked out of optional writes."""

    def __init__(self, repo: Path, runner: ReadOnlyRunner) -> None:
        self.repo = repo
        self._runner = runner

    def read(self, *arguments: str) -> str:
        result = self._runner.run(["git", "-C", str(self.repo), *arguments])
        if result.returncode != 0:
            raise ProviderError("git read failed")
        return result.stdout

    def base_sha(self) -> str | None:
        result = self._runner.run(
            [
                "git",
                "-C",
                str(self.repo),
                "rev-parse",
                "--verify",
                "--quiet",
                "origin/main^{commit}",
            ]
        )
        sha = result.stdout.strip()
        return sha if result.returncode == 0 and sha else None

    def project_name(self) -> str | None:
        try:
            common = Path(
                self.read(
                    "rev-parse",
                    "--path-format=absolute",
                    "--git-common-dir",
                ).strip()
            )
        except (ProviderError, OSError):
            return None
        if common.name == ".git":
            return common.parent.name
        return common.name or None

    def repository_identity(self) -> factory_lease.RepositoryIdentity:
        common = Path(
            self.read(
                "rev-parse",
                "--path-format=absolute",
                "--git-common-dir",
            ).strip()
        ).resolve()
        shallow = self.read(
            "rev-parse", "--is-shallow-repository"
        ).strip()
        if shallow != "false":
            raise ProviderError("repository identity is shallow")
        roots = tuple(
            line
            for line in self.read(
                "rev-list", "--max-parents=0", "main"
            ).splitlines()
            if line
        )
        if len(roots) != 1:
            raise ProviderError("repository identity is ambiguous")
        return factory_lease.RepositoryIdentity(
            common_dir=common, root_commit=roots[0]
        )

    def worktrees(self) -> tuple["Worktree", ...]:
        output = self.read("worktree", "list", "--porcelain")
        found: list[Worktree] = []
        for block in output.strip().split("\n\n"):
            values: dict[str, str | bool] = {
                "path": "",
                "head": "",
                "branch": "",
                "locked": False,
            }
            for line in block.splitlines():
                key, _, value = line.partition(" ")
                if key == "worktree":
                    values["path"] = value
                elif key == "HEAD":
                    values["head"] = value
                elif key == "branch":
                    values["branch"] = (
                        value.removeprefix("refs/heads/")
                        if value.startswith("refs/heads/")
                        else value
                    )
                elif key == "locked":
                    values["locked"] = True
            if not values["path"] or not values["head"]:
                raise ProviderError("malformed worktree inventory")
            found.append(
                Worktree(
                    path=Path(str(values["path"])),
                    head=str(values["head"]),
                    branch=str(values["branch"]),
                    locked=bool(values["locked"]),
                )
            )
        return tuple(found)

    def status(self, path: Path) -> tuple[bool, bool, bool]:
        result = self._runner.run(
            [
                "git",
                "-C",
                str(path),
                "status",
                "--porcelain=v1",
                "-z",
                "--untracked-files=all",
                "--ignored=matching",
                "--no-renames",
            ]
        )
        if result.returncode != 0:
            raise ProviderError("git status failed")
        dirty = untracked = ignored = False
        for entry in result.stdout.split("\0"):
            if len(entry) < 2:
                continue
            code = entry[:2]
            if code == "??":
                untracked = True
            elif code == "!!":
                ignored = True
            else:
                dirty = True
        return dirty, untracked, ignored

    def merge_evidence(self, sha: str, base_sha: str | None) -> str:
        if not sha or base_sha is None:
            return "unknown"
        result = self._runner.run(
            [
                "git",
                "-C",
                str(self.repo),
                "merge-base",
                "--is-ancestor",
                sha,
                base_sha,
            ]
        )
        if result.returncode == 0:
            return "ancestor"
        if result.returncode == 1:
            return "unmerged"
        return "unknown"


@dataclass(frozen=True)
class Worktree:
    path: Path
    head: str
    branch: str
    locked: bool


@dataclass(frozen=True)
class LeaseSnapshot:
    """Validated read-only lease records and their incomplete-read count."""

    identity: factory_lease.RepositoryIdentity | None
    records: tuple[dict, ...] = ()
    invalid: int = 0

    @property
    def partial(self) -> bool:
        return self.invalid > 0

    @classmethod
    def empty(cls) -> "LeaseSnapshot":
        return cls(identity=None)


def path_is_within(child: Path, parent: Path) -> bool:
    child_name = os.path.realpath(str(child))
    parent_name = os.path.realpath(str(parent))
    return child_name == parent_name or child_name.startswith(
        parent_name.rstrip(os.sep) + os.sep
    )


def process_status(
    resource: Path, processes: ProcessObservation
) -> tuple[bool, bool]:
    if processes.cwds is None:
        return False, True
    if not processes.cwds and processes.pids:
        return False, True
    return (
        any(path_is_within(cwd, resource) for cwd in processes.cwds),
        False,
    )


def holder_status(
    record: Mapping, processes: ProcessObservation
) -> tuple[bool, bool]:
    """Return live-holder and partial-holder facts without signaling the pid."""

    holder = record.get("holder")
    if holder is None:
        return False, False
    if processes.pids is None or processes.starts is None:
        return False, True
    pid = holder.get("pid")
    start = holder.get("start")
    if not isinstance(pid, int) or not isinstance(start, str):
        return False, True
    normalized_start = factory_lease.normalize_process_start(start)
    if normalized_start is None:
        return False, True
    if pid not in processes.pids:
        return False, False
    observed = factory_lease.normalize_process_start(
        processes.starts.get(pid)
    )
    if observed is None:
        return False, True
    return observed == normalized_start, False


class GitResourceProvider:
    """Inventory one Git-backed resource class without changing repository state."""

    def __init__(
        self,
        resource_class: str,
        repo: Path,
        reader: GitReader,
        leases: LeaseSnapshot | None = None,
        now: float | None = None,
    ) -> None:
        if resource_class not in RESOURCE_CLASSES or resource_class == "simulators":
            raise ValueError("invalid Git resource class")
        self.resource_class = resource_class
        self.repo = repo
        self._reader = reader
        self._leases = leases or LeaseSnapshot.empty()
        self._now = now

    @property
    def now(self) -> int:
        return int(time.time()) if self._now is None else int(self._now)

    def _candidate_worktrees(
        self, worktrees: Sequence[Worktree]
    ) -> tuple[Worktree, ...]:
        current = self.repo.resolve()
        return tuple(
            tree
            for index, tree in enumerate(worktrees)
            if index != 0 and tree.path.resolve() != current
        )

    def inventory(self, processes: ProcessObservation) -> Inventory:
        try:
            worktrees = self._reader.worktrees()
            base_sha = self._reader.base_sha()
            if self.resource_class == "worktrees":
                return self._worktrees(worktrees, base_sha, processes)
            if self.resource_class == "branches":
                return self._branches(worktrees, base_sha, processes)
            if self.resource_class == "build_output":
                return self._build_output(worktrees, processes)
            if self.resource_class == "scratch":
                return self._scratch(worktrees, processes)
            if self.resource_class == "run_markers":
                return self._run_markers(worktrees, processes)
        except Exception:
            return Inventory(unreadable=1)
        return Inventory(unreadable=1)

    def _worktrees(
        self,
        worktrees: Sequence[Worktree],
        base_sha: str | None,
        processes: ProcessObservation,
    ) -> Inventory:
        observations = []
        for tree in self._candidate_worktrees(worktrees):
            observations.append(
                self._worktree_observation(tree, base_sha, processes)
            )
        return Inventory(tuple(observations))

    def _unique_lease(
        self, resource_class: str, matches
    ) -> tuple[Mapping | None, bool]:
        candidates = tuple(
            record
            for record in self._leases.records
            if record["class"] == resource_class and matches(record)
        )
        return (
            candidates[0] if len(candidates) == 1 else None,
            len(candidates) > 1 or self._leases.partial,
        )

    def _lease_timing(
        self, lease: Mapping | None
    ) -> tuple[bool, bool]:
        if lease is None:
            return False, False
        unexpired = self.now < lease["expires"]
        released = lease["state"] == "released"
        return released and not unexpired, unexpired

    def _attested(
        self, lease: Mapping | None, branch: str, head: str
    ) -> bool:
        if lease is None or lease["state"] != "released":
            return False
        release = lease["release"]
        if release is None or release["reason"] != "merged":
            return False
        merged = release["merged"]
        return bool(
            merged
            and merged["generation"] == lease["generation"]
            and merged["branch"] == branch
            and merged["local_tip"] == head
            and merged["head_oid"]
        )

    def _worktree_observation(
        self, tree: Worktree, base_sha: str | None, processes: ProcessObservation
    ) -> ResourceObservation:
        try:
            dirty, untracked, ignored = self._reader.status(tree.path)
            unreadable = False
        except Exception:
            dirty = untracked = ignored = False
            unreadable = True
        lease, lease_partial = self._unique_lease(
            "worktree",
            lambda record: (
                record["subject"]["path"] == str(tree.path.resolve())
                and factory_lease.lease_matches_worktree(
                    record, tree.path, tree.branch, tree.head
                )
            ),
        )
        owned = lease is not None
        finished, lease_active = self._lease_timing(lease)
        holder_live, holder_partial = holder_status(
            lease if lease is not None else {}, processes
        )
        live, process_partial = process_status(tree.path, processes)
        merge_evidence = (
            "attested"
            if self._attested(lease, tree.branch, tree.head)
            else self._reader.merge_evidence(tree.head, base_sha)
        )
        return ResourceObservation(
            resource_class=self.resource_class,
            owned=True if owned else None,
            finished=finished if owned else None,
            merge_evidence=merge_evidence if owned else self._reader.merge_evidence(
                tree.head, base_sha
            ),
            active_hold=lease_active or holder_live or live,
            fresh_at_main=bool(base_sha and tree.head == base_sha),
            dirty=dirty,
            ignored=ignored,
            live_process=holder_live or live,
            locked=tree.locked,
            partial=(
                lease_partial
                or holder_partial
                or process_partial
            ),
            unreadable=unreadable,
            untracked=untracked,
        )

    def _branches(
        self,
        worktrees: Sequence[Worktree],
        base_sha: str | None,
        processes: ProcessObservation,
    ) -> Inventory:
        output = self._reader.read(
            "for-each-ref",
            "--format=%(refname:short)%00%(objectname)",
            "refs/heads",
        )
        checked_out = {
            tree.branch: tree.locked for tree in worktrees if tree.branch
        }
        observations = []
        for line in output.splitlines():
            parts = line.split("\0")
            if len(parts) != 2 or not parts[0] or not parts[1]:
                raise ProviderError("malformed branch inventory")
            branch, sha = parts
            if branch == "main":
                continue
            merge_evidence = self._reader.merge_evidence(sha, base_sha)
            lease, partial = self._unique_lease(
                "branch",
                lambda record, name=branch, tip=sha: (
                    record["subject"]["name"] == name
                    and record["subject"]["head"] == tip
                ),
            )
            if lease is not None:
                parent = tuple(
                    record
                    for record in self._leases.records
                    if record["class"] == "worktree"
                    and record["lease_id"] == lease["subject"]["parent_lease_id"]
                )
                current = tuple(
                    tree
                    for tree in worktrees
                    if tree.branch == branch
                )
                if (
                    len(parent) != 1
                    or parent[0]["generation"]
                    != lease["subject"]["parent_generation"]
                    or len(current) != 1
                    or not factory_lease.lease_matches_worktree(
                        parent[0],
                        current[0].path,
                        current[0].branch,
                        current[0].head,
                    )
                ):
                    lease = None
                    partial = True
            finished, lease_active = self._lease_timing(lease)
            holder_live, holder_partial = holder_status(
                lease if lease is not None else {}, processes
            )
            if self._attested(lease, branch, sha):
                merge_evidence = "attested"
            observations.append(
                ResourceObservation(
                    resource_class=self.resource_class,
                    owned=True if lease is not None else None,
                    finished=finished if lease is not None else None,
                    merge_evidence=merge_evidence,
                    active_hold=branch in checked_out or lease_active or holder_live,
                    fresh_at_main=bool(base_sha and sha == base_sha),
                    locked=checked_out.get(branch, False),
                    partial=partial or holder_partial,
                    live_process=holder_live,
                )
            )
        return Inventory(tuple(observations))

    def _directory_observation(
        self,
        path: Path,
        worktree: Worktree,
        base_sha: str | None,
        processes: ProcessObservation,
    ) -> ResourceObservation:
        live, partial = process_status(path, processes)
        parent = self._worktree_observation(
            worktree, base_sha, processes
        )
        owned = parent.owned is True
        merge_evidence = (
            "not_required"
            if owned
            and parent.finished is True
            and (
                self.resource_class != "scratch"
                or path.name in REGENERABLE_SCRATCH
            )
            else "unknown"
        )
        recent = self._directory_recent(path)
        return ResourceObservation(
            resource_class=self.resource_class,
            owned=True if owned else None,
            finished=parent.finished if owned else None,
            merge_evidence=merge_evidence,
            active_hold=live or parent.active_hold,
            dirty=parent.dirty,
            ignored=parent.ignored,
            live_process=live or parent.live_process,
            locked=parent.locked,
            partial=partial or parent.partial,
            recent=recent,
            unreadable=parent.unreadable,
            untracked=parent.untracked,
        )

    def _directory_recent(self, path: Path) -> bool:
        newest = float(path.lstat().st_mtime)
        seen = 0
        try:
            if path.is_symlink():
                return True
            for base, directories, files in os.walk(path, followlinks=False):
                directories.sort()
                files.sort()
                seen += len(directories) + len(files)
                if seen > 10_000:
                    return True
                for name in directories + files:
                    child = Path(base) / name
                    info = child.lstat()
                    newest = max(newest, info.st_mtime)
            return newest > self.now - factory_lease.LEASE_TTL_SECONDS
        except OSError:
            return True

    def _build_output(
        self, worktrees: Sequence[Worktree], processes: ProcessObservation
    ) -> Inventory:
        observations = []
        base_sha = self._reader.base_sha()
        for tree in self._candidate_worktrees(worktrees):
            for relative in BUILD_OUTPUT_PATHS:
                path = tree.path / relative
                try:
                    if not os.path.lexists(path):
                        continue
                    mode = path.lstat().st_mode
                    if path.is_symlink() or not stat.S_ISDIR(mode):
                        observations.append(
                            ResourceObservation(
                                resource_class=self.resource_class,
                                unreadable=True,
                            )
                        )
                    else:
                        observations.append(
                            self._directory_observation(
                                path, tree, base_sha, processes
                            )
                        )
                except OSError as error:
                    raise ProviderError("build output unreadable") from error
        return Inventory(tuple(observations))

    def _scratch(
        self, worktrees: Sequence[Worktree], processes: ProcessObservation
    ) -> Inventory:
        observations = []
        base_sha = self._reader.base_sha()
        for tree in self._candidate_worktrees(worktrees):
            build = tree.path / "build"
            try:
                if not build.exists():
                    continue
                children = tuple(
                    child
                    for child in build.iterdir()
                    if child.name not in PROTECTED_SCRATCH
                )
            except OSError as error:
                raise ProviderError("scratch inventory unreadable") from error
            for child in children:
                if child.is_symlink():
                    observations.append(
                        ResourceObservation(
                            resource_class=self.resource_class,
                            unreadable=True,
                        )
                    )
                elif stat.S_ISDIR(child.lstat().st_mode):
                    observations.append(
                        self._directory_observation(
                            child, tree, base_sha, processes
                        )
                    )
        return Inventory(tuple(observations))

    def _run_markers(
        self, worktrees: Sequence[Worktree], processes: ProcessObservation
    ) -> Inventory:
        observations = []
        for tree in self._candidate_worktrees(worktrees):
            directory = tree.path / "build" / "runs"
            try:
                if not directory.exists():
                    continue
                markers = tuple(directory.glob("*.running"))
            except OSError as error:
                raise ProviderError("run markers unreadable") from error
            for marker in markers:
                unreadable = False
                live = False
                partial = processes.pids is None or self._leases.partial
                owned = False
                finished = None
                active_hold = False
                lease_id = None
                marker_record = None
                try:
                    record = factory_lease.strict_json_loads(
                        marker.read_text(encoding="utf-8")
                    )
                    pid = record.get("pid") if isinstance(record, dict) else None
                    if not isinstance(pid, int) or pid <= 0:
                        raise ValueError("invalid marker")
                    marker_start = record.get("start")
                    marker_pgid = record.get("pgid")
                    lease_id = record.get("lease_id")
                    if record.get("v") == 1:
                        expected = (
                            "v",
                            "pid",
                            "label",
                            "started",
                            "cwd",
                            "lease_id",
                            "start",
                            "pgid",
                        )
                        if set(record) != set(expected):
                            raise ValueError("invalid marker")
                    normalized_marker_start = (
                        factory_lease.normalize_process_start(marker_start)
                    )
                    if processes.pids is not None:
                        if normalized_marker_start is None:
                            live = pid in processes.pids
                            partial = True
                        elif processes.starts is None:
                            partial = True
                        else:
                            observed_start = (
                                factory_lease.normalize_process_start(
                                    processes.starts.get(pid)
                                )
                            )
                            live = (
                                pid in processes.pids
                                and observed_start == normalized_marker_start
                            )
                            if pid in processes.pids and observed_start is None:
                                partial = True
                    if isinstance(marker_pgid, int):
                        if processes.pgids is None:
                            partial = True
                        else:
                            live = live or marker_pgid in processes.pgids
                    elif record.get("v") == 1:
                        partial = True
                    if lease_id is not None:
                        matches = tuple(
                            candidate
                            for candidate in self._leases.records
                            if candidate["class"] == "run_marker"
                            and candidate["lease_id"] == lease_id
                            and candidate["subject"]["path"]
                            == str(marker.resolve())
                            and candidate["subject"]["label"] == marker.stem
                            and candidate["subject"]["nonce"] == lease_id
                        )
                        if len(matches) != 1:
                            partial = True
                        else:
                            marker_lease = matches[0]
                            parent = tuple(
                                candidate
                                for candidate in self._leases.records
                                if candidate["class"] == "worktree"
                                and candidate["lease_id"]
                                == marker_lease["subject"]["parent_lease_id"]
                            )
                            if (
                                len(parent) == 1
                                and parent[0]["generation"]
                                == marker_lease["subject"]["parent_generation"]
                                and factory_lease.lease_matches_worktree(
                                    parent[0],
                                    tree.path,
                                    tree.branch,
                                    tree.head,
                                )
                            ):
                                owned = True
                                marker_record = marker_lease
                                finished, active_hold = self._lease_timing(
                                    marker_lease
                                )
                    if marker_record is not None:
                        holder_live, holder_partial = holder_status(
                            marker_record, processes
                        )
                        live = live or holder_live
                        partial = partial or holder_partial
                except (
                    OSError,
                    ValueError,
                    UnicodeError,
                    TypeError,
                ):
                    unreadable = True
                observations.append(
                    ResourceObservation(
                        resource_class=self.resource_class,
                        owned=True if owned else None,
                        finished=finished if owned and not partial else None,
                        merge_evidence="not_required",
                        active_hold=live or active_hold,
                        live_process=live,
                        partial=partial,
                        unreadable=unreadable,
                    )
                )
        return Inventory(tuple(observations))


class SimulatorResourceProvider:
    """Read simulator and devcap state without invoking any reaper command."""

    resource_class = "simulators"

    def __init__(
        self,
        repo: Path,
        runner: ReadOnlyRunner,
        git: GitReader,
        devcap_root: Path | None = None,
        now: float | None = None,
    ) -> None:
        self._repo = repo
        self._runner = runner
        self._git = git
        self._devcap_root = devcap_root or Path(
            os.environ.get("DEVCAP_DIR") or Path.home() / ".devcap"
        )
        self._now = now

    def inventory(self, _processes: ProcessObservation) -> Inventory:
        try:
            output = self._runner.run(
                ["xcrun", "simctl", "list", "devices", "-j"]
            )
            if output.returncode != 0:
                return Inventory(unreadable=1)
            listing = json.loads(output.stdout)
            devices = listing.get("devices")
            if not isinstance(devices, dict):
                return Inventory(unreadable=1)
        except (ProviderError, TypeError, ValueError, UnicodeError):
            return Inventory(unreadable=1)

        registry, registry_partial = self._registry()
        held, hold_partial = self._held()
        project = os.environ.get("DEVCAP_PROJECT") or self._git.project_name()
        observations = []
        partial_inventory = 0
        stamp = time.time() if self._now is None else self._now
        for runtime_devices in devices.values():
            if not isinstance(runtime_devices, list):
                partial_inventory += 1
                continue
            for device in runtime_devices:
                if not isinstance(device, dict):
                    partial_inventory += 1
                    continue
                udid = str(device.get("udid", "")).upper()
                raw_state = device.get("state")
                state = raw_state if isinstance(raw_state, str) else ""
                if not udid:
                    observations.append(
                        ResourceObservation(
                            resource_class=self.resource_class,
                            unreadable=True,
                        )
                    )
                    continue
                record = registry.get(udid)
                owned = None
                owner_current = True
                partial = registry_partial or hold_partial
                if not state:
                    partial = True
                if isinstance(record, dict):
                    kind = record.get("kind")
                    owner = record.get("project")
                    if kind in ("pool", "ephemeral") and owner is not None:
                        if project:
                            owned = owner == project
                        else:
                            owner_current = False
                            partial = True
                    released = record.get("last_release_epoch")
                    if not isinstance(released, (int, float)):
                        partial = True
                        recent = False
                    else:
                        recent = stamp - float(released) < SIMULATOR_IDLE_SECONDS
                else:
                    recent = False
                booted = state != "Shutdown"
                active = udid in held
                observations.append(
                    ResourceObservation(
                        resource_class=self.resource_class,
                        owned=owned,
                        owner_current=owner_current,
                        finished=not booted and not active,
                        merge_evidence="not_required",
                        active_hold=active,
                        booted=booted,
                        partial=partial,
                        recent=recent,
                    )
                )
        return Inventory(tuple(observations), partial=partial_inventory)

    def _registry(self) -> tuple[dict[str, dict], bool]:
        path = self._devcap_root / "sims.json"
        try:
            if not path.exists():
                return {}, False
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError, UnicodeError):
            return {}, True
        if not isinstance(value, dict):
            return {}, True
        return (
            {
                str(key).upper(): record
                for key, record in value.items()
                if isinstance(record, dict)
            },
            len(value) != sum(
                isinstance(record, dict) for record in value.values()
            ),
        )

    def _held(self) -> tuple[set[str], bool]:
        if not self._devcap_root.exists():
            return set(), False
        held: set[str] = set()
        partial = False
        try:
            gates = tuple(
                path
                for path in self._devcap_root.iterdir()
                if path.name.startswith("device-") and path.is_dir()
            )
        except OSError:
            return set(), True
        for gate in gates:
            try:
                holders = tuple(gate.glob("slot-*.json"))
                queue = gate / "queue"
                has_waiter = queue.is_dir() and any(queue.iterdir())
            except OSError:
                partial = True
                continue
            if holders or has_waiter:
                held.add(gate.name[len("device-") :].upper())
        return held, partial


def classify(observation: ResourceObservation) -> frozenset[str]:
    """Return every enumerated reason a resource must be held."""

    if observation.resource_class not in RESOURCE_CLASSES:
        return frozenset(("unreadable",))
    if observation.unreadable:
        return frozenset(("unreadable",))
    reasons: set[str] = set()
    if observation.partial:
        reasons.add("partial_observation")
    if observation.owned is None:
        reasons.add("unknown_owner")
    elif not observation.owned:
        reasons.add("foreign")
    else:
        if not observation.owner_current:
            reasons.add("stale_owner")
        if observation.finished is not True:
            reasons.add("not_finished")
    if observation.active_hold:
        reasons.add("active_hold")
    if observation.booted:
        reasons.add("booted")
    if observation.dirty:
        reasons.add("dirty")
    if observation.fresh_at_main:
        reasons.add("fresh_at_main")
    if observation.ignored:
        reasons.add("ignored")
    if observation.live_process:
        reasons.add("live_process")
    if observation.locked:
        reasons.add("locked")
    if observation.recent:
        reasons.add("recent")
    if observation.untracked:
        reasons.add("untracked")
    if observation.merge_evidence == "unmerged":
        reasons.add("unmerged")
    elif observation.merge_evidence == "ancestor":
        if not observation.fresh_at_main:
            reasons.add("insufficient_merge_evidence")
    elif observation.merge_evidence == "attested":
        if observation.resource_class == "simulators":
            reasons.add("insufficient_merge_evidence")
    elif observation.merge_evidence == "not_required":
        if observation.resource_class in ("worktrees", "branches"):
            reasons.add("insufficient_merge_evidence")
    else:
        reasons.add("insufficient_merge_evidence")
    return frozenset(reasons)


def empty_report() -> Report:
    return {
        resource_class: {
            "total": 0,
            "eligible": 0,
            "held": 0,
            "hold_reasons": {reason: 0 for reason in HOLD_REASONS},
        }
        for resource_class in RESOURCE_CLASSES
    }


def add_inventory(
    report: Report, resource_class: str, inventory: Inventory
) -> None:
    aggregate = report[resource_class]
    reasons = aggregate["hold_reasons"]
    for observation in inventory.observations:
        aggregate["total"] += 1
        held_for = classify(observation)
        if held_for:
            aggregate["held"] += 1
            for reason in held_for:
                reasons[reason] += 1
        else:
            aggregate["eligible"] += 1
    reasons["unreadable"] += inventory.unreadable
    reasons["partial_observation"] += inventory.partial


def build_report(
    providers: Iterable[ResourceProvider],
    processes: ProcessProvider,
) -> Report:
    """Aggregate provider observations into counts and enumerated reasons."""

    report = empty_report()
    try:
        process_snapshot = processes.inventory()
    except Exception:
        process_snapshot = ProcessObservation(pids=None, cwds=None)
    if not isinstance(process_snapshot, ProcessObservation):
        process_snapshot = ProcessObservation(pids=None, cwds=None)
    seen = set()
    for provider in providers:
        try:
            resource_class = provider.resource_class
        except Exception:
            continue
        if resource_class not in RESOURCE_CLASSES:
            continue
        seen.add(resource_class)
        try:
            inventory = provider.inventory(process_snapshot)
            add_inventory(report, resource_class, inventory)
        except Exception:
            inventory = Inventory(unreadable=1)
            add_inventory(report, resource_class, inventory)
    for resource_class in RESOURCE_CLASSES:
        if resource_class not in seen:
            add_inventory(report, resource_class, Inventory(unreadable=1))
    return report


def render_text(report: Mapping[str, ResourceCounts]) -> str:
    lines = []
    for resource_class in RESOURCE_CLASSES:
        aggregate = report[resource_class]
        lines.append(
            f"{resource_class} total={aggregate['total']} "
            f"eligible={aggregate['eligible']} held={aggregate['held']}"
        )
        reasons = aggregate["hold_reasons"]
        if not isinstance(reasons, Mapping):
            raise TypeError("hold_reasons must be a mapping")
        for reason in HOLD_REASONS:
            lines.append(f"{resource_class}.{reason}={reasons[reason]}")
    return "\n".join(lines) + "\n"


def default_providers(
    repo: Path, runner: ReadOnlyRunner | None = None
) -> tuple[tuple[ResourceProvider, ...], ProcessProvider]:
    command_runner = runner or ReadOnlyRunner()
    git = GitReader(repo, command_runner)
    try:
        identity = git.repository_identity()
        records, invalid = factory_lease.LeaseStore(identity).read_records()
        leases = LeaseSnapshot(
            identity=identity, records=tuple(records), invalid=invalid
        )
    except Exception:
        leases = LeaseSnapshot(identity=None, invalid=1)
    providers: list[ResourceProvider] = [
        GitResourceProvider(resource_class, repo, git, leases)
        for resource_class in (
            "worktrees",
            "branches",
            "build_output",
            "scratch",
            "run_markers",
        )
    ]
    providers.append(SimulatorResourceProvider(repo, command_runner, git))
    return tuple(providers), ReadOnlyProcessProvider(command_runner)


def main(arguments: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Count factory resources and hold reasons without changing state."
    )
    commands = parser.add_subparsers(dest="command", required=True)
    report = commands.add_parser("report", help="report aggregate counts only")
    report.add_argument("--json", action="store_true", help="emit JSON counts")
    report.add_argument(
        "--repo",
        type=Path,
        default=Path.cwd(),
        help="repository checkout to inspect read-only",
    )
    args = parser.parse_args(arguments)
    try:
        providers, processes = default_providers(args.repo.resolve())
        result = build_report(providers, processes)
        if args.json:
            print(json.dumps(result, indent=2, sort_keys=True))
        else:
            sys.stdout.write(render_text(result))
    except Exception:
        sys.stderr.write("factory report failed\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
