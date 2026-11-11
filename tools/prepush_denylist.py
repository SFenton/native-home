#!/usr/bin/env python3
"""Entry point of ``.githooks/pre-push``: refuse a push to a public repo whose new content matches the private house denylist.

Git feeds ``<local ref> <local sha> <remote ref> <remote sha>`` lines on stdin and ``<remote name> <url>`` as arguments.

What is scanned, per pushed ref (deletes are skipped):

- the commits the push adds: every commit reachable from the local sha that is not reachable from the known remote sha nor from
  any object **advertised by the destination at push time** (``git ls-remote <push url>``, once per push, 20 s bound; a failure
  excludes nothing, so the whole history is scanned). Local ``refs/remotes/*`` are never trusted;
- per commit: message, author and committer name and email, every changed path, every changed blob;
- tag objects (message and tagger, nested tags too) and a tag or ref that points straight at a tree or blob.

Blobs are scanned as bytes, in chunks, with no size cap and no binary skip: UTF-8, plus UTF-16 little and big endian (terms
encoded, whole-word), and backslash escapes decoded per line. Any git or read error refuses the push (never a silent skip).

Policy: a push to a target in :data:`PUBLIC_REPOS` is refused on any hit, and when the list is missing or under :data:`MIN_TERMS`
terms. Any other remote is scanned and only warned about (exit 0), so the private origin is not blocked by recorded debt.
Output is counts, shas and ``path:line`` with every path segment that matches the list replaced by an ellipsis; never a term.
"""

from __future__ import annotations

import os
import re
import signal
import subprocess
import sys
import threading
from typing import Dict, Iterator, List, Optional, Sequence, Set, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import house_scan  # noqa: E402

#: Smallest term list the public repo may be pushed with (the go-public gate's number).
MIN_TERMS = 20
#: Public push targets (the single list): a URL whose path ends in one of these, case-insensitive, is public.
PUBLIC_REPOS = ("sfenton/native-home",)
ZERO = "0" * 40
#: Bytes read per step of a blob, and how many bytes of the previous step are rescanned for a term that straddles two steps.
CHUNK = 1 << 20
CARRY = 4096
_PREFIX = r"(?<![0-9A-Za-z])"
_SUFFIX = r"(?![0-9A-Za-z])"


class ScanError(Exception):
    """A git or read failure while scanning: the push is refused."""


def git(*args: str, data: Optional[bytes] = None) -> bytes:
    """Stdout bytes of ``git <args>``; raises :class:`ScanError` on any failure (never an empty result)."""
    try:
        done = subprocess.run(["git", *args], input=data, capture_output=True)
    except OSError as exc:
        raise ScanError(f"git {args[0]}: {exc.__class__.__name__}") from exc
    if done.returncode != 0:
        raise ScanError(f"git {args[0]} failed")
    return done.stdout


def is_public(url: str) -> bool:
    """Does the push URL (https, ssh, scp form; any case; ``.git`` and trailing slashes optional) name a public repo?"""
    low = url.strip().lower().rstrip("/")
    low = low.removesuffix(".git").rstrip("/")
    return any(low.endswith(("/" + repo, ":" + repo)) or low == repo for repo in PUBLIC_REPOS)


def terms_of(patterns: Sequence["re.Pattern"]) -> List[str]:
    """The plain terms behind :func:`house_scan.load_denylist`'s compiled patterns."""
    terms = []
    for pattern in patterns:
        text = pattern.pattern
        if not (text.startswith(_PREFIX) and text.endswith(_SUFFIX)):
            raise ScanError("unexpected denylist pattern shape")
        terms.append(re.sub(r"\\(.)", r"\1", text[len(_PREFIX):-len(_SUFFIX)]))
    return terms


def byte_regexes(terms: Sequence[str]) -> List["re.Pattern"]:
    """One case-insensitive byte regex per encoding: UTF-8, UTF-16 little endian, UTF-16 big endian (whole-word in each)."""
    if not terms:
        return []
    alnum = b"[0-9A-Za-z]"
    shapes = (("utf-8", b"(?<!" + alnum + b")", b"(?!" + alnum + b")"),
              ("utf-16-le", b"(?<!" + alnum + b"\\x00)", b"(?!" + alnum + b"\\x00)"),
              ("utf-16-be", b"(?<!\\x00" + alnum + b")", b"(?!\\x00" + alnum + b")"))
    # bytes only fold ASCII case, so non-ASCII terms are also listed in their other cases
    cased = sorted({v for t in terms for v in (t, t.lower(), t.upper(), t.title(), t.capitalize())})
    return [re.compile(before + b"(?:" + b"|".join(re.escape(t.encode(codec)) for t in cased) + b")" + after, re.I)
            for codec, before, after in shapes]


