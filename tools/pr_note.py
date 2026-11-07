#!/usr/bin/env python3
"""Keep a pull request followable from the PR alone: timeline comments plus the status and device blocks.

Roles call this instead of typing ``gh``. Every comment carries a marker so the helper finds its own earlier comment
and edits it in place (never ``--edit-last``: every role shares one login). Spec: ``build/research/visual-prs.md``
sections J and K.6.

Commands::

    pr_note.py post KIND --task T [--class C] --round N --body-file F [--pr N] [--as ROLE]
    pr_note.py flush --task T [--pr N] [--as ROLE]
    pr_note.py status --task T --line TEXT [--pr N]
    pr_note.py devices --task T --file F [--pr N]
    pr_note.py resolve --task T --round N --text TEXT [--pr N] [--as ROLE]
    pr_note.py init --task T [--pr N]

Kinds are ``pick``, ``evidence``, ``verdict``, ``owner``, ``handoff`` and ``shipped``. An ``evidence`` comment is per
device class (``iphone``, ``duo``, ``ipad``) per round, marker ``<!-- sh:evidence:<task>:<class>:<round> -->``; a class
with nothing to show gets no comment. Other markers are ``<!-- sh:<kind>:<task>:<round> -->``.

Behaviour:

- A body hash is stored in the comment; an unchanged body is a no-op, a changed one edits the comment and adds
  "updated HH:MMZ" to its header line, a new marker posts a new comment.
- With no PR yet the note is queued under ``build/pr-notes/<task>/queue/`` with its original time, and ``flush`` posts
  the queue in order once the PR exists ("happened 11:32Z, posted when the PR opened").
- ``status`` and ``devices`` replace only the text between their own ``sh-status`` / ``sh-devices`` markers in the PR
  body. Everything else, including the reviewer's block, is left byte for byte.
- Local images and videos referenced as markdown paths are attached with ``gh pr comment --attach`` /
  ``gh pr edit --attach``; the URLs GitHub returns are remembered so an edit keeps them.
- ``init`` (run once, right after ``ship.sh`` opens the PR) makes the PR body follow the template: the plain sections
  are prepended when missing and any missing ``sh-status`` / ``sh-devices`` / review marker block is appended, all
  existing text untouched; then it flushes the task's queue. ``post`` also flushes the task's queue first and drops
  queued entries for a marker it just posted, so a stale queued note never overwrites a newer comment.
- ``--as ROLE`` (orchestrator, researcher, designer, coder, verifier, reviewer, steward, menial, triage): when that
  role's GitHub App key exists (``tools/gh_app_token.py``) comments are posted and edited through the REST API with
  its installation token; otherwise one stderr line and the owner's ``gh`` login, exactly as without ``--as``.
  ``handoff`` and ``owner`` comments from an app start with ``@SFenton`` (GitHub Mobile pushes only on a mention).
  Marker lookup matches comments by marker whoever wrote them: an app edits its own comment; a comment by another
  author (the owner's login before the switch, or the reverse) is replaced, since an app cannot edit it, by posting
  the new one and removing the old one with the owner's login, but only when its author is the owner or one
  of our ``s-h-<role>[bot]`` apps. The marker counts only in the trailer ``compose`` writes, not quoted in a body. Media upload and PR-body edits always use the owner's
  login (an installation token cannot upload), so a comment with a new local picture is posted as the owner.
- Fail safe: a ``gh`` error or a 20 second timeout prints one warning line and exits 0, so work never blocks on a
  comment. Bodies pass through ``tools/redact.py`` first. Only issue comments and the PR body are ever written, and the only delete is the old copy of a
  helper comment after a change of author (never a third party's).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from redact import redact as _redact
except ImportError:  # pragma: no cover - redact ships in the repo
    _redact = None
import gh_app_token  # noqa: E402

KINDS = ("pick", "evidence", "verdict", "owner", "handoff", "shipped")
CLASSES = ("iphone", "duo", "ipad")
ROLES = gh_app_token.ROLES
MENTION = "@SFenton"
MENTION_KINDS = ("handoff", "owner")
TIMEOUT = 20
NOTES_DIR = ROOT / "build" / "pr-notes"
_MEDIA = re.compile(r"!\[([^\]]*)\]\(([^)\s]+)\)")
_TASK = re.compile(r"^[A-Za-z0-9._-]+$")
_HASH = re.compile(r"<!-- sh-hash:([0-9a-f]+) -->")


class NoteError(Exception):
    """A ``gh`` or input problem; ``main`` turns it into one warning line and exit 0."""


def redact(text: str) -> str:
    """Run text through ``tools/redact.py``; refuses (so nothing posts unredacted) when it cannot be imported."""
    if _redact is None:
        raise NoteError("tools/redact.py unavailable, not posting")
    return _redact(text)


def task_id(value: str) -> str:
    """Validate ``--task`` (letters, digits, ``.``, ``_``, ``-``; no ``..``)."""
    if not _TASK.match(value) or ".." in value:
        raise argparse.ArgumentTypeError(f"bad task id {value!r}")
    return value


# MARK: - gh

def gh(args: List[str], stdin: Optional[str] = None) -> str:
    """Run ``gh`` with a 20 second timeout; raises ``NoteError`` on any failure."""
    try:
        done = subprocess.run(["gh", *args], input=stdin, capture_output=True, text=True, timeout=TIMEOUT, cwd=ROOT)
    except subprocess.TimeoutExpired:
        raise NoteError(f"gh {args[0]} timed out after {TIMEOUT}s") from None
    except OSError as exc:
        raise NoteError(f"gh unavailable: {exc}") from None
    if done.returncode != 0:
        raise NoteError(f"gh {' '.join(args[:2])} failed: {(done.stderr or done.stdout).strip()[:160]}")
    return done.stdout


def find_pr(explicit: Optional[str]) -> Optional[int]:
    """The PR number: ``--pr``, else the current branch's PR, else ``None`` (no PR yet)."""
    if explicit:
        return int(explicit)
    try:
        return int(json.loads(gh(["pr", "view", "--json", "number"]))["number"])
    except NoteError as exc:
        if "no pull requests found" in str(exc).lower():
            return None
        raise
    except (ValueError, KeyError):
        return None


