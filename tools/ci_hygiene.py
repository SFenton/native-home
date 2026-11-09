#!/usr/bin/env python3
"""Disk hygiene for the CI jobs on the Mac runners (hass-mac on the MacBook, host-mini on the Mac mini; the disk filled overnight on 2026-10-29: simulators 297 GB, DerivedData 142 GB).

    ci_hygiene.py preflight [--min-gb 30] [--path /]      fail early with a clear message when free space is low; first runs the
                                                          reap chain (prune-worktrees, idle simulators, prune-results, orphaned
                                                          DerivedData), rechecking free space after each step
    ci_hygiene.py prune-worktrees [--days 3] [--dry-run]  remove linked worktrees merged into origin/main or the workflow base that
                                                          are clean, unlocked, idle, unheld by devcap, and not the primary,
                                                          current or base-branch worktree; needs the primary clone (--repo,
                                                          FENTON_PRIMARY_REPO or ~/.config/fenton-hass/primary_repo)
    ci_hygiene.py sims-snapshot FILE                     remember the simulators and the time before a run
    ci_hygiene.py sims-clean FILE [--dry-run]            after a run: delete pool simulators devcap's registry (sims.json) says it created during
                                                          the run that this checkout used, and erase this checkout's idle
                                                          simulators (apple/.build/uitest-*.udid); aborts on any unreadable fact
    ci_hygiene.py prune-results [--days 7] [--dry-run]   delete xcresults and nightly logs older than N days
    ci_hygiene.py derived-orphans [--dry-run]            delete ~/Library/Developer/Xcode/DerivedData/FentonHome-* whose info.plist
                                                          WorkspacePath names a project that no longer exists (deleted worktrees)
    ci_hygiene.py rm-dir DIR                              remove a per-job DerivedData directory (only dd-* under the runner's _work)

With FENTON_CI_HOSTED=1 on a GitHub-hosted runner (RUNNER_ENVIRONMENT=github-hosted; tools/ci_hosted.py) every command but rm-dir is a no-op.
Never touches a simulator that is booted or that devcap holds, and deletes nothing it cannot attribute to this run. Stdlib only (macOS system Python 3.9).
"""
from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable, Dict, List, Optional, Set, Tuple

ROOT = Path(__file__).resolve().parents[1]
POOL_NAME = re.compile(r"\(pool \d+\)$")


def free_gb(path: str = "/") -> float:
    override = os.environ.get("HASS_CI_FREE_GB")
    if override:
        return float(override)
    usage = shutil.disk_usage(path)
    return usage.free / 1e9


RUNNER_PLIST = "actions.runner.SFenton-native-home.{name}.plist"


def runner_plist_path(env: Optional[dict] = None) -> Path:
    """The LaunchAgent of the runner running this job: ``RUNNER_NAME`` (``hass-mac``, ``host-mini``), else ``hass-mac``."""
    environment = os.environ if env is None else env
    if environment.get("HASS_RUNNER_PLIST"):
        return Path(environment["HASS_RUNNER_PLIST"])
    name = environment.get("RUNNER_NAME") or "hass-mac"
    return Path.home() / "Library" / "LaunchAgents" / RUNNER_PLIST.format(name=name)


def session_create_warning(plist: Optional[Path] = None, platform: Optional[str] = None,
                           env: Optional[dict] = None) -> Optional[str]:
    """A GitHub ``::warning::`` line when the runner's LaunchAgent has ``SessionCreate`` true, else None.

    Only on macOS under GitHub Actions. With SessionCreate true every job gets a new security session with no access to
    the login Keychain (-25308 in tests, a failed signing probe in ios-release). Warns only; an unreadable plist is silent.
    """
    environment = os.environ if env is None else env
    if (platform or sys.platform) != "darwin" or environment.get("GITHUB_ACTIONS") != "true":
        return None
    try:
        with open(plist or runner_plist_path(environment), "rb") as handle:
            data = plistlib.load(handle)
    except Exception:  # a warning must never fail the job: malformed XML (ExpatError), odd encodings, anything
        return None
    if not isinstance(data, dict) or data.get("SessionCreate") is not True:
        return None
    return ("::warning title=Runner SessionCreate is true::The runner LaunchAgent has SessionCreate = true, so jobs cannot use "
            "the login Keychain. Fix: plutil -replace SessionCreate -bool false <plist>, then launchctl bootout and "
            "launchctl bootstrap gui/$(id -u) <plist> while the runner is idle (svc.sh install resets it). "
            "See .agents/workflow/ci.md, Keychain on the runner.")