class Matcher:
    """The denylist as text patterns (paths, messages, escapes) and byte regexes (blobs)."""

    def __init__(self, patterns: Sequence["re.Pattern"]):
        self.patterns = list(patterns)
        self.regexes = byte_regexes(terms_of(patterns))

    def text(self, text: str) -> bool:
        """Does ``text`` (or its backslash-decoded form) hold a term?"""
        if any(p.search(text) for p in self.patterns):
            return True
        if "\\" in text:
            decoded = house_scan.decode_escapes(text)
            return decoded != text and any(p.search(decoded) for p in self.patterns)
        return False

    def lines(self, data: bytes) -> Set[int]:
        """1-based line numbers of ``data`` with a term, scanning the bytes in :data:`CHUNK` steps."""
        found: Set[int] = set()
        carry = b""
        newlines = 0  # newlines before the start of carry
        previous_end = 0  # absolute end offset of the data handed to the last step
        pos = 0
        while pos < len(data) or pos == 0:
            chunk = data[pos:pos + CHUNK]
            window = carry + chunk
            base = previous_end - len(carry)
            for regex in self.regexes:
                for match in regex.finditer(window):
                    if base + match.end() > previous_end:  # a match wholly inside the carry was found by the last step
                        found.add(newlines + window.count(b"\n", 0, match.start()) + 1)
            if b"\\" in window:
                for offset, line in enumerate(window.decode("utf-8", "replace").split("\n")):
                    if "\\" in line and self.text(line):
                        found.add(newlines + offset + 1)  # approximate for lines cut at a step edge; the line set stays a superset
            pos += CHUNK
            previous_end = base + len(window)
            keep = window[-CARRY:]
            newlines += window.count(b"\n", 0, len(window) - len(keep))
            carry = keep
            if not chunk:
                break
        return found


def redact(path: str, matcher: Matcher) -> str:
    """``path`` with every segment that matches the list replaced by an ellipsis."""
    return "/".join("…" if matcher.text(part) else part for part in path.split("/"))


#: Seconds ``git ls-remote`` may take before the push is scanned in full.
LS_REMOTE_TIMEOUT = 20


def ls_remote(target: str) -> Optional[bytes]:
    """``git ls-remote -- <target>`` stdout, or ``None`` when it fails, times out, or the URL is rewritten.

    A configured ``insteadOf`` / ``pushInsteadOf`` rewrite means the hook is asked about a different place than git pushes to, so
    nothing is trusted. The child runs in its own session with prompts off; on timeout the whole group (ssh included) is killed.
    """
    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0", "GIT_ASKPASS": ""}
    try:
        resolved = subprocess.run(["git", "ls-remote", "--get-url", "--", target], capture_output=True, env=env, timeout=LS_REMOTE_TIMEOUT)
        if resolved.returncode != 0 or resolved.stdout.decode("utf-8", "replace").strip() != target.strip():
            return None
        proc = subprocess.Popen(["git", "ls-remote", "--", target], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                env=env, start_new_session=True)
    except (OSError, subprocess.SubprocessError):
        return None
    try:
        out, _ = proc.communicate(timeout=LS_REMOTE_TIMEOUT)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except OSError:
            pass
        proc.communicate()
        return None
    return out if proc.returncode == 0 else None


def advertised_shas(target: str) -> List[str]:
    """Object ids the destination advertises right now (``git ls-remote <target>``) that exist in this clone, commits and tags only.

    Any failure or timeout returns ``[]``: nothing is excluded and the push is scanned in full. Local tracking refs are never
    consulted, because they can be stale (after a rewrite or prune) or fetched from a different URL than the push target.
    """
    out = ls_remote(target)
    if out is None:
        return []
    shas = list(dict.fromkeys(line.split()[0].decode() for line in out.splitlines()
                              if line.split() and re.fullmatch(rb"[0-9a-f]{40,64}", line.split()[0])))
    if not shas:
        return []
    try:
        checked = git("cat-file", "--batch-check=%(objecttype) %(objectname)", data=("\n".join(shas) + "\n").encode()).decode().splitlines()
    except ScanError:
        return []
    return [line.split()[1] for line in checked if line.split()[0] in ("commit", "tag")]