def list_comments(pr: int) -> List[Dict[str, Any]]:
    """All issue comments on the PR as ``{id, body, user: {login, type}}`` (read with the owner's login)."""
    out = gh(["api", "repos/{slug}/issues/{pr}/comments".format(slug=gh_app_token.repo(), pr=pr), "--paginate", "--jq",
              ".[] | {id, body, user: {login: .user.login, type: .user.type}}"])
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def patch_comment(comment_id: Any, body: str) -> None:
    """Replace the text of one comment with the owner's login."""
    gh(["api", "-X", "PATCH", "repos/{slug}/issues/comments/{id}".format(slug=gh_app_token.repo(), id=comment_id),
        "--input", "-"],
       json.dumps({"body": body}))


def remove_comment(comment_id: Any) -> None:
    """Remove one comment with the owner's login (the old copy after a change of author)."""
    gh(["api", "-X", "DELETE", "repos/{slug}/issues/comments/{id}".format(slug=gh_app_token.repo(), id=comment_id)])


_OWNER_LOGIN: List[str] = []


def owner_login() -> Optional[str]:
    """The owner's GitHub login (``gh api user``), remembered for the run; ``None`` when it cannot be read."""
    if not _OWNER_LOGIN:
        try:
            _OWNER_LOGIN.append(gh(["api", "user", "--jq", ".login"]).strip())
        except NoteError:
            return None
    return _OWNER_LOGIN[0] or None


def is_app_login(login: str) -> bool:
    """Whether ``login`` is one of our role apps: ``<recorded slug>[bot]`` per role (``s-h-<role>`` when no slug is
    recorded in ``apps.json``)."""
    return login.endswith("[bot]") and login in {f"{gh_app_token.recorded_slug(r)}[bot]" for r in ROLES}


def has_tag(comment: Dict[str, Any], tag: str) -> bool:
    """Whether the comment carries ``tag`` in the trailer ``compose`` writes (the end), not quoted elsewhere."""
    return (comment.get("body") or "").rstrip().endswith(tag)


# MARK: - Identity

