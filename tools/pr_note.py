#!/usr/bin/env python3
"""Keep a pull request followable from the PR alone: one comment per step, plus the status, device and timeline blocks.

Roles call this instead of typing ``gh``. Every comment carries a marker so the helper finds its own earlier comment
and edits it in place (never ``--edit-last``: every role shares one login). Spec: ``build/research/visual-prs.md``
sections J and K.6.

Commands::

    pr_note.py post KIND --task T [--class C] --round N --body-file F [--pr N] [--branch B] [--as ROLE] [--step N] [--head SHA]
    pr_note.py flush --task T [--pr N] [--as ROLE]
    pr_note.py status --task T --line TEXT [--pr N]
    pr_note.py devices --task T --file F [--pr N]
    pr_note.py timeline --task T [--pr N]
    pr_note.py resolve --task T --round N --text TEXT [--pr N] [--as ROLE]
    pr_note.py init --task T [--pr N]

Every command also takes ``--branch B`` and ``--ledger-dir D`` (see "Finding the PR").

Kinds are ``pick``, ``evidence``, ``verdict``, ``owner``, ``handoff``, ``shipped`` and, one for each role that had none,
``research`` (Researcher), ``build`` (Coder), ``review`` (Reviewer) and ``retro`` (Steward). An ``evidence`` comment is per
device class (``iphone``, ``duo``, ``ipad``) per round, marker ``<!-- sh:evidence:<task>:<class>:<round> -->``; a class
with nothing to show gets no comment. Other markers are ``<!-- sh:<kind>:<task>:<round> -->``.

Header: every comment starts with ``Step N · <Role> · round R · head <sha7> · HH:MMZ`` (head only when ``--head`` is
given). ``N`` is ``--step`` or, when absent, the count of this task's distinct markers already posted or queued, plus one;
an edit keeps its number. The role is ``--as`` or the kind's usual role (Researcher, Designer, Coder, Verifier,
Reviewer, Steward, Orchestrator). A body whose first line is its own ``**Role**`` header (or, for an app's ``@SFenton``
comment, its first text line) shares the line with the step header, so the mention stays first.

Behaviour:

- A body hash is stored in the comment; an unchanged body is a no-op, a changed one edits the comment and adds
  "updated HH:MMZ" to its header line, a new marker posts a new comment.
- Finding the PR: ``--pr N``; else ``--branch B`` (``gh pr list --head B``); else the branches of the task ledger
  (``build/tasks/<task>.json``, directory ``--ledger-dir``, ``TASKS_DIR`` or this checkout's ``build/tasks``); else the
  current branch. So a caller in another worktree finds the PR.
- With no PR yet the note is queued under ``~/hass-agents/pr-notes/<task>/queue/`` (``SH_PR_NOTES_DIR`` overrides the
  folder; shared by every worktree) with its original time, and ``flush`` posts the queue in order once the PR exists
  ("happened 11:32Z, posted when the PR opened"). ``flush``, ``init`` and ``post`` also move the old per-checkout queue
  ``build/pr-notes/<task>/queue/`` into the shared one first, keeping names (so time and order).
- House data (first gate): before any body, line or file is posted or queued it goes through the house denylist with the
  push gate's own rules (``tools/house_scan.py``, matcher of ``tools/prepush_denylist.py``). A hit refuses the post:
  exit 1, the count and the source name are printed, never the term, and nothing is queued. A list that is not loaded
  prints "denylist not loaded" once and goes on, unless ``denylist_required`` is true in ``tools/triage/config.json``.
  This is the one failure that is not warn-and-exit-0.
- Pictures: a local picture or video is attached only when its path is under ``.agents/design/mockups/`` (atlas renders) or
  an evidence ``manifest.json`` (the file's folder and its parents up to ``build/evidence/<branch>/``) names it with
  ``"source": "demo"`` or ``"mockup"``. Manifest shape, extending ``pose-matrix``: a pose entry may carry ``"source"``
  that covers its ``screenshots``, ``recordings`` and ``videos``; a top-level ``"media"`` list holds ``{"path", "source"}``
  entries. ``"live"`` or no entry refuses the post (exit 1, names the file), as does a file over 10 MB (names its size).
  The SHA-256 of each file posted for a PR is kept next to the URL cache; a second file with the same hash is not uploaded:
  its image becomes ``Same as <first caption or file name>``.
- ``status`` and ``devices`` replace only the text between their own ``sh-status`` / ``sh-devices`` markers in the PR
  body. Everything else, including the reviewer's block, is left byte for byte.
- ``timeline`` rewrites the text between ``<!-- sh-timeline:start -->`` and ``<!-- sh-timeline:end -->`` (appended when
  missing) with one line per posted step, in order: ``N. [Role, round R: first sentence](comment url)``. ``post``
  runs it after a post that changed something; a failure there only warns.
- Local images and videos referenced as markdown paths are attached with ``gh pr comment --attach`` /
  ``gh pr edit --attach``; the URLs GitHub returns are remembered so an edit keeps them.
- ``init`` (run once, right after ``ship.sh`` opens the PR) appends any missing ``sh-devices`` / ``sh-status`` /
  ``sh-timeline`` / review marker block to the PR body, existing text untouched and no placeholder text added; then it
  flushes the task's queue. ``post`` also flushes the task's queue first and drops queued entries for a marker it just
  posted, so a stale queued note never overwrites a newer comment.
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
import os
import re
import shutil
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
import agent_login  # noqa: E402
import house_scan  # noqa: E402
import prepush_denylist  # noqa: E402
import gh_app_token  # noqa: E402

KINDS = ("pick", "evidence", "verdict", "owner", "handoff", "shipped", "research", "build", "review", "retro")
#: The role that usually writes each kind (the header shows it unless ``--as`` names another).
KIND_ROLE = {"pick": "Designer", "verdict": "Designer", "evidence": "Verifier", "research": "Researcher",
             "build": "Coder", "review": "Reviewer", "retro": "Steward", "owner": "Orchestrator",
             "handoff": "Orchestrator", "shipped": "Orchestrator"}
CLASSES = ("iphone", "duo", "ipad")
ROLES = gh_app_token.ROLES
MENTION = "@SFenton"
MENTION_KINDS = ("handoff", "owner")
TIMEOUT = 20
#: The shared queue and media memory; ``SH_PR_NOTES_DIR`` overrides it (tests). One folder for every worktree.
NOTES_DIR = Path.home() / "hass-agents" / "pr-notes"
#: Largest picture or video GitHub takes without a special plan.
MAX_MEDIA = 10 * 1024 * 1024
#: Folder of the mockup atlas renders, relative to the checkout.
ATLAS = Path(".agents") / "design" / "mockups"
_HEADER = re.compile(r"Step (\d+) · ([A-Za-z]+) · round (\d+)(?: · head [0-9a-f]{7,40})?(?: · \d\d:\d\dZ)?")
_MEDIA = re.compile(r"!\[([^\]]*)\]\(([^)\s]+)\)")
_TASK = re.compile(r"^[A-Za-z0-9._-]+$")
_HASH = re.compile(r"<!-- sh-hash:([0-9a-f]+) -->")


class NoteError(Exception):
    """A ``gh`` or input problem; ``main`` turns it into one warning line and exit 0."""


class Refusal(Exception):
    """House data or a picture the rules do not allow: ``main`` prints the reason (never a term) and exits 1."""


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


def pr_of_branch(branch: str) -> Optional[int]:
    """The newest PR whose head is ``branch`` (open or not), else ``None``."""
    rows = json.loads(gh(["pr", "list", "--head", branch, "--state", "all", "--limit", "1", "--json", "number"]) or "[]")
    return int(rows[0]["number"]) if rows else None


def ledger_branches(task: str, ledger_dir: Optional[str] = None) -> List[str]:
    """The lane branches recorded in the task ledger (``tasks.py add-branch``); empty when there is no readable entry."""
    folder = Path(ledger_dir or os.environ.get("TASKS_DIR") or ROOT / "build" / "tasks")
    try:
        data = json.loads((folder / f"{task}.json").read_text())
    except (OSError, ValueError):
        return []
    branches = data.get("branches") if isinstance(data, dict) else None
    return [b for b in branches if isinstance(b, str)] if isinstance(branches, list) else []


def find_pr(explicit: Optional[str], branch: Optional[str] = None, task: Optional[str] = None,
            ledger_dir: Optional[str] = None) -> Optional[int]:
    """The PR number: ``--pr``, else ``--branch``, else the ledger's branches, else the current branch's PR, else ``None``.

    ``None`` means no PR yet. The first three let a caller in another worktree find the PR."""
    if explicit:
        return int(explicit)
    candidates = ([branch] if branch else []) + (ledger_branches(task, ledger_dir) if task else [])
    for name in candidates:
        found = pr_of_branch(name)
        if found is not None:
            return found
    try:
        return int(json.loads(gh(["pr", "view", "--json", "number"]))["number"])
    except NoteError as exc:
        if "no pull requests found" in str(exc).lower():
            return None
        raise
    except (ValueError, KeyError):
        return None


def list_comments(pr: int) -> List[Dict[str, Any]]:
    """All issue comments on the PR as ``{id, body, html_url, user: {login, type}}`` (read with the owner's login)."""
    out = gh(["api", "repos/{slug}/issues/{pr}/comments".format(slug=gh_app_token.repo(), pr=pr), "--paginate", "--jq",
              ".[] | {id, body, html_url, user: {login: .user.login, type: .user.type}}"])
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


def agent_login_name() -> str:
    """The configured agent login (``tools/agent_login.py``: ``agent_login`` of ``tools/triage/config.json`` only), ``""`` when none."""
    return agent_login.resolve(agent_login.configured(ROOT / "tools" / "triage" / "config.json"))


def gh_logins() -> set:
    """Logins that write through plain ``gh`` (no app role): the owner and, when configured, the agent login."""
    return {login for login in (owner_login(), agent_login_name()) if login}


def owner_login() -> Optional[str]:
    """The owner's GitHub login, remembered for the run. With an agent login configured ``gh`` is the agent, so it is the constant
    ``SFenton`` (comments that mention ``@SFenton`` stay addressed to the owner); otherwise ``gh api user``, ``None`` when unreadable."""
    if agent_login_name():
        return agent_login.OWNER
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
        owners = gh_logins()
        return user.get("login") in owners if owners and user else user.get("type") != "Bot"

    def replaceable(self, comment: Dict[str, Any]) -> bool:
        """Whether ``comment`` is the counterpart this identity may delete after replacing it: the owner's own
        (when an app posts) or one of our apps' (when the owner posts). Anyone else's is never touched."""
        login = (comment.get("user") or {}).get("login") or ""
        if self.role:
            return bool(login) and login in gh_logins()
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


def role_label(kind: str, role: Optional[str]) -> str:
    """The role named in the header: ``--as`` (capitalised) or the kind's usual role."""
    return role.capitalize() if role else KIND_ROLE.get(kind, "Orchestrator")


def header_line(step: int, role: str, round_no: int, head: Optional[str], when: str) -> str:
    """``Step N · Role · round R · head <sha7> · HH:MMZ`` (head left out when unknown)."""
    parts = [f"Step {step}", role, f"round {round_no}"]
    if head:
        parts.append(f"head {head[:7]}")
    return " · ".join([*parts, when])


def compose(body: str, tag: str, note: Optional[str] = None, digest: Optional[str] = None,
            header: Optional[str] = None) -> str:
    """The final comment text: header (with ``note`` appended), body, hash and marker.

    ``digest`` is the hash of the raw body (before upload URLs were substituted) so a re-post compares equal. ``header`` is the
    step header: it is the first line, except that a body whose first line is its own ``**Role**`` header shares that line, and
    a ``#`` heading or an ``@SFenton`` mention stays first with the header at the end of its line (of the first text line after the
    mention)."""
    clean = strip_markers(body)
    lines = clean.split("\n")
    at = 0
    if header is None:
        pass
    elif clean.startswith(MENTION):
        at = 0 if lines[0].strip() != MENTION else next((n for n, x in enumerate(lines) if n and x.strip()), -1)
        if at < 0:
            lines += ["", header]
            at = len(lines) - 1
        else:
            lines[at] = f"{lines[at]} · {header}"
    elif lines[0].startswith("**"):
        lines[0] = f"{header} · {lines[0]}"
    elif lines[0].startswith("#"):  # a heading stays the first line
        lines[0] = f"{lines[0]} · {header}"
    else:
        lines.insert(0, header)
    if note:
        lines[at] = f"{lines[at]} · {note}"
    return f"{chr(10).join(lines)}\n\n<!-- sh-hash:{digest or body_hash(clean)} -->\n{tag}\n"


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


# MARK: - Gates

_WARNED = []


def denylist_required() -> bool:
    """Whether ``tools/triage/config.json`` makes a missing denylist a refusal (``denylist_required`` is true)."""
    try:
        data = json.loads((ROOT / "tools" / "triage" / "config.json").read_text())
    except (OSError, ValueError):
        return False
    return isinstance(data, dict) and data.get("denylist_required") is True


def house_gate(text: str, source: str) -> None:
    """Refuse (``Refusal``) text that holds a term of the house denylist, with the push gate's own list and matcher.

    The message has the hit count and ``source`` only, never a term. A list that is not loaded prints one line and goes on, unless
    ``denylist_required``."""
    patterns = house_scan.load_denylist()
    if not patterns:
        if denylist_required():
            raise Refusal(f"denylist not loaded and denylist_required is true, not posting {source}")
        if not _WARNED:
            _WARNED.append(True)
            print("pr_note: denylist not loaded, house terms were not checked", file=sys.stderr)
        return
    if not prepush_denylist.Matcher(patterns).text(text):
        return
    decoded = house_scan.decode_escapes(text) if "\\" in text else text
    hits = max(sum(len(p.findall(t)) for p in patterns) for t in (text, decoded))
    raise Refusal(f"{max(hits, 1)} house-denylist hit(s) in {source}, not posting")


def manifest_source(path: Path) -> Optional[str]:
    """The ``source`` an evidence ``manifest.json`` gives ``path``: looked up in the file's folder and its parents up to
    ``build/evidence/<branch>/``. A pose entry's ``source`` covers its ``screenshots``, ``recordings`` and ``videos``; a top-level
    ``media`` list holds ``{path, source}``. ``live`` wins over any other entry for the same file; ``None`` when no entry names it."""
    target = path.resolve()
    sources: List[str] = []
    for folder in (path.resolve().parent, *path.resolve().parents):
        manifest = folder / "manifest.json"
        if manifest.is_file():
            try:
                data = json.loads(manifest.read_text())
            except (OSError, ValueError):
                data = {}
            entries = [(m.get("path"), m.get("source")) for m in data.get("media", []) if isinstance(m, dict)]
            for pose in (data.get("poses") or {}).values():
                if isinstance(pose, dict):
                    for key in ("screenshots", "recordings", "videos"):
                        entries += [(f, pose.get("source")) for f in pose.get(key) or [] if isinstance(f, str)]
            for name, source in entries:
                if isinstance(name, str) and isinstance(source, str) and target in {
                        (base / name).resolve() for base in (ROOT, folder)}:
                    sources.append(source)
        if folder.parent.name == "evidence" or folder == folder.parent:
            break
    return "live" if "live" in sources else (sources[0] if sources else None)


def media_gate(text: str, known: Optional[Dict[str, str]] = None) -> None:
    """Refuse (``Refusal``) a local picture or video that is not an atlas render or a demo/mockup manifest entry, or is over 10 MB.

    Paths already uploaded (``known``) were checked when they went up."""
    atlas = (ROOT / ATLAS).resolve()
    for _alt, ref in _MEDIA.findall(text):
        found = _local(ref)
        if not found or ref in (known or {}):
            continue
        under_atlas = found.resolve().is_relative_to(atlas)
        if not under_atlas and manifest_source(found) not in ("demo", "mockup"):
            raise Refusal(f"picture {found.name} is not an atlas render or a demo/mockup entry of an evidence manifest, not posting")
        size = found.stat().st_size
        if size > MAX_MEDIA:
            raise Refusal(f"picture {found.name} is {size / 1048576:.1f} MB, over the {MAX_MEDIA // 1048576} MB limit, not posting")


def gate(text: str, source: str, known: Optional[Dict[str, str]] = None) -> None:
    """Everything that must pass before text is posted or queued: the house denylist first, then the picture rules."""
    house_gate(text, source)
    media_gate(text, known)


# MARK: - Media memory

def notes_root() -> Path:
    """The shared notes folder: ``SH_PR_NOTES_DIR`` when set, else ``~/hass-agents/pr-notes``."""
    return Path(os.environ.get("SH_PR_NOTES_DIR") or NOTES_DIR)


def task_dir(task: str) -> Path:
    """``<notes root>/<task>/`` (created)."""
    path = notes_root() / task
    path.mkdir(parents=True, exist_ok=True)
    return path


def load_media(task: str) -> Dict[str, str]:
    """Local path to uploaded URL, remembered so an edit keeps the pictures."""
    f = task_dir(task) / "media.json"
    return json.loads(f.read_text()) if f.is_file() else {}


def apply_media(text: str, media: Dict[str, str]) -> str:
    """Swap known local paths for their uploaded URLs."""
    return _MEDIA.sub(lambda m: f"![{m.group(1)}]({media[m.group(2)]})" if m.group(2) in media else m.group(0), text)


def load_hashes(task: str) -> Dict[str, Dict[str, Dict[str, str]]]:
    """``{pr: {sha256: {path, caption}}}`` of the files posted so far, next to the URL cache."""
    f = task_dir(task) / "hashes.json"
    return json.loads(f.read_text()) if f.is_file() else {}


def file_hash(path: Path) -> str:
    """SHA-256 of the file's bytes."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dedupe_media(text: str, pr: int, task: str) -> str:
    """Replace the image of a file whose bytes were already posted for this PR (under another path) with ``Same as <caption>``."""
    seen: Dict[str, Dict[str, str]] = dict(load_hashes(task).get(str(pr), {}))
    media = load_media(task)

    def swap(m: "re.Match[str]") -> str:
        found = _local(m.group(2))
        if not found or m.group(2) in media:
            return m.group(0)
        first = seen.setdefault(file_hash(found), {"path": str(found), "caption": m.group(1) or found.name})
        return m.group(0) if first["path"] == str(found) else f"Same as {first['caption']}"
    return _MEDIA.sub(swap, text)


def remember_hashes(pr: int, task: str, sent: str) -> None:
    """After a post, remember the hash of every local file it attached (the first caption wins)."""
    stored = load_hashes(task)
    mine = stored.setdefault(str(pr), {})
    for alt, ref in _MEDIA.findall(sent):
        found = _local(ref)
        if found:
            mine.setdefault(file_hash(found), {"path": str(found), "caption": alt or found.name})
    (task_dir(task) / "hashes.json").write_text(json.dumps(stored, indent=1, sort_keys=True))


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


# MARK: - Steps

_TAG = re.compile(r"<!-- (sh:[a-z]+:[^ ]+) -->$")


def comment_tag(comment: Dict[str, Any], task: str) -> Optional[str]:
    """The marker in the trailer of a helper comment of ``task``, else ``None``."""
    m = _TAG.search((comment.get("body") or "").rstrip())
    return m.group(1) if m and f":{task}:" in m.group(1) else None


def header_of(comment: Dict[str, Any]) -> "Optional[re.Match[str]]":
    """The step header match in the first lines of a comment, else ``None``."""
    return _HEADER.search("\n".join((comment.get("body") or "").splitlines()[:4]))


def step_of(comment: Dict[str, Any]) -> Optional[int]:
    """The step number in a comment's header, else ``None``."""
    m = header_of(comment)
    return int(m.group(1)) if m else None


def next_step(comments: List[Dict[str, Any]], task: str, tag: str, queued: bool = False) -> int:
    """This task's distinct markers already posted (and, with ``queued``, queued) plus one."""
    seen = {t for t in (comment_tag(c, task) for c in comments) if t}
    if queued:
        for path in queue_files(task):
            try:
                n = json.loads(path.read_text())
                seen.add(marker(n["kind"], task, n["round"], n.get("class"))[5:-4])
            except (OSError, ValueError, KeyError):
                continue
    seen.discard(tag[5:-4])
    return len(seen) + 1


# MARK: - Comments

def post_comment(pr: int, task: str, kind: str, cls: Optional[str], round_no: int, body: str,
                 happened: Optional[str] = None, ident: Optional[Identity] = None, role: Optional[str] = None,
                 step: Optional[int] = None, head: Optional[str] = None) -> str:
    """Post or edit the comment for this marker; returns ``posted``, ``edited``, ``replaced`` or ``unchanged``.

    Comments are found by marker whoever wrote them. The identity's own is edited; one by another author is
    replaced (new comment first, then the old one removed) because an app cannot edit the owner's comment. The header shows
    ``step`` (an edit keeps its own), the role, the round, ``head`` and the time (``happened`` for a queued note)."""
    ident = ident or _ACTIVE
    tag = marker(kind, task, round_no, cls)
    body = with_mention(kind, body, ident)
    digest = body_hash(strip_markers(body))
    comments = list_comments(pr)
    matches = [c for c in comments if has_tag(c, tag)]
    shown = dedupe_media(apply_media(body, load_media(task)), pr, task)
    if local_media(shown):  # an installation token cannot upload: this post goes out under the owner's login
        ident = OWNER
    own = next((c for c in matches if ident.mine(c)), None)
    foreign = [c for c in matches if not ident.mine(c) and ident.replaceable(c)]
    label = role_label(kind, role)
    if own:
        m = _HASH.search(own["body"])
        if m and m.group(1) == digest:
            return "unchanged"
        number = step_of(own) or step or next_step(comments, task, tag)
        header = header_line(number, label, round_no, head, now_z())
        ident.edit(own["id"], compose(shown, tag, f"updated {now_z()}", digest, header))
        remember_hashes(pr, task, shown)
        return "edited"
    number = step or next((step_of(c) for c in matches if step_of(c)), None) or next_step(comments, task, tag, happened is None)
    header = header_line(number, label, round_no, head, happened or now_z())
    note = f"happened {happened}, posted when the PR opened" if happened else None
    text = compose(shown, tag, note, digest, header)
    if ident.role:
        ident.create(pr, text)
    else:
        gh(["pr", "comment", str(pr), "--body-file", "-", *attach_args(text)], text)
        remember_media(pr, task, tag, text)
    remember_hashes(pr, task, text)
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

def queue_root(task: str) -> Path:
    """The task's shared queue folder (created)."""
    folder = task_dir(task) / "queue"
    folder.mkdir(exist_ok=True)
    return folder


def queue_files(task: str) -> List[Path]:
    """The queued notes of ``task`` in posting order."""
    return sorted((task_dir(task) / "queue").glob("*.json"))


def unique_stamp(folder: Path, floor: int = 0) -> int:
    """A nanosecond stamp above every one in ``folder`` (and ``floor``), so names sort in posting order."""
    existing = [int(p.name.split("-", 1)[0]) for p in folder.glob("*.json") if p.name.split("-", 1)[0].isdigit()]
    return max([time.time_ns(), floor, *[e + 1 for e in existing]])


def drain_legacy(task: str) -> int:
    """Move the old per-checkout queue ``build/pr-notes/<task>/queue/`` into the shared one, keeping each name (so its time and
    order). Returns how many moved."""
    old = ROOT / "build" / "pr-notes" / task / "queue"
    if not old.is_dir() or old.resolve() == (task_dir(task) / "queue").resolve():
        return 0
    folder, moved = queue_root(task), 0
    for path in sorted(old.glob("*.json")):
        target = folder / path.name
        if target.exists():
            head, _sep, rest = path.name.partition("-")
            target = folder / f"{unique_stamp(folder, int(head) + 1 if head.isdigit() else 0):020d}-{rest}"
        shutil.move(str(path), str(target))
        moved += 1
    return moved


def queue_note(task: str, kind: str, cls: Optional[str], round_no: int, body: str,
               role: Optional[str] = None, step: Optional[int] = None, head: Optional[str] = None) -> Path:
    """Write the note to the task's queue with its original time; names are unique and sort in posting order."""
    folder = queue_root(task)
    stamp = unique_stamp(folder)
    path = folder / f"{stamp:020d}-{kind}-{cls or 'all'}-{round_no}.json"
    path.write_text(json.dumps({"kind": kind, "class": cls, "round": round_no, "body": body, "time": now_z(),
                                "branch": current_branch(), "as": role, "step": step, "head": head}))
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
    for path in queue_files(task):
        n = json.loads(path.read_text())
        if (n["kind"], n["class"], n["round"]) == (kind, cls, round_no):
            path.unlink()


def flush(task: str, pr: int) -> int:
    """Post the queue in order (after draining the legacy one); stops at the first failure so order is kept.

    A queued note is gated again before it goes out. Returns how many were posted."""
    drain_legacy(task)
    count = 0
    for path in queue_files(task):
        n = json.loads(path.read_text())
        gate(n["body"], f"queued note {path.name}", load_media(task))
        post_comment(pr, task, n["kind"], n["class"], n["round"], redact(n["body"]), happened=n["time"],
                     ident=resolve_identity(n.get("as")), role=n.get("as"), step=n.get("step"), head=n.get("head"))
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


def update_block(pr: int, name: str, content: str, task: Optional[str] = None, add_missing: bool = False) -> str:
    """Write one block of the PR body; returns ``updated``, ``unchanged`` or ``no markers`` (``add_missing`` appends the block)."""
    body = json.loads(gh(["pr", "view", str(pr), "--json", "body"]))["body"] or ""
    new = replace_block(body, name, content)
    if new is None and add_missing:
        new = body.rstrip("\n") + f"\n\n<!-- {name}:start -->\n{content.strip(chr(10))}\n<!-- {name}:end -->\n"
    if new is None:
        return "no markers"
    if new == body:
        return "unchanged"
    if task:
        new = dedupe_media(apply_media(new, load_media(task)), pr, task)
    gh(["pr", "edit", str(pr), "--body-file", "-", *attach_args(new)], new)
    if task:
        remember_hashes(pr, task, new)
    return "updated"


# MARK: - Timeline

def first_sentence(comment: Dict[str, Any]) -> str:
    """The first sentence of a step comment's text (140 characters at most), without its header, mention and markers."""
    lines = [ln.strip() for ln in strip_markers(comment.get("body") or "").splitlines()]
    text = next((ln for ln in lines[1:] if ln and not ln.startswith(("@", "<"))), "")
    if not text:  # the text shares the header line
        text = _HEADER.sub("", lines[0] if lines else "")
        text = re.sub(r" · (?:updated|happened) [^·]*", "", text).replace("·", " ")
    text = re.sub(r"[*#`>]+|^\s*[-\d.]+\s+", "", text).strip()
    sentence = re.split(r"(?<=[.!?])\s", " ".join(text.split()), maxsplit=1)[0]
    return sentence[:140].rstrip()


def timeline_lines(comments: List[Dict[str, Any]], task: str) -> List[str]:
    """``N. [Role, round R: first sentence](url)`` for each step posted for ``task``, in step order."""
    rows = []
    for c in comments:
        if comment_tag(c, task):
            m = header_of(c)
            if m:
                rows.append((int(m.group(1)), c.get("id") or 0, m.group(2), int(m.group(3)), c))
    out = []
    for number, _id, role, round_no, c in sorted(rows, key=lambda r: r[:2]):
        label = f"{role}, round {round_no}: {first_sentence(c)}".rstrip(": ")
        out.append(f"{number}. [{label}]({c['html_url']})" if c.get("html_url") else f"{number}. {label}")
    return out


def timeline(pr: int, task: str) -> str:
    """Write the step index into the PR body between the ``sh-timeline`` markers (appended when missing)."""
    lines = timeline_lines(list_comments(pr), task)
    if not lines:
        return "no steps"
    content = "\n".join(lines)
    gate(content, "the timeline")
    return update_block(pr, "sh-timeline", content, add_missing=True)


#: Kept for callers that name it; the body no longer copies text from the template.
TEMPLATE = ROOT / ".github" / "pull_request_template.md"
_BLOCKS = (("sh-devices", "<!-- sh-devices:start -->\n<!-- sh-devices:end -->"),
           ("sh-status", "<!-- sh-status:start -->\n<!-- sh-status:end -->"),
           ("sh-timeline", "<!-- sh-timeline:start -->\n<!-- sh-timeline:end -->"),
           ("review", "<!-- review:start -->\n<!-- review:end -->"))


def follow_template(body: str, template: str = "") -> str:
    """``body`` with the marker blocks it lacks appended; nothing else is added.

    No plain sections or placeholder text are copied from ``template`` (unused, kept for old callers). Existing text, including
    any review block, is kept byte for byte."""
    out = body
    for name, block in _BLOCKS:
        if f"<!-- {name}:start -->" not in out:
            out = out.rstrip("\n") + "\n\n" + block + "\n"
    return out


def init_pr(pr: int, task: str) -> str:
    """Append the marker blocks the PR body lacks, then flush the task's queue (legacy queue included)."""
    body = json.loads(gh(["pr", "view", str(pr), "--json", "body"]))["body"] or ""
    new = follow_template(body)
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
        s.add_argument("--branch", help="find the PR by its head branch")
        s.add_argument("--ledger-dir", help="folder of the task ledger (default: TASKS_DIR or this checkout's build/tasks)")
        s.add_argument("--as", dest="role", choices=ROLES, help="post as this role's GitHub App when its key exists")
        return s

    s = add("post")
    s.add_argument("kind", choices=KINDS)
    s.add_argument("--class", dest="cls", choices=CLASSES)
    s.add_argument("--round", type=int, required=True)
    s.add_argument("--body-file", required=True)
    s.add_argument("--step", type=int, help="step number (default: this task's markers posted or queued, plus one)")
    s.add_argument("--head", help="head commit shown in the header (first 7 characters)")
    add("flush")
    add("init")
    add("timeline")
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


def _lookup(args: argparse.Namespace) -> Optional[int]:
    """The PR for this command: ``--pr``, ``--branch``, the ledger's branches, the current branch."""
    return find_pr(args.pr, args.branch, args.task, args.ledger_dir)


def _post(args: argparse.Namespace) -> str:
    """``post``: gate, find the PR (queue when none), flush, post, then refresh the timeline."""
    body = Path(args.body_file).read_text()
    gate(body, f"body file {Path(args.body_file).name}", load_media(args.task))
    tag = marker(args.kind, args.task, args.round, args.cls)
    try:
        pr = _lookup(args)
        if pr is None:
            step = args.step or next_step([], args.task, tag, queued=True)
            return f"queued {queue_note(args.task, args.kind, args.cls, args.round, body, args.role, step, args.head).name}"
        try:
            flush(args.task, pr)
        except (NoteError, Refusal) as exc:
            print(f"pr_note: warning, queue not flushed: {exc}", file=sys.stderr)
        result = post_comment(pr, args.task, args.kind, args.cls, args.round, redact(body), role=args.role,
                              step=args.step, head=args.head)
        drop_queued(args.task, args.kind, args.cls, args.round)
    except NoteError:
        queue_note(args.task, args.kind, args.cls, args.round, body, args.role, args.step, args.head)
        raise
    if result != "unchanged":
        try:
            timeline(pr, args.task)
        except (NoteError, Refusal) as exc:
            print(f"pr_note: warning, timeline not updated: {exc}", file=sys.stderr)
    return result


def _run(args: argparse.Namespace) -> str:
    """The command itself, with ``_ACTIVE`` set."""
    if args.cmd == "post" and args.kind == "evidence" and not args.cls:
        raise NoteError("evidence needs --class (iphone, duo or ipad)")
    if args.cmd == "post":
        return _post(args)
    if args.cmd == "status":
        gate(args.line, "the status line")
    elif args.cmd == "devices":
        gate(Path(args.file).read_text(), f"file {Path(args.file).name}", load_media(args.task))
    elif args.cmd == "resolve":
        gate(args.text, "the resolve text")
    if args.cmd in ("init", "flush"):
        drain_legacy(args.task)
    pr = _lookup(args)
    if pr is None:
        return "no PR yet"
    if args.cmd == "init":
        return init_pr(pr, args.task)
    if args.cmd == "flush":
        return f"flushed {flush(args.task, pr)}"
    if args.cmd == "timeline":
        return timeline(pr, args.task)
    if args.cmd == "status":
        return update_block(pr, "sh-status", redact(args.line))
    if args.cmd == "devices":
        return update_block(pr, "sh-devices", redact(Path(args.file).read_text()), args.task)
    return resolve_handoff(pr, args.task, args.round, redact(args.text))


def main(argv: Optional[List[str]] = None) -> int:
    """Entry point. A ``gh`` problem prints one warning line and exits 0; a refusal (house data, a picture the rules do not
    allow) prints its reason and exits 1; usage errors exit 2 via argparse."""
    args = build_parser().parse_args(argv)
    try:
        print(f"pr_note: {run(args)}")
    except Refusal as exc:
        print(f"pr_note: refused: {exc}", file=sys.stderr)
        return 1
    except Exception as exc:  # noqa: BLE001 - a comment must never block work
        print(f"pr_note: warning, not posted: {exc}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