def new_commits(local: str, remote: str, advertised: Sequence[str]) -> List[str]:
    """Commits a push adds: reachable from ``local`` but not from the destination's known sha nor from anything it advertised at push time.

    A branch that merged the destination's main is thus not rescanned for main's own commits. With ``advertised`` empty
    (``ls-remote`` failed, or a new, empty destination) only the known remote sha is excluded.
    """
    known = remote != ZERO and subprocess.run(["git", "cat-file", "-e", remote + "^{commit}"], capture_output=True).returncode == 0
    exclude = list(advertised) + ([remote] if known else [])
    stdin = "".join(f"^{sha}\n" for sha in dict.fromkeys(exclude)).encode()
    return git("rev-list", local, "--stdin", data=stdin).decode().split()


def commit_hits(sha: str, matcher: Matcher) -> List[str]:
    """``sha8:message`` / ``sha8:author`` locations of hits in one commit's message and identities.

    The message also hits on the private request repository's name (:data:`house_scan.REPO_NAME`; none configured: no such hit).
    Only the location is reported, never the matched text.
    """
    out = git("log", "-1", "--format=%an%x00%ae%x00%cn%x00%ce%x00%B", sha).decode("utf-8", "replace")
    *identity, message = out.split("\x00", 4)
    found = []
    if matcher.text(message) or (house_scan.REPO_NAME is not None and house_scan.REPO_NAME.search(message)):
        found.append(f"{sha[:8]}:message")
    if matcher.text("\n".join(identity)):
        found.append(f"{sha[:8]}:author")
    return found


def tree_changes(sha: str) -> List[Tuple[str, str]]:
    """``(blob sha, path)`` of every file a commit adds or changes (a merge: against its first parent)."""
    out = git("diff-tree", "-r", "--root", "--no-commit-id", "--diff-filter=AMCR", "-z", "--raw", "--first-parent", "-m", sha)
    items = out.split(b"\x00")
    changes = []
    for i in range(0, len(items) - 1, 2):
        meta = items[i].split()
        if len(meta) >= 5 and not meta[1].startswith(b"16"):  # mode 160000 is a submodule: no blob
            changes.append((meta[3].decode(), items[i + 1].decode("utf-8", "replace")))
    return changes


def tree_files(sha: str) -> List[Tuple[str, str]]:
    """``(blob sha, path)`` of every file under a tree."""
    items = git("ls-tree", "-r", "-z", sha).split(b"\x00")
    files = []
    for item in items:
        if not item:
            continue
        meta, _, path = item.partition(b"\t")
        mode, kind, blob = meta.decode().split()
        if kind == "blob":
            files.append((blob, path.decode("utf-8", "replace")))
    return files