class Identity:
    """Who writes: an app role (``role`` and its ``login``, ``<slug>[bot]``) or the owner's ``gh`` login (no role)."""

    def __init__(self, role: Optional[str] = None, login: str = "") -> None:
        self.role = role
        self.login = login

    def mine(self, comment: Dict[str, Any]) -> bool:
        """Whether this identity wrote ``comment`` (so it may edit it)."""
        user = comment.get("user") or {}
        if self.role:
            return user.get("login") == self.login
        owner = owner_login()
        return user.get("login") == owner if owner and user else user.get("type") != "Bot"

    def replaceable(self, comment: Dict[str, Any]) -> bool:
        """Whether ``comment`` is the counterpart this identity may delete after replacing it: the owner's own
        (when an app posts) or one of our apps' (when the owner posts). Anyone else's is never touched."""
        login = (comment.get("user") or {}).get("login") or ""
        if self.role:
            return bool(login) and login == owner_login()
        return is_app_login(login)

    def create(self, pr: int, text: str) -> None:
        """Post a new issue comment as an app (REST, installation token in-process)."""
        self.call("POST", "repos/{slug}/issues/{pr}/comments".format(slug=gh_app_token.repo(), pr=pr), {"body": text})

    def edit(self, comment_id: Any, text: str) -> None:
        """Edit one of this identity's own comments."""
        if not self.role:
            patch_comment(comment_id, text)
            return
        self.call("PATCH", "repos/{slug}/issues/comments/{id}".format(slug=gh_app_token.repo(), id=comment_id),
                  {"body": text})

    def call(self, method: str, path: str, payload: Dict[str, Any]) -> None:
        """One REST call with the role's installation token."""
        try:
            gh_app_token.api_request(method, path, gh_app_token.token(self.role or ""), payload)
        except Exception as exc:  # noqa: BLE001 - any failure queues the note instead of losing it
            raise NoteError(f"app call failed: {type(exc).__name__}") from None


OWNER = Identity()
_ACTIVE = OWNER


def resolve_identity(role: Optional[str]) -> Identity:
    """The app identity for ``role`` when its key, ids and token work; else the owner (one stderr line)."""
    if not role:
        return OWNER
    try:
        if gh_app_token.available(role):
            gh_app_token.token(role, timeout=gh_app_token.PROBE_TIMEOUT)
            own = (gh_app_token.recorded_slug(role) if gh_app_token.has_recorded_slug(role)
                   else gh_app_token.slug(role, timeout=gh_app_token.PROBE_TIMEOUT))
            return Identity(role, f"{own}[bot]")
    except Exception as exc:  # noqa: BLE001 - never lose a note over identity
        print(f"pr_note: app identity for {role} failed ({type(exc).__name__}: {exc}), posting as the owner login",
              file=sys.stderr)
        return OWNER
    print(f"pr_note: no app identity for {role}, posting as the owner login", file=sys.stderr)
    return OWNER


def with_mention(kind: str, body: str, ident: Identity) -> str:
    """App comments of kind handoff or owner start with ``@SFenton`` so GitHub Mobile pushes the owner."""
    if ident.role and kind in MENTION_KINDS and not body.lstrip().startswith(MENTION):
        return f"{MENTION}\n\n{body.lstrip()}"
    return body


# MARK: - Text

def marker(kind: str, task: str, round_no: int, cls: Optional[str] = None) -> str:
    """The comment marker; evidence carries its device class."""
    if kind == "evidence":
        return f"<!-- sh:evidence:{task}:{cls}:{round_no} -->"
    return f"<!-- sh:{kind}:{task}:{round_no} -->"


def body_hash(body: str) -> str:
    """Short hash of the body content (without header decoration)."""
    return hashlib.sha256(body.encode()).hexdigest()[:12]


def now_z() -> str:
    """Current time as ``HH:MMZ`` (UTC)."""
    return datetime.now(timezone.utc).strftime("%H:%MZ")


def strip_markers(body: str) -> str:
    """Remove any sh marker or hash line a renderer already put in."""
    return re.sub(r"\n?<!-- sh(?:-hash)?:[^>]*-->[ \t]*", "", body).strip()


