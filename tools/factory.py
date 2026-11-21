#!/usr/bin/env python3
"""Read-only inventory of resources an agent factory can leave behind.

``factory.py report [--json] [--repo PATH]`` prints counts only. Providers
observe resources; the classifier never performs cleanup. All incomplete
observations are holds, and no patch/tree equivalence counts as merge proof.
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
                or (subcommand == "merge-base" and "--is-ancestor" in rest)
                or (subcommand == "status")
            )
        return (
            list(command) == ["xcrun", "simctl", "list", "devices", "-j"]
            or list(command) == ["lsof", "-d", "cwd", "-Fn"]
            or list(command) == ["ps", "-axo", "pid=,command="]
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
            return self._runner(
                args,
                cwd=str(cwd) if cwd is not None else None,
                capture_output=True,
                text=True,
                env=environment,
                timeout=60,
            )
        except (OSError, subprocess.SubprocessError) as error:
            raise ProviderError("read command failed") from error


class ReadOnlyProcessProvider:
    """A private, read-only snapshot of process ids and working directories."""

    def __init__(self, runner: ReadOnlyRunner) -> None:
        self._runner = runner

    def inventory(self) -> ProcessObservation:
        try:
            ps = self._runner.run(["ps", "-axo", "pid=,command="])
            pids = (
                frozenset(
                    int(parts[0])
                    for line in ps.stdout.splitlines()
                    if (parts := line.split(None, 1)) and parts[0].isdigit()
                )
                if ps.returncode == 0
                else None
            )
        except ProviderError:
            pids = None
        try:
            lsof = self._runner.run(["lsof", "-d", "cwd", "-Fn"])
            cwds = (
                tuple(
                    Path(line[1:])
                    for line in lsof.stdout.splitlines()
                    if line.startswith("n/")
                )
                if lsof.returncode == 0
                else None
            )
        except ProviderError:
            cwds = None
        return ProcessObservation(pids=pids, cwds=cwds)


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
    return (
        any(path_is_within(cwd, resource) for cwd in processes.cwds),
        False,
    )


class GitResourceProvider:
    """Inventory one Git-backed resource class without changing repository state."""

    def __init__(
        self, resource_class: str, repo: Path, reader: GitReader
    ) -> None:
        if resource_class not in RESOURCE_CLASSES or resource_class == "simulators":
            raise ValueError("invalid Git resource class")
        self.resource_class = resource_class
        self.repo = repo
        self._reader = reader

    def inventory(self, processes: ProcessObservation) -> Inventory:
        try:
            worktrees = self._reader.worktrees()
            base_sha = self._reader.base_sha()
            if self.resource_class == "worktrees":
                return self._worktrees(worktrees, base_sha, processes)
            if self.resource_class == "branches":
                return self._branches(worktrees, base_sha)
            if self.resource_class == "build_output":
                return self._build_output(worktrees, processes)
            if self.resource_class == "scratch":
                return self._scratch(worktrees, processes)
            if self.resource_class == "run_markers":
                return self._run_markers(worktrees, processes)
        except ProviderError:
            return Inventory(unreadable=1)
        return Inventory(unreadable=1)

    def _worktrees(
        self,
        worktrees: Sequence[Worktree],
        base_sha: str | None,
        processes: ProcessObservation,
    ) -> Inventory:
        observations = []
        for tree in worktrees[1:]:
            try:
                dirty, untracked, ignored = self._reader.status(tree.path)
                unreadable = False
            except ProviderError:
                dirty = untracked = ignored = False
                unreadable = True
            live, process_partial = process_status(tree.path, processes)
            observations.append(
                ResourceObservation(
                    resource_class=self.resource_class,
                    finished=(
                        self._reader.merge_evidence(tree.head, base_sha)
                        == "ancestor"
                    ),
                    merge_evidence=self._reader.merge_evidence(
                        tree.head, base_sha
                    ),
                    active_hold=live,
                    fresh_at_main=bool(base_sha and tree.head == base_sha),
                    dirty=dirty,
                    ignored=ignored,
                    live_process=live,
                    locked=tree.locked,
                    partial=process_partial,
                    unreadable=unreadable,
                    untracked=untracked,
                )
            )
        return Inventory(tuple(observations))

    def _branches(
        self, worktrees: Sequence[Worktree], base_sha: str | None
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
            observations.append(
                ResourceObservation(
                    resource_class=self.resource_class,
                    finished=self._reader.merge_evidence(sha, base_sha)
                    == "ancestor",
                    merge_evidence=self._reader.merge_evidence(sha, base_sha),
                    active_hold=branch in checked_out,
                    fresh_at_main=bool(base_sha and sha == base_sha),
                    locked=checked_out.get(branch, False),
                )
            )
        return Inventory(tuple(observations))

    def _directory_observation(
        self, path: Path, processes: ProcessObservation
    ) -> ResourceObservation:
        live, partial = process_status(path, processes)
        return ResourceObservation(
            resource_class=self.resource_class,
            finished=True,
            merge_evidence="not_required",
            active_hold=live,
            live_process=live,
            partial=partial,
        )

    def _build_output(
        self, worktrees: Sequence[Worktree], processes: ProcessObservation
    ) -> Inventory:
        observations = []
        for tree in worktrees:
            for relative in BUILD_OUTPUT_PATHS:
                path = tree.path / relative
                try:
                    if path.exists() and stat.S_ISDIR(path.stat().st_mode):
                        observations.append(
                            self._directory_observation(path, processes)
                        )
                except OSError as error:
                    raise ProviderError("build output unreadable") from error
        return Inventory(tuple(observations))

    def _scratch(
        self, worktrees: Sequence[Worktree], processes: ProcessObservation
    ) -> Inventory:
        observations = []
        for tree in worktrees:
            build = tree.path / "build"
            if not build.exists():
                continue
            try:
                children = tuple(
                    child
                    for child in build.iterdir()
                    if child.name not in PROTECTED_SCRATCH
                    and stat.S_ISDIR(child.stat().st_mode)
                )
            except OSError as error:
                raise ProviderError("scratch inventory unreadable") from error
            observations.extend(
                self._directory_observation(child, processes)
                for child in children
            )
        return Inventory(tuple(observations))

    def _run_markers(
        self, worktrees: Sequence[Worktree], processes: ProcessObservation
    ) -> Inventory:
        observations = []
        for tree in worktrees:
            directory = tree.path / "build" / "runs"
            if not directory.exists():
                continue
            try:
                markers = tuple(directory.glob("*.running"))
            except OSError as error:
                raise ProviderError("run markers unreadable") from error
            for marker in markers:
                unreadable = False
                live = False
                partial = processes.pids is None
                try:
                    record = json.loads(marker.read_text(encoding="utf-8"))
                    pid = record.get("pid") if isinstance(record, dict) else None
                    if not isinstance(pid, int) or pid <= 0:
                        raise ValueError("invalid marker")
                    if processes.pids is not None:
                        live = pid in processes.pids
                except (OSError, ValueError, UnicodeError):
                    unreadable = True
                observations.append(
                    ResourceObservation(
                        resource_class=self.resource_class,
                        finished=not live if not partial else None,
                        merge_evidence="not_required",
                        active_hold=live,
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
    elif observation.merge_evidence not in ("ancestor", "not_required"):
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
    process_snapshot = processes.inventory()
    seen = set()
    for provider in providers:
        resource_class = provider.resource_class
        if resource_class not in RESOURCE_CLASSES:
            continue
        seen.add(resource_class)
        try:
            inventory = provider.inventory(process_snapshot)
        except ProviderError:
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
    providers: list[ResourceProvider] = [
        GitResourceProvider(resource_class, repo, git)
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
    providers, processes = default_providers(args.repo.resolve())
    result = build_report(providers, processes)
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        sys.stdout.write(render_text(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
