#!/usr/bin/env python3
"""Private, fail-closed leases for resources created by the agent factory.

The store lives below the repository's verified Git common directory. Report
readers never create it and never take its writer lock. Every mutation is
serialized by the same ``flock`` and publishes a bounded, closed-schema record
through a private file, ``fsync`` and atomic replacement. A lease is evidence
for ownership and finish; it is never permission to remove a resource.
"""

from __future__ import annotations

import argparse
import calendar
import fcntl
import json
import math
import os
import re
import secrets
import stat
import subprocess
import sys
import time
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, List, Mapping, Optional, Sequence, Tuple


SCHEMA_VERSION = 1
LEASE_TTL_SECONDS = 72 * 60 * 60
MAX_RECORD_BYTES = 64 * 1024
RESOURCE_CLASSES = ("worktree", "branch", "run_marker")
CREATORS = ("lane_new", "bg_run", "hook_session", "hook_agent_tool", "adopt")
RELEASE_REASONS = ("merged", "ended", "abandoned")
LEASE_ID_PATTERN = re.compile(r"^[0-9a-f]{32}$")
OID_PATTERN = re.compile(r"^[0-9a-f]{40}$")
BRANCH_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,254}$")
LABEL_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


class LeaseError(RuntimeError):
    """A fixed, non-sensitive reason that a lease operation could not complete."""


class LockBusy(LeaseError):
    """The common writer lock is already held."""


class InvalidLease(LeaseError):
    """A lease record or resource identity is not valid."""


@dataclass(frozen=True)
class RepositoryIdentity:
    common_dir: Path
    root_commit: str

    def as_json(self) -> Dict[str, Any]:
        return {
            "common_dir": str(self.common_dir),
            "root_commit": self.root_commit,
        }


@dataclass(frozen=True)
class WorktreeBinding:
    path: Path
    device: int
    inode: int
    branch: str
    head: str
    gitfile: Path
    admin_dir: Path
    backpointer: Path
    nonce_path: Path
    common_dir: Path

    def as_subject(
        self, branch_lease_id: Optional[str] = None, branch_created: bool = False
    ) -> Dict[str, Any]:
        return {
            "path": str(self.path),
            "device": self.device,
            "inode": self.inode,
            "branch": self.branch,
            "head": self.head,
            "gitfile": str(self.gitfile),
            "admin_dir": str(self.admin_dir),
            "backpointer": str(self.backpointer),
            "nonce_path": str(self.nonce_path),
            "branch_lease_id": branch_lease_id,
            "branch_created": branch_created,
        }


@dataclass(frozen=True)
class PullRequestEvidence:
    number: int
    repository: str
    base: str
    branch: str
    state: str
    head_oid: str
    created_at: Optional[int] = None


class PullRequestProvider:
    """Injectable read-only pull-request provider."""

    def list_for_branch(self, repository: str, branch: str) -> Sequence[PullRequestEvidence]:
        raise NotImplementedError


class GhPullRequestProvider(PullRequestProvider):
    """Production pull-request evidence from read-only ``gh`` calls."""

    def __init__(self, runner: Any = None) -> None:
        self._runner = runner or subprocess.run

    def list_for_branch(self, repository: str, branch: str) -> Sequence[PullRequestEvidence]:
        completed = self._runner(
            [
                "gh",
                "pr",
                "list",
                "--repo",
                repository,
                "--head",
                branch,
                "--state",
                "all",
                "--json",
                "number,baseRefName,headRefName,state,headRefOid,headRepository,createdAt",
            ],
            capture_output=True,
            text=True,
            timeout=60,
            env=_clean_environment(),
        )
        if completed.returncode != 0:
            raise LeaseError("pull request evidence unavailable")
        try:
            payload = strict_json_loads(completed.stdout)
        except (TypeError, ValueError, UnicodeError) as error:
            raise LeaseError("pull request evidence unavailable") from error
        if not isinstance(payload, list):
            raise LeaseError("pull request evidence unavailable")
        found = []
        for raw in payload:
            if not isinstance(raw, dict):
                raise LeaseError("pull request evidence ambiguous")
            repository_name = raw.get("headRepository")
            if isinstance(repository_name, dict):
                repository_name = repository_name.get("nameWithOwner")
            try:
                found.append(
                    PullRequestEvidence(
                        number=_positive_integer(raw.get("number")),
                        repository=_bounded_text(repository_name, 200),
                        base=_bounded_text(raw.get("baseRefName"), 255),
                        branch=_bounded_text(raw.get("headRefName"), 255),
                        state=_bounded_text(raw.get("state"), 16).upper(),
                        head_oid=_oid(raw.get("headRefOid")),
                        created_at=_github_epoch(raw.get("createdAt")),
                    )
                )
            except LeaseError as error:
                raise LeaseError("pull request evidence ambiguous") from error
        return tuple(found)


def strict_json_loads(value: str) -> Any:
    """Decode JSON with duplicate keys, non-finite numbers and trailing data refused."""

    def pairs(items: Sequence[Tuple[str, Any]]) -> Dict[str, Any]:
        result: Dict[str, Any] = {}
        for key, item in items:
            if key in result:
                raise ValueError("duplicate key")
            result[key] = item
        return result

    def constant(_token: str) -> Any:
        raise ValueError("non-finite number")

    def floating(token: str) -> float:
        result = float(token)
        if not math.isfinite(result):
            raise ValueError("non-finite number")
        return result

    try:
        decoded = json.loads(
            value,
            object_pairs_hook=pairs,
            parse_constant=constant,
            parse_float=floating,
        )
        _bounded_json_depth(decoded)
        return decoded
    except RecursionError as error:
        raise ValueError("excessive JSON depth") from error


def _bounded_json_depth(value: Any, depth: int = 0) -> None:
    if depth > 32:
        raise ValueError("excessive JSON depth")
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                raise ValueError("non-string JSON key")
            _bounded_json_depth(child, depth + 1)
    elif isinstance(value, list):
        for child in value:
            _bounded_json_depth(child, depth + 1)