def blob_lines(blobs: Sequence[str], matcher: Matcher) -> Dict[str, Set[int]]:
    """Matching line numbers per blob, reading every blob through one ``git cat-file --batch`` process in :data:`CHUNK` pieces."""
    result: Dict[str, Set[int]] = {}
    if not blobs:
        return result
    proc = subprocess.Popen(["git", "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    feeder = threading.Thread(target=lambda: (proc.stdin.write(("\n".join(blobs) + "\n").encode()), proc.stdin.close()), daemon=True)
    feeder.start()
    try:
        for sha in blobs:
            header = proc.stdout.readline().split()
            if len(header) != 3:
                raise ScanError("git cat-file: object missing")
            size = int(header[2])
            data = bytearray()
            left = size
            while left:
                piece = proc.stdout.read(min(left, 8 * CHUNK))
                if not piece:
                    raise ScanError("git cat-file: short read")
                data += piece
                left -= len(piece)
            proc.stdout.read(1)  # the newline after the object
            result[sha] = matcher.lines(bytes(data))
    finally:
        proc.stdout.close()
        proc.wait()
        feeder.join()
    return result


def scan_files(label: str, files: Sequence[Tuple[str, str]], matcher: Matcher, seen: Set[str]) -> List[str]:
    """Hits in ``(blob, path)`` pairs: matching paths and matching blob lines. ``label`` is the commit or tree sha8."""
    hits = [f"{label}:{redact(path, matcher)}:path" for _blob, path in files if matcher.text(path)]
    fresh = list(dict.fromkeys(b for b, _p in files if b not in seen))
    lines = blob_lines(fresh, matcher)
    seen.update(fresh)
    for blob, path in files:
        for number in sorted(lines.get(blob, ())):
            hits.append(f"{redact(path, matcher)}:{number}")
    return hits


def scan_object(sha: str, remote: str, advertised: Sequence[str], matcher: Matcher, seen: Set[str]) -> Tuple[List[str], int]:
    """Hits and the commit count of one pushed object: a commit, a (nested) tag, a tree or a blob."""
    hits: List[str] = []
    for _depth in range(16):
        kind = git("cat-file", "-t", sha).decode().strip()
        if kind != "tag":
            break
        body = git("cat-file", "tag", sha)
        if matcher.lines(body):
            hits.append(f"{sha[:8]}:tag")
        match = re.match(rb"object ([0-9a-f]{40,64})\n", body)
        if not match:
            raise ScanError("malformed tag object")
        sha = match.group(1).decode()
    else:
        raise ScanError("tag chain too deep")
    if kind == "blob":
        return hits + [f"{sha[:8]}:blob:{n}" for n in sorted(blob_lines([sha], matcher)[sha])], 0
    if kind == "tree":
        return hits + scan_files(sha[:8], tree_files(sha), matcher, seen), 0
    if kind != "commit":
        raise ScanError(f"unexpected object type {kind}")
    commits = new_commits(sha, remote, advertised)
    for commit in commits:
        hits.extend(commit_hits(commit, matcher))
        hits.extend(scan_files(commit[:8], tree_changes(commit), matcher, seen))
    return hits, len(commits)


def read_pushes(stream) -> Iterator[List[str]]:
    """The 4-field lines git writes on stdin."""
    for line in stream.read().splitlines():
        fields = line.split()
        if len(fields) == 4:
            yield fields


def main(argv: Optional[List[str]] = None, stdin=None) -> int:
    """Run the hook; ``argv`` is ``[remote name, url]``. Exit 0 allows the push, 1 refuses it."""
    argv = sys.argv[1:] if argv is None else argv
    remote_name = argv[0] if argv else ""
    public = is_public(argv[1] if len(argv) > 1 else remote_name)
    pushes = list(read_pushes(sys.stdin if stdin is None else stdin))
    patterns = house_scan.load_denylist()
    count = len(patterns)
    if count < MIN_TERMS:
        state = "is not loaded" if not count else f"has {count} term(s), fewer than {MIN_TERMS}"
        if public:
            print(f"pre-push: the house denylist {state}; refusing the push to the public repo "
                  "(set HOUSE_SCAN_DENYLIST, or add house_denylist.txt to the config folder or ~/hass-agents).", file=sys.stderr)
            return 1
        print(f"pre-push: warning: the house denylist {state}.", file=sys.stderr)
        if not count:
            return 0
    try:
        matcher = Matcher(patterns)
        hits: List[str] = []
        scanned = 0
        seen: Set[str] = set()
        cache: List[List[str]] = []

        def advertised() -> List[str]:
            """The destination's advertised shas, asked once per push."""
            if not cache:
                cache.append(advertised_shas(argv[1] if len(argv) > 1 else remote_name))
            return cache[0]

        for local_ref, local, remote_ref, remote in pushes:
            # a ref name is pushed too (a branch or lightweight tag named after a term), deletes included
            for name in dict.fromkeys((local_ref, remote_ref)):
                if matcher.text(name):
                    hits.append(f"ref:{redact(name, matcher)}")
            if local == ZERO:
                continue  # a delete adds nothing
            found, commits = scan_object(local, remote, advertised(), matcher, seen)
            hits.extend(found)
            scanned += commits
    except (ScanError, OSError, ValueError) as exc:
        print(f"pre-push: the denylist scan could not finish ({exc}); refusing the push.", file=sys.stderr)
        return 1
    hits = list(dict.fromkeys(hits))
    print(f"pre-push: denylist {count} term(s), {scanned} commit(s) scanned, {len(hits)} hit(s)")
    for hit in hits:
        print(f"  {hit} denylist")
    if hits and public:
        print("pre-push: refusing the push. Remove the house data from the commits (rewrite them; reword a ':message' hit, the request repo's name included), then send them again (`tools/ship.sh --update` for a rewritten lane branch).", file=sys.stderr)
        return 1
    if hits:
        print("pre-push: warning: hits above are allowed for a non-public remote.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # any failure refuses: a gate that crashes must not let the push through
        print(f"pre-push: the denylist scan crashed ({exc.__class__.__name__}); refusing the push.", file=sys.stderr)
        sys.exit(1)