def derived_data_root() -> Path:
    return Path(os.environ.get("HASS_DERIVED_DATA") or Path.home() / "Library" / "Developer" / "Xcode" / "DerivedData")


def orphaned_derived_data(root: Optional[Path] = None) -> List[Path]:
    """``FentonHome-*`` folders whose ``info.plist`` ``WorkspacePath`` names a path that no longer exists.

    A folder with no readable ``info.plist``, no ``WorkspacePath`` or whose project still exists is never listed.
    """
    base = root or derived_data_root()
    found: List[Path] = []
    for folder in sorted(base.glob("FentonHome-*")):
        try:
            with open(folder / "info.plist", "rb") as handle:
                workspace = plistlib.load(handle).get("WorkspacePath")
        except Exception:  # unreadable or malformed: not provably an orphan
            continue
        if folder.is_dir() and isinstance(workspace, str) and workspace and _missing(workspace):
            found.append(folder)
    return found


def _missing(path: str) -> bool:
    """True only when ``path`` is certainly gone (FileNotFoundError); a permission error or unmounted volume keeps the folder."""
    try:
        os.stat(path)
    except FileNotFoundError:
        return True
    except OSError:
        return False
    return False


def clean_derived_orphans(dry: bool = False, root: Optional[Path] = None) -> int:
    """Delete the orphaned DerivedData folders (Xcode leaves them behind when a worktree is deleted); returns how many."""
    count = 0
    for folder in orphaned_derived_data(root):
        print("%s orphaned DerivedData %s" % ("would delete" if dry else "delete", folder.name))
        if not dry:
            shutil.rmtree(folder, ignore_errors=True)
        count += 1
    return count


def preflight(min_gb: float, path: str = "/") -> int:
    """Check free space; when short, run the reap chain and recheck after each step before failing.

    The orphaned-DerivedData sweep always runs (cheap, provably safe). Only when free space is under ``min_gb`` do the heavier
    steps run, in order: ``prune-worktrees``, ``clean-sims`` (idle simulators), ``prune-results``, then the DerivedData
    orphans again. Each step reports the GB it freed; the job fails only if space is still short after the last one.
    """
    clean_derived_orphans()
    warning = session_create_warning()
    if warning:
        print(warning)
    free = free_gb(path)
    if free < min_gb:
        print("free space %.0f GB on %s is under %.0f GB: reaping" % (free, path, min_gb))
        for name, step in reap_steps():
            before = free
            try:
                step()
            except Exception as exc:  # a failing step must not stop the next one
                print("reap step %s failed: %s" % (name, exc), file=sys.stderr)
            free = free_gb(path)
            print("reap %s: freed %.1f GB (%.0f GB free)" % (name, max(free - before, 0.0), free))
            if free >= min_gb:
                break
    if free < min_gb:
        print("ERROR: only %.0f GB free on %s (need %.0f GB). CI stopped before it could fill the disk.\n"
              "The reap chain already ran (merged worktrees, idle simulators, old results, orphaned DerivedData). Still short: "
              "`xcrun simctl delete unavailable`, remove ~/Library/Developer/Xcode/DerivedData, erase big devices "
              "in ~/Library/Developer/CoreSimulator/Devices (du -sh * | sort -h), then re-run the job. "
              "See .agents/workflow/ci.md (disk hygiene)." % (free, path, min_gb), file=sys.stderr)
        return 1
    print("disk ok: %.0f GB free on %s" % (free, path))
    return 0


def reap_steps() -> List[Tuple[str, Callable[[], object]]]:
    """The reap chain in order, each a no-argument callable (tests replace this)."""
    return [("prune-worktrees", lambda: prune_worktrees(3, False)),
            ("clean-sims", lambda: clean_idle_sims(False)),
            ("prune-results", lambda: prune_results(7, False)),
            ("derived-orphans", lambda: clean_derived_orphans())]


class HygieneError(RuntimeError):
    """Something needed to decide safely could not be read: the caller deletes nothing."""