def canonical_bytes(value: Mapping[str, Any]) -> bytes:
    encoded = (
        json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")
    if len(encoded) > MAX_RECORD_BYTES:
        raise InvalidLease("lease record too large")
    return encoded


def _clean_environment() -> Dict[str, str]:
    environment = os.environ.copy()
    for key in (
        "GIT_DIR",
        "GIT_WORK_TREE",
        "GIT_INDEX_FILE",
        "GIT_COMMON_DIR",
        "GIT_OBJECT_DIRECTORY",
        "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    ):
        environment.pop(key, None)
    environment["GIT_OPTIONAL_LOCKS"] = "0"
    environment["GIT_TERMINAL_PROMPT"] = "0"
    environment["LC_ALL"] = "C"
    return environment


def _git(repo: Path, *arguments: str) -> str:
    completed = subprocess.run(
        ["git", "-C", str(repo), *arguments],
        capture_output=True,
        text=True,
        env=_clean_environment(),
        timeout=60,
    )
    if completed.returncode != 0:
        raise LeaseError("repository evidence unavailable")
    return completed.stdout


def _canonical(path: Path, strict: bool = True) -> Path:
    try:
        return Path(os.path.realpath(str(path), strict=strict))
    except TypeError:
        # ``strict`` did not exist on every Python supported by this repository.
        return Path(os.path.realpath(str(path)))


def _open_directory(path: Path, create: bool = False) -> int:
    canonical = _canonical(path, strict=False)
    parts = canonical.parts
    if not parts or parts[0] != os.sep:
        raise LeaseError("invalid path")
    descriptor = os.open(os.sep, os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in parts[1:]:
            flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
            created = False
            try:
                child = os.open(part, flags, dir_fd=descriptor)
            except FileNotFoundError:
                if not create:
                    raise
                os.mkdir(part, 0o700, dir_fd=descriptor)
                child = os.open(part, flags, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
    except Exception:
        os.close(descriptor)
        raise
    return descriptor


def _open_child_directory(parent_fd: int, name: str, create: bool = False) -> int:
    if name in ("", ".", "..") or os.sep in name:
        raise LeaseError("invalid path")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    try:
        descriptor = os.open(name, flags, dir_fd=parent_fd)
    except FileNotFoundError:
        if not create:
            raise
        os.mkdir(name, 0o700, dir_fd=parent_fd)
        descriptor = os.open(name, flags, dir_fd=parent_fd)
    if create:
        os.fchmod(descriptor, 0o700)
    elif stat.S_IMODE(os.fstat(descriptor).st_mode) != 0o700:
        os.close(descriptor)
        raise InvalidLease("private directory mode is invalid")
    return descriptor


def _read_path_nofollow(
    path: Path, limit: int, expected_mode: Optional[int] = None
) -> bytes:
    canonical = _canonical(path, strict=False)
    parent = canonical.parent
    parent_fd = _open_directory(parent)
    descriptor = None
    try:
        descriptor = os.open(
            canonical.name,
            os.O_RDONLY | os.O_NOFOLLOW,
            dir_fd=parent_fd,
        )
        info = os.fstat(descriptor)
        if (
            not stat.S_ISREG(info.st_mode)
            or info.st_size > limit
            or (
                expected_mode is not None
                and stat.S_IMODE(info.st_mode) != expected_mode
            )
        ):
            raise InvalidLease("invalid private file")
        chunks = []
        remaining = limit + 1
        while remaining > 0:
            chunk = os.read(descriptor, min(8192, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        data = b"".join(chunks)
        if len(data) > limit:
            raise InvalidLease("private file too large")
        return data
    finally:
        if descriptor is not None:
            os.close(descriptor)
        os.close(parent_fd)


def _require_regular_directory(path: Path) -> None:
    canonical = _canonical(path)
    if path.is_symlink() or not canonical.exists():
        raise InvalidLease("resource identity unavailable")
    info = canonical.lstat()
    if not stat.S_ISDIR(info.st_mode):
        raise InvalidLease("resource identity unavailable")


def _bounded_text(value: Any, limit: int, nonempty: bool = True) -> str:
    if not isinstance(value, str) or len(value) > limit:
        raise InvalidLease("invalid lease value")
    if nonempty and not value:
        raise InvalidLease("invalid lease value")
    return value


def _nullable_text(value: Any, limit: int) -> Optional[str]:
    if value is None:
        return None
    return _bounded_text(value, limit)


def _integer(value: Any) -> int:
    if type(value) is not int or value < 0 or value > 2**63 - 1:
        raise InvalidLease("invalid lease integer")
    return value


def _positive_integer(value: Any) -> int:
    result = _integer(value)
    if result <= 0:
        raise InvalidLease("invalid lease integer")
    return result


def _oid(value: Any) -> str:
    text = _bounded_text(value, 40)
    if not OID_PATTERN.fullmatch(text):
        raise InvalidLease("invalid object identity")
    return text


def _lease_id(value: Any) -> str:
    text = _bounded_text(value, 32)
    if not LEASE_ID_PATTERN.fullmatch(text):
        raise InvalidLease("invalid lease identity")
    return text


def _branch(value: Any) -> str:
    text = _bounded_text(value, 255)
    if not BRANCH_PATTERN.fullmatch(text) or text.endswith("/") or ".." in text:
        raise InvalidLease("invalid branch")
    return text


def _github_epoch(value: Any) -> Optional[int]:
    if value is None:
        return None
    text = _bounded_text(value, 40)
    try:
        parsed = time.strptime(text.replace("Z", "+00:00")[:19], "%Y-%m-%dT%H:%M:%S")
        return calendar.timegm(parsed)
    except (ValueError, OverflowError) as error:
        raise InvalidLease("invalid pull request time") from error


def discover_repository(repo: Path) -> RepositoryIdentity:
    """Return a canonical identity from the complete, unique ``main`` history."""

    common_text = _git(
        repo, "rev-parse", "--path-format=absolute", "--git-common-dir"
    ).strip()
    if not common_text:
        raise LeaseError("repository identity unavailable")
    common = _canonical(Path(common_text))
    shallow = _git(repo, "rev-parse", "--is-shallow-repository").strip()
    if shallow != "false":
        raise LeaseError("repository identity unavailable")
    roots = [
        _oid(line.strip())
        for line in _git(repo, "rev-list", "--max-parents=0", "main").splitlines()
        if line.strip()
    ]
    if len(roots) != 1:
        raise LeaseError("repository identity ambiguous")
    descriptor = _open_directory(common)
    os.close(descriptor)
    return RepositoryIdentity(common_dir=common, root_commit=roots[0])


def _parse_worktrees(output: str) -> Dict[Path, Dict[str, str]]:
    found: Dict[Path, Dict[str, str]] = {}
    for block in output.strip().split("\n\n"):
        row: Dict[str, str] = {}
        for line in block.splitlines():
            key, _, value = line.partition(" ")
            if key in ("worktree", "HEAD", "branch"):
                row[key] = value
        if "worktree" not in row or "HEAD" not in row:
            raise LeaseError("worktree identity unavailable")
        found[_canonical(Path(row["worktree"]))] = row
    return found


def inspect_worktree(path: Path, identity: RepositoryIdentity) -> WorktreeBinding:
    """Validate one linked worktree's live registration, gitdir and backpointer."""

    canonical = _canonical(path)
    _require_regular_directory(canonical)
    if path.is_symlink():
        raise InvalidLease("resource identity unavailable")
    inventory = _parse_worktrees(_git(canonical, "worktree", "list", "--porcelain"))
    row = inventory.get(canonical)
    if row is None:
        raise InvalidLease("worktree is not registered")
    branch_ref = row.get("branch", "")
    if not branch_ref.startswith("refs/heads/"):
        raise InvalidLease("worktree branch unavailable")
    branch = _branch(branch_ref[len("refs/heads/") :])
    head = _oid(row.get("HEAD"))
    gitfile = canonical / ".git"
    raw = _read_path_nofollow(gitfile, 4096).decode("utf-8")
    prefix = "gitdir: "
    if not raw.startswith(prefix) or not raw.endswith("\n"):
        raise InvalidLease("worktree gitfile invalid")
    admin = _canonical(Path(raw[len(prefix) : -1]))
    if admin == identity.common_dir or not path_is_within(admin, identity.common_dir / "worktrees"):
        raise InvalidLease("worktree admin directory invalid")
    _require_regular_directory(admin)
    backpointer = admin / "gitdir"
    target_text = _read_path_nofollow(backpointer, 4096).decode("utf-8").strip()
    target = _canonical(Path(target_text))
    if target != gitfile:
        raise InvalidLease("worktree backpointer mismatch")
    actual_branch = _git(canonical, "symbolic-ref", "--quiet", "--short", "HEAD").strip()
    actual_head = _git(canonical, "rev-parse", "--verify", "HEAD").strip()
    if actual_branch != branch or actual_head != head:
        raise InvalidLease("worktree state changed")
    info = canonical.lstat()
    return WorktreeBinding(
        path=canonical,
        device=info.st_dev,
        inode=info.st_ino,
        branch=branch,
        head=_oid(head),
        gitfile=gitfile,
        admin_dir=admin,
        backpointer=backpointer,
        nonce_path=admin / "factory-lease",
        common_dir=identity.common_dir,
    )


def path_is_within(child: Path, parent: Path) -> bool:
    child_name = str(_canonical(child, strict=False))
    parent_name = str(_canonical(parent, strict=False))
    return child_name == parent_name or child_name.startswith(
        parent_name.rstrip(os.sep) + os.sep
    )


def process_start(pid: int) -> Optional[str]:
    """Read one process start in the C locale without using signals."""

    if type(pid) is not int or pid <= 0:
        return None
    try:
        completed = subprocess.run(
            ["ps", "-o", "lstart=", "-p", str(pid)],
            capture_output=True,
            text=True,
            timeout=10,
            env=_clean_environment(),
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if completed.returncode != 0:
        return None
    value = completed.stdout.strip()
    return value[:200] if value else None


def _holder(pid: int) -> Optional[Dict[str, Any]]:
    start = process_start(pid)
    if start is None:
        return None
    return {"pid": pid, "start": start}


def _expect_keys(value: Any, keys: Iterable[str], label: str) -> Mapping[str, Any]:
    if not isinstance(value, dict) or set(value) != set(keys):
        raise InvalidLease(label)
    return value


def validate_repository(value: Any, identity: Optional[RepositoryIdentity] = None) -> Mapping[str, Any]:
    repo = _expect_keys(value, ("common_dir", "root_commit"), "invalid repository")
    common = _bounded_text(repo["common_dir"], 4096)
    if Path(common) != _canonical(Path(common), strict=False):
        raise InvalidLease("noncanonical repository")
    root = _oid(repo["root_commit"])
    if identity is not None:
        if common != str(identity.common_dir) or root != identity.root_commit:
            raise InvalidLease("repository identity mismatch")
    return {"common_dir": common, "root_commit": root}


def _validate_holder(value: Any) -> Optional[Dict[str, Any]]:
    if value is None:
        return None
    holder = _expect_keys(value, ("pid", "start"), "invalid holder")
    return {
        "pid": _positive_integer(holder["pid"]),
        "start": _bounded_text(holder["start"], 200),
    }


def _validate_release(value: Any, state: str, renewed: int, now: int) -> Optional[Dict[str, Any]]:
    if state == "active":
        if value is not None:
            raise InvalidLease("active lease has release")
        return None
    release = _expect_keys(value, ("at", "reason", "merged"), "invalid release")
    at = _integer(release["at"])
    reason = _bounded_text(release["reason"], 16)
    if reason not in RELEASE_REASONS or renewed > at or at > now:
        raise InvalidLease("invalid release")
    if reason == "merged":
        merged = _expect_keys(
            release["merged"],
            (
                "repository",
                "target",
                "branch",
                "pull_request",
                "head_oid",
                "local_tip",
                "generation",
            ),
            "invalid merge evidence",
        )
        result_merged = {
            "repository": _bounded_text(merged["repository"], 200),
            "target": _branch(merged["target"]),
            "branch": _branch(merged["branch"]),
            "pull_request": _positive_integer(merged["pull_request"]),
            "head_oid": _oid(merged["head_oid"]),
            "local_tip": _oid(merged["local_tip"]),
            "generation": _positive_integer(merged["generation"]),
        }
    else:
        if release["merged"] is not None:
            raise InvalidLease("unexpected merge evidence")
        result_merged = None
    return {"at": at, "reason": reason, "merged": result_merged}


def _validate_subject(resource_class: str, value: Any) -> Dict[str, Any]:
    if resource_class == "worktree":
        subject = _expect_keys(
            value,
            (
                "path",
                "device",
                "inode",
                "branch",
                "head",
                "gitfile",
                "admin_dir",
                "backpointer",
                "nonce_path",
                "branch_lease_id",
                "branch_created",
            ),
            "invalid worktree subject",
        )
        path = _bounded_text(subject["path"], 4096)
        if Path(path) != _canonical(Path(path), strict=False):
            raise InvalidLease("noncanonical worktree path")
        if not isinstance(subject["branch_created"], bool):
            raise InvalidLease("invalid branch claim")
        return {
            "path": path,
            "device": _integer(subject["device"]),
            "inode": _integer(subject["inode"]),
            "branch": _branch(subject["branch"]),
            "head": _oid(subject["head"]),
            "gitfile": _bounded_text(subject["gitfile"], 4096),
            "admin_dir": _bounded_text(subject["admin_dir"], 4096),
            "backpointer": _bounded_text(subject["backpointer"], 4096),
            "nonce_path": _bounded_text(subject["nonce_path"], 4096),
            "branch_lease_id": (
                None
                if subject["branch_lease_id"] is None
                else _lease_id(subject["branch_lease_id"])
            ),
            "branch_created": subject["branch_created"],
        }
    if resource_class == "branch":
        subject = _expect_keys(
            value, ("name", "ref", "head", "parent_lease_id", "parent_generation"), "invalid branch subject"
        )
        ref = _bounded_text(subject["ref"], 300)
        if not ref.startswith("refs/heads/") or _branch(ref[len("refs/heads/") :]) != subject["name"]:
            raise InvalidLease("invalid branch reference")
        return {
            "name": _branch(subject["name"]),
            "ref": ref,
            "head": _oid(subject["head"]),
            "parent_lease_id": _lease_id(subject["parent_lease_id"]),
            "parent_generation": _positive_integer(subject["parent_generation"]),
        }
    if resource_class == "run_marker":
        subject = _expect_keys(
            value,
            ("parent_lease_id", "parent_generation", "path", "label", "nonce"),
            "invalid marker subject",
        )
        label = _bounded_text(subject["label"], 128)
        if not LABEL_PATTERN.fullmatch(label):
            raise InvalidLease("invalid marker label")
        path = _bounded_text(subject["path"], 4096)
        if Path(path) != _canonical(Path(path), strict=False):
            raise InvalidLease("noncanonical marker path")
        return {
            "parent_lease_id": _lease_id(subject["parent_lease_id"]),
            "parent_generation": _positive_integer(subject["parent_generation"]),
            "path": path,
            "label": label,
            "nonce": _lease_id(subject["nonce"]),
        }
    raise InvalidLease("invalid resource class")


def validate_record(
    value: Any,
    now: Optional[int] = None,
    identity: Optional[RepositoryIdentity] = None,
) -> Dict[str, Any]:
    """Validate the exact v1 schema and return normalized private record data."""

    timestamp = int(time.time()) if now is None else now
    if type(timestamp) is not int:
        timestamp = int(timestamp)
    record = _expect_keys(
        value,
        (
            "v",
            "lease_id",
            "generation",
            "class",
            "repo",
            "subject",
            "creator",
            "task",
            "thread",
            "holder",
            "created",
            "renewed",
            "expires",
            "state",
            "release",
        ),
        "invalid lease schema",
    )
    if type(record["v"]) is not int or record["v"] != SCHEMA_VERSION:
        raise InvalidLease("invalid lease schema")
    resource_class = _bounded_text(record["class"], 32)
    if resource_class not in RESOURCE_CLASSES:
        raise InvalidLease("invalid resource class")
    created = _integer(record["created"])
    renewed = _integer(record["renewed"])
    expires = _integer(record["expires"])
    if created > renewed or renewed > timestamp or expires != renewed + LEASE_TTL_SECONDS:
        raise InvalidLease("invalid lease time")
    creator = _bounded_text(record["creator"], 32)
    if creator not in CREATORS:
        raise InvalidLease("invalid creator")
    state = _bounded_text(record["state"], 16)
    if state not in ("active", "released"):
        raise InvalidLease("invalid lease state")
    generation = _positive_integer(record["generation"])
    return {
        "v": SCHEMA_VERSION,
        "lease_id": _lease_id(record["lease_id"]),
        "generation": generation,
        "class": resource_class,
        "repo": dict(validate_repository(record["repo"], identity)),
        "subject": _validate_subject(resource_class, record["subject"]),
        "creator": creator,
        "task": _nullable_text(record["task"], 128),
        "thread": _nullable_text(record["thread"], 128),
        "holder": _validate_holder(record["holder"]),
        "created": created,
        "renewed": renewed,
        "expires": expires,
        "state": state,
        "release": _validate_release(record["release"], state, renewed, timestamp),
    }


class LeaseStore:
    """A repository-bound lease store with a single common writer lock."""

    def __init__(
        self,
        identity: RepositoryIdentity,
        now: Optional[int] = None,
        pr_provider: Optional[PullRequestProvider] = None,
        store_root: Optional[Path] = None,
    ) -> None:
        self.identity = identity
        self.root = (
            _canonical(store_root, strict=False)
            if store_root is not None
            else identity.common_dir / "factory"
        )
        self._now = now
        self.pr_provider = pr_provider

    @classmethod
    def for_repo(cls, repo: Path, **values: Any) -> "LeaseStore":
        return cls(discover_repository(repo), **values)

    def now(self) -> int:
        return int(time.time()) if self._now is None else int(self._now)

    def _factory(self, create: bool = False) -> int:
        if self.root.is_symlink():
            raise InvalidLease("lease store is linked")
        if create:
            factory_fd = _open_directory(self.root, True)
            os.fchmod(factory_fd, 0o700)
        else:
            try:
                factory_fd = _open_directory(self.root)
            except OSError as error:
                raise InvalidLease("lease store unavailable") from error
        if stat.S_IMODE(os.fstat(factory_fd).st_mode) != 0o700:
            os.close(factory_fd)
            raise InvalidLease("lease store mode is invalid")
        return factory_fd

    def exists(self) -> bool:
        try:
            descriptor = _open_directory(self.root)
        except OSError:
            return False
        os.close(descriptor)
        return True

    @contextmanager
    def writer_lock(self) -> Iterator[None]:
        factory_fd = self._factory(True)
        lock_dir = None
        lock = None
        try:
            leases_fd = _open_child_directory(factory_fd, "leases", True)
            for resource_class in RESOURCE_CLASSES:
                class_fd = _open_child_directory(leases_fd, resource_class, True)
                os.close(class_fd)
            os.close(leases_fd)
            lock_dir = _open_child_directory(factory_fd, "locks", True)
            lock = os.open(
                "writer.lock",
                os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW,
                0o600,
                dir_fd=lock_dir,
            )
            os.fchmod(lock, 0o600)
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise LockBusy("lease writer busy") from error
            yield
        finally:
            if lock is not None:
                try:
                    fcntl.flock(lock, fcntl.LOCK_UN)
                except OSError:
                    pass
                os.close(lock)
            if lock_dir is not None:
                os.close(lock_dir)
            os.close(factory_fd)

    def _record_file(self, resource_class: str, lease_id: str) -> Path:
        return self.root / "leases" / resource_class / (lease_id + ".json")

    def _read_all(self) -> Tuple[Sequence[Dict[str, Any]], int]:
        if not self.exists():
            return (), 0
        factory_fd = self._factory()
        leases_fd = None
        found: List[Dict[str, Any]] = []
        invalid = 0
        try:
            leases_fd = _open_child_directory(factory_fd, "leases")
            for resource_class in sorted(RESOURCE_CLASSES):
                try:
                    class_fd = _open_child_directory(leases_fd, resource_class)
                except OSError:
                    continue
                try:
                    names = sorted(os.listdir(class_fd))
                    for name in names:
                        if not LEASE_ID_PATTERN.fullmatch(name[:-5] if name.endswith(".json") else ""):
                            invalid += 1
                            continue
                        descriptor = None
                        try:
                            descriptor = os.open(
                                name,
                                os.O_RDONLY | os.O_NOFOLLOW,
                                dir_fd=class_fd,
                            )
                            info = os.fstat(descriptor)
                            if (
                                not stat.S_ISREG(info.st_mode)
                                or info.st_size > MAX_RECORD_BYTES
                                or stat.S_IMODE(info.st_mode) != 0o600
                            ):
                                raise InvalidLease("invalid lease file")
                            raw = os.read(descriptor, MAX_RECORD_BYTES + 1)
                            if len(raw) > MAX_RECORD_BYTES:
                                raise InvalidLease("lease record too large")
                            value = strict_json_loads(raw.decode("utf-8"))
                            record = validate_record(value, self.now(), self.identity)
                            if record["class"] != resource_class or name != record["lease_id"] + ".json":
                                raise InvalidLease("lease class mismatch")
                            found.append(record)
                        except (OSError, ValueError, UnicodeError, InvalidLease):
                            invalid += 1
                        finally:
                            if descriptor is not None:
                                os.close(descriptor)
                finally:
                    os.close(class_fd)
        except OSError as error:
            raise InvalidLease("lease store unreadable") from error
        finally:
            if leases_fd is not None:
                os.close(leases_fd)
            os.close(factory_fd)
        return tuple(found), invalid

    def read_records(self) -> Tuple[Sequence[Dict[str, Any]], int]:
        """Read validated records without creating state or acquiring a writer lock."""

        return self._read_all()

    def _write_record(self, record: Mapping[str, Any]) -> None:
        validated = validate_record(record, self.now(), self.identity)
        data = canonical_bytes(validated)
        destination = self._record_file(str(validated["class"]), str(validated["lease_id"]))
        parent_fd = _open_directory(destination.parent)
        temporary = ".tmp-" + secrets.token_hex(16)
        descriptor = None
        try:
            descriptor = os.open(
                temporary,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
                dir_fd=parent_fd,
            )
            os.fchmod(descriptor, 0o600)
            view = memoryview(data)
            while view:
                written = os.write(descriptor, view)
                view = view[written:]
            os.fsync(descriptor)
            os.close(descriptor)
            descriptor = None
            os.replace(
                temporary,
                destination.name,
                src_dir_fd=parent_fd,
                dst_dir_fd=parent_fd,
            )
            os.fsync(parent_fd)
        finally:
            if descriptor is not None:
                os.close(descriptor)
            try:
                os.unlink(temporary, dir_fd=parent_fd)
            except FileNotFoundError:
                pass
            os.close(parent_fd)

    def _remove_record(self, resource_class: str, lease_id: str) -> None:
        path = self._record_file(resource_class, lease_id)
        parent_fd = _open_directory(path.parent)
        try:
            try:
                os.unlink(path.name, dir_fd=parent_fd)
                os.fsync(parent_fd)
            except FileNotFoundError:
                pass
        finally:
            os.close(parent_fd)

    def _write_nonce(self, path: Path, lease_id: str) -> None:
        parent_fd = _open_directory(path.parent)
        descriptor = None
        temporary = ".factory-lease-" + secrets.token_hex(16)
        try:
            descriptor = os.open(
                temporary,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                0o600,
                dir_fd=parent_fd,
            )
            os.fchmod(descriptor, 0o600)
            data = (lease_id + "\n").encode("ascii")
            view = memoryview(data)
            while view:
                view = view[os.write(descriptor, view) :]
            os.fsync(descriptor)
            os.close(descriptor)
            descriptor = None
            os.link(
                temporary,
                path.name,
                src_dir_fd=parent_fd,
                dst_dir_fd=parent_fd,
                follow_symlinks=False,
            )
            os.fsync(parent_fd)
        finally:
            if descriptor is not None:
                os.close(descriptor)
            try:
                os.unlink(temporary, dir_fd=parent_fd)
            except FileNotFoundError:
                pass
            os.close(parent_fd)

    def _remove_nonce(self, binding: WorktreeBinding, expected: str) -> None:
        parent_fd = _open_directory(binding.admin_dir)
        try:
            try:
                raw = _read_path_nofollow(
                    binding.nonce_path, 64, 0o600
                ).decode("ascii").strip()
                if raw == expected:
                    os.unlink(binding.nonce_path.name, dir_fd=parent_fd)
                    os.fsync(parent_fd)
            except (OSError, UnicodeError, InvalidLease):
                pass
        finally:
            os.close(parent_fd)

    def _base_record(
        self,
        resource_class: str,
        subject: Mapping[str, Any],
        creator: str,
        task: Optional[str],
        thread: Optional[str],
        holder: Optional[Dict[str, Any]],
    ) -> Dict[str, Any]:
        now = self.now()
        record = {
            "v": SCHEMA_VERSION,
            "lease_id": secrets.token_hex(16),
            "generation": 1,
            "class": resource_class,
            "repo": self.identity.as_json(),
            "subject": dict(subject),
            "creator": _bounded_text(creator, 32),
            "task": _nullable_text(task, 128),
            "thread": _nullable_text(thread, 128),
            "holder": holder,
            "created": now,
            "renewed": now,
            "expires": now + LEASE_TTL_SECONDS,
            "state": "active",
            "release": None,
        }
        validate_record(record, now, self.identity)
        return record

    def _matching(
        self,
        records: Sequence[Dict[str, Any]],
        resource_class: str,
        predicate: Any,
    ) -> Dict[str, Any]:
        found = [record for record in records if record["class"] == resource_class and predicate(record)]
        if len(found) != 1:
            raise InvalidLease("lease identity ambiguous")
        return found[0]

    def create_worktree(
        self,
        path: Path,
        creator: str,
        task: Optional[str] = None,
        thread: Optional[str] = None,
        holder_pid: Optional[int] = None,
        branch_created: Optional[str] = None,
    ) -> Tuple[str, Optional[str]]:
        """Create one worktree lease and, only when requested, its new branch lease."""

        binding = inspect_worktree(path, self.identity)
        if branch_created is not None and branch_created != binding.branch:
            raise InvalidLease("created branch mismatch")
        holder = _holder(holder_pid) if holder_pid is not None else None
        if holder_pid is not None and holder is None:
            raise InvalidLease("holder identity unavailable")
        with self.writer_lock():
            records, _invalid = self._read_all()
            try:
                self._matching(
                    records,
                    "worktree",
                    lambda record: record["subject"]["path"] == str(binding.path),
                )
            except InvalidLease:
                existing = [
                    record
                    for record in records
                    if record["class"] == "worktree"
                    and record["subject"]["path"] == str(binding.path)
                ]
                if existing:
                    raise
            if binding.nonce_path.exists() or binding.nonce_path.is_symlink():
                raise InvalidLease("worktree nonce already exists")
            worktree = self._base_record(
                "worktree",
                binding.as_subject(),
                creator,
                task,
                thread,
                holder,
            )
            branch: Optional[Dict[str, Any]] = None
            if branch_created is not None:
                branch = self._base_record(
                    "branch",
                    {
                        "name": binding.branch,
                        "ref": "refs/heads/" + binding.branch,
                        "head": binding.head,
                        "parent_lease_id": worktree["lease_id"],
                        "parent_generation": 1,
                    },
                    creator,
                    task,
                    thread,
                    holder,
                )
                worktree["subject"]["branch_created"] = True
                worktree["subject"]["branch_lease_id"] = branch["lease_id"]
            written: List[Tuple[str, str]] = []
            try:
                self._write_record(worktree)
                written.append(("worktree", worktree["lease_id"]))
                if branch is not None:
                    self._write_record(branch)
                    written.append(("branch", branch["lease_id"]))
                self._write_nonce(binding.nonce_path, worktree["lease_id"])
            except Exception:
                self._remove_nonce(binding, worktree["lease_id"])
                for resource_class, lease_id in reversed(written):
                    self._remove_record(resource_class, lease_id)
                raise
            return worktree["lease_id"], branch["lease_id"] if branch is not None else None

    def renew_worktree(
        self,
        path: Path,
        expected_branch: Optional[str] = None,
        holder_pid: Optional[int] = None,
    ) -> str:
        """Renew one matching generation and branch, never adopting a missing lease."""

        binding = inspect_worktree(path, self.identity)
        if expected_branch is not None and binding.branch != expected_branch:
            raise InvalidLease("worktree branch mismatch")
        holder = _holder(holder_pid) if holder_pid is not None else None
        with self.writer_lock():
            records, _invalid = self._read_all()
            worktree = self._matching(
                records,
                "worktree",
                lambda record: record["subject"]["path"] == str(binding.path),
            )
            if worktree["subject"]["branch"] != binding.branch:
                raise InvalidLease("worktree branch mismatch")
            nonce = _read_path_nofollow(
                binding.nonce_path, 64, 0o600
            ).decode("ascii").strip()
            if nonce != worktree["lease_id"] or not self._subject_matches_binding(worktree, binding):
                raise InvalidLease("worktree nonce mismatch")
            old_worktree = worktree
            old_branch = None
            worktree = self._renewed_record(worktree, binding)
            branch_id = worktree["subject"]["branch_lease_id"]
            branch = None
            if branch_id is not None:
                old_branch = self._matching(
                    records,
                    "branch",
                    lambda record: record["lease_id"] == branch_id,
                )
                branch_subject = old_branch["subject"]
                if (
                    branch_subject["name"] != binding.branch
                    or branch_subject["parent_lease_id"] != old_worktree["lease_id"]
                    or branch_subject["parent_generation"] != old_worktree["generation"]
                ):
                    raise InvalidLease("branch parent mismatch")
                branch = self._renewed_record(old_branch, binding)
                branch["subject"]["head"] = binding.head
                branch["subject"]["parent_generation"] = worktree["generation"]
            if holder is not None:
                worktree["holder"] = holder
                if branch is not None:
                    branch["holder"] = holder
            try:
                if branch is not None:
                    self._write_record(branch)
                self._write_record(worktree)
            except Exception:
                self._write_record(old_worktree)
                if old_branch is not None:
                    self._write_record(old_branch)
                raise
            return str(worktree["lease_id"])

    def _subject_matches_binding(
        self, record: Mapping[str, Any], binding: WorktreeBinding
    ) -> bool:
        subject = record["subject"]
        return (
            subject["device"] == binding.device
            and subject["inode"] == binding.inode
            and subject["branch"] == binding.branch
            and subject["gitfile"] == str(binding.gitfile)
            and subject["admin_dir"] == str(binding.admin_dir)
            and subject["backpointer"] == str(binding.backpointer)
            and subject["nonce_path"] == str(binding.nonce_path)
        )

    def _renewed_record(
        self, record: Mapping[str, Any], binding: Optional[WorktreeBinding] = None
    ) -> Dict[str, Any]:
        updated = dict(record)
        updated["subject"] = dict(record["subject"])
        now = self.now()
        updated["generation"] = record["generation"] + 1
        updated["renewed"] = now
        updated["expires"] = now + LEASE_TTL_SECONDS
        updated["state"] = "active"
        updated["release"] = None
        if binding is not None and updated["class"] == "worktree":
            updated["subject"]["head"] = binding.head
        validate_record(updated, now, self.identity)
        return updated

    def begin_run(
        self,
        worktree: Path,
        marker: Path,
        label: str,
        holder_pid: int,
    ) -> Optional[str]:
        """Renew a leased worktree and create a per-run marker lease."""

        if not self.exists():
            return None
        marker = _canonical(marker, strict=False)
        worktree = _canonical(worktree)
        if marker != worktree / "build" / "runs" / (label + ".running"):
            return None
        if not LABEL_PATTERN.fullmatch(label):
            return None
        try:
            binding = inspect_worktree(worktree, self.identity)
        except LeaseError:
            return None
        holder = _holder(holder_pid)
        if holder is None:
            return None
        try:
            with self.writer_lock():
                records, _invalid = self._read_all()
                parent = self._matching(
                    records,
                    "worktree",
                    lambda record: record["subject"]["path"] == str(binding.path),
                )
                nonce = _read_path_nofollow(
                    binding.nonce_path, 64, 0o600
                ).decode("ascii").strip()
                if nonce != parent["lease_id"] or not self._subject_matches_binding(parent, binding):
                    raise InvalidLease("parent lease unavailable")
                if parent["subject"]["branch"] != binding.branch:
                    raise InvalidLease("parent branch mismatch")
                renewed = self._renewed_record(parent, binding)
                renewed["holder"] = holder
                old_branch = None
                renewed_branch = None
                branch_id = renewed["subject"]["branch_lease_id"]
                if branch_id is not None:
                    old_branch = self._matching(
                        records,
                        "branch",
                        lambda record: record["lease_id"] == branch_id,
                    )
                    if (
                        old_branch["subject"]["parent_lease_id"]
                        != parent["lease_id"]
                        or old_branch["subject"]["parent_generation"]
                        != parent["generation"]
                    ):
                        raise InvalidLease("branch parent mismatch")
                    renewed_branch = self._renewed_record(old_branch, binding)
                    renewed_branch["subject"]["head"] = binding.head
                    renewed_branch["subject"]["parent_generation"] = renewed[
                        "generation"
                    ]
                    renewed_branch["holder"] = holder
                run = self._base_record(
                    "run_marker",
                    {
                        "parent_lease_id": parent["lease_id"],
                        "parent_generation": renewed["generation"],
                        "path": str(marker),
                        "label": label,
                        "nonce": secrets.token_hex(16),
                    },
                    "bg_run",
                    parent["task"],
                    parent["thread"],
                    holder,
                )
                run["lease_id"] = run["subject"]["nonce"]
                run = validate_record(run, self.now(), self.identity)
                try:
                    if renewed_branch is not None:
                        self._write_record(renewed_branch)
                    self._write_record(renewed)
                    self._write_record(run)
                except Exception:
                    self._write_record(parent)
                    if old_branch is not None:
                        self._write_record(old_branch)
                    self._remove_record("run_marker", run["lease_id"])
                    raise
                return str(run["lease_id"])
        except (LeaseError, OSError, UnicodeError):
            return None

    def release(
        self,
        lease_id: str,
        reason: str,
        resource_class: Optional[str] = None,
    ) -> bool:
        """Release one active lease without inventing merge evidence."""

        _lease_id(lease_id)
        if reason not in ("ended", "abandoned"):
            raise LeaseError("invalid release reason")
        with self.writer_lock():
            records, _invalid = self._read_all()
            choices = [
                record
                for record in records
                if record["lease_id"] == lease_id
                and (resource_class is None or record["class"] == resource_class)
            ]
            if len(choices) != 1:
                raise InvalidLease("lease identity ambiguous")
            record = dict(choices[0])
            if record["state"] != "active":
                raise InvalidLease("lease is already released")
            now = self.now()
            if record["renewed"] > now:
                raise InvalidLease("lease time unavailable")
            record["state"] = "released"
            record["release"] = {"at": now, "reason": reason, "merged": None}
            self._write_record(record)
            return True

    def _repository_slug(self) -> str:
        # The common directory belongs to one checkout; inspect its primary tree.
        repo = self.identity.common_dir.parent
        remote = _git(repo, "remote", "get-url", "origin").strip()
        match = re.search(r"github\.com[:/]+([^/]+/[^/]+?)(?:\.git)?$", remote)
        if not match:
            raise LeaseError("repository identity unavailable")
        return match.group(1)

    def reconcile(
        self,
        lease_id: str,
        target: str = "main",
        resource_class: Optional[str] = None,
        provider: Optional[PullRequestProvider] = None,
    ) -> bool:
        """Attest one current generation from a unique same-repository merged PR."""

        _lease_id(lease_id)
        target_name = _branch(target)
        source = provider or self.pr_provider or GhPullRequestProvider()
        with self.writer_lock():
            records, _invalid = self._read_all()
            selected = [
                record
                for record in records
                if record["lease_id"] == lease_id
                and (resource_class is None or record["class"] == resource_class)
            ]
            if len(selected) != 1:
                raise InvalidLease("lease identity ambiguous")
            record = selected[0]
            if record["class"] not in ("worktree", "branch"):
                raise InvalidLease("merge subject unavailable")
            branch_record = record
            worktree_record = None
            if record["class"] == "worktree":
                branch_id = record["subject"]["branch_lease_id"]
                if branch_id is None:
                    raise InvalidLease("branch creation not attested")
                found = [
                    value for value in records
                    if value["class"] == "branch" and value["lease_id"] == branch_id
                ]
                if len(found) != 1:
                    raise InvalidLease("branch lease unavailable")
                branch_record = found[0]
                worktree_record = record
            elif record["class"] == "branch":
                found = [
                    value
                    for value in records
                    if value["class"] == "worktree"
                    and value["lease_id"] == branch_record["subject"]["parent_lease_id"]
                ]
                if len(found) != 1:
                    raise InvalidLease("parent lease unavailable")
                worktree_record = found[0]
            assert worktree_record is not None
            binding = inspect_worktree(Path(worktree_record["subject"]["path"]), self.identity)
            if (
                not self._subject_matches_binding(worktree_record, binding)
                or binding.branch != branch_record["subject"]["name"]
                or binding.head != worktree_record["subject"]["head"]
                or binding.head != branch_record["subject"]["head"]
                or branch_record["subject"]["parent_generation"] != worktree_record["generation"]
                or branch_record["subject"]["parent_lease_id"] != worktree_record["lease_id"]
            ):
                raise InvalidLease("lease generation changed")
            nonce = _read_path_nofollow(
                binding.nonce_path, 64, 0o600
            ).decode("ascii").strip()
            if nonce != worktree_record["lease_id"]:
                raise InvalidLease("worktree nonce mismatch")
            repository = getattr(source, "repository", None) or self._repository_slug()
            repository = _bounded_text(repository, 200)
            evidence = tuple(source.list_for_branch(repository, binding.branch))
            if any(item.state == "OPEN" for item in evidence):
                raise InvalidLease("open pull request successor")
            candidates = []
            for item in evidence:
                if (
                    item.repository == repository
                    and item.base == target_name
                    and item.branch == binding.branch
                    and item.state == "MERGED"
                    and (item.created_at is None or item.created_at >= worktree_record["created"])
                    and self._oid_is_contained(binding.head, item.head_oid)
                ):
                    candidates.append(item)
            if len(candidates) != 1:
                raise InvalidLease("pull request evidence ambiguous")
            pull = candidates[0]
            now = self.now()
            merged = {
                "repository": repository,
                "target": target_name,
                "branch": binding.branch,
                "pull_request": pull.number,
                "head_oid": pull.head_oid,
                "local_tip": binding.head,
                "generation": worktree_record["generation"],
            }
            release = {"at": now, "reason": "merged", "merged": merged}
            updated_branch = dict(branch_record)
            updated_branch["state"] = "released"
            updated_branch["release"] = release
            updated_worktree = dict(worktree_record)
            updated_worktree["state"] = "released"
            updated_worktree["release"] = release
            try:
                self._write_record(updated_branch)
                self._write_record(updated_worktree)
            except Exception:
                self._write_record(worktree_record)
                self._write_record(branch_record)
                raise
            return True

    def _oid_is_contained(self, local_tip: str, merged_head: str) -> bool:
        if local_tip == merged_head:
            return True
        repo = self.identity.common_dir.parent
        completed = subprocess.run(
            [
                "git",
                "-C",
                str(repo),
                "merge-base",
                "--is-ancestor",
                local_tip,
                merged_head,
            ],
            capture_output=True,
            env=_clean_environment(),
            timeout=60,
        )
        if completed.returncode not in (0, 1):
            raise LeaseError("merge identity unavailable")
        return completed.returncode == 0

    def adopt_worktree(
        self,
        path: Path,
        evidence: Mapping[str, Any],
        task: Optional[str] = None,
        thread: Optional[str] = None,
    ) -> str:
        """Fixture-only adoption, gated by exact reviewed creation evidence."""

        binding = inspect_worktree(path, self.identity)
        expected = _expect_keys(
            evidence,
            ("reviewed", "repo", "path", "branch", "head", "generation", "creation"),
            "invalid adoption evidence",
        )
        validate_repository(expected["repo"], self.identity)
        if (
            expected["reviewed"] is not True
            or expected["path"] != str(binding.path)
            or expected["branch"] != binding.branch
            or expected["head"] != binding.head
            or _positive_integer(expected["generation"]) != 1
            or expected["creation"] not in ("fixture", "reviewed-list")
        ):
            raise InvalidLease("adoption evidence mismatch")
        # Reuse the same transaction as create, with no branch ownership claim.
        return self.create_worktree(path, "adopt", task, thread, None, None)[0]

    def end_run(self, lease_id: str) -> bool:
        try:
            return self.release(lease_id, "ended", "run_marker")
        except (LeaseError, OSError):
            return False

    def abort_run(self, lease_id: str) -> bool:
        """Rollback a run lease that was never successfully linked to its marker."""

        try:
            _lease_id(lease_id)
            with self.writer_lock():
                records, _invalid = self._read_all()
                found = [
                    record
                    for record in records
                    if record["class"] == "run_marker"
                    and record["lease_id"] == lease_id
                    and record["state"] == "active"
                ]
                if len(found) != 1:
                    raise InvalidLease("run lease unavailable")
                self._remove_record("run_marker", lease_id)
            return True
        except (LeaseError, OSError):
            return False


def find_worktree_lease(
    records: Sequence[Mapping[str, Any]],
    path: Path,
) -> Optional[Mapping[str, Any]]:
    """Return a unique worktree lease candidate without treating it as validated."""

    found = [
        record
        for record in records
        if record["class"] == "worktree"
        and record["subject"]["path"] == str(_canonical(path, strict=False))
    ]
    return found[0] if len(found) == 1 else None


def lease_matches_worktree(
    record: Mapping[str, Any],
    path: Path,
    branch: str,
    head: str,
) -> bool:
    """Validate the on-disk nonce and Git-file backlink for a worktree record."""

    try:
        if record["class"] != "worktree":
            return False
        subject = record["subject"]
        canonical = _canonical(path)
        if str(canonical) != subject["path"] or branch != subject["branch"]:
            return False
        if path.is_symlink():
            return False
        info = canonical.lstat()
        if (
            not stat.S_ISDIR(info.st_mode)
            or info.st_dev != subject["device"]
            or info.st_ino != subject["inode"]
        ):
            return False
        gitfile = canonical / ".git"
        raw = _read_path_nofollow(gitfile, 4096).decode("utf-8")
        if not raw.startswith("gitdir: ") or not raw.endswith("\n"):
            return False
        admin = _canonical(Path(raw[len("gitdir: ") : -1]))
        nonce = _read_path_nofollow(
            Path(subject["nonce_path"]), 64, 0o600
        ).decode("ascii").strip()
        backpointer = _read_path_nofollow(Path(subject["backpointer"]), 4096).decode("utf-8").strip()
        merged = record.get("release") or {}
        merge_facts = merged.get("merged") if isinstance(merged, dict) else None
        if merge_facts is not None and (
            merge_facts["local_tip"] != head
            or merge_facts["branch"] != branch
            or merge_facts["generation"] != record["generation"]
        ):
            return False
        return (
            str(admin) == subject["admin_dir"]
            and str(gitfile) == subject["gitfile"]
            and _canonical(Path(backpointer)) == gitfile
            and nonce == record["lease_id"]
        )
    except (KeyError, OSError, ValueError, UnicodeError, LeaseError):
        return False


def load_for_repo(repo: Path, now: Optional[int] = None) -> Tuple[
    Optional[LeaseStore], Sequence[Dict[str, Any]], int
]:
    """Read-only lease lookup; a missing store is empty and never gets created."""

    try:
        identity = discover_repository(repo)
        store = LeaseStore(identity, now=now)
        records, invalid = store.read_records()
        return store, records, invalid
    except (LeaseError, OSError, UnicodeError):
        return None, (), 1


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Create and release private factory leases without cleanup authority."
    )
    commands = parser.add_subparsers(dest="operation", required=True)

    create = commands.add_parser("create")
    create.add_argument("--repo", type=Path, required=True)
    create.add_argument("--worktree", type=Path, required=True)
    create.add_argument("--creator", choices=CREATORS, default="lane_new")
    create.add_argument("--branch-created", default=None)
    create.add_argument("--task")
    create.add_argument("--thread")
    create.add_argument("--holder-pid", type=int)

    renew = commands.add_parser("renew")
    renew.add_argument("--repo", type=Path, required=True)
    renew.add_argument("--worktree", type=Path, required=True)
    renew.add_argument("--branch")
    renew.add_argument("--holder-pid", type=int)

    release = commands.add_parser("release")
    release.add_argument("--repo", type=Path, required=True)
    release.add_argument("--lease-id", required=True)
    release.add_argument("--class", dest="resource_class", choices=RESOURCE_CLASSES)
    release.add_argument("--reason", choices=("ended", "abandoned"), required=True)

    reconcile = commands.add_parser("reconcile")
    reconcile.add_argument("--repo", type=Path, required=True)
    reconcile.add_argument("--lease-id", required=True)
    reconcile.add_argument("--class", dest="resource_class", choices=RESOURCE_CLASSES)
    reconcile.add_argument("--target", default="main")

    adopt = commands.add_parser("adopt")
    adopt.add_argument("--repo", type=Path, required=True)
    adopt.add_argument("--worktree", type=Path, required=True)
    adopt.add_argument("--evidence", type=Path, required=True)
    adopt.add_argument("--task")
    adopt.add_argument("--thread")
    return parser


def main(arguments: Optional[Sequence[str]] = None) -> int:
    args = _parser().parse_args(arguments)
    try:
        store = LeaseStore.for_repo(args.repo)
        if args.operation == "create":
            store.create_worktree(
                args.worktree,
                args.creator,
                args.task,
                args.thread,
                args.holder_pid,
                args.branch_created,
            )
        elif args.operation == "renew":
            store.renew_worktree(args.worktree, args.branch, args.holder_pid)
        elif args.operation == "release":
            store.release(args.lease_id, args.reason, args.resource_class)
        elif args.operation == "reconcile":
            store.reconcile(args.lease_id, args.target, args.resource_class)
        elif args.operation == "adopt":
            evidence_bytes = _read_path_nofollow(args.evidence, MAX_RECORD_BYTES)
            evidence = strict_json_loads(evidence_bytes.decode("utf-8"))
            store.adopt_worktree(args.worktree, evidence, args.task, args.thread)
        else:
            raise LeaseError("unknown operation")
    except (LeaseError, OSError, UnicodeError, ValueError, TypeError):
        sys.stderr.write("factory lease operation failed\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
