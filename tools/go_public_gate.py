#!/usr/bin/env python3
"""Hard gates before a snapshot of this repository becomes a public repository (owner, 2026-11-07).

    python3 tools/go_public_gate.py SNAPSHOT_DIR [--base-ref origin/main]

Agents may create a new repository, push a clean snapshot and make it public themselves, but only through ``tools/go_public.sh``,
which runs this gate first (``merge_guard`` refuses every other way of going public). The repository stays private if any gate fails:

1. **History.** The snapshot is a git repository with exactly one commit (an orphan snapshot: no history to hide a term in), one branch,
   no tags, no other refs, a clean working tree and no submodules; its commit author and committer are exactly ``S+H <noreply@example.com>``
   and it has no remote (a hand-built snapshot cannot leak an identity).
2. **House scan.** ``tools/house_scan.py`` reports 0 hits on the snapshot, judged by the **trusted base config** (``contracts/house_scan.json``
   read from ``--base-ref`` of this repository, with its ``skip_prefixes`` and recorded debt removed). The snapshot's own copy is never read:
   its ``skip_prefixes`` and allowlists cannot hide a hit.
3. **Denylist.** The local denylist is loaded with **at least 20 terms** (the env override, the config-folder list or the ``~/hass-agents`` list;
   the owner approved the agent-built list, 2026-11-07) and has 0 hits in **every file type** (``.plist``, ``.svg`` and the rest).
4. **Paths and commit text.** Every file path and the commit's message, author and committer name and email get the same denylist and
   house_scan rules as file contents. Files over 50 MB, which cannot be scanned, are refused; UTF-16 text is scanned too.
5. **gitleaks** finds nothing in the snapshot's files nor in its history.

The gate prints counts and the denylist's source (``env``, ``config`` or ``agents``) only, never a matched value and never the list's contents.
Exit 0 when every gate passes, 1 when one finds something, 3 when the denylist is not loaded or too short, 2 on a usage or tool error
(fails closed).

Standard library only. Documentation: .agents/workflow/pr-lifecycle.md ("Going public").
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import List, Optional, Tuple

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
EXIT_FOUND, EXIT_ERROR, EXIT_NO_DENYLIST = 1, 2, 3
MIN_TERMS = 20
NEUTRAL_IDENTITY = "S+H <noreply@example.com>"
#: The only keys ``git init`` writes to ``.git/config``; anything else (``url.*.insteadOf``, ``credential.*``, ``remote.*``, ``include*``) would apply to the push.
INIT_CONFIG_KEYS = {"core.repositoryformatversion", "core.filemode", "core.bare", "core.logallrefupdates", "core.ignorecase", "core.precomposeunicode"}
SUMMARY = re.compile(r"house_scan: (\d+) hit\(s\);.*\(local denylist (on|off)\)")
DENYLIST_LINE = re.compile(r"house_scan: denylist loaded, (\d+) hit\(s\)")
SOURCE_LINE = re.compile(r"house_scan: denylist source (\w+), (\d+) term\(s\)")


def git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    """git with hooks, fsmonitor and ssh overridden: the snapshot is never trusted."""
    return subprocess.run(["git", "-C", str(repo), "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false",
                           "-c", "core.sshCommand=ssh", *args], capture_output=True, text=True)


def trusted_config(base_ref: str, repo: Path = REPO) -> Optional[dict]:
    """``contracts/house_scan.json`` of ``base_ref`` in the tool repository (not the snapshot), or ``None`` when git cannot read it."""
    proc = git(repo, "show", f"{base_ref}:contracts/house_scan.json")
    if proc.returncode:
        return None
    try:
        data = json.loads(proc.stdout)
    except ValueError:
        return None
    return data if isinstance(data, dict) else None


def strict_config(data: dict) -> dict:
    """The trusted config with nothing hidden: no ``skip_prefixes``, no recorded debt (a public repository has no debt)."""
    allow = {k: v for k, v in (data.get("allow") or {}).items() if k != "skip_prefixes"}
    return {**{k: v for k, v in data.items() if k not in ("debt", "allow")}, "allow": allow, "debt": []}


def history_gate(snapshot: Path) -> Tuple[int, str]:
    """``(exit code, message)``: the snapshot is one orphan commit, nothing else in its object graph, and clean."""
    if not (snapshot / ".git").exists() or git(snapshot, "rev-parse", "--git-dir").returncode:
        return EXIT_ERROR, "history: the snapshot is not a git repository (fails closed)"
    if git(snapshot, "rev-parse", "--verify", "-q", "HEAD").returncode:
        return EXIT_ERROR, "history: the snapshot has no commit (fails closed)"
    count = git(snapshot, "rev-list", "--all", "--count")
    refs = git(snapshot, "for-each-ref", "--format=%(refname)")
    if count.returncode or refs.returncode:
        return EXIT_ERROR, "history: git could not list the snapshot's commits (fails closed)"
    commits = int(count.stdout.strip() or 0)
    parents = git(snapshot, "rev-list", "--parents", "-n", "1", "HEAD").stdout.split()
    if commits != 1 or len(parents) != 1:
        return EXIT_FOUND, f"history: the snapshot has {commits} commit(s) reachable (need exactly 1 orphan commit)"
    if len([r for r in refs.stdout.split() if r]) != 1:
        return EXIT_FOUND, "history: the snapshot has more than one ref (one branch, no tags or stashes)"
    status = git(snapshot, "status", "--porcelain", "--untracked-files=all")
    if status.returncode or status.stdout.strip():
        return EXIT_FOUND, "history: the snapshot's working tree is not clean (what is scanned must be what is committed)"
    if (snapshot / ".gitmodules").exists():
        return EXIT_FOUND, "history: the snapshot has submodules"
    return 0, "history: 1 orphan commit, 1 ref, clean tree"


def identity_gate(snapshot: Path) -> Tuple[int, str]:
    """``(exit code, message)``: the commit's author and committer are exactly ``S+H <noreply@example.com>`` and the snapshot has 0 remotes,
    so a hand-built snapshot cannot carry a real identity or a remote. Counts only."""
    who = git(snapshot, "log", "-1", "--format=%an <%ae>%n%cn <%ce>")
    remotes = git(snapshot, "remote")
    configured = git(snapshot, "config", "--local", "--get-regexp", r"^remote\.")
    if who.returncode or remotes.returncode:
        return EXIT_ERROR, "identity: git could not read the commit or remotes (fails closed)"
    raw = git(snapshot, "cat-file", "commit", "HEAD")
    keys = git(snapshot, "config", "--local", "--name-only", "--list")
    if raw.returncode or keys.returncode not in (0, 1):
        return EXIT_ERROR, "identity: git could not read the commit object or config (fails closed)"
    headers = [line.split(" ", 1)[0] for line in raw.stdout.split("\n\n", 1)[0].split("\n") if not line.startswith(" ")]
    if headers != ["tree", "author", "committer"]:
        return EXIT_FOUND, "identity: the commit has extra headers or a parent (only tree, author and committer are allowed)"
    extra = [k for k in keys.stdout.split() if k.lower() not in INIT_CONFIG_KEYS]
    if extra:
        return EXIT_FOUND, f"identity: .git/config has {len(extra)} key(s) beyond what git init writes"
    if who.stdout.split("\n")[:2] != [NEUTRAL_IDENTITY] * 2:
        return EXIT_FOUND, "identity: the commit author and committer must both be S+H <noreply@example.com>"
    if remotes.stdout.strip() or configured.stdout.strip():
        return EXIT_FOUND, "identity: the snapshot has a remote (need 0)"
    return 0, "identity: neutral author and committer, 0 remotes"


def house_scan_gate(snapshot: Path, config: Path, tool: Path = HERE / "house_scan.py", min_terms: int = MIN_TERMS) -> Tuple[int, str]:
    """``(exit code, message)`` for the house_scan gates: counts and the denylist source only. ``config`` is the trusted, strict config."""
    proc = subprocess.run([sys.executable, str(tool), "report", "--root", str(snapshot), "--config", str(config)], capture_output=True, text=True)
    summary = SUMMARY.search(proc.stdout)
    if proc.returncode or not summary:
        return EXIT_ERROR, "house_scan failed to run on the snapshot (fails closed)"
    hits, state = int(summary.group(1)), summary.group(2)
    if state != "on":
        return EXIT_NO_DENYLIST, "house_scan: local denylist off, refusing (set HOUSE_SCAN_DENYLIST or create the list)"
    deny = subprocess.run([sys.executable, str(tool), "denylist", "--root", str(snapshot), "--config", str(config), "--mode", "all",
                           "--min-terms", str(min_terms), "--required", "true"], capture_output=True, text=True)
    source = SOURCE_LINE.search(deny.stdout)
    label = f"denylist source {source.group(1)}, {source.group(2)} term(s)" if source else "denylist source unknown"
    if deny.returncode == EXIT_NO_DENYLIST:
        return EXIT_NO_DENYLIST, f"house_scan: {label}; need at least {min_terms} terms (refusing)"
    denied = DENYLIST_LINE.search(deny.stdout)
    if not denied:
        return EXIT_ERROR, "house_scan did not report denylist hits (fails closed)"
    denylist_hits = int(denied.group(1))
    if hits or denylist_hits or deny.returncode:
        return EXIT_FOUND, f"house_scan: {hits} hit(s); {label}, {denylist_hits} denylist hit(s) in every file type"
    return 0, f"house_scan: 0 hits; {label}, 0 denylist hits in every file type"


def metadata_gate(snapshot: Path, config: Path, min_terms: int = MIN_TERMS) -> Tuple[int, str]:
    """``(exit code, message)``: every file path (directory and file names) and the snapshot commit's message, author and committer
    (name and email) are judged by the denylist and the house_scan rules, the same as file contents. Counts only."""
    sys.path.insert(0, str(HERE))
    import house_scan
    paths = git(snapshot, "ls-files", "-z")
    meta = git(snapshot, "log", "-1", "--format=%B%n%an%n%ae%n%cn%n%ce")
    if paths.returncode or meta.returncode:
        return EXIT_ERROR, "metadata: git could not list the snapshot's paths or commit (fails closed)"
    denylist = house_scan.load_denylist()
    if len(denylist) < min_terms:
        return EXIT_NO_DENYLIST, f"metadata: denylist has {len(denylist)} term(s), fewer than the {min_terms} required (refusing)"
    cfg = house_scan.load_config(config)
    names = "\n".join(p for p in paths.stdout.split("\0") if p)
    hits = house_scan.scan_text("paths.md", names, cfg, denylist) + house_scan.scan_text("commit.md", meta.stdout, cfg, denylist)
    if hits:
        return EXIT_FOUND, f"metadata: {len(hits)} hit(s) in file paths or the commit message, author or committer"
    return 0, "metadata: 0 hits in file paths, commit message, author and committer"


#: What gitleaks runs with when the trusted base carries no ``.gitleaks.toml``: its built-in rules, named explicitly so it never looks for one.
DEFAULT_GITLEAKS_CONFIG = '[extend]\nuseDefault = true\n'


def trusted_file(base_ref: str, name: str, repo: Path = REPO) -> Optional[str]:
    """``name`` of ``base_ref`` in the tool repository (not the snapshot), or ``None`` when it does not exist there."""
    proc = git(repo, "show", f"{base_ref}:{name}")
    return proc.stdout if proc.returncode == 0 else None


def gitleaks_gate(snapshot: Path, binary: Optional[str] = None, config_text: Optional[str] = None,
                  ignore_text: Optional[str] = None) -> Tuple[int, str]:
    """``(exit code, message)`` for the gitleaks gates: findings in the files (``dir``) and in the history (``git``), never their values.
    gitleaks runs from the snapshot root on ``.`` with the **trusted** ``--config`` (``config_text``, else the built-in rules) and the trusted
    ``.gitleaksignore`` (``ignore_text``, else none); a ``.gitleaks.toml`` or ``gitleaks:allow`` comment the snapshot brings is never read, and
    a ``.gitleaksignore`` that differs from the trusted one (which gitleaks would read from the root regardless) refuses the snapshot."""
    tool = binary or shutil.which("gitleaks")
    if not tool:
        return EXIT_ERROR, "gitleaks is not installed (fails closed)"
    own = snapshot / ".gitleaksignore"
    if own.is_symlink() or (own.exists() and (not own.is_file() or own.read_text(errors="replace") != (ignore_text or ""))):
        # gitleaks reads this file from the scanned root whatever --gitleaks-ignore-path says, so a snapshot may carry only the trusted one
        return EXIT_FOUND, "gitleaks: the snapshot carries a .gitleaksignore that differs from the trusted base's"
    total = 0
    with tempfile.TemporaryDirectory() as tmp:
        config = Path(tmp) / "gitleaks.toml"
        config.write_text(config_text if config_text else DEFAULT_GITLEAKS_CONFIG)
        ignore = Path(tmp) / "ignore"
        ignore.mkdir()
        (ignore / ".gitleaksignore").write_text(ignore_text or "")
        for mode in ("dir", "git"):
            report = Path(tmp) / f"{mode}.json"
            try:
                proc = subprocess.run([tool, mode, ".", "--config", str(config), "--gitleaks-ignore-path", str(ignore), "--ignore-gitleaks-allow",
                                       "--no-banner", "--redact", "--report-format", "json", "--report-path", str(report), "--exit-code", "1"],
                                      capture_output=True, text=True, cwd=str(snapshot))
            except OSError:
                return EXIT_ERROR, "gitleaks could not run (fails closed)"
            if proc.returncode not in (0, 1):
                return EXIT_ERROR, f"gitleaks {mode} failed (exit {proc.returncode}, fails closed)"
            try:
                found = len(json.loads(report.read_text() or "[]")) if report.exists() else 0
            except ValueError:
                return EXIT_ERROR, "gitleaks wrote an unreadable report (fails closed)"
            total += max(found, 1 if proc.returncode == 1 else 0)
    if total:
        return EXIT_FOUND, f"gitleaks: {total} finding(s) in files and history"
    return 0, "gitleaks: 0 findings in files and history"


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(prog="go_public_gate.py", description=__doc__.split("\n\n")[0])
    parser.add_argument("snapshot", help="the directory that would be pushed")
    parser.add_argument("--gitleaks", help="path of the gitleaks binary (default: the one on PATH)")
    parser.add_argument("--base-ref", default="origin/main", help="the ref of this repository whose house_scan config is trusted")
    parser.add_argument("--base-repo", default=str(REPO), help="the repository that holds --base-ref (default: the one this tool sits in)")
    args = parser.parse_args(argv)
    snapshot = Path(args.snapshot)
    if not snapshot.is_dir():
        print(f"go_public_gate: {snapshot} is not a directory", file=sys.stderr)
        return EXIT_ERROR
    trusted = trusted_config(args.base_ref, Path(args.base_repo))
    if trusted is None:
        print(f"go_public_gate: cannot read contracts/house_scan.json from {args.base_ref} (fails closed)", file=sys.stderr)
        return EXIT_ERROR
    worst = 0
    with tempfile.TemporaryDirectory() as tmp:
        config = Path(tmp) / "house_scan.json"
        config.write_text(json.dumps(strict_config(trusted)))
        results = [history_gate(snapshot)]
        if not results[0][0]:  # an unsafe history is not worth scanning further
            results += [identity_gate(snapshot), house_scan_gate(snapshot, config), metadata_gate(snapshot, config), gitleaks_gate(
                snapshot, args.gitleaks, trusted_file(args.base_ref, ".gitleaks.toml", Path(args.base_repo)),
                trusted_file(args.base_ref, ".gitleaksignore", Path(args.base_repo)))]
    for code, message in results:
        print(message)
        worst = worst or code
    print("go_public_gate: " + ("every gate passed, the repository may go public" if not worst else "refused, the repository stays private"))
    return worst


if __name__ == "__main__":
    sys.exit(main())