def simulators() -> List[dict]:
    out = subprocess.run(["xcrun", "simctl", "list", "devices", "-j"], capture_output=True, text=True)
    if out.returncode != 0:
        raise HygieneError("simctl list failed: " + (out.stderr or "").strip()[:200])
    try:
        listing = json.loads(out.stdout).get("devices", {})
    except ValueError as exc:
        raise HygieneError("simctl list printed no JSON") from exc
    found = []
    for runtime, devices in listing.items():
        for device in devices:
            found.append({"udid": device["udid"].upper(), "name": device["name"], "state": device.get("state", ""),
                          "runtime": runtime})
    return found


def devcap_root() -> Path:
    return Path(os.environ.get("DEVCAP_DIR") or Path.home() / ".devcap")


def devcap_gates() -> List[dict]:
    """Every devcap gate as ``{"gate", "holders": [{"pid", "cwd"}], "waiting"}``, read straight from the gate folders under
    :func:`devcap_root` (a slot is held when its ``slot-N.lock`` cannot be locked; ``slot-N.json`` names the holder; any ticket in
    ``queue/`` counts as a waiter), without importing or running ``tools/devcap.py``. Raises :class:`HygieneError` when the
    root or a lock cannot be read."""
    import fcntl
    root = devcap_root()
    if not root.is_dir():
        raise HygieneError("devcap root %s is not a directory" % root)
    gates: List[dict] = []
    try:
        for folder in sorted(p for p in root.iterdir() if p.is_dir() and p.name not in ("lib", "bin")):
            holders: List[dict] = []
            for lock in sorted(folder.glob("slot-*.lock")):
                with open(lock, "rb") as handle:
                    try:
                        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    except OSError:
                        try:
                            record = json.loads(lock.with_suffix(".json").read_text(encoding="utf-8"))
                        except (OSError, ValueError):
                            record = {}
                        holders.append(record if isinstance(record, dict) else {})
                        continue
                    fcntl.flock(handle, fcntl.LOCK_UN)
            queue = folder / "queue"
            gates.append({"gate": folder.name, "holders": holders, "waiting": queue.is_dir() and any(queue.iterdir())})
    except OSError as exc:
        raise HygieneError("devcap state unreadable: %s" % exc) from exc
    return gates


def held_udids() -> Set[str]:
    """UDIDs whose devcap device gate has a holder or a waiter. Raises when the devcap state cannot be read."""
    held: Set[str] = set()
    for gate in devcap_gates():
        name = str(gate["gate"])
        if name.startswith("device-") and (gate["holders"] or gate["waiting"]):
            held.add(name[len("device-"):].upper())
    return held


def devcap_registry() -> Dict[str, dict]:
    """devcap's reaper registry (``sims.json`` under :func:`devcap_root`, UDID to record) that ``create_sim`` writes for every simulator
    it makes: ``kind`` (``pool`` or ``ephemeral``), ``project`` and ``created_epoch``. A missing file is empty (nothing is attributable);
    an unreadable or malformed one raises :class:`HygieneError`."""
    path = devcap_root() / "sims.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except (OSError, ValueError) as exc:
        raise HygieneError("devcap registry %s unreadable: %s" % (path, exc)) from exc
    if not isinstance(data, dict):
        raise HygieneError("devcap registry %s is not an object" % path)
    return {str(k).upper(): v for k, v in data.items() if isinstance(v, dict)}


def created_since(epoch: float) -> Set[str]:
    """UDIDs the registry says devcap created (kind pool or ephemeral) at or after ``epoch`` (seconds since the Unix epoch).
    A record without a numeric ``created_epoch`` is not attributable and is left out."""
    found: Set[str] = set()
    for udid, record in devcap_registry().items():
        stamp = record.get("created_epoch")
        if record.get("kind") in ("pool", "ephemeral") and isinstance(stamp, (int, float)) and stamp >= epoch:
            found.add(udid)
    return found


def snapshot(file: Path) -> int:
    """Remember the simulators and the time before a run (the registry's ``created_epoch`` is compared to it). Writes nothing when `simctl list` fails."""
    try:
        sims = simulators()
    except HygieneError as exc:
        print("ERROR: no snapshot: %s" % exc, file=sys.stderr)
        return 1
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(json.dumps({"udids": sorted(s["udid"] for s in sims), "epoch": time.time()}))
    print("snapshot: %d simulators" % len(sims))
    return 0


