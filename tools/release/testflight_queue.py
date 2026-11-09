#!/usr/bin/env python3
"""The TestFlight upload queue: which ``ios/v*`` versions still need uploading, in order, and the ledger of those done.

Every version tag ``ios/v<YYMM.DD.NN>`` (cut by ``versioning.py bump``) is uploaded to TestFlight exactly once, oldest
first, never skipped and never reordered, even when several bumps land close together. GitHub keeps at most one
*pending* workflow run per concurrency group, so a run can be dropped; the queue therefore lives in git, not in the run
list. A release run computes *every* version that is not yet uploaded and uploads them oldest first, so a dropped run is
harmless: the next run catches up.

The ledger is one annotated tag per uploaded version, ``ios/tf/<version>``, pushed after the upload succeeded. Its
message carries ``build=<CFBundleVersion>``. Build numbers strictly increase in upload order: the next build is the
UTC minute stamp ``YYYYMMDDHHMM`` or the newest ledgered build plus one, whichever is larger.

Commands (all JSON on stdout unless stated):

    testflight_queue.py pending [--main-ref origin/main] [--from ios/v…]
    testflight_queue.py mark --tag ios/v… --build N [--push]
    testflight_queue.py run [--dry-run] [--max N] [--from ios/v…] [--] [upload-script args…]

``run`` is the release loop: fetch tags, take the oldest pending version, check its tag out in a throwaway worktree,
call ``testflight_upload.sh --tag T --build N --source DIR``, then write the ledger tag; repeat until nothing is
pending. A failed upload stops the loop (nothing newer may jump the queue); the next run starts with that version again.

Documentation: .agents/platforms/apple/testflight.md.
"""

import argparse
import datetime as _dt
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent))
import versioning as v  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
#: Ledger tag prefix: ``ios/tf/<version>`` marks ``<version>`` as uploaded to TestFlight.
LEDGER_PREFIX = "ios/tf/"
UPLOAD_SCRIPT = REPO_ROOT / "tools" / "release" / "testflight_upload.sh"
BUILD_RE = re.compile(r"\bbuild=(\d+)\b")


def ledger(git: v.Git) -> Dict[str, int]:
    """Return ``{version: build}`` for every version already uploaded (a missing build reads as 0)."""
    out: Dict[str, int] = {}
    for line in git("tag", "--list", LEDGER_PREFIX + "*", "--format=%(refname)\t%(contents:subject)").splitlines():
        ref, _, subject = line.partition("\t")
        version = ref[len("refs/tags/" + LEDGER_PREFIX):]
        if v.is_version(version):
            found = BUILD_RE.search(subject)
            out[version] = int(found.group(1)) if found else 0
    return out


def pending_versions(versions: Sequence[str], uploaded: Sequence[str], start: Optional[str] = None) -> List[str]:
    """Versions to upload, oldest first.

    With a ledger, everything newer than the newest uploaded version (versions only ever grow, so an unledgered older
    one is history from before TestFlight was switched on). Without one, ``start`` and everything after it; with no
    ``start`` either, just the newest version.
    """
    ordered = sorted(set(versions), key=v.parse_version)
    if uploaded:
        floor = max(uploaded, key=v.parse_version)
        return [x for x in ordered if v.parse_version(x) > v.parse_version(floor)]
    if start:
        return [x for x in ordered if v.parse_version(x) >= v.parse_version(start)]
    return ordered[-1:]


def next_build(builds: Sequence[int], now: _dt.datetime) -> int:
    """The next ``CFBundleVersion``: the UTC minute stamp, but always above every build already uploaded."""
    return max(int(now.strftime("%Y%m%d%H%M")), max(builds, default=0) + 1)


def pending(git: v.Git, main_ref: Optional[str] = None, start: Optional[str] = None) -> List[str]:
    """The pending version *tags* (``ios/v…``), oldest first. Tags not reachable from ``main_ref`` are never built."""
    found = [(version, tag) for version, tag in git.version_tags(v.PLATFORM)]
    if main_ref:
        found = [(version, tag) for version, tag in found if git.is_ancestor(tag, main_ref)]
    start_version = v.parse_tag(start)[1] if start else None
    todo = pending_versions([version for version, _ in found], list(ledger(git)), start_version)
    return [v.tag_for(v.PLATFORM, version) for version in todo]


def mark(git: v.Git, tag: str, build: int, note: str = "", push: bool = False) -> str:
    """Write the ledger tag for ``tag`` (annotated, at the version tag's commit); optionally push it. Returns its name."""
    _, version = v.parse_tag(tag)
    name = LEDGER_PREFIX + version
    message = "TestFlight %s build=%d%s" % (version, build, (" " + note) if note else "")
    git("tag", "-a", name, git.rev(tag), "-m", message)
    if push:
        for attempt in range(3):
            try:
                git("push", "origin", "refs/tags/" + name)
                break
            except RuntimeError:
                if attempt == 2:
                    raise
    return name