def compose(body: str, tag: str, note: Optional[str] = None, digest: Optional[str] = None) -> str:
    """The final comment text: header (with ``note`` appended), body, hash and marker.

    ``digest`` is the hash of the raw body (before upload URLs were substituted) so a re-post compares equal."""
    clean = strip_markers(body)
    if note:
        first, sep, rest = clean.partition("\n")
        text = f"{first} · {note}{sep}{rest}"
    else:
        text = clean
    return f"{text}\n\n<!-- sh-hash:{digest or body_hash(clean)} -->\n{tag}\n"


def _local(path: str) -> Optional[Path]:
    if path.startswith(("http://", "https://")):
        return None
    for candidate in (Path(path), ROOT / path):
        if candidate.is_file():
            return candidate
    return None


def local_media(text: str) -> List[str]:
    """Paths of markdown media references that exist on disk, in order."""
    return [p for _a, p in _MEDIA.findall(text) if _local(p)]


def attach_args(text: str) -> List[str]:
    """``--attach file#alt`` arguments for every local media reference."""
    out: List[str] = []
    for alt, path in _MEDIA.findall(text):
        found = _local(path)
        if found:
            out += ["--attach", f"{found}#{alt or found.name}"]
    return out


# MARK: - Media memory

def task_dir(task: str) -> Path:
    """``build/pr-notes/<task>/`` (created)."""
    path = NOTES_DIR / task
    path.mkdir(parents=True, exist_ok=True)
    return path


def load_media(task: str) -> Dict[str, str]:
    """Local path to uploaded URL, remembered so an edit keeps the pictures."""
    f = task_dir(task) / "media.json"
    return json.loads(f.read_text()) if f.is_file() else {}


def apply_media(text: str, media: Dict[str, str]) -> str:
    """Swap known local paths for their uploaded URLs."""
    return _MEDIA.sub(lambda m: f"![{m.group(1)}]({media[m.group(2)]})" if m.group(2) in media else m.group(0), text)


def remember_media(pr: int, task: str, tag: str, sent: str) -> None:
    """After an attach upload, map each local path to the URL GitHub rewrote it to."""
    paths = local_media(sent)
    posted = next((c for c in reversed(list_comments(pr)) if has_tag(c, tag)), None)
    if not paths or not posted:
        return
    urls = [u for _a, u in _MEDIA.findall(posted["body"]) if u.startswith("http")]
    media = load_media(task)
    media.update(dict(zip(paths, urls)))
    (task_dir(task) / "media.json").write_text(json.dumps(media, indent=1, sort_keys=True))


# MARK: - Comments

def post_comment(pr: int, task: str, kind: str, cls: Optional[str], round_no: int, body: str,
                 happened: Optional[str] = None, ident: Optional[Identity] = None) -> str:
    """Post or edit the comment for this marker; returns ``posted``, ``edited``, ``replaced`` or ``unchanged``.

    Comments are found by marker whoever wrote them. The identity's own is edited; one by another author is
    replaced (new comment first, then the old one removed) because an app cannot edit the owner's comment."""
    ident = ident or _ACTIVE
    tag = marker(kind, task, round_no, cls)
    body = with_mention(kind, body, ident)
    digest = body_hash(strip_markers(body))
    matches = [c for c in list_comments(pr) if has_tag(c, tag)]
    shown = apply_media(body, load_media(task))
    if local_media(shown):  # an installation token cannot upload: this post goes out under the owner's login
        ident = OWNER
    own = next((c for c in matches if ident.mine(c)), None)
    foreign = [c for c in matches if not ident.mine(c) and ident.replaceable(c)]
    if own:
        m = _HASH.search(own["body"])
        if m and m.group(1) == digest:
            return "unchanged"
        ident.edit(own["id"], compose(shown, tag, f"updated {now_z()}", digest))
        return "edited"
    note = f"happened {happened}, posted when the PR opened" if happened else None
    text = compose(shown, tag, note, digest)
    if ident.role:
        ident.create(pr, text)
    else:
        gh(["pr", "comment", str(pr), "--body-file", "-", *attach_args(text)], text)
        remember_media(pr, task, tag, text)
    for old in foreign:
        try:
            remove_comment(old["id"])
        except NoteError:
            pass
    return "replaced" if foreign else "posted"