def own_udids(root: Path) -> Set[str]:
    """The simulators this checkout's journeys ran on (apple/.build/uitest-*.udid)."""
    return {p.read_text().strip().upper() for p in (root / "apple" / ".build").glob("uitest-*.udid")}


def sims_to_remove(sims: List[dict], before: Set[str], created: Set[str], mine: Set[str], held: Set[str]) -> List[dict]:
    """Pool simulators that did not exist before the run, that the registry says devcap created during it, that this
    checkout used, and that are shut down and not held."""
    return [s for s in sims if s["udid"] not in before and s["udid"] in created and s["udid"] in mine
            and POOL_NAME.search(s["name"]) and s["state"] == "Shutdown" and s["udid"] not in held]


def sims_to_erase(sims: List[dict], mine: Set[str], held: Set[str]) -> List[dict]:
    """This checkout's own simulators that are shut down and not held."""
    return [s for s in sims if s["udid"] in mine and s["state"] == "Shutdown" and s["udid"] not in held]


def clean_sims(file: Path, dry: bool, root: Path = ROOT) -> int:
    """Delete what this run created and erase what this checkout used. Any failure to read the facts aborts it all."""
    try:
        recorded = json.loads(file.read_text())
        before = {u.upper() for u in recorded["udids"]}
        epoch = float(recorded["epoch"])
        sims = simulators()
        held = held_udids()
        created = created_since(epoch)
    except (OSError, ValueError, KeyError, HygieneError) as exc:
        print("ERROR: not touching any simulator: %s" % exc, file=sys.stderr)
        return 1
    mine = own_udids(root)
    for sim in sims_to_remove(sims, before, created, mine, held):
        print("delete %s (%s)" % (sim["name"], sim["udid"]))
        if not dry:
            subprocess.run(["xcrun", "simctl", "delete", sim["udid"]], capture_output=True)
    gone = {s["udid"] for s in sims_to_remove(sims, before, created, mine, held)}
    for sim in sims_to_erase([s for s in sims if s["udid"] not in gone], mine, held):
        print("erase %s (%s)" % (sim["name"], sim["udid"]))
        if not dry:
            subprocess.run(["xcrun", "simctl", "erase", sim["udid"]], capture_output=True)
    return 0


def project_members() -> Set[str]:
    """UDIDs ``~/.devcap/sims.json`` tags as this project's pool or job simulators (devcap 1.5.0 and later).

    The state file is shared with FestivalNativeApps, so an untagged legacy simulator and the other
    project's members are not in the set. An unresolvable project or unreadable file gives an empty set.
    """
    import importlib.util
    spec = importlib.util.spec_from_file_location("hass_devcap_tag", Path(__file__).with_name("devcap.py"))
    if spec is None or spec.loader is None:
        return set()
    os.environ.setdefault("DEVCAP_NO_DEFER", "1")  # only the tag helpers are used: never run a shared install
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module  # dataclasses look their module up here
    try:
        spec.loader.exec_module(module)
        tag = module.project_tag()
        state = module.load_sims_state()
    except Exception:
        return set()
    finally:
        sys.modules.pop(spec.name, None)
    if tag == module.UNKNOWN_PROJECT:
        return set()
    return {udid.upper() for udid, rec in state.items()
            if rec.get("project") == tag and rec.get("kind") in ("pool", "ephemeral")}


def idle_sims(sims: List[dict], held: Set[str], created: Set[str]) -> List[dict]:
    """Pool simulators (``(pool N)``) that the registry names as created by devcap, that are shut down and that devcap does not hold or await."""
    return [s for s in sims if s["state"] == "Shutdown" and s["udid"] not in held and s["udid"] in created
            and POOL_NAME.search(s["name"])]


def clean_idle_sims(dry: bool) -> int:
    """Delete idle pool simulators devcap created (``pick-sim`` recreates them). Never erases or touches a simulator it does not own:
    not a booted or held one, not a non-pool one, not one devcap's registry does not name. Touches nothing when ``simctl``,
    devcap's status or its registry cannot be read."""
    try:
        sims = simulators()
        held = held_udids()
        created = project_members()  # the registry's pool and ephemeral records tagged as this project's, never legacy or the other repo's
    except HygieneError as exc:
        print("ERROR: not touching any simulator: %s" % exc, file=sys.stderr)
        return 1
    for sim in idle_sims(sims, held, created):
        print("%sdelete %s (%s)" % ("would " if dry else "", sim["name"], sim["udid"]))
        if not dry:
            subprocess.run(["xcrun", "simctl", "delete", sim["udid"]], capture_output=True)
    return 0


