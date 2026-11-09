#!/usr/bin/env python3
"""Review before push, enforced by git itself: ``.githooks/pre-push`` runs this before the house denylist.

Git hands the hook the destination (``<remote name> <url>`` as arguments, the url after ``insteadOf`` and ``pushurl`` are applied, once
per push url) and, on stdin, one ``<local ref> <local sha> <remote ref> <remote sha>`` line for every ref that is really being pushed,
after every earlier command of the line has run. So no command text is parsed here.

A push is gated when the url, or any push url of the named remote, is SFenton/native-home (https, ssh or scp form, any case, ``user@``,
``.git`` suffix; ``tools/review_verdict.py`` classifies). A gated push is refused unless every ref that is not a delete points at a commit
with an independent ``pass`` in the trusted store (the account's home from the password database, not ``$HOME``), and no ref is ``main`` or
``master`` (deleting included). Deleting any other remote branch is allowed. A url this cannot classify is refused. Other GitHub
repositories and local paths are not gated. Any error is a refusal (exit 1, which is how a git hook refuses).

Usage (git runs it): ``prepush_review.py REMOTE URL < refs``. Stdlib only.
"""
from __future__ import annotations

import os
import subprocess
import sys
from typing import Callable, Iterable, List, Optional

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import review_verdict  # noqa: E402

ZERO = "0" * 40
PROTECTED = ("main", "master")


def git_out(*args: str) -> Optional[str]:
    """Stdout of ``git <args>`` (stripped) or ``None`` on any failure."""
    try:
        done = subprocess.run(["git", *args], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return None
    return done.stdout.strip() if done.returncode == 0 else None


def push_urls(remote: str, url: str) -> List[str]:
    """``url`` plus every push url of the remote named ``remote`` (empty extra list when ``remote`` is itself a url or unknown)."""
    urls = [url]
    if remote and remote != url:
        listed = git_out("remote", "get-url", "--push", "--all", remote)
        if listed:
            urls.extend(line for line in listed.splitlines() if line.strip())
    return urls


def commit_of(sha: str, resolve: Callable[[str], Optional[str]]) -> Optional[str]:
    """The commit a pushed object peels to (a tag is followed), or ``None``."""
    found = resolve(sha)
    return found if found and review_verdict.FULL_SHA.match(found) else None


def refusal(remote: str, url: str, lines: Iterable[str], store=None, resolve=None, urls=None) -> Optional[str]:
    """Why this push is refused, or ``None``. ``store`` is the verdict folder (tests only; git never passes it)."""
    resolve = resolve or (lambda sha: git_out("rev-parse", "--verify", "-q", sha + "^{commit}"))
    kinds = [review_verdict.remote_kind(u) for u in (urls if urls is not None else push_urls(remote, url))]
    if "native-home" not in kinds:
        if "unknown" in kinds:
            return "the push url %r is not a form this check can read (fails closed)" % url
        return None
    for line in lines:
        parts = line.split()
        if not line.strip():
            continue
        if len(parts) != 4:
            return "an unreadable ref line from git: %r" % line[:80]
        local_ref, local_sha, remote_ref, _remote_sha = parts
        branch = remote_ref[len("refs/heads/"):] if remote_ref.startswith("refs/heads/") else remote_ref
        if branch in PROTECTED:
            return "a push to %s on SFenton/native-home" % branch
        if local_sha == ZERO:
            continue  # deleting a remote branch is allowed
        commit = commit_of(local_sha, resolve)
        if commit is None:
            return "%s (%s) is not a commit" % (local_ref, local_sha[:12])
        if not review_verdict.has_pass(commit, store):
            return "%s at %s has no independent pass" % (local_ref, commit[:12])
    return None


def main(argv: Optional[List[str]] = None, stdin=None) -> int:
    """Hook entry: exit 0 to allow, 1 to refuse (git aborts the push)."""
    args = list(sys.argv[1:] if argv is None else argv)
    try:
        if len(args) != 2:
            raise ValueError("expected REMOTE URL")
        why = refusal(args[0], args[1], (stdin or sys.stdin).read().splitlines())
    except Exception as error:  # noqa: BLE001 - fail closed
        why = "the check failed (%s)" % type(error).__name__
    if why:
        print("pre-push: refusing the push to SFenton/native-home: %s. Nothing an agent pushes there may leave this machine without an "
              "independent `pass` for that exact commit: have the reviewer record one (tools/review/record.py --lane BRANCH), then push "
              "that commit unchanged." % why, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