def resolve_handoff(pr: int, task: str, round_no: int, text: str, ident: Optional[Identity] = None) -> str:
    """Make the round's handoff start with ``**Resolved:**`` (another author's comment is edited as the owner)."""
    ident = ident or _ACTIVE
    tag = marker("handoff", task, round_no)
    matches = [c for c in list_comments(pr) if has_tag(c, tag)]
    comment = next((c for c in matches if ident.mine(c)), matches[0] if matches else None)
    if not comment:
        return "no handoff"
    if comment["body"].lstrip().startswith("**Resolved:**"):
        return "unchanged"
    new = f"**Resolved:** {text} (as of {now_z()})\n\n{comment['body']}"
    (ident if ident.mine(comment) else OWNER).edit(comment["id"], new)
    return "resolved"


# MARK: - Queue

def queue_note(task: str, kind: str, cls: Optional[str], round_no: int, body: str,
               role: Optional[str] = None) -> Path:
    """Write the note to the task's queue with its original time; names are unique and sort in posting order."""
    folder = task_dir(task) / "queue"
    folder.mkdir(exist_ok=True)
    existing = [int(p.name.split("-", 1)[0]) for p in folder.glob("*.json") if p.name.split("-", 1)[0].isdigit()]
    stamp = max([time.time_ns(), *[e + 1 for e in existing]])
    path = folder / f"{stamp:020d}-{kind}-{cls or 'all'}-{round_no}.json"
    path.write_text(json.dumps({"kind": kind, "class": cls, "round": round_no, "body": body, "time": now_z(),
                                "branch": current_branch(), "as": role}))
    return path


def current_branch() -> str:
    """The checked-out branch, for information only (queues are keyed by task)."""
    try:
        return subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True,
                              timeout=TIMEOUT, cwd=ROOT).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def drop_queued(task: str, kind: str, cls: Optional[str], round_no: int) -> None:
    """Remove queued entries for a marker that was just posted."""
    for path in (task_dir(task) / "queue").glob("*.json"):
        n = json.loads(path.read_text())
        if (n["kind"], n["class"], n["round"]) == (kind, cls, round_no):
            path.unlink()


def flush(task: str, pr: int) -> int:
    """Post the queue in order; stops at the first failure so order is kept. Returns how many were posted."""
    count = 0
    for path in sorted((task_dir(task) / "queue").glob("*.json")):
        n = json.loads(path.read_text())
        post_comment(pr, task, n["kind"], n["class"], n["round"], redact(n["body"]), happened=n["time"],
                     ident=resolve_identity(n.get("as")))
        path.unlink()
        count += 1
    return count


# MARK: - PR body blocks

def replace_block(body: str, name: str, content: str) -> Optional[str]:
    """``body`` with only the text between ``<!-- name:start -->`` and ``<!-- name:end -->`` replaced, else ``None``."""
    start, end = f"<!-- {name}:start -->", f"<!-- {name}:end -->"
    i = body.find(start)
    j = body.find(end, i + len(start)) if i >= 0 else -1
    if i < 0 or j < 0:
        return None
    return body[:i + len(start)] + "\n" + content.strip("\n") + "\n" + body[j:]


def update_block(pr: int, name: str, content: str) -> str:
    """Write one block of the PR body; returns ``updated``, ``unchanged`` or ``no markers``."""
    body = json.loads(gh(["pr", "view", str(pr), "--json", "body"]))["body"] or ""
    new = replace_block(body, name, content)
    if new is None:
        return "no markers"
    if new == body:
        return "unchanged"
    gh(["pr", "edit", str(pr), "--body-file", "-", *attach_args(new)], new)
    return "updated"


TEMPLATE = ROOT / ".github" / "pull_request_template.md"
_SECTION = "## What changed for you"
_BLOCKS = (("sh-devices", "<!-- sh-devices:start -->\n<!-- sh-devices:end -->"),
           ("sh-status", "<!-- sh-status:start -->\n<!-- sh-status:end -->"),
           ("review", "<!-- review:start -->\n<!-- review:end -->"))