def _git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    env = {k: v for k, v in os.environ.items() if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR")}
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, env=env)


PRIMARY_REPO_FILE = Path.home() / ".config" / "fenton-hass" / "primary_repo"


def _norm_url(url: str) -> str:
    url = url.strip().lower()
    url = re.sub(r"^(git@|ssh://git@|https?://)", "", url)
    return re.sub(r"\.git$", "", url.replace(":", "/", 1) if "://" not in url and ":" in url.split("/")[0] else url).rstrip("/")


def validate_primary(path: Path, expected_origin: Optional[str] = None) -> Optional[str]:
    """None when ``path`` is a primary (not linked) clone of this repo, else why not."""
    if not path.is_dir():
        return "%s is not a directory" % path
    git_dir = _git(path, "rev-parse", "--path-format=absolute", "--git-dir")
    common = _git(path, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if git_dir.returncode != 0 or common.returncode != 0:
        return "%s is not a git checkout" % path
    if os.path.realpath(git_dir.stdout.strip()) != os.path.realpath(common.stdout.strip()):
        return "%s is a linked worktree, not the primary clone" % path
    expected = expected_origin if expected_origin is not None else _git(ROOT, "remote", "get-url", "origin").stdout
    actual = _git(path, "remote", "get-url", "origin").stdout
    if not expected.strip() or _norm_url(actual) != _norm_url(expected):
        return "%s has origin %r, not this repo's %r" % (path, actual.strip(), expected.strip())
    return None


def resolve_primary_repo(arg: Optional[str] = None, env: Optional[dict] = None, config: Optional[Path] = None,
                         expected_origin: Optional[str] = None) -> Tuple[Optional[Path], str]:
    """The primary clone to prune: ``--repo``, else ``FENTON_PRIMARY_REPO``, else the one line in ``~/.config/fenton-hass/primary_repo``.

    Returns ``(path, "")`` or ``(None, why)``. A runner's own clone has no linked worktrees, so nothing is guessed.
    """
    environment = os.environ if env is None else env
    candidate = arg or environment.get("FENTON_PRIMARY_REPO")
    if not candidate:
        try:
            candidate = (config or PRIMARY_REPO_FILE).read_text().strip().splitlines()[0].strip()
        except (OSError, IndexError):
            candidate = ""
    if not candidate:
        return None, ("no primary clone configured: pass --repo PATH, set FENTON_PRIMARY_REPO, or put the path of the primary clone "
                      "on one line in ~/.config/fenton-hass/primary_repo")
    path = Path(candidate).expanduser()
    why = validate_primary(path, expected_origin)
    return (None, why) if why else (path, "")


def list_worktrees(repo: Path) -> List[dict]:
    """``git worktree list --porcelain`` as dicts (``path``, ``head``, ``branch`` or '', ``locked``, ``prunable``); the first is the primary."""
    out = _git(repo, "worktree", "list", "--porcelain")
    if out.returncode != 0:
        raise HygieneError("git worktree list failed: " + (out.stderr or "").strip()[:200])
    trees: List[dict] = []
    for block in out.stdout.strip().split("\n\n"):
        entry = {"path": "", "head": "", "branch": "", "locked": False, "prunable": False}
        for line in block.splitlines():
            key, _, value = line.partition(" ")
            if key == "worktree":
                entry["path"] = value
            elif key == "HEAD":
                entry["head"] = value
            elif key == "branch":
                entry["branch"] = value[len("refs/heads/"):] if value.startswith("refs/heads/") else value
            elif key == "locked":
                entry["locked"] = True
            elif key == "prunable":
                entry["prunable"] = True
        if entry["path"]:
            trees.append(entry)
    return trees


def workflow_base(root: Path = ROOT) -> str:
    """``workflow_base`` from ``tools/triage/config.json`` (default ``main``)."""
    try:
        return str(json.loads((root / "tools" / "triage" / "config.json").read_text()).get("workflow_base") or "main")
    except (OSError, ValueError):
        return "main"


def devcap_cwds() -> List[str]:
    """Working directories of every devcap holder in any gate. Raises when the devcap state cannot be read."""
    return [str(h["cwd"]) for g in devcap_gates() for h in g["holders"] if h.get("cwd")]


def _under(path: str, parent: str) -> bool:
    child, base = os.path.realpath(path), os.path.realpath(parent)
    return child == base or child.startswith(base.rstrip(os.sep) + os.sep)


def _is_merged(repo: Path, sha: str, bases: List[str]) -> bool:
    """True when ``sha`` is an ancestor of a base ref, or every commit it adds is patch-equivalent to one already there."""
    for base in bases:
        if _git(repo, "merge-base", "--is-ancestor", sha, base).returncode == 0:
            return True
        cherry = _git(repo, "cherry", base, sha)
        if cherry.returncode == 0 and not any(line.startswith("+") for line in cherry.stdout.splitlines()):
            return True
        # pr_land squash-merges: the branch's commits are not in the base, but merging it changes nothing.
        merged = _git(repo, "merge-tree", "--write-tree", base, sha)
        want = _git(repo, "rev-parse", base + "^{tree}")
        if merged.returncode == 0 and want.returncode == 0 and merged.stdout.split("\n")[0].strip() == want.stdout.strip():
            return True
    return False


def _last_activity(tree: dict) -> float:
    """Newest mtime of the worktree directory, its HEAD and its index (a lane in use touches these)."""
    gitfile = Path(tree["path"]) / ".git"
    times = []
    try:
        times.append(Path(tree["path"]).stat().st_mtime)
        if gitfile.is_file():
            gitdir = Path(gitfile.read_text().split(":", 1)[1].strip())
            for name in ("HEAD", "index"):
                if (gitdir / name).exists():
                    times.append((gitdir / name).stat().st_mtime)
    except (OSError, IndexError):
        return time.time()  # unknown: treat as just used
    return max(times)


def prunable_worktrees(repo: Path, days: float, current: Optional[Path] = None, held_cwds: Optional[List[str]] = None,
                       protected_branches: Optional[Set[str]] = None) -> List[dict]:
    """The linked worktrees that are safe to remove.

    Safe means all of: not the primary (first listed) or the current worktree, not on ``main`` or the workflow base, unlocked, no
    devcap holder working inside it, idle for ``days``, a clean tree (no modified or untracked files), and its HEAD merged into
    ``origin/main`` or ``origin/<workflow base>``. Anything that cannot be read keeps the worktree.
    """
    trees = list_worktrees(repo)
    names = protected_branches if protected_branches is not None else {"main", workflow_base(repo)}
    refs = [r for r in ("origin/" + n for n in sorted(names)) if _git(repo, "rev-parse", "--verify", "--quiet", r).returncode == 0]
    held = held_cwds if held_cwds is not None else devcap_cwds()
    here = current or Path.cwd()
    cutoff = time.time() - days * 86400
    found: List[dict] = []
    for tree in trees[1:]:
        path = tree["path"]
        if tree["locked"] or tree["branch"] in names or _under(str(here), path) or any(_under(c, path) for c in held):
            continue
        if not Path(path).is_dir() or not refs or not tree["head"] or _last_activity(tree) >= cutoff:
            continue
        if list((Path(path) / "build" / "handoff").glob("*.md")):
            continue  # a session's hand-off note is unfinished work
        status = _git(Path(path), "status", "--porcelain", "--untracked-files=all")
        if status.returncode != 0 or status.stdout.strip():
            continue
        if _is_merged(repo, tree["head"], refs):
            found.append(tree)
    return found


def live_process_cwds() -> List[str]:
    """Working directories of every process ``lsof`` can see. Raises :class:`HygieneError` when they cannot be read."""
    proc = subprocess.run(["lsof", "-d", "cwd", "-Fn"], capture_output=True, text=True)
    paths = [line[1:] for line in proc.stdout.splitlines() if line.startswith("n/")]
    if not paths:
        raise HygieneError("lsof listed no working directories: " + (proc.stderr or "").strip()[:200])
    return paths


def reap_blocker(tree: dict, merged_sha: str, repo: Path, held: List[str], live: List[str],
                 here: Optional[Path] = None, protected: Optional[Set[str]] = None) -> str:
    """Why a just-merged lane's worktree must stay, or '' when it can go.

    The protections of :func:`prunable_worktrees` without its idle-days wait (a merge just happened): not locked, not on
    ``main`` or the workflow base, no devcap holder or live process with its cwd inside it (nor the caller), no hand-off note,
    a clean tree with no untracked files, and nothing unpushed (its HEAD is ``merged_sha`` or an ancestor of it).
    """
    path = tree["path"]
    names = protected if protected is not None else {"main", workflow_base(repo)}
    if tree["locked"]:
        return "locked"
    if tree["branch"] in names:
        return "base branch"
    if not Path(path).is_dir():
        return "directory missing"
    if _under(str(here or Path.cwd()), path):
        return "the caller is inside it"
    if any(_under(c, path) for c in held):
        return "a devcap hold works inside it"
    if any(_under(c, path) for c in live):
        return "a live process has its cwd inside it"
    if list((Path(path) / "build" / "handoff").glob("*.md")):
        return "a hand-off note is unfinished work"
    status = _git(Path(path), "status", "--porcelain", "--untracked-files=all")
    if status.returncode != 0:
        return "git status failed"
    if status.stdout.strip():
        return "uncommitted or untracked files"
    if not tree["head"] or _git(repo, "merge-base", "--is-ancestor", tree["head"], merged_sha).returncode != 0:
        return "commits that are not in the merged %s" % merged_sha[:8]
    return ""


def reap_merged_branch(repo: Path, branch: str, merged_sha: str, here: Optional[Path] = None,
                       held: Optional[List[str]] = None, live: Optional[List[str]] = None) -> List[str]:
    """After ``branch`` merged at ``merged_sha``: remove its worktree(s) and local branch when :func:`reap_blocker` allows it.

    Returns one log line per decision (removed or kept, with the reason). The caller deletes the remote branch. Raises
    :class:`HygieneError` only before anything is touched (devcap, lsof or git unreadable); a worktree git itself refuses to
    remove (no ``--force``) is kept and logged.
    """
    trees = list_worktrees(repo)
    primary = trees[0] if trees else None
    if primary is not None and primary["branch"] == branch:
        return ["kept branch %s: checked out in the primary clone %s" % (branch, primary["path"])]
    mine = [t for t in trees[1:] if t["branch"] == branch]
    held_now: List[str] = []
    live_now: List[str] = []
    if mine:
        held_now = held if held is not None else devcap_cwds()
        live_now = live if live is not None else live_process_cwds()
    lines: List[str] = []
    for tree in mine:
        why = reap_blocker(tree, merged_sha, repo, held_now, live_now, here)
        if why:
            lines.append("kept worktree %s: %s" % (tree["path"], why))
            continue
        result = _git(repo, "worktree", "remove", tree["path"])
        if result.returncode == 0:
            lines.append("removed worktree %s" % tree["path"])
        else:
            lines.append("kept worktree %s: %s" % (tree["path"], (result.stderr or "").strip()[:120]))
    _git(repo, "worktree", "prune")
    if _git(repo, "rev-parse", "--verify", "--quiet", "refs/heads/" + branch).returncode != 0:
        return lines
    still = [t for t in list_worktrees(repo) if t["branch"] == branch]
    if still:
        return lines + ["kept branch %s: still checked out in %s" % (branch, still[0]["path"])]
    tip = _git(repo, "rev-parse", "refs/heads/" + branch).stdout.strip()
    if _git(repo, "merge-base", "--is-ancestor", tip, merged_sha).returncode != 0:
        return lines + ["kept branch %s: local tip %s is not in the merged %s" % (branch, tip[:8], merged_sha[:8])]
    deleted = _git(repo, "branch", "-D", branch)
    return lines + (["deleted local branch %s" % branch] if deleted.returncode == 0
                    else ["kept branch %s: %s" % (branch, (deleted.stderr or "").strip()[:120])])


def prune_worktrees(days: float, dry: bool, repo: Optional[Path] = None, current: Optional[Path] = None) -> int:
    """Remove merged, clean, idle, unlocked, unheld linked worktrees, then ``git worktree prune``. Removes nothing when devcap or git cannot be read."""
    if repo is None:
        repo, why = resolve_primary_repo()
        if repo is None:
            print("prune-worktrees skipped: %s" % why)
            return 0
    try:
        victims = prunable_worktrees(repo, days, current)
    except HygieneError as exc:
        print("ERROR: not removing any worktree: %s" % exc, file=sys.stderr)
        return 1
    removed = 0
    for tree in victims:
        label = tree["branch"] or tree["head"][:8]
        print("%s worktree %s (%s)" % ("would remove" if dry else "remove", tree["path"], label))
        if dry:
            removed += 1
            continue
        # No --force: git itself refuses a dirty or locked tree, a second guard behind the checks above.
        result = _git(repo, "worktree", "remove", tree["path"])
        if result.returncode == 0:
            removed += 1
        else:
            print("kept %s: %s" % (tree["path"], (result.stderr or "").strip()[:160]), file=sys.stderr)
    if not dry:
        _git(repo, "worktree", "prune")
    print("%s %d worktree(s)" % ("would remove" if dry else "removed", removed))
    return 0


def prune_results(days: float, dry: bool, root: Path = ROOT) -> int:
    cutoff = time.time() - days * 86400
    targets = list((root / "apple" / ".build").glob("uitest-*.xcresult")) + list((root / "build" / "nightly").glob("*")) \
        + list((root / "build" / "runs").glob("*"))
    removed = 0
    for path in targets:
        try:
            if path.stat().st_mtime >= cutoff:
                continue
        except OSError:
            continue
        print("prune %s" % path)
        removed += 1
        if not dry:
            shutil.rmtree(path, ignore_errors=True) if path.is_dir() else path.unlink()
    print("pruned %d item(s) older than %g days" % (removed, days))
    return 0


def rm_dir(directory: str) -> int:
    path = Path(directory).resolve()
    if "_work" not in path.parts or not path.name.startswith("dd-"):
        print("refusing to remove %s: only a dd-* directory under _work" % path, file=sys.stderr)
        return 1
    shutil.rmtree(path, ignore_errors=True)
    print("removed %s" % path)
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    if os.getenv("FENTON_CI_HOSTED") == "1" and os.getenv("RUNNER_ENVIRONMENT") == "github-hosted" and (sys.argv[1:] if argv is None else argv)[:1] != ["rm-dir"]:
        # A hosted runner is a fresh VM per job (tools/ci_hosted.py): no disk to guard, no pool simulators or worktrees to reap.
        print("ci_hygiene: FENTON_CI_HOSTED=1, nothing to clean on a hosted runner")
        return 0
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("preflight")
    p.add_argument("--min-gb", type=float, default=30)
    p.add_argument("--path", default="/")
    p = sub.add_parser("sims-snapshot")
    p.add_argument("file")
    p = sub.add_parser("sims-clean")
    p.add_argument("file")
    p.add_argument("--dry-run", action="store_true")
    p = sub.add_parser("prune-results")
    p.add_argument("--days", type=float, default=7)
    p.add_argument("--dry-run", action="store_true")
    p = sub.add_parser("prune-worktrees")
    p.add_argument("--repo", help="the primary clone (else FENTON_PRIMARY_REPO, else ~/.config/fenton-hass/primary_repo)")
    p.add_argument("--days", type=float, default=3)
    p.add_argument("--dry-run", action="store_true")
    p = sub.add_parser("derived-orphans")
    p.add_argument("--dry-run", action="store_true")
    p = sub.add_parser("rm-dir")
    p.add_argument("dir")
    args = parser.parse_args(argv)
    if args.cmd == "preflight":
        return preflight(args.min_gb, args.path)
    if args.cmd == "sims-snapshot":
        return snapshot(Path(args.file))
    if args.cmd == "sims-clean":
        return clean_sims(Path(args.file), args.dry_run)
    if args.cmd == "prune-results":
        return prune_results(args.days, args.dry_run)
    if args.cmd == "prune-worktrees":
        repo, why = resolve_primary_repo(args.repo)
        if repo is None:
            print("prune-worktrees skipped: %s" % why, file=sys.stderr if args.repo else sys.stdout)
            return 1 if args.repo else 0
        return prune_worktrees(args.days, args.dry_run, repo)
    if args.cmd == "derived-orphans":
        print("%d orphaned folder(s)" % clean_derived_orphans(args.dry_run))
        return 0
    return rm_dir(args.dir)


if __name__ == "__main__":
    sys.exit(main())
