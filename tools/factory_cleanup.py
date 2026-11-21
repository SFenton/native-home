#!/usr/bin/env python3
"""Plan and verify private, archive-only cleanup of factory worktrees.

This module deliberately has no removal mode.  Its only public operations are
``plan`` and digest-approved ``apply``.  A plan is private evidence, not
authority, and an applied plan leaves every subject and Git ref in place.

The archive is self-contained: it contains one Git bundle for the expected
tip, the linked worktree's exact index bytes, an enumerated working-tree
payload and a closed manifest.  Verification restores those products into a
fresh private repository without using source objects or alternates.  The
digest-keyed archive directory and its journal receipt are published together.

Only the factory plan, staging, archive and receipt areas below the verified
Git common directory receive writes.  Verification scratch is also private to
that store.  The disposable restore clone may receive Git's incidental local
configuration and index writes.  No subject, worktree administration, ref,
process or simulator mutation is performed here, and every Git child command
is read-bounded and allow-listed.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import os
import re
import secrets
import stat
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple

import factory
import factory_lease


SCHEMA_VERSION = 1
PLAN_LIFETIME_SECONDS = 24 * 60 * 60
MAX_PLAN_BYTES = 32 * 1024 * 1024
MAX_MANIFEST_BYTES = 16 * 1024 * 1024
MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
MAX_LEAF_BYTES = 128 * 1024 * 1024
MAX_ENTRIES = 100_000
MAX_COMMAND_OUTPUT_BYTES = 32 * 1024 * 1024
COMMAND_TIMEOUT_SECONDS = 60
DIGEST_PATTERN = re.compile(r"^[0-9a-f]{64}$")
OID_PATTERN = re.compile(r"^[0-9a-f]{40}$")
SELECTED_IGNORED = (
    b"build/evidence/",
    b"build/handoff/",
    b"build/research/",
    b"build/review/",
)

PLAN_KEYS = (
    "v",
    "action",
    "created",
    "repository",
    "workflow_base",
    "candidates",
    "hold_counts",
)
CANDIDATE_KEYS = (
    "action",
    "lease_id",
    "lease_generation",
    "branch_lease_id",
    "branch_generation",
    "expires",
    "binding",
    "release",
    "expected",
)
BINDING_KEYS = (
    "path",
    "device",
    "inode",
    "branch",
    "head",
    "gitfile",
    "admin_dir",
    "backpointer",
    "nonce_path",
    "common_dir",
)
RELEASE_KEYS = (
    "repository",
    "target",
    "branch",
    "pull_request",
    "head_oid",
    "local_tip",
    "generation",
)
EXPECTED_KEYS = (
    "head",
    "branch",
    "root_mode",
    "status",
    "index",
    "entries",
    "deletions",
)
RECEIPT_KEYS = ("v", "plan_digest", "created", "outcomes")


class CleanupError(RuntimeError):
    """A fixed, non-sensitive cleanup outcome."""

    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


@dataclass(frozen=True)
class ExternalObservation:
    """Complete offline ownership and activity facts for one linked worktree."""

    complete: bool
    t3_owned: bool = False
    thread_active: Optional[bool] = None
    devcap_active: bool = False


class ExternalProvider:
    """Injectable complete offline hold evidence."""

    def observe(
        self,
        repo: Path,
        path: Path,
        binding: factory_lease.WorktreeBinding,
        record: Mapping[str, Any],
    ) -> ExternalObservation:
        raise NotImplementedError


class UnknownExternalProvider(ExternalProvider):
    """Production fails closed until a complete offline source exists."""

    def observe(
        self,
        repo: Path,
        path: Path,
        binding: factory_lease.WorktreeBinding,
        record: Mapping[str, Any],
    ) -> ExternalObservation:
        return ExternalObservation(complete=False)


def _clock_value(value: Optional[Any]) -> int:
    if value is None:
        return int(time.time())
    result = value() if callable(value) else value
    if type(result) is not int or result < 0:
        raise CleanupError("clock_invalid")
    return result


@dataclass(frozen=True)
class PlanResult:
    digest: str
    plan_path: Path
    planned: int
    held: int
    unknown: int


@dataclass(frozen=True)
class ApplyResult:
    digest: str
    archived: int
    held: int
    replay: bool


def _fixed_environment() -> Dict[str, str]:
    environment = os.environ.copy()
    for key in tuple(environment):
        if key.startswith("GIT_") and key not in (
            "GIT_AUTHOR_NAME",
            "GIT_AUTHOR_EMAIL",
            "GIT_COMMITTER_NAME",
            "GIT_COMMITTER_EMAIL",
        ):
            environment.pop(key, None)
    environment.update(
        {
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_OPTIONAL_LOCKS": "0",
            "GIT_TERMINAL_PROMPT": "0",
            "LC_ALL": "C",
        }
    )
    return environment


def _run(
    command: Sequence[str],
    cwd: Optional[Path] = None,
    input_bytes: Optional[bytes] = None,
) -> subprocess.CompletedProcess:
    if not command or not all(isinstance(item, str) for item in command):
        raise CleanupError("command_invalid")
    if command[0] != "git":
        raise CleanupError("command_denied")
    args = tuple(command)
    if len(args) < 4 or args[1] != "-C":
        raise CleanupError("command_denied")
    subcommand = args[3]
    rest = args[4:]
    accepted = (
        (
            subcommand == "bundle"
            and bool(rest)
            and rest[0] in ("create", "verify")
        )
        or (subcommand == "check-ignore" and rest[:2] == ("-z", "--stdin"))
        or (
            subcommand == "checkout"
            and rest[:2] == ("-q", "--detach")
            and len(rest) == 3
        )
        or (
            subcommand == "clone"
            and rest[:2] == ("-q", "--no-hardlinks")
            and len(rest) == 4
        )
        or (
            subcommand == "cat-file"
            and rest[:1] == ("blob",)
            and len(rest) == 2
        )
        or (
            subcommand == "for-each-ref"
            and all(item not in ("--points-at",) for item in rest)
        )
        or (subcommand == "init" and rest == ("-q",))
        or (subcommand in ("ls-files", "status"))
        or (
            subcommand == "merge-base"
            and rest[:1] == ("--is-ancestor",)
            and len(rest) == 3
        )
        or (subcommand == "remote" and rest[:1] == ("get-url",))
        or (subcommand == "hash-object" and rest == ("-w", "--stdin"))
        or (subcommand in ("rev-parse", "rev-list", "symbolic-ref"))
        or (subcommand == "sparse-checkout" and rest[:1] == ("list",))
        or (subcommand == "worktree" and rest[:1] == ("list",))
    )
    if not accepted:
        raise CleanupError("command_denied")
    try:
        completed = subprocess.run(
            list(args),
            cwd=str(cwd) if cwd is not None else None,
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=COMMAND_TIMEOUT_SECONDS,
            env=_fixed_environment(),
            check=False,
        )
        if (
            len(completed.stdout or b"") > MAX_COMMAND_OUTPUT_BYTES
            or len(completed.stderr or b"") > MAX_COMMAND_OUTPUT_BYTES
        ):
            raise CleanupError("command_output_too_large")
        return completed
    except (OSError, subprocess.SubprocessError) as error:
        raise CleanupError("command_failed") from error


def _git(root: Path, *arguments: str, input_bytes: Optional[bytes] = None) -> bytes:
    completed = _run(
        ("git", "-C", str(root), *arguments), input_bytes=input_bytes
    )
    if completed.returncode != 0:
        raise CleanupError("git_read_failed")
    stdout = completed.stdout
    return stdout if isinstance(stdout, bytes) else stdout.encode("utf-8")


def _git_text(root: Path, *arguments: str) -> str:
    return _git(root, *arguments).decode("utf-8")


def _canonical_bytes(value: Any) -> bytes:
    return (
        json.dumps(
            value,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=True,
            allow_nan=False,
        )
        + "\n"
    ).encode("utf-8")


def _strict_pairs(pairs: Iterable[Tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise CleanupError("input_duplicate")
        result[key] = value
    return result


def _strict_json(raw: bytes, limit: int) -> Any:
    if len(raw) > limit:
        raise CleanupError("input_too_large")
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=_strict_pairs)
    except (UnicodeError, ValueError) as error:
        if isinstance(error, CleanupError):
            raise
        raise CleanupError("input_invalid") from error
    if _canonical_bytes(value) != raw:
        raise CleanupError("input_noncanonical")
    return value


def _integer(value: Any, label: str, minimum: int = 0) -> int:
    if type(value) is not int or value < minimum:
        raise CleanupError(label)
    return value


def _text(value: Any, limit: int, label: str) -> str:
    if not isinstance(value, str) or not value or len(value) > limit:
        raise CleanupError(label)
    return value


def _exact_keys(value: Any, keys: Sequence[str], label: str) -> Mapping[str, Any]:
    if not isinstance(value, dict) or set(value) != set(keys):
        raise CleanupError(label)
    return value


def _oid(value: Any) -> str:
    text = _text(value, 40, "input_oid")
    if not OID_PATTERN.fullmatch(text):
        raise CleanupError("input_oid")
    return text


def _digest(value: Any) -> str:
    text = _text(value, 64, "input_digest")
    if not DIGEST_PATTERN.fullmatch(text):
        raise CleanupError("input_digest")
    return text


def _lease_id(value: Any) -> str:
    text = _text(value, 32, "input_lease")
    if not re.fullmatch(r"[0-9a-f]{32}", text):
        raise CleanupError("input_lease")
    return text


def _path_text(value: Any) -> str:
    text = _text(value, 4096, "input_path")
    if not os.path.isabs(text) or os.path.normpath(text) != text:
        raise CleanupError("input_path")
    return text


def _encoded_path(value: Any) -> bytes:
    text = _text(value, 16384, "input_path")
    try:
        raw = base64.b64decode(text.encode("ascii"), validate=True)
    except (UnicodeError, binascii.Error) as error:
        raise CleanupError("input_path") from error
    if not raw or b"\0" in raw:
        raise CleanupError("input_path")
    components = raw.split(b"/")
    if any(component in (b"", b".", b"..") for component in components):
        raise CleanupError("input_path")
    return raw


def _path_component(value: str) -> str:
    if value in ("", ".", "..") or "/" in value or "\0" in value:
        raise CleanupError("archive_path")
    return value


def _read_all(descriptor: int, limit: int) -> bytes:
    chunks: List[bytes] = []
    total = 0
    while True:
        data = os.read(descriptor, min(65536, limit - total + 1))
        if not data:
            break
        chunks.append(data)
        total += len(data)
        if total > limit:
            raise CleanupError("input_too_large")
    return b"".join(chunks)


def _write_all(descriptor: int, data: bytes) -> None:
    view = memoryview(data)
    while view:
        written = os.write(descriptor, view)
        if written <= 0:
            raise CleanupError("archive_failed")
        view = view[written:]


def _fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _fsync_file(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _mkdir_private(path: Path) -> None:
    try:
        path.mkdir(mode=0o700)
    except FileExistsError:
        pass
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or path.is_symlink():
        raise CleanupError("store_unsafe")
    if stat.S_IMODE(info.st_mode) != 0o700:
        os.chmod(path, 0o700)
    _fsync_directory(path.parent)


def _assert_nonlinked_absolute(path: Path) -> None:
    if not path.is_absolute():
        raise CleanupError("store_unsafe")
    current = Path(path.anchor)
    for component in path.parts[1:]:
        current = current / component
        try:
            info = current.lstat()
        except OSError as error:
            raise CleanupError("path_changed") from error
        if stat.S_ISLNK(info.st_mode):
            raise CleanupError("path_changed")


def _verify_store(identity: factory_lease.RepositoryIdentity) -> None:
    root = identity.common_dir / "factory"
    _assert_nonlinked_absolute(identity.common_dir)
    try:
        info = root.lstat()
    except FileNotFoundError as error:
        raise CleanupError("store_unavailable") from error
    if root.is_symlink() or not stat.S_ISDIR(info.st_mode):
        raise CleanupError("store_unsafe")
    if stat.S_IMODE(info.st_mode) != 0o700:
        raise CleanupError("store_unsafe")
    for name in ("worktree", "branch", "run_marker"):
        child = root / "leases" / name
        try:
            child_info = child.lstat()
        except OSError as error:
            raise CleanupError("lease_store_incomplete") from error
        if child.is_symlink() or not stat.S_ISDIR(child_info.st_mode):
            raise CleanupError("store_unsafe")
        if stat.S_IMODE(child_info.st_mode) != 0o700:
            raise CleanupError("store_unsafe")


def _read_file_nofollow(path: Path, limit: int, mode: Optional[int] = None) -> bytes:
    descriptor = None
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode):
            raise CleanupError("input_not_regular")
        if mode is not None and stat.S_IMODE(info.st_mode) != mode:
            raise CleanupError("input_mode")
        return _read_all(descriptor, limit)
    except CleanupError:
        raise
    except OSError as error:
        raise CleanupError("input_unreadable") from error
    finally:
        if descriptor is not None:
            os.close(descriptor)


def _write_private_file(path: Path, data: bytes) -> None:
    descriptor = None
    temporary = path.parent / ("." + path.name + "-" + secrets.token_hex(8))
    try:
        descriptor = os.open(
            temporary,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
        )
        os.fchmod(descriptor, 0o600)
        _write_all(descriptor, data)
        os.fsync(descriptor)
        os.close(descriptor)
        descriptor = None
        os.link(temporary, path)
        os.unlink(temporary)
        _fsync_directory(path.parent)
    except FileExistsError as error:
        raise CleanupError("publication_exists") from error
    except CleanupError:
        raise
    except OSError as error:
        raise CleanupError("archive_failed") from error
    finally:
        if descriptor is not None:
            os.close(descriptor)
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def _remove_private_tree(path: Path) -> None:
    try:
        info = path.lstat()
    except FileNotFoundError:
        return
    if path.is_symlink() or not stat.S_ISDIR(info.st_mode):
        raise CleanupError("recovery_ambiguous")
    directory = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        names = sorted(os.listdir(directory))
        for name in names:
            _path_component(name)
            child_info = os.stat(name, dir_fd=directory, follow_symlinks=False)
            child = path / name
            if stat.S_ISDIR(child_info.st_mode):
                _remove_private_tree(child)
            else:
                os.unlink(name, dir_fd=directory)
    finally:
        os.close(directory)
    os.rmdir(path)
    _fsync_directory(path.parent)


class _ScopedReader:
    def __init__(
        self,
        reader: factory.GitReader,
        primary: factory.Worktree,
        target: factory.Worktree,
    ) -> None:
        self._reader = reader
        self._primary = primary
        self._target = target

    def __getattr__(self, name: str) -> Any:
        return getattr(self._reader, name)

    def worktrees(self) -> Tuple[factory.Worktree, factory.Worktree]:
        return self._primary, self._target


def _same_worktree(first: factory.Worktree, second: factory.Worktree) -> bool:
    return (
        Path(first.path).resolve() == Path(second.path).resolve()
        and first.head == second.head
        and first.branch == second.branch
        and first.locked == second.locked
    )


def _invocation_root(repo: Path) -> Path:
    output = _git_text(repo, "rev-parse", "--show-toplevel").strip()
    if not output:
        raise CleanupError("repository_unavailable")
    root = Path(output).resolve()
    _assert_nonlinked_absolute(root)
    return root


def _trusted_origin(repo: Path) -> str:
    output = _git_text(repo, "remote", "get-url", "origin").strip()
    match = re.search(
        r"(?:github\.com[:/])([^/]+/[^/]+?)(?:\.git)?$", output
    )
    if match is None:
        raise CleanupError("origin_unavailable")
    return match.group(1)


def _current_worktrees(reader: factory.GitReader) -> Tuple[factory.Worktree, ...]:
    values = reader.worktrees()
    if not values or len(values) > 10_000:
        raise CleanupError("inventory_incomplete")
    canonical = [str(Path(value.path).resolve()) for value in values]
    if len(canonical) != len(set(canonical)):
        raise CleanupError("inventory_ambiguous")
    return tuple(values)


def _primary_worktree(
    full: Sequence[factory.Worktree], identity: factory_lease.RepositoryIdentity
) -> factory.Worktree:
    expected = identity.common_dir.parent.resolve()
    found = tuple(
        tree for tree in full if Path(tree.path).resolve() == expected
    )
    if len(found) != 1:
        raise CleanupError("primary_ambiguous")
    return found[0]


def _unique_records(
    records: Sequence[Mapping[str, Any]],
    resource_class: str,
    binding: factory_lease.WorktreeBinding,
) -> Tuple[Mapping[str, Any], Mapping[str, Any]]:
    worktree_values = tuple(
        record
        for record in records
        if record["class"] == resource_class
        and record["subject"]["path"] == str(binding.path)
    )
    if len(worktree_values) != 1:
        raise CleanupError("lease_changed")
    worktree = worktree_values[0]
    branch_id = worktree["subject"]["branch_lease_id"]
    branch_values = tuple(
        record
        for record in records
        if record["class"] == "branch"
        and record["lease_id"] == branch_id
    )
    if len(branch_values) != 1:
        raise CleanupError("lease_changed")
    branch = branch_values[0]
    return worktree, branch


def _release_matches(
    worktree: Mapping[str, Any],
    branch: Mapping[str, Any],
    binding: factory_lease.WorktreeBinding,
    now: int,
) -> Mapping[str, Any]:
    if now < max(worktree["expires"], branch["expires"]):
        raise CleanupError("lease_live")
    if (
        worktree["state"] != "released"
        or branch["state"] != "released"
        or worktree["release"] != branch["release"]
    ):
        raise CleanupError("lease_unreleased")
    release = worktree["release"]
    if release is None or release["reason"] != "merged":
        raise CleanupError("lease_unattested")
    merged = release["merged"]
    if (
        branch["generation"] != worktree["generation"]
        or branch["subject"]["parent_lease_id"] != worktree["lease_id"]
        or branch["subject"]["parent_generation"] != worktree["generation"]
        or branch["subject"]["name"] != binding.branch
        or branch["subject"]["head"] != binding.head
        or worktree["generation"] != merged["generation"]
        or merged["branch"] != binding.branch
        or merged["local_tip"] != binding.head
    ):
        raise CleanupError("lease_changed")
    return merged


def _binding_json(binding: factory_lease.WorktreeBinding) -> Dict[str, Any]:
    return {
        "path": str(binding.path),
        "device": binding.device,
        "inode": binding.inode,
        "branch": binding.branch,
        "head": binding.head,
        "gitfile": str(binding.gitfile),
        "admin_dir": str(binding.admin_dir),
        "backpointer": str(binding.backpointer),
        "nonce_path": str(binding.nonce_path),
        "common_dir": str(binding.common_dir),
    }


def _validate_binding_json(value: Any) -> Dict[str, Any]:
    binding = _exact_keys(value, BINDING_KEYS, "input_binding")
    return {
        "path": _path_text(binding["path"]),
        "device": _integer(binding["device"], "input_binding"),
        "inode": _integer(binding["inode"], "input_binding"),
        "branch": _text(binding["branch"], 255, "input_binding"),
        "head": _oid(binding["head"]),
        "gitfile": _path_text(binding["gitfile"]),
        "admin_dir": _path_text(binding["admin_dir"]),
        "backpointer": _path_text(binding["backpointer"]),
        "nonce_path": _path_text(binding["nonce_path"]),
        "common_dir": _path_text(binding["common_dir"]),
    }


def _validate_release_json(value: Any) -> Dict[str, Any]:
    release = _exact_keys(value, RELEASE_KEYS, "input_release")
    return {
        "repository": _text(release["repository"], 200, "input_release"),
        "target": _text(release["target"], 255, "input_release"),
        "branch": _text(release["branch"], 255, "input_release"),
        "pull_request": _integer(
            release["pull_request"], "input_release", 1
        ),
        "head_oid": _oid(release["head_oid"]),
        "local_tip": _oid(release["local_tip"]),
        "generation": _integer(release["generation"], "input_release", 1),
    }


def _validate_entry(value: Any) -> Dict[str, Any]:
    entry = _exact_keys(
        value, ("path", "kind", "mode", "size", "sha256", "target"), "input_tree"
    )
    path = _encoded_path(entry["path"])
    kind = entry["kind"]
    if kind not in ("directory", "file", "link"):
        raise CleanupError("input_tree")
    mode = _integer(entry["mode"], "input_tree")
    if mode < 0 or mode > 0o7777:
        raise CleanupError("input_tree")
    size = _integer(entry["size"], "input_tree")
    digest = entry["sha256"]
    if digest is not None:
        _digest(digest)
    target = entry["target"]
    if target is not None and not isinstance(target, str):
        raise CleanupError("input_tree")
    if kind == "file" and (digest is None or target is not None):
        raise CleanupError("input_tree")
    if kind == "link" and (digest is not None or target is None):
        raise CleanupError("input_tree")
    if kind == "directory" and (digest is not None or target is not None or size != 0):
        raise CleanupError("input_tree")
    if b"/" not in path and os.fsdecode(path) == ".git":
        raise CleanupError("input_tree")
    return entry


def _validate_expected(value: Any) -> Dict[str, Any]:
    expected = _exact_keys(value, EXPECTED_KEYS, "input_expected")
    entries = expected["entries"]
    deletions = expected["deletions"]
    if not isinstance(entries, list) or len(entries) > MAX_ENTRIES:
        raise CleanupError("input_tree")
    normalized = []
    paths = set()
    for entry_value in entries:
        entry = _validate_entry(entry_value)
        if entry["path"] in paths:
            raise CleanupError("input_tree")
        paths.add(entry["path"])
        normalized.append(entry)
    if not isinstance(deletions, list):
        raise CleanupError("input_tree")
    for deleted in deletions:
        _encoded_path(deleted)
    index = _exact_keys(
        expected["index"], ("mode", "size", "sha256", "entries"), "input_index"
    )
    index_entries = index["entries"]
    if not isinstance(index_entries, list):
        raise CleanupError("input_index")
    for item in index_entries:
        record = _exact_keys(
            item, ("path", "mode", "oid", "stage"), "input_index"
        )
        _encoded_path(record["path"])
        _text(record["mode"], 12, "input_index")
        _oid(record["oid"])
        if record["stage"] != 0:
            raise CleanupError("input_index")
    try:
        base64.b64decode(expected["status"].encode("ascii"), validate=True)
    except (UnicodeError, binascii.Error, AttributeError) as error:
        raise CleanupError("input_status") from error
    root_mode = _integer(expected["root_mode"], "input_tree")
    if root_mode > 0o7777:
        raise CleanupError("input_tree")
    return {
        "head": _oid(expected["head"]),
        "branch": _text(expected["branch"], 255, "input_branch"),
        "root_mode": root_mode,
        "status": expected["status"],
        "index": {
            "mode": _integer(index["mode"], "input_index"),
            "size": _integer(index["size"], "input_index"),
            "sha256": _digest(index["sha256"]),
            "entries": index_entries,
        },
        "entries": normalized,
        "deletions": list(deletions),
    }


def _validate_candidate(value: Any) -> Dict[str, Any]:
    candidate = _exact_keys(value, CANDIDATE_KEYS, "input_candidate")
    if candidate["action"] != "archive_only":
        raise CleanupError("input_action")
    return {
        "action": "archive_only",
        "lease_id": _lease_id(candidate["lease_id"]),
        "lease_generation": _integer(
            candidate["lease_generation"], "input_generation", 1
        ),
        "branch_lease_id": _lease_id(candidate["branch_lease_id"]),
        "branch_generation": _integer(
            candidate["branch_generation"], "input_generation", 1
        ),
        "expires": _integer(candidate["expires"], "input_expiry"),
        "binding": _validate_binding_json(candidate["binding"]),
        "release": _validate_release_json(candidate["release"]),
        "expected": _validate_expected(candidate["expected"]),
    }


def _validate_plan(value: Any) -> Dict[str, Any]:
    plan = _exact_keys(value, PLAN_KEYS, "input_schema")
    if type(plan["v"]) is not int or plan["v"] != SCHEMA_VERSION:
        raise CleanupError("input_schema")
    if plan["action"] != "archive_only":
        raise CleanupError("input_action")
    repository = _exact_keys(
        plan["repository"], ("common_dir", "root_commit"), "input_repository"
    )
    candidates_value = plan["candidates"]
    if not isinstance(candidates_value, list):
        raise CleanupError("input_candidate")
    candidates = [_validate_candidate(candidate) for candidate in candidates_value]
    if len({candidate["binding"]["path"] for candidate in candidates}) != len(
        candidates
    ):
        raise CleanupError("input_duplicate_subject")
    if len({candidate["lease_id"] for candidate in candidates}) != len(candidates):
        raise CleanupError("input_duplicate_subject")
    if len({candidate["branch_lease_id"] for candidate in candidates}) != len(
        candidates
    ):
        raise CleanupError("input_duplicate_subject")
    hold_counts = _exact_keys(
        plan["hold_counts"], ("held", "unknown"), "input_counts"
    )
    return {
        "v": SCHEMA_VERSION,
        "action": "archive_only",
        "created": _integer(plan["created"], "input_created"),
        "repository": {
            "common_dir": _path_text(repository["common_dir"]),
            "root_commit": _oid(repository["root_commit"]),
        },
        "workflow_base": _text(
            plan["workflow_base"], 255, "input_branch"
        ),
        "candidates": candidates,
        "hold_counts": {
            "held": _integer(hold_counts["held"], "input_counts"),
            "unknown": _integer(hold_counts["unknown"], "input_counts"),
        },
    }


def _index_entries(path: Path) -> List[Dict[str, Any]]:
    sparse = _run(
        ("git", "-C", str(path), "sparse-checkout", "list")
    )
    if sparse.returncode == 0:
        raise CleanupError("index_unsupported")
    staged = _git(path, "ls-files", "--stage", "-z")
    visible = _git(path, "ls-files", "-v", "-z")
    flags: Dict[bytes, bytes] = {}
    for raw in visible.split(b"\0"):
        if not raw:
            continue
        if len(raw) < 3 or raw[1:2] != b" ":
            raise CleanupError("index_unsupported")
        flags[raw[2:]] = raw[:1]
    found = []
    for raw in staged.split(b"\0"):
        if not raw:
            continue
        metadata, separator, relative = raw.partition(b"\t")
        fields = metadata.split(b" ")
        if not separator or len(fields) != 3:
            raise CleanupError("index_unsupported")
        mode, object_id, stage = fields
        if stage != b"0" or flags.get(relative) != b"H":
            raise CleanupError("index_unsupported")
        if mode not in (b"100644", b"100755", b"120000"):
            raise CleanupError("index_unsupported")
        try:
            found.append(
                {
                    "path": base64.b64encode(relative).decode("ascii"),
                    "mode": mode.decode("ascii"),
                    "oid": object_id.decode("ascii"),
                    "stage": 0,
                }
            )
        except UnicodeError as error:
            raise CleanupError("index_unsupported") from error
    return sorted(found, key=lambda item: item["path"])


def _ignored_paths(path: Path, entries: Sequence[Mapping[str, Any]]) -> set:
    leaves = [
        _encoded_path(entry["path"])
        for entry in entries
        if entry["kind"] in ("file", "link")
    ]
    if not leaves:
        return set()
    completed = _run(
        (
            "git",
            "-C",
            str(path),
            "check-ignore",
            "-z",
            "--stdin",
        ),
        input_bytes=b"\0".join(leaves) + b"\0",
    )
    if completed.returncode not in (0, 1):
        raise CleanupError("ignored_unknown")
    stdout = completed.stdout
    raw = stdout if isinstance(stdout, bytes) else stdout.encode("utf-8")
    return set(value for value in raw.split(b"\0") if value)


def _status_bytes(path: Path) -> bytes:
    return _git(
        path,
        "status",
        "--porcelain=v1",
        "-z",
        "--untracked-files=all",
        "--ignored=matching",
        "--no-renames",
    )


def _open_directory_at(parent: int, name: str) -> int:
    descriptor = os.open(
        name,
        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
        dir_fd=parent,
    )
    info = os.fstat(descriptor)
    if not stat.S_ISDIR(info.st_mode):
        os.close(descriptor)
        raise CleanupError("archive_path")
    return descriptor


def _tree_entries(
    root: Path,
    root_fd: int,
    payload_dir: Optional[Path],
) -> List[Dict[str, Any]]:
    entries: List[Dict[str, Any]] = []
    total = 0
    payload_number = 0

    def visit(directory: int, prefix: bytes) -> None:
        nonlocal payload_number, total
        for name in sorted(os.listdir(directory), key=os.fsencode):
            if prefix == b"" and name == ".git":
                continue
            _path_component(name)
            encoded_name = os.fsencode(name)
            if encoded_name == b".git":
                raise CleanupError("nested_repository")
            relative = prefix + b"/" + encoded_name if prefix else encoded_name
            info = os.stat(name, dir_fd=directory, follow_symlinks=False)
            mode = stat.S_IMODE(info.st_mode)
            display = base64.b64encode(relative).decode("ascii")
            if stat.S_ISDIR(info.st_mode):
                entries.append(
                    {
                        "path": display,
                        "kind": "directory",
                        "mode": mode,
                        "size": 0,
                        "sha256": None,
                        "target": None,
                    }
                )
                child = _open_directory_at(directory, name)
                try:
                    visit(child, relative)
                finally:
                    os.close(child)
            elif stat.S_ISLNK(info.st_mode):
                target = os.readlink(name, dir_fd=directory)
                target_b64 = base64.b64encode(os.fsencode(target)).decode(
                    "ascii"
                )
                entries.append(
                    {
                        "path": display,
                        "kind": "link",
                        "mode": mode,
                        "size": len(os.fsencode(target)),
                        "sha256": None,
                        "target": target_b64,
                    }
                )
            elif stat.S_ISREG(info.st_mode):
                descriptor = os.open(
                    name,
                    os.O_RDONLY | os.O_NOFOLLOW,
                    dir_fd=directory,
                )
                try:
                    opened = os.fstat(descriptor)
                    if (
                        opened.st_dev != info.st_dev
                        or opened.st_ino != info.st_ino
                        or not stat.S_ISREG(opened.st_mode)
                    ):
                        raise CleanupError("tree_changed")
                    raw = _read_all(descriptor, MAX_LEAF_BYTES)
                    after = os.fstat(descriptor)
                    if (
                        after.st_size != len(raw)
                        or after.st_mtime_ns != opened.st_mtime_ns
                        or after.st_ctime_ns != opened.st_ctime_ns
                    ):
                        raise CleanupError("tree_changed")
                finally:
                    os.close(descriptor)
                digest = hashlib.sha256(raw).hexdigest()
                payload_name = None
                if payload_dir is not None:
                    payload_name = "%08d" % payload_number
                    payload_number += 1
                    payload_file = payload_dir / payload_name
                    descriptor = os.open(
                        payload_file,
                        os.O_WRONLY
                        | os.O_CREAT
                        | os.O_EXCL
                        | os.O_NOFOLLOW,
                        0o600,
                    )
                    try:
                        os.fchmod(descriptor, 0o600)
                        _write_all(descriptor, raw)
                        os.fsync(descriptor)
                    finally:
                        os.close(descriptor)
                entries.append(
                    {
                        "path": display,
                        "kind": "file",
                        "mode": mode,
                        "size": len(raw),
                        "sha256": digest,
                        "target": None,
                    }
                )
                total += len(raw)
                if total > MAX_ARCHIVE_BYTES:
                    raise CleanupError("archive_too_large")
            else:
                raise CleanupError("special_file")
            if len(entries) > MAX_ENTRIES:
                raise CleanupError("archive_too_large")

    visit(root_fd, b"")
    return sorted(entries, key=lambda item: item["path"])


def _read_index(binding: factory_lease.WorktreeBinding) -> bytes:
    index_path = Path(binding.admin_dir) / "index"
    return _read_file_nofollow(index_path, MAX_MANIFEST_BYTES)


def _capture_expected(
    binding: factory_lease.WorktreeBinding,
    payload_dir: Optional[Path] = None,
) -> Tuple[Dict[str, Any], Dict[str, bytes]]:
    root = Path(binding.path)
    descriptor = os.open(
        root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    )
    try:
        root_info = os.fstat(descriptor)
        if (
            root_info.st_dev != binding.device
            or root_info.st_ino != binding.inode
        ):
            raise CleanupError("path_changed")
        entries = _tree_entries(root, descriptor, payload_dir)
        if any(
            _encoded_path(entry["path"]) == b"build/runs"
            or _encoded_path(entry["path"]).startswith(b"build/runs/")
            for entry in entries
        ):
            raise CleanupError("marker_content")
        root_mode = stat.S_IMODE(root_info.st_mode)
    except CleanupError:
        raise
    except OSError as error:
        raise CleanupError("tree_unreadable") from error
    finally:
        os.close(descriptor)
    ignored = _ignored_paths(root, entries)
    for relative in ignored:
        selected = any(
            relative.startswith(prefix) for prefix in SELECTED_IGNORED
        )
        if not selected:
            raise CleanupError("ignored_unselected")
    index_bytes = _read_index(binding)
    index_info = (Path(binding.admin_dir) / "index").lstat()
    status = _status_bytes(root)
    index_entries = _index_entries(root)
    present = {_encoded_path(entry["path"]) for entry in entries}
    deletions = [
        entry["path"]
        for entry in index_entries
        if _encoded_path(entry["path"]) not in present
    ]
    expected = {
        "head": binding.head,
        "branch": binding.branch,
        "root_mode": root_mode,
        "status": base64.b64encode(status).decode("ascii"),
        "index": {
            "mode": stat.S_IMODE(index_info.st_mode),
            "size": len(index_bytes),
            "sha256": hashlib.sha256(index_bytes).hexdigest(),
            "entries": index_entries,
        },
        "entries": entries,
        "deletions": sorted(deletions),
    }
    return _validate_expected(expected), {}


def _same_binding(
    expected: Mapping[str, Any],
    binding: factory_lease.WorktreeBinding,
) -> bool:
    return expected == _binding_json(binding)


def _open_record_paths_first(
    record: Mapping[str, Any], binding: factory_lease.WorktreeBinding
) -> None:
    subject = record["subject"]
    expected = {
        "path": str(binding.path),
        "device": binding.device,
        "inode": binding.inode,
        "branch": binding.branch,
        "head": binding.head,
        "gitfile": str(binding.gitfile),
        "admin_dir": str(binding.admin_dir),
        "backpointer": str(binding.backpointer),
        "nonce_path": str(binding.nonce_path),
    }
    for key, value in expected.items():
        if subject[key] != value:
            raise CleanupError("lease_changed")
    for path_value in (
        binding.path,
        binding.gitfile,
        binding.admin_dir,
        binding.backpointer,
        binding.nonce_path,
    ):
        _assert_nonlinked_absolute(Path(path_value))


def _pr_evidence_matches(
    repo: Path,
    origin: str,
    binding: factory_lease.WorktreeBinding,
    merged: Mapping[str, Any],
    provider: factory_lease.PullRequestProvider,
) -> None:
    try:
        evidence = tuple(provider.list_for_branch(origin, binding.branch))
    except Exception as error:
        raise CleanupError("pr_unknown") from error
    if len(evidence) >= 30:
        raise CleanupError("pr_partial")
    if any(item.state.upper() == "OPEN" for item in evidence):
        raise CleanupError("open_successor")
    matching = tuple(
        item
        for item in evidence
        if item.number == merged["pull_request"]
        and item.repository == origin
        and item.base == merged["target"]
        and item.branch == binding.branch
        and item.state.upper() == "MERGED"
        and item.head_oid == merged["head_oid"]
    )
    if len(matching) != 1:
        raise CleanupError("pr_changed")
    if binding.head != merged["head_oid"]:
        if _run(
            (
                "git",
                "-C",
                str(repo),
                "merge-base",
                "--is-ancestor",
                binding.head,
                merged["head_oid"],
            )
        ).returncode != 0:
            raise CleanupError("pr_changed")


def _marker_and_holder_holds(
    records: Sequence[Mapping[str, Any]],
    worktree: Mapping[str, Any],
    processes: factory.ProcessObservation,
) -> None:
    if processes.pids is None or processes.cwds is None:
        raise CleanupError("process_unknown")
    if processes.starts is None or processes.pgids is None:
        raise CleanupError("process_unknown")
    current_markers = [
        record
        for record in records
        if record["class"] == "run_marker"
        and record["subject"]["parent_lease_id"] == worktree["lease_id"]
        and record["subject"]["parent_generation"] == worktree["generation"]
    ]
    if any(now_record["state"] == "active" for now_record in current_markers):
        raise CleanupError("active_marker")


def _candidate_containment(
    target: factory.Worktree, full: Sequence[factory.Worktree]
) -> None:
    target_path = Path(target.path).resolve()
    for other in full:
        if _same_worktree(other, target):
            continue
        other_path = Path(other.path).resolve()
        try:
            other_path.relative_to(target_path)
        except ValueError:
            continue
        raise CleanupError("nested_worktree")


def _evaluate_candidate(
    repo: Path,
    identity: factory_lease.RepositoryIdentity,
    full: Sequence[factory.Worktree],
    primary: factory.Worktree,
    target: factory.Worktree,
    caller: Path,
    workflow_base: str,
    records: Sequence[Mapping[str, Any]],
    invalid: int,
    processes: factory.ProcessObservation,
    now: int,
    pr_provider: factory_lease.PullRequestProvider,
    external_provider: ExternalProvider,
    runner: factory.ReadOnlyRunner,
) -> Tuple[Optional[Dict[str, Any]], str]:
    target_path = Path(target.path).resolve()
    if target_path in (Path(primary.path).resolve(), caller):
        return None, "protected_worktree"
    if target.branch in ("main", workflow_base) or not target.branch:
        return None, "protected_base"
    _candidate_containment(target, full)
    binding = factory_lease.inspect_worktree(target_path, identity)
    if target.head != binding.head or target.branch != binding.branch:
        return None, "head_changed"
    worktree, branch = _unique_records(records, "worktree", binding)
    _open_record_paths_first(worktree, binding)
    if not factory_lease.lease_matches_worktree(
        worktree, target_path, binding.branch, binding.head
    ):
        return None, "lease_changed"
    if invalid:
        return None, "lease_unknown"
    merged = _release_matches(worktree, branch, binding, now)
    external = external_provider.observe(repo, target_path, binding, worktree)
    if not external.complete:
        return None, "external_unknown"
    if (
        external.t3_owned
        or worktree.get("thread") is not None
        or worktree.get("creator") in ("hook_session", "hook_agent_tool")
    ):
        return None, "t3_owned"
    if external.thread_active is not False:
        return None, "thread_unknown" if external.thread_active is None else "thread_active"
    if external.devcap_active:
        return None, "active_hold"
    _marker_and_holder_holds(records, worktree, processes)
    scoped = _ScopedReader(
        factory.GitReader(repo, runner), primary, target
    )
    snapshot = factory.LeaseSnapshot(identity, tuple(records), invalid)
    inventory = factory.GitResourceProvider(
        "worktrees", repo, scoped, snapshot, now=now
    ).inventory(processes)
    if (
        len(inventory.observations) != 1
        or inventory.unreadable != 0
        or inventory.partial != 0
    ):
        return None, "inventory_incomplete"
    holds = factory.classify(inventory.observations[0])
    if not holds.issubset(frozenset(("dirty", "untracked", "ignored"))):
        reason = sorted(holds)[0]
        return None, "class_" + reason
    reader = factory.GitReader(repo, runner)
    if reader.base_sha() is None:
        return None, "base_unavailable"
    origin = _trusted_origin(repo)
    _pr_evidence_matches(repo, origin, binding, merged, pr_provider)
    expected, _payloads = _capture_expected(binding)
    if expected["head"] != target.head or expected["branch"] != target.branch:
        return None, "head_changed"
    return (
        {
            "action": "archive_only",
            "lease_id": worktree["lease_id"],
            "lease_generation": worktree["generation"],
            "branch_lease_id": branch["lease_id"],
            "branch_generation": branch["generation"],
            "expires": max(worktree["expires"], branch["expires"]),
            "binding": _binding_json(binding),
            "release": dict(merged),
            "expected": expected,
        },
        "planned",
    )


def _evaluation_inputs(
    repo: Path,
    store: factory_lease.LeaseStore,
    now: int,
    process_provider: Optional[factory.ProcessProvider],
    runner: Optional[factory.ReadOnlyRunner],
) -> Tuple[
    factory.ReadOnlyRunner,
    factory.ProcessObservation,
    Tuple[factory.Worktree, ...],
    factory.Worktree,
    Sequence[Mapping[str, Any]],
    int,
]:
    actual_runner = runner or factory.ReadOnlyRunner()
    reader = factory.GitReader(repo, actual_runner)
    full = _current_worktrees(reader)
    primary = _primary_worktree(full, store.identity)
    records, invalid = store.read_records()
    source = process_provider or factory.ReadOnlyProcessProvider(actual_runner)
    processes = source.inventory()
    if processes.pids is None or processes.cwds is None:
        raise CleanupError("process_unknown")
    return actual_runner, processes, full, primary, records, invalid


def _plan_publication(store: factory_lease.LeaseStore, raw: bytes, digest: str) -> Path:
    root = store.root
    if not root.exists():
        raise CleanupError("store_unavailable")
    plans = root / "plans"
    _mkdir_private(plans)
    destination = plans / (digest + ".json")
    try:
        _write_private_file(destination, raw)
    except CleanupError as error:
        if error.reason == "publication_exists":
            existing = _read_file_nofollow(destination, MAX_PLAN_BYTES, 0o600)
            if existing != raw:
                raise CleanupError("plan_collision") from error
            return destination
        raise
    return destination


def plan_cleanup(
    repo: Path,
    *,
    now: Optional[int] = None,
    workflow_base: str = "main",
    pr_provider: Optional[factory_lease.PullRequestProvider] = None,
    process_provider: Optional[factory.ProcessProvider] = None,
    external_provider: Optional[ExternalProvider] = None,
    runner: Optional[factory.ReadOnlyRunner] = None,
) -> PlanResult:
    """Create one canonical private plan and never alter a subject."""

    timestamp = _clock_value(now)
    invocation = _invocation_root(repo)
    store = factory_lease.LeaseStore.for_repo(invocation, now=timestamp)
    _verify_store(store.identity)
    actual_runner, processes, full, primary, records, invalid = (
        _evaluation_inputs(invocation, store, timestamp, process_provider, runner)
    )
    provider = pr_provider or factory_lease.GhPullRequestProvider()
    external = external_provider or UnknownExternalProvider()
    candidates = []
    held = 0
    unknown = 0
    for target in full:
        if Path(target.path).resolve() in (
            Path(primary.path).resolve(),
            invocation,
        ):
            continue
        try:
            candidate, reason = _evaluate_candidate(
                invocation,
                store.identity,
                full,
                primary,
                target,
                invocation,
                workflow_base,
                records,
                invalid,
                processes,
                timestamp,
                provider,
                external,
                actual_runner,
            )
        except CleanupError as error:
            candidate, reason = None, error.reason
        except (OSError, ValueError, UnicodeError, factory_lease.LeaseError):
            candidate, reason = None, "inventory_incomplete"
        if candidate is not None:
            candidates.append(candidate)
        else:
            held += 1
            if reason.endswith("_unknown") or reason in (
                "inventory_incomplete",
                "lease_unknown",
                "external_unknown",
                "process_unknown",
                "pr_unknown",
            ):
                unknown += 1
    plan = _validate_plan(
        {
            "v": SCHEMA_VERSION,
            "action": "archive_only",
            "created": timestamp,
            "repository": store.identity.as_json(),
            "workflow_base": workflow_base,
            "candidates": sorted(candidates, key=lambda item: item["binding"]["path"]),
            "hold_counts": {"held": held, "unknown": unknown},
        }
    )
    raw = _canonical_bytes(plan)
    if len(raw) > MAX_PLAN_BYTES:
        raise CleanupError("plan_too_large")
    digest = hashlib.sha256(raw).hexdigest()
    plan_path = _plan_publication(store, raw, digest)
    return PlanResult(digest, plan_path, len(candidates), held, unknown)


def _open_plan_path(
    identity: factory_lease.RepositoryIdentity, plan_path: Path, digest: str
) -> bytes:
    if any(part == ".." for part in plan_path.parts):
        raise CleanupError("input_path")
    expected_dir = identity.common_dir / "factory" / "plans"
    _assert_nonlinked_absolute(expected_dir)
    try:
        actual = plan_path.resolve(strict=True)
    except OSError as error:
        raise CleanupError("input_file") from error
    if actual.parent != expected_dir.resolve():
        raise CleanupError("input_outside_store")
    if actual.name != digest + ".json" or plan_path.is_symlink():
        raise CleanupError("input_name")
    return _read_file_nofollow(actual, MAX_PLAN_BYTES, 0o600)


def _input_gate(
    store: factory_lease.LeaseStore,
    plan_path: Path,
    approve: str,
    now: int,
) -> Tuple[str, Dict[str, Any], bytes]:
    digest = _digest(approve)
    raw = _open_plan_path(store.identity, plan_path, digest)
    if hashlib.sha256(raw).hexdigest() != digest:
        raise CleanupError("input_digest")
    plan = _validate_plan(_strict_json(raw, MAX_PLAN_BYTES))
    if plan["repository"] != store.identity.as_json():
        raise CleanupError("repository_changed")
    age = now - plan["created"]
    if age < 0:
        raise CleanupError("plan_future")
    if age >= PLAN_LIFETIME_SECONDS:
        raise CleanupError("plan_expired")
    return digest, plan, raw


def _candidate_from_plan(plan_candidate: Mapping[str, Any]) -> factory.Worktree:
    binding = plan_candidate["binding"]
    return factory.Worktree(
        Path(binding["path"]), binding["head"], binding["branch"], False
    )


def _lookup_current(
    full: Sequence[factory.Worktree], candidate: Mapping[str, Any]
) -> Optional[factory.Worktree]:
    path = Path(candidate["binding"]["path"]).resolve(strict=False)
    values = tuple(
        item for item in full if Path(item.path).resolve() == path
    )
    return values[0] if len(values) == 1 else None


def _validate_fresh_candidate(
    repo: Path,
    store: factory_lease.LeaseStore,
    plan_candidate: Mapping[str, Any],
    workflow_base: str,
    process_provider: factory.ProcessProvider,
    pr_provider: factory_lease.PullRequestProvider,
    external_provider: ExternalProvider,
    runner: factory.ReadOnlyRunner,
    now: int,
) -> Tuple[Optional[factory_lease.WorktreeBinding], str]:
    try:
        actual_runner, processes, full, primary, records, invalid = (
            _evaluation_inputs(repo, store, now, process_provider, runner)
        )
    except CleanupError as error:
        return None, error.reason
    except (OSError, ValueError, UnicodeError, factory_lease.LeaseError):
        return None, "inventory_incomplete"
    target = _lookup_current(full, plan_candidate)
    if target is None:
        return None, "path_changed"
    try:
        target_info = Path(plan_candidate["binding"]["path"]).lstat()
    except OSError:
        return None, "path_changed"
    if not stat.S_ISDIR(target_info.st_mode):
        return None, "path_changed"
    try:
        fresh, reason = _evaluate_candidate(
            repo,
            store.identity,
            full,
            primary,
            target,
            _invocation_root(repo),
            workflow_base,
            records,
            invalid,
            processes,
            now,
            pr_provider,
            external_provider,
            actual_runner,
        )
    except CleanupError as error:
        return None, error.reason
    except (OSError, ValueError, UnicodeError, factory_lease.LeaseError):
        return None, "inventory_incomplete"
    if fresh is None:
        return None, reason
    if fresh != plan_candidate:
        if fresh["binding"] != plan_candidate["binding"]:
            return None, "path_changed"
        if (
            fresh["lease_id"] != plan_candidate["lease_id"]
            or fresh["lease_generation"] != plan_candidate["lease_generation"]
            or fresh["branch_lease_id"] != plan_candidate["branch_lease_id"]
            or fresh["branch_generation"] != plan_candidate["branch_generation"]
            or fresh["release"] != plan_candidate["release"]
        ):
            return None, "lease_changed"
        if fresh["binding"]["head"] != plan_candidate["binding"]["head"]:
            return None, "head_changed"
        return None, "tree_changed"
    return factory_lease.inspect_worktree(
        Path(plan_candidate["binding"]["path"]), store.identity
    ), "planned"


def _publish_file(path: Path, raw: bytes) -> None:
    descriptor = os.open(
        path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600
    )
    try:
        os.fchmod(descriptor, 0o600)
        _write_all(descriptor, raw)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _bundle(
    binding: factory_lease.WorktreeBinding, candidate_dir: Path
) -> Path:
    path = candidate_dir / "commits.bundle"
    _git(
        Path(binding.path),
        "bundle",
        "create",
        str(path),
        "HEAD",
    )
    info = path.lstat()
    if path.is_symlink() or not stat.S_ISREG(info.st_mode) or info.st_size == 0:
        raise CleanupError("bundle_invalid")
    os.chmod(path, 0o600)
    _fsync_file(path)
    return path


def _restore_write_tree(
    root: Path, manifest: Mapping[str, Any], payload_dir: Path
) -> None:
    root_descriptor = os.open(
        root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    )
    try:
        for entry in manifest["entries"]:
            relative = _encoded_path(entry["path"])
            components = [os.fsdecode(item) for item in relative.split(b"/")]
            if any(component in ("", ".", "..", ".git") for component in components):
                raise CleanupError("archive_path")
            if entry["kind"] != "directory":
                continue
            current = root_descriptor
            opened = []
            try:
                for component in components:
                    try:
                        child = os.open(
                            component,
                            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                            dir_fd=current,
                        )
                    except FileNotFoundError:
                        os.mkdir(component, mode=0o700, dir_fd=current)
                        child = os.open(
                            component,
                            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                            dir_fd=current,
                        )
                    opened.append(child)
                    current = child
                os.fchmod(current, entry["mode"])
            finally:
                for child in reversed(opened):
                    os.close(child)
        for entry in manifest["entries"]:
            if entry["kind"] == "directory":
                continue
            relative = _encoded_path(entry["path"])
            components = [os.fsdecode(item) for item in relative.split(b"/")]
            current = root_descriptor
            opened = []
            try:
                for component in components[:-1]:
                    child = os.open(
                        component,
                        os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                        dir_fd=current,
                    )
                    opened.append(child)
                    current = child
                leaf = components[-1]
                if entry["kind"] == "link":
                    raw_target = base64.b64decode(entry["target"].encode("ascii"))
                    os.symlink(os.fsdecode(raw_target), leaf, dir_fd=current)
                else:
                    payload = payload_dir / entry["payload"]
                    data = _read_file_nofollow(payload, MAX_LEAF_BYTES, 0o600)
                    descriptor = os.open(
                        leaf,
                        os.O_WRONLY
                        | os.O_CREAT
                        | os.O_EXCL
                        | os.O_NOFOLLOW,
                        0o600,
                        dir_fd=current,
                    )
                    try:
                        os.fchmod(descriptor, entry["mode"])
                        _write_all(descriptor, data)
                        os.fsync(descriptor)
                    finally:
                        os.close(descriptor)
            finally:
                for child in reversed(opened):
                    os.close(child)
        os.fchmod(root_descriptor, manifest["root_mode"])
    finally:
        os.close(root_descriptor)


def _clear_restore_worktree(root: Path) -> None:
    descriptor = os.open(
        root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    )
    try:
        for name in sorted(os.listdir(descriptor)):
            if name == ".git":
                continue
            info = os.stat(name, dir_fd=descriptor, follow_symlinks=False)
            child = root / name
            if stat.S_ISDIR(info.st_mode):
                _remove_private_tree(child)
            else:
                os.unlink(name, dir_fd=descriptor)
    finally:
        os.close(descriptor)


def _restore_archive(
    candidate_dir: Path,
    restore_dir: Path,
    expected: Mapping[str, Any],
):
    bundle = candidate_dir / "commits.bundle"
    index = candidate_dir / "index"
    payload_dir = candidate_dir / "files"
    manifest_path = candidate_dir / "manifest.json"
    raw_manifest = _read_file_nofollow(
        manifest_path, MAX_MANIFEST_BYTES, 0o600
    )
    manifest_value = _strict_json(raw_manifest, MAX_MANIFEST_BYTES)
    if not isinstance(manifest_value, dict) or set(manifest_value) != {
        "v",
        "candidate",
        "expected",
        "bundle_sha256",
        "index_sha256",
        "files",
        "index_objects",
    }:
        raise CleanupError("archive_manifest")
    expected_value = manifest_value["expected"]
    normalized = _validate_expected(expected_value)
    if normalized != expected:
        raise CleanupError("archive_manifest")
    _lease_id(manifest_value["candidate"])
    if (
        manifest_value["v"] != SCHEMA_VERSION
        or hashlib.sha256(_read_file_nofollow(bundle, MAX_ARCHIVE_BYTES, 0o600)).hexdigest()
        != manifest_value["bundle_sha256"]
        or hashlib.sha256(_read_file_nofollow(index, MAX_MANIFEST_BYTES, 0o600)).hexdigest()
        != manifest_value["index_sha256"]
    ):
        raise CleanupError("archive_manifest")
    files = manifest_value["files"]
    if not isinstance(files, list):
        raise CleanupError("archive_manifest")
    payload_by_path = {}
    for item in files:
        row = _exact_keys(item, ("path", "payload", "sha256"), "archive_manifest")
        path = _encoded_path(row["path"])
        _digest(row["sha256"])
        payload = _path_component(_text(row["payload"], 64, "archive_manifest"))
        if path in payload_by_path:
            raise CleanupError("archive_manifest")
        payload_by_path[path] = row
        actual = _read_file_nofollow(payload_dir / payload, MAX_LEAF_BYTES, 0o600)
        if hashlib.sha256(actual).hexdigest() != row["sha256"]:
            raise CleanupError("archive_manifest")
    expected_files = {
        _encoded_path(entry["path"])
        for entry in expected["entries"]
        if entry["kind"] == "file"
    }
    if set(payload_by_path) != expected_files:
        raise CleanupError("archive_manifest")
    payload_names = {str(row["payload"]) for row in payload_by_path.values()}
    actual_names = set()
    for path in payload_dir.iterdir():
        info = path.lstat()
        if (
            path.is_symlink()
            or not stat.S_ISREG(info.st_mode)
            or stat.S_IMODE(info.st_mode) != 0o600
        ):
            raise CleanupError("archive_manifest")
        actual_names.add(path.name)
    if actual_names != payload_names:
        raise CleanupError("archive_manifest")
    object_rows = manifest_value["index_objects"]
    if not isinstance(object_rows, list):
        raise CleanupError("archive_manifest")
    object_dir = candidate_dir / "index-objects"
    index_objects = {}
    expected_oids = {
        entry["oid"] for entry in expected["index"]["entries"]
    }
    for item in object_rows:
        row = _exact_keys(
            item, ("oid", "sha256", "size"), "archive_manifest"
        )
        object_id = _oid(row["oid"])
        if object_id in index_objects:
            raise CleanupError("archive_manifest")
        digest = _digest(row["sha256"])
        size = _integer(row["size"], "archive_manifest")
        content = _read_file_nofollow(
            object_dir / object_id, MAX_LEAF_BYTES, 0o600
        )
        object_header = (
            "blob %d\0" % len(content)
        ).encode("ascii") + content
        if (
            hashlib.sha256(content).hexdigest() != digest
            or len(content) != size
            or hashlib.sha1(object_header).hexdigest() != object_id
        ):
            raise CleanupError("archive_manifest")
        index_objects[object_id] = content
    if set(index_objects) != expected_oids:
        raise CleanupError("archive_manifest")
    object_names = set()
    for path in object_dir.iterdir():
        info = path.lstat()
        if (
            path.is_symlink()
            or not stat.S_ISREG(info.st_mode)
            or stat.S_IMODE(info.st_mode) != 0o600
        ):
            raise CleanupError("archive_manifest")
        object_names.add(path.name)
    if object_names != expected_oids:
        raise CleanupError("archive_manifest")
    if restore_dir.exists():
        raise CleanupError("restore_collision")
    verify_dir = restore_dir.parent / (restore_dir.name + "-verify")
    _mkdir_private(verify_dir)
    try:
        initialized = _run(("git", "-C", str(verify_dir), "init", "-q"))
        if initialized.returncode != 0:
            raise CleanupError("bundle_invalid")
        verifier = _run(
            (
                "git",
                "-C",
                str(verify_dir),
                "bundle",
                "verify",
                str(bundle),
            )
        )
        if verifier.returncode != 0:
            raise CleanupError("bundle_invalid")
    finally:
        _remove_private_tree(verify_dir)
    completed = _run(
        (
            "git",
            "-C",
            str(candidate_dir),
            "clone",
            "-q",
            "--no-hardlinks",
            str(bundle),
            str(restore_dir),
        )
    )
    if completed.returncode != 0:
        raise CleanupError("restore_failed")
    _assert_nonlinked_absolute(restore_dir)
    _git(restore_dir, "checkout", "-q", "--detach", expected["head"])
    if (restore_dir / ".git" / "objects" / "info" / "alternates").exists():
        raise CleanupError("restore_alternates")
    for object_id, content in index_objects.items():
        written = _run(
            (
                "git",
                "-C",
                str(restore_dir),
                "hash-object",
                "-w",
                "--stdin",
            ),
            input_bytes=content,
        )
        if written.returncode != 0 or written.stdout.strip() != object_id.encode("ascii"):
            raise CleanupError("restore_index")
    _clear_restore_worktree(restore_dir)
    materialized = []
    for entry in expected["entries"]:
        item = dict(entry)
        if entry["kind"] == "file":
            path = _encoded_path(entry["path"])
            row = payload_by_path.get(path)
            if row is None:
                raise CleanupError("archive_manifest")
            item["payload"] = row["payload"]
        materialized.append(item)
    materialized_manifest = dict(expected)
    materialized_manifest["entries"] = materialized
    _restore_write_tree(restore_dir, materialized_manifest, payload_dir)
    clone_index = restore_dir / ".git" / "index"
    index_bytes = _read_file_nofollow(index, MAX_MANIFEST_BYTES, 0o600)
    clone_index.unlink()
    _publish_file(clone_index, index_bytes)
    os.chmod(clone_index, expected["index"]["mode"])


def _verify_restore(
    restore_dir: Path, expected: Mapping[str, Any]
) -> None:
    head = _git_text(restore_dir, "rev-parse", "--verify", "HEAD").strip()
    if head != expected["head"]:
        raise CleanupError("restore_head")
    status = _status_bytes(restore_dir)
    if base64.b64encode(status).decode("ascii") != expected["status"]:
        raise CleanupError("restore_status")
    index_bytes = _read_file_nofollow(
        restore_dir / ".git" / "index", MAX_MANIFEST_BYTES
    )
    index_info = (restore_dir / ".git" / "index").lstat()
    if (
        hashlib.sha256(index_bytes).hexdigest() != expected["index"]["sha256"]
        or stat.S_IMODE(index_info.st_mode) != expected["index"]["mode"]
        or len(index_bytes) != expected["index"]["size"]
    ):
        raise CleanupError("restore_index")
    descriptor = os.open(
        restore_dir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    )
    try:
        entries = _tree_entries(restore_dir, descriptor, None)
    finally:
        os.close(descriptor)
    if entries != expected["entries"]:
        raise CleanupError("restore_tree")
    if _index_entries(restore_dir) != expected["index"]["entries"]:
        raise CleanupError("restore_index_entries")


def _archive_candidate(
    binding: factory_lease.WorktreeBinding,
    candidate: Mapping[str, Any],
    candidate_dir: Path,
    restore_dir: Path,
) -> None:
    _mkdir_private(candidate_dir)
    files_dir = candidate_dir / "files"
    _mkdir_private(files_dir)
    object_dir = candidate_dir / "index-objects"
    _mkdir_private(object_dir)
    expected, _payloads = _capture_expected(binding, files_dir)
    if expected != candidate["expected"]:
        raise CleanupError("tree_changed")
    bundle = _bundle(binding, candidate_dir)
    index_bytes = _read_index(binding)
    _publish_file(candidate_dir / "index", index_bytes)
    if hashlib.sha256(index_bytes).hexdigest() != expected["index"]["sha256"]:
        raise CleanupError("index_changed")
    index_objects = []
    total_objects = 0
    for object_id in sorted(
        {entry["oid"] for entry in expected["index"]["entries"]}
    ):
        content = _git(binding.path, "cat-file", "blob", object_id)
        total_objects += len(content)
        if total_objects > MAX_ARCHIVE_BYTES:
            raise CleanupError("archive_too_large")
        _publish_file(object_dir / object_id, content)
        index_objects.append(
            {
                "oid": object_id,
                "sha256": hashlib.sha256(content).hexdigest(),
                "size": len(content),
            }
        )
    payload_by_digest: Dict[str, str] = {}
    for path in sorted(files_dir.iterdir()):
        if not path.is_file():
            raise CleanupError("archive_manifest")
        content_digest = hashlib.sha256(
            _read_file_nofollow(path, MAX_LEAF_BYTES, 0o600)
        ).hexdigest()
        payload_by_digest.setdefault(content_digest, path.name)
    files = []
    for entry in expected["entries"]:
        if entry["kind"] != "file":
            continue
        payload = payload_by_digest.get(entry["sha256"])
        if payload is None:
            raise CleanupError("archive_manifest")
        files.append(
            {
                "path": entry["path"],
                "payload": payload,
                "sha256": entry["sha256"],
            }
        )
    manifest = {
        "v": SCHEMA_VERSION,
        "candidate": candidate["lease_id"],
        "expected": expected,
        "bundle_sha256": hashlib.sha256(
            _read_file_nofollow(bundle, MAX_ARCHIVE_BYTES, 0o600)
        ).hexdigest(),
        "index_sha256": hashlib.sha256(index_bytes).hexdigest(),
        "files": files,
        "index_objects": index_objects,
    }
    raw_manifest = _canonical_bytes(manifest)
    if len(raw_manifest) > MAX_MANIFEST_BYTES:
        raise CleanupError("archive_too_large")
    _publish_file(candidate_dir / "manifest.json", raw_manifest)
    _fsync_directory(files_dir)
    _fsync_directory(object_dir)
    _fsync_directory(candidate_dir)
    _restore_archive(candidate_dir, restore_dir, expected)
    _verify_restore(restore_dir, expected)


def _outcome(
    candidate: Mapping[str, Any], status: str, reason: Optional[str] = None
) -> Dict[str, Any]:
    value = {
        "lease_id": candidate["lease_id"],
        "generation": candidate["lease_generation"],
        "outcome": status,
    }
    if reason is not None:
        value["reason"] = reason
    return value


def _validate_outcome(value: Any) -> Dict[str, Any]:
    if not isinstance(value, dict):
        raise CleanupError("receipt_invalid")
    keys = set(value)
    if keys not in (
        {"lease_id", "generation", "outcome"},
        {"lease_id", "generation", "outcome", "reason"},
    ):
        raise CleanupError("receipt_invalid")
    if value["outcome"] not in ("archived", "held"):
        raise CleanupError("receipt_invalid")
    return value


def _validate_receipt(
    path: Path,
    digest: str,
    candidate_ids: Sequence[Tuple[str, int]],
    candidates: Sequence[Mapping[str, Any]] = (),
    staging_root: Optional[Path] = None,
) -> ApplyResult:
    receipt_path = path / "receipt.json"
    raw = _read_file_nofollow(receipt_path, MAX_PLAN_BYTES, 0o600)
    receipt = _strict_json(raw, MAX_PLAN_BYTES)
    values = _exact_keys(receipt, RECEIPT_KEYS, "receipt_invalid")
    if (
        values["v"] != SCHEMA_VERSION
        or _digest(values["plan_digest"]) != digest
        or type(values["created"]) is not int
        or not isinstance(values["outcomes"], list)
    ):
        raise CleanupError("receipt_invalid")
    outcomes = [_validate_outcome(item) for item in values["outcomes"]]
    ids = []
    archived = held = 0
    for item in outcomes:
        if item["outcome"] == "archived":
            archived += 1
        else:
            held += 1
        ids.append((_lease_id(item["lease_id"]), _integer(item["generation"], "receipt_invalid", 1)))
    if tuple(ids) != tuple(candidate_ids):
        raise CleanupError("receipt_invalid")
    if candidates:
        by_id = {
            (candidate["lease_id"], candidate["lease_generation"]): candidate
            for candidate in candidates
        }
        for item in outcomes:
            if item["outcome"] != "archived":
                continue
            key = (item["lease_id"], item["generation"])
            candidate = by_id.get(key)
            if candidate is None or staging_root is None:
                raise CleanupError("receipt_invalid")
            candidate_dir = path / candidate["lease_id"] / str(
                candidate["lease_generation"]
            )
            restore = staging_root / (
                "replay-" + digest + "-" + secrets.token_hex(6)
            )
            try:
                _restore_archive(
                    candidate_dir, restore, candidate["expected"]
                )
                _verify_restore(restore, candidate["expected"])
            finally:
                if restore.exists() or restore.is_symlink():
                    _remove_private_tree(restore)
    return ApplyResult(digest, archived, held, True)


def _prepare_store_dirs(store: factory_lease.LeaseStore) -> Tuple[Path, Path]:
    archive = store.root / "archive"
    staging = store.root / "staging"
    _mkdir_private(archive)
    _mkdir_private(staging)
    return archive, staging


def _recover_staging(
    staging_root: Path,
    digest: str,
    candidate_ids: Sequence[Tuple[str, int]],
) -> None:
    matching = sorted(
        path
        for path in staging_root.iterdir()
        if path.name.startswith(digest + "-")
    )
    if not matching:
        return
    if len(matching) != 1:
        raise CleanupError("recovery_ambiguous")
    stage = matching[0]
    marker_path = stage / "stage.json"
    raw = _read_file_nofollow(marker_path, 4096, 0o600)
    marker = _strict_json(raw, 4096)
    values = _exact_keys(
        marker, ("v", "plan_digest", "candidates"), "recovery_ambiguous"
    )
    if values["v"] != SCHEMA_VERSION or values["plan_digest"] != digest:
        raise CleanupError("recovery_ambiguous")
    ids = []
    if not isinstance(values["candidates"], list):
        raise CleanupError("recovery_ambiguous")
    for item in values["candidates"]:
        row = _exact_keys(item, ("lease_id", "generation"), "recovery_ambiguous")
        ids.append(
            (
                _lease_id(row["lease_id"]),
                _integer(row["generation"], "recovery_ambiguous", 1),
            )
        )
    if tuple(ids) != tuple(candidate_ids):
        raise CleanupError("recovery_ambiguous")
    _remove_private_tree(stage)


def apply_cleanup(
    repo: Path,
    plan_path: Path,
    approve: str,
    *,
    now: Optional[int] = None,
    pr_provider: Optional[factory_lease.PullRequestProvider] = None,
    process_provider: Optional[factory.ProcessProvider] = None,
    external_provider: Optional[ExternalProvider] = None,
    runner: Optional[factory.ReadOnlyRunner] = None,
    lock_hook: Optional[Any] = None,
    publish_hook: Optional[Any] = None,
) -> ApplyResult:
    """Verify and publish one digest-approved archive plan under the writer lock."""

    timestamp = _clock_value(now)
    invocation = _invocation_root(repo)
    store = factory_lease.LeaseStore.for_repo(invocation, now=timestamp)
    digest, plan, _raw = _input_gate(
        store, Path(plan_path), approve, timestamp
    )
    _verify_store(store.identity)
    candidate_ids = tuple(
        (item["lease_id"], item["lease_generation"])
        for item in plan["candidates"]
    )
    provider = pr_provider or factory_lease.GhPullRequestProvider()
    external = external_provider or UnknownExternalProvider()
    actual_runner = runner or factory.ReadOnlyRunner()
    process_source = process_provider or factory.ReadOnlyProcessProvider(
        actual_runner
    )
    try:
        with store.writer_lock():
            if lock_hook is not None:
                lock_hook()
            archive_root, staging_root = _prepare_store_dirs(store)
            final = archive_root / digest
            if final.exists() or final.is_symlink():
                return _validate_receipt(
                    final,
                    digest,
                    candidate_ids,
                    plan["candidates"],
                    staging_root,
                )
            _recover_staging(staging_root, digest, candidate_ids)
            stage = staging_root / (digest + "-" + secrets.token_hex(8))
            _mkdir_private(stage)
            _publish_file(
                stage / "stage.json",
                _canonical_bytes(
                    {
                        "v": SCHEMA_VERSION,
                        "plan_digest": digest,
                        "candidates": [
                            {
                                "lease_id": lease_id,
                                "generation": generation,
                            }
                            for lease_id, generation in candidate_ids
                        ],
                    }
                ),
            )
            outcomes = []
            archived = held = 0
            try:
                restore_root = stage / "restore"
                _mkdir_private(restore_root)
                for index, candidate in enumerate(plan["candidates"]):
                    candidate_now = _clock_value(now)
                    if candidate_now - plan["created"] >= PLAN_LIFETIME_SECONDS:
                        raise CleanupError("plan_expired")
                    candidate_dir = (
                        stage
                        / candidate["lease_id"]
                        / str(candidate["lease_generation"])
                    )
                    _mkdir_private(
                        stage / candidate["lease_id"]
                    )
                    candidate_binding, reason = _validate_fresh_candidate(
                        invocation,
                        store,
                        candidate,
                        plan["workflow_base"],
                        process_source,
                        provider,
                        external,
                        actual_runner,
                        candidate_now,
                    )
                    if candidate_binding is None:
                        outcomes.append(_outcome(candidate, "held", reason))
                        held += 1
                        continue
                    candidate_restore = restore_root / ("%04d" % index)
                    try:
                        _archive_candidate(
                            candidate_binding,
                            candidate,
                            candidate_dir,
                            candidate_restore,
                        )
                    except CleanupError:
                        raise
                    final_binding, final_reason = _validate_fresh_candidate(
                        invocation,
                        store,
                        candidate,
                        plan["workflow_base"],
                        process_source,
                        provider,
                        external,
                        actual_runner,
                        _clock_value(now),
                    )
                    if final_binding is None:
                        _remove_private_tree(candidate_dir)
                        outcomes.append(
                            _outcome(candidate, "held", final_reason)
                        )
                        held += 1
                    else:
                        outcomes.append(_outcome(candidate, "archived"))
                        archived += 1
                final_now = _clock_value(now)
                if final_now - plan["created"] >= PLAN_LIFETIME_SECONDS:
                    raise CleanupError("plan_expired")
                receipt = {
                    "v": SCHEMA_VERSION,
                    "plan_digest": digest,
                    "created": timestamp,
                    "outcomes": outcomes,
                }
                _publish_file(stage / "receipt.json", _canonical_bytes(receipt))
                _remove_private_tree(restore_root)
                _fsync_directory(stage)
                _fsync_directory(staging_root)
                if publish_hook is not None:
                    publish_hook("before_publish", stage, final)
                try:
                    os.rename(stage, final)
                except OSError as error:
                    if final.exists() and (final / "receipt.json").is_file():
                        return _validate_receipt(
                            final,
                            digest,
                            candidate_ids,
                            plan["candidates"],
                            staging_root,
                        )
                    raise CleanupError("publication_failed") from error
                _fsync_directory(archive_root)
                if publish_hook is not None:
                    publish_hook("after_publish", final, final)
                return ApplyResult(digest, archived, held, False)
            except Exception:
                try:
                    _remove_private_tree(stage)
                except CleanupError:
                    pass
                raise
    except factory_lease.LockBusy as error:
        raise CleanupError("busy") from error


def _parser() -> argparse.ArgumentParser:
    class CountedParser(argparse.ArgumentParser):
        def error(self, message: str) -> None:
            raise CleanupError("arguments_invalid")

    parser = CountedParser(
        description="Plan and digest-apply private archive-only factory cleanup."
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("plan")
    apply_parser = commands.add_parser("apply")
    apply_parser.add_argument("--plan", required=True)
    apply_parser.add_argument("--approve", required=True)
    return parser


def _emit(value: str) -> None:
    sys.stdout.write(value + "\n")


def main(arguments: Optional[Sequence[str]] = None) -> int:
    try:
        args = _parser().parse_args(arguments)
        if args.command == "plan":
            result = plan_cleanup(Path.cwd())
            _emit(
                "result=planned planned=%d held=%d unknown=%d"
                % (result.planned, result.held, result.unknown)
            )
            return 0
        result = apply_cleanup(Path.cwd(), Path(args.plan), args.approve)
        _emit(
            "result=%s archived=%d held=%d"
            % (
                "replay" if result.replay else "published",
                result.archived,
                result.held,
            )
        )
        return 0
    except CleanupError as error:
        sys.stderr.write("result=refused reason=%s\n" % error.reason)
        return 1
    except (
        OSError,
        ValueError,
        UnicodeError,
        factory_lease.LeaseError,
    ):
        sys.stderr.write("result=refused reason=unavailable\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