def follow_template(body: str, template: str) -> str:
    """``body`` with the template's plain sections prepended when missing and absent marker blocks appended.

    Existing text, including any review block, is kept byte for byte."""
    out = body
    if _SECTION not in out and _SECTION in template:
        head = template.split("\n<details>", 1)[0].strip("\n")
        out = head + ("\n\n" + out if out.strip() else "\n")
    for name, block in _BLOCKS:
        if f"<!-- {name}:start -->" not in out:
            out = out.rstrip("\n") + "\n\n" + block + "\n"
    return out


def init_pr(pr: int, task: str) -> str:
    """Make the PR body follow the template, then flush the task's queue."""
    body = json.loads(gh(["pr", "view", str(pr), "--json", "body"]))["body"] or ""
    template = TEMPLATE.read_text() if TEMPLATE.is_file() else ""
    new = follow_template(body, template)
    state = "body kept"
    if new != body:
        gh(["pr", "edit", str(pr), "--body-file", "-"], new)
        state = "body updated"
    return f"{state}, flushed {flush(task, pr)}"


# MARK: - CLI

def build_parser() -> argparse.ArgumentParser:
    """The argument parser."""
    p = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    sub = p.add_subparsers(dest="cmd", required=True)

    def add(name: str) -> argparse.ArgumentParser:
        s = sub.add_parser(name)
        s.add_argument("--task", required=True, type=task_id)
        s.add_argument("--pr")
        s.add_argument("--as", dest="role", choices=ROLES, help="post as this role's GitHub App when its key exists")
        return s

    s = add("post")
    s.add_argument("kind", choices=KINDS)
    s.add_argument("--class", dest="cls", choices=CLASSES)
    s.add_argument("--round", type=int, required=True)
    s.add_argument("--body-file", required=True)
    add("flush")
    add("init")
    add("status").add_argument("--line", required=True)
    add("devices").add_argument("--file", required=True)
    s = add("resolve")
    s.add_argument("--round", type=int, required=True)
    s.add_argument("--text", required=True)
    return p


def run(args: argparse.Namespace) -> str:
    """Execute one command; returns the one-line result."""
    global _ACTIVE
    _ACTIVE = resolve_identity(getattr(args, "role", None)) if args.cmd in ("post", "flush", "resolve") else OWNER
    try:
        return _run(args)
    finally:
        _ACTIVE = OWNER


def _run(args: argparse.Namespace) -> str:
    """The command itself, with ``_ACTIVE`` set."""
    if args.cmd == "post" and args.kind == "evidence" and not args.cls:
        raise NoteError("evidence needs --class (iphone, duo or ipad)")
    if args.cmd == "post":
        body = Path(args.body_file).read_text()
        try:
            pr = find_pr(args.pr)
            if pr is None:
                return f"queued {queue_note(args.task, args.kind, args.cls, args.round, body, args.role).name}"
            try:
                flush(args.task, pr)
            except NoteError:
                pass
            result = post_comment(pr, args.task, args.kind, args.cls, args.round, redact(body))
            drop_queued(args.task, args.kind, args.cls, args.round)
            return result
        except NoteError:
            queue_note(args.task, args.kind, args.cls, args.round, body, args.role)
            raise
    pr = find_pr(args.pr)
    if pr is None:
        return "no PR yet"
    if args.cmd == "init":
        return init_pr(pr, args.task)
    if args.cmd == "flush":
        return f"flushed {flush(args.task, pr)}"
    if args.cmd == "status":
        return update_block(pr, "sh-status", redact(args.line))
    if args.cmd == "devices":
        return update_block(pr, "sh-devices", redact(Path(args.file).read_text()))
    return resolve_handoff(pr, args.task, args.round, redact(args.text))


def main(argv: Optional[List[str]] = None) -> int:
    """Entry point. A ``gh`` problem prints one warning line and exits 0; usage errors exit 2 via argparse."""
    args = build_parser().parse_args(argv)
    try:
        print(f"pr_note: {run(args)}")
    except Exception as exc:  # noqa: BLE001 - a comment must never block work
        print(f"pr_note: warning, not posted: {exc}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