def _summary(lines: Sequence[str]) -> None:
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")


def run_queue(git: v.Git, upload: str, extra: Sequence[str], main_ref: Optional[str], start: Optional[str],
              limit: int, dry_run: bool, push: bool, fetch: bool, now: Optional[_dt.datetime] = None) -> int:
    """The release loop. Returns 0 when the queue is empty or ``limit`` versions went out, else the failing exit code."""
    def refresh() -> List[str]:
        if fetch:
            git("fetch", "--force", "--tags", "origin", "+refs/heads/main:refs/remotes/origin/main")
        return pending(git, main_ref, start)

    clock = lambda: now or _dt.datetime.now(_dt.timezone.utc)  # noqa: E731
    if dry_run:
        builds = list(ledger(git).values())
        todo = refresh()[:limit]
        for tag in todo:
            build = next_build(builds, clock())
            builds.append(build)
            print("[testflight-queue] would upload %s as build %d" % (tag, build), flush=True)
            subprocess.run([upload, "--tag", tag, "--build", str(build), "--dry-run"] + list(extra), check=False)
        if not todo:
            print("[testflight-queue] nothing pending", flush=True)
        return 0
    uploaded = 0
    while uploaded < limit:
        todo = refresh()  # re-read every time: bumps that landed during the last upload join the queue
        if not todo:
            print("[testflight-queue] nothing pending" if not uploaded else "[testflight-queue] queue empty", flush=True)
            if not uploaded:
                _summary(["- nothing pending"])
            return 0
        tag = todo[0]
        build = next_build(list(ledger(git).values()), clock())
        print("[testflight-queue] %s -> build %d (%d pending)" % (tag, build, len(todo)), flush=True)
        worktree = tempfile.mkdtemp(prefix="tf-src-")
        try:
            git("worktree", "add", "--detach", "--force", worktree, "refs/tags/" + tag)
            result = subprocess.run([upload, "--tag", tag, "--build", str(build), "--source", worktree] + list(extra),
                                    check=False)
        finally:
            try:
                git("worktree", "remove", "--force", worktree)
            except RuntimeError:
                shutil.rmtree(worktree, ignore_errors=True)
        if result.returncode != 0:
            print("[testflight-queue] upload of %s failed (exit %d); stopping so nothing newer jumps the queue"
                  % (tag, result.returncode), file=sys.stderr, flush=True)
            _summary(["- `%s`: **upload failed** (exit %d); later versions wait" % (tag, result.returncode)])
            return result.returncode or 1
        mark(git, tag, build, "source=%s run=%s" % (tag, os.environ.get("GITHUB_RUN_ID", "local")), push)
        uploaded += 1
        _summary(["- `%s` uploaded as build %d" % (tag, build)])
    print("[testflight-queue] stopped at --max %d; the next run continues" % limit, flush=True)
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Create the command-line parser."""
    parser = argparse.ArgumentParser(prog="testflight_queue.py", description=__doc__.split("\n")[0])
    parser.add_argument("--repo", default=str(REPO_ROOT))
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("pending", help="the version tags still to upload, oldest first")
    p.add_argument("--main-ref", default="origin/main")
    p.add_argument("--from", dest="start", help="first tag to upload when nothing has been uploaded yet")
    p = sub.add_parser("mark", help="write the ledger tag for an uploaded version")
    p.add_argument("--tag", required=True)
    p.add_argument("--build", type=int, required=True)
    p.add_argument("--push", action="store_true")
    p = sub.add_parser("run", help="upload every pending version, oldest first")
    p.add_argument("--main-ref", default="origin/main")
    p.add_argument("--from", dest="start")
    p.add_argument("--max", type=int, default=10, help="most versions per run (the next run continues)")
    p.add_argument("--dry-run", action="store_true", help="print the upload commands, change nothing")
    p.add_argument("--no-push", action="store_true", help="write ledger tags locally only")
    p.add_argument("--no-fetch", action="store_true", help="do not fetch tags and main first")
    p.add_argument("--upload", default=str(UPLOAD_SCRIPT), help="the upload script (tests pass a stand-in)")
    p.add_argument("extra", nargs="*", help="arguments after -- go to the upload script")
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    """Run the CLI; returns the exit code."""
    args = build_parser().parse_args(argv)
    git = v.Git(Path(args.repo))
    try:
        if args.command == "pending":
            doc: object = {"pending": pending(git, args.main_ref, args.start), "ledger": ledger(git)}
        elif args.command == "mark":
            doc = {"marked": mark(git, args.tag, args.build, push=args.push)}
        else:
            return run_queue(git, args.upload, args.extra, args.main_ref, args.start, args.max,
                             args.dry_run, not args.no_push, not args.no_fetch)
    except (ValueError, RuntimeError, OSError) as err:
        print(json.dumps({"error": str(err)}))
        return 1
    print(json.dumps(doc))
    return 0


if __name__ == "__main__":
    sys.exit(main())
