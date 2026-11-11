#!/usr/bin/env python3
"""Keep a pull request followable from the PR alone: one comment per step, plus the status, device and timeline blocks.

Roles call this instead of typing ``gh``. Every comment carries a marker so the helper finds its own earlier comment
and edits it in place (never ``--edit-last``: every role shares one login). Spec: ``build/research/visual-prs.md``
sections J and K.6.

Commands::

    pr_note.py post KIND --task T [--class C] --round N --body-file F [--pr N] [--branch B] [--as ROLE] [--step N [--now]] [--head SHA]
    pr_note.py flush --task T [--pr N] [--as ROLE]
    pr_note.py status --task T --line TEXT [--pr N]
    pr_note.py devices --task T --file F [--pr N]
    pr_note.py timeline --task T [--pr N]
    pr_note.py resolve --task T --round N --text TEXT [--pr N] [--as ROLE]
    pr_note.py init --task T [--pr N]

Every command also takes ``--branch B`` and ``--ledger-dir D`` (see "Finding the PR").

Kinds are ``pick``, ``evidence``, ``verdict``, ``owner``, ``handoff``, ``shipped`` and, one for each role that had none,
``research`` (Researcher), ``build`` (Coder), ``review`` (Reviewer) and ``retro`` (Steward). An ``evidence`` comment is per
device class (``iphone``, ``duo`` for iPhone Duo, ``ipad``); a class with nothing to show gets no comment.

Which comment a post means (the marker): with ``--step N`` it is the kind plus the step, ``<!-- sh:<kind>:<task>:s<N> -->``
(evidence: ``<!-- sh:evidence:<task>:<class>:s<N> -->``), so two notes of one kind in one round are two comments and
``--round`` is only the text in the header. Without ``--step`` it is the older form, the kind plus the round
(``<!-- sh:<kind>:<task>:<round> -->``, ``<!-- sh:evidence:<task>:<class>:<round> -->``). Both forms are read on every
pull request: a post by step also finds the round-form comment of its kind whose header shows that step, a post by round
also finds the single step-form comment of its kind with that round, and an edit keeps the marker the comment has.

Step order: a new comment with ``--step N`` is held in the queue (result ``held ...``, exit 0) while a step below N is not
on the pull request, and goes out right after its predecessors (the next ``post``, ``flush`` or ``init``), so the page reads
in step order. ``--now`` sends it at once with one warning line. An edit is never held.

Header: every comment has its own heading line ``#### Step N · <Role> · round R · head <sha7> · HH:MMZ`` (head only when
``--head`` is given, 7 to 40 hex characters), then a blank line and the body unchanged. ``N`` is ``--step`` or, when absent, the count of this task's distinct markers already posted or queued, plus one;
an edit keeps its number. The role is ``--as`` or the kind's usual role (Researcher, Designer, Coder, Verifier,
Reviewer, Steward, Orchestrator). A body that starts with its own ``#`` heading keeps it first and the header follows;
an app's ``@SFenton`` mention stays first. A comment in the older glued form is rewritten in the new one on its next post.

Behaviour:

- A body hash is stored in the comment; an unchanged body is a no-op, a changed one edits the comment and adds
  "updated HH:MMZ" to its header line, a new marker posts a new comment. The hash counts each local picture by its bytes, so
  a retaken or corrected picture is a change and the same picture under another name is not.
- Finding the PR: ``--pr N``; else ``--branch B`` (``gh pr list --head B``; nothing else is tried when B has none yet); else
  the current branch's PR; else, only when the task ledger (``build/tasks/<task>.json``, directory ``--ledger-dir``, ``TASKS_DIR``
  or this checkout's ``build/tasks``) lists branches and the current branch is not one of them, the single open PR among them
  (named on stderr). The ledger is never needed to queue.
- A queued note has one target, fixed when it is queued: a PR (its number, plus its head branch when it was read) or a branch
  with no PR yet (``--branch B``, else the writer's current branch). A write that names neither, from a checkout whose branch a
  readable ledger does not list (or with no branch checked out), is refused: exit 1, ``pass --pr N or --branch B``. A note is
  sent to a PR only when its target is that PR's number or its target branch is that PR's head branch. A note with no target
  (written by an older version) is sent only by a run with ``--pr`` or ``--branch`` while the ledger lists at most one branch.
  Every ``flush``, ``init`` and ``post`` ends with one stderr line per note left queued (kind, round, target, reason).
- With no PR yet the note is queued under ``~/hass-agents/pr-notes/<task>/queue/`` (``SH_PR_NOTES_DIR`` overrides the
  folder; shared by every worktree) with its original time, and ``flush`` posts the queue in order once the PR exists (a queued note whose marker is posted with the same body is dropped;
  with a different body it is applied as an edit; one that is refused or fails stays queued, is reported, and the notes behind it
  still go out)
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
  Every manifest shape is read by ``tools/evidence_manifest.py`` (path strings, ``{"path", "source"}`` objects, the
  ``"media"`` list); a pose that did not run names no picture.
- The picture rule (``resolve_picture``): a body names a picture by a path relative to the checkout or to the branch's
  evidence folder (``build/evidence/<branch>/``); it is looked for in this checkout and in the repository's other worktrees
  (evidence stays in the worktree that captured it). An absolute path under one of those checkouts is rewritten to the
  relative one before the house denylist reads the text; an absolute path anywhere else is refused (exit 1) and the message
  never shows the path. A picture is its bytes: the URL cache (``media.json``) and the posted-file list (``hashes.json``)
  are keyed by SHA-256, and a file takes the URL at its own place in the posted comment, never by counting over the comment.
  The same bytes are uploaded once per PR: in any later comment, class or path the image becomes
  ``Same as <first caption or file name>``; a picture that differs is uploaded.
- ``status`` and ``devices`` replace only the text between their own ``sh-status`` / ``sh-devices`` markers in the PR
  body. Everything else, including the reviewer's block, is left byte for byte.
- ``timeline`` rewrites the text between ``<!-- sh-timeline:start -->`` and ``<!-- sh-timeline:end -->`` (appended when
  missing) with one line per posted step, in order: ``N. [Role, round R: first sentence](comment url)``. ``post``
  runs it after a post that changed something; a failure there only warns.
- Local images and videos referenced as markdown paths are attached with ``gh pr comment --attach`` /
  ``gh pr edit --attach`` from a temporary folder under neutral names, so no local path is ever in the text sent; the
  URLs GitHub returns are remembered so an edit keeps them. An edit cannot upload: a changed comment with a picture that is
  not uploaded yet is posted anew (same step and marker) and the old copy removed, result ``replaced``.
- ``init`` (run once, right after ``ship.sh`` opens the PR) appends any missing ``sh-devices`` / ``sh-status`` /
  ``sh-timeline`` / review marker block to the PR body, existing text untouched and no placeholder text added; then it
  flushes the task's queue. ``post`` also flushes the task's queue first and drops queued entries for a marker it just
  posted (those with this PR as their target), so a stale queued note never overwrites a newer comment.
- ``--as ROLE`` (orchestrator, researcher, designer, coder, verifier, reviewer, steward, menial, triage): when that
  role's GitHub App key exists (``tools/gh_app_token.py``) comments are posted and edited through the REST API with
  its installation token; otherwise one stderr line and the owner's ``gh`` login, exactly as without ``--as``. When the
  app call itself fails, one stderr line ``pr_note: <role> app failed (<reason>); posted with the gh login`` (the error's
  own message, redacted) and the comment goes out with the ``gh`` login: a note is never lost, and a queued note for a
  failing role never blocks the queue. REST paths use the repository of ``origin``, not the ``repo`` of ``apps.json``.
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
import contextlib
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterator, List, Optional

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from redact import redact as _redact
except ImportError:  # pragma: no cover - redact ships in the repo
    _redact = None
import agent_login  # noqa: E402
import evidence_manifest  # noqa: E402
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
_SHA = re.compile(r"^[0-9a-f]{64}$")
#: Extensions GitHub shows as a player, not as an image reference.
VIDEO = (".mp4", ".mov", ".webm")


class NoteError(Exception):
    """A ``gh`` or input problem; ``main`` turns it into one warning line and exit 0."""


class AppFailed(NoteError):
    """A role's GitHub App call failed; ``str`` is the redacted reason (status code and API path, never a secret)."""


class Refusal(Exception):
    """House data or a picture the rules do not allow: ``main`` prints the reason (never a term) and exits 1."""


def redact(text: str) -> str:
    """Run text through ``tools/redact.py``; refuses (so nothing posts unredacted) when it cannot be imported."""
    if _redact is None:
        raise NoteError("tools/redact.py unavailable, not posting")
    return _redact(text)


def head_sha(value: str) -> str:
    """Validate ``--head`` (7 to 40 hexadecimal characters)."""
    if not re.fullmatch(r"[0-9a-fA-F]{7,40}", value):
        raise argparse.ArgumentTypeError(f"bad head {value!r}: 7 to 40 hex characters")
    return value.lower()


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


def pr_of_branch(branch: str, state: str = "all") -> Optional[int]:
    """The newest PR whose head is ``branch`` (``state``: ``open`` or ``all``), else ``None``."""
    rows = json.loads(gh(["pr", "list", "--head", branch, "--state", state, "--limit", "1", "--json", "number"]) or "[]")
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
            ledger_dir: Optional[str] = None) -> "tuple[Optional[int], str]":
    """``(PR number, head branch)``: ``--pr``, else ``--branch``, else the current branch's PR, else the single open PR of the
    task ledger's branches; ``(None, "")`` when there is no PR yet. The head is ``""`` when ``gh`` cannot read it.

    ``--branch B`` decides alone: when B has no PR nothing else is tried. The ledger is read only when the current branch is not
    one of its branches (a lane's own branch names its PR, never a sibling's); two or more open PRs raise ``NoteError``."""
    if explicit:
        return int(explicit), pr_head_branch(int(explicit))
    if branch:
        found = pr_of_branch(branch)
        return found, branch if found is not None else ""
    try:
        number = int(json.loads(gh(["pr", "view", "--json", "number"]))["number"])
        return number, pr_head_branch(number)
    except NoteError as exc:
        if "no pull requests found" not in str(exc).lower():
            raise
    except (ValueError, KeyError):
        pass
    listed = ledger_branches(task, ledger_dir) if task else []
    if not listed or current_branch() in listed:
        return None, ""
    open_prs = {pr_of_branch(name, "open"): name for name in listed}
    open_prs.pop(None, None)
    if len(open_prs) > 1:
        raise NoteError(f"task {task} has {len(open_prs)} branches with open pull requests "
                        f"({', '.join(f'#{n}' for n in sorted(open_prs))}); pass --pr N or --branch B")
    for number, name in open_prs.items():
        print(f"pr_note: using #{number} ({name}): the current branch has no pull request and it is the only open one among "
              f"the task's ledger branches", file=sys.stderr)
        return number, name
    return None, ""


def repo_slug() -> str:
    """``owner/name`` the PR lives in: the environment or ``origin`` of this checkout, else the ``repo`` of ``apps.json``.

    ``apps.json`` can name a renamed repository, whose REST path lists no comments, so it comes last."""
    try:
        return gh_app_token.default_repo()
    except Exception:  # noqa: BLE001 - no remote: fall back to the apps file
        return gh_app_token.repo()


def list_comments(pr: int) -> List[Dict[str, Any]]:
    """All issue comments on the PR as ``{id, body, html_url, user: {login, type}}`` (read with the owner's login)."""
    out = gh(["api", "repos/{slug}/issues/{pr}/comments".format(slug=repo_slug(), pr=pr), "--paginate", "--jq",
              ".[] | {id, body, html_url, user: {login: .user.login, type: .user.type}}"])
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def patch_comment(comment_id: Any, body: str) -> None:
    """Replace the text of one comment with the owner's login."""
    gh(["api", "-X", "PATCH", "repos/{slug}/issues/comments/{id}".format(slug=repo_slug(), id=comment_id),
        "--input", "-"],
       json.dumps({"body": body}))


def remove_comment(comment_id: Any) -> None:
    """Remove one comment with the owner's login (the old copy after a change of author)."""
    gh(["api", "-X", "DELETE", "repos/{slug}/issues/comments/{id}".format(slug=repo_slug(), id=comment_id)])


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

def reason_of(exc: BaseException) -> str:
    """The error's own message (``ExcName`` when it has none), through ``tools/redact.py`` when it can be imported."""
    text = " ".join(str(exc).split()) or type(exc).__name__
    return (_redact(text) if _redact else text)[:200]


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
        self.call("POST", "repos/{slug}/issues/{pr}/comments".format(slug=repo_slug(), pr=pr), {"body": text})

    def edit(self, comment_id: Any, text: str) -> None:
        """Edit one of this identity's own comments."""
        if not self.role:
            patch_comment(comment_id, text)
            return
        self.call("PATCH", "repos/{slug}/issues/comments/{id}".format(slug=repo_slug(), id=comment_id),
                  {"body": text})

    def call(self, method: str, path: str, payload: Dict[str, Any]) -> None:
        """One REST call with the role's installation token."""
        try:
            gh_app_token.api_request(method, path, gh_app_token.token(self.role or ""), payload)
        except Exception as exc:  # noqa: BLE001 - the caller falls back to the gh login instead of losing the note
            raise AppFailed(reason_of(exc)) from None


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
        print(f"pr_note: app identity for {role} failed ({reason_of(exc)}), posting as the owner login", file=sys.stderr)
        return OWNER
    print(f"pr_note: no app identity for {role}, posting as the owner login", file=sys.stderr)
    return OWNER


def with_mention(kind: str, body: str, ident: Identity) -> str:
    """App comments of kind handoff or owner start with ``@SFenton`` so GitHub Mobile pushes the owner."""
    if ident.role and kind in MENTION_KINDS and not body.lstrip().startswith(MENTION):
        return f"{MENTION}\n\n{body.lstrip()}"
    return body


# MARK: - Text

def marker(kind: str, task: str, round_no: int, cls: Optional[str] = None, step: Optional[int] = None) -> str:
    """The comment marker: kind (evidence: kind and device class) plus the step, ``s<step>``, when ``step`` is given.

    Without ``step`` it is the older form keyed by the round, which is still written for a post that names no step and
    still read on every pull request that carries it."""
    key = f"s{step}" if step is not None else str(round_no)
    if kind == "evidence":
        return f"<!-- sh:evidence:{task}:{cls}:{key} -->"
    return f"<!-- sh:{kind}:{task}:{key} -->"


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

    ``digest`` is ``digest_of`` the body (each local picture counted by its bytes) so a re-post compares equal. ``header`` is
    its own line, ``#### Step N · ...``, then a blank line, then the body unchanged. A body that starts with its own ``#``
    heading keeps it first and gets the header as the next line; an ``@SFenton`` mention stays first, the header follows it."""
    clean = strip_markers(body)
    lines = clean.split("\n")
    if header is None:
        if note:
            lines[0] = f"{lines[0]} · {note}"
        return f"{chr(10).join(lines)}\n\n<!-- sh-hash:{digest or body_hash(clean)} -->\n{tag}\n"
    shown = f"#### {header}" + (f" · {note}" if note else "")
    if clean.startswith(MENTION):
        text = f"{lines[0]}\n\n{shown}\n\n" + "\n".join(lines[1:]).lstrip("\n")
    elif lines[0].startswith("#"):  # a heading stays the first line
        text = f"{lines[0]}\n{shown}\n\n" + "\n".join(lines[1:]).lstrip("\n")
    else:
        text = f"{shown}\n\n{clean}"
    return f"{text.rstrip()}\n\n<!-- sh-hash:{digest or body_hash(clean)} -->\n{tag}\n"


# MARK: - Pictures

_CHECKOUTS: Dict[str, List[Path]] = {}


def checkouts() -> List[Path]:
    """This checkout first, then the other worktrees of the same repository (``git worktree list``), remembered for the run.

    Evidence is git-ignored and lives in the worktree that captured it, so a picture is looked for in all of them."""
    key = str(ROOT)
    if key not in _CHECKOUTS:
        found = [ROOT]
        try:
            out = subprocess.run(["git", "worktree", "list", "--porcelain"], capture_output=True, text=True,
                                 timeout=TIMEOUT, cwd=ROOT)
            lines = out.stdout.splitlines() if out.returncode == 0 else []
        except (OSError, subprocess.SubprocessError):
            lines = []
        for line in lines:
            path = Path(line[len("worktree "):]) if line.startswith("worktree ") else None
            if path and path.is_dir() and path.resolve() != ROOT.resolve():
                found.append(path)
        _CHECKOUTS[key] = found
    return _CHECKOUTS[key]


def checkout_of(path: Path) -> Optional[Path]:
    """The checkout (``checkouts``) that holds ``path``, else ``None``. Worktrees can sit inside one another (a lane worktree
    under the primary checkout), so the deepest one wins."""
    best: Optional[Path] = None
    for form in (Path(os.path.abspath(path)), path.resolve()):
        for root in checkouts():
            for base in (root, root.resolve()):
                if form.is_relative_to(base) and (best is None or len(base.parts) > len(best.parts)):
                    best = base
    return best


def evidence_slug() -> str:
    """The evidence folder name of the current branch (``/`` replaced by ``-``), ``""`` with no branch."""
    branch = current_branch()
    return "" if branch in ("", "HEAD") else branch.replace("/", "-")


def resolve_picture(ref: str, position: int = 0) -> "tuple[str, Optional[Path]]":
    """The one picture rule: ``(the reference the text keeps, the local file or None)`` for a markdown image target.

    A URL is kept and is not local. A relative path is looked for under this checkout, the working directory, this branch's
    evidence folder (``build/evidence/<branch>/``), then the same repository's other worktrees, then as a path inside exactly
    one evidence folder of any of them; the text keeps it as written. An absolute path under one of the checkouts is
    rewritten to the path relative to that checkout, whether or not the file exists, so a home folder name never reaches
    the denylist or the comment. An absolute path anywhere else is refused (``Refusal``) with a message that names its
    ``position`` in the text and never the path."""
    if re.match(r"^(https?:|data:|mailto:|#)", ref):
        return ref, None
    if ref.startswith(("file:", "~")) or os.path.isabs(ref):
        path = Path("/" + ref[len("file:"):].lstrip("/")) if ref.startswith("file:") else Path(ref).expanduser()
        root = checkout_of(path)
        if root is None:
            raise Refusal(f"picture {position or 1} of the text has an absolute path outside this repository's checkouts; "
                          "name it relative to the evidence folder or the checkout, not posting")
        form = next(f for f in (Path(os.path.abspath(path)), path.resolve()) if f.is_relative_to(root))
        return form.relative_to(root).as_posix(), (form if form.is_file() else None)
    name = ref[2:] if ref.startswith("./") else ref
    roots = checkouts()
    for candidate in (roots[0] / name, Path(name)):
        if candidate.is_file():
            return ref, candidate
    slug = evidence_slug()
    candidates = [roots[0] / "build" / "evidence" / slug / name] if slug else []
    candidates += [root / name for root in roots[1:]]
    candidates += [root / "build" / "evidence" / slug / name for root in roots[1:]] if slug else []
    for candidate in candidates:
        if candidate.is_file():
            return ref, candidate
    inside = [folder / name for root in roots for folder in sorted((root / "build" / "evidence").glob("*"))
              if (folder / name).is_file()]
    return ref, (inside[0] if len(inside) == 1 else None)


def normalize_pictures(text: str) -> str:
    """``text`` with every picture reference in the form ``resolve_picture`` keeps (absolute paths made relative)."""
    count = [0]

    def swap(m: "re.Match[str]") -> str:
        count[0] += 1
        return f"![{m.group(1)}]({resolve_picture(m.group(2), count[0])[0]})"
    return _MEDIA.sub(swap, text)


def _local(path: str) -> Optional[Path]:
    """The local file a picture reference names (``resolve_picture``), ``None`` for a URL or a missing file."""
    return resolve_picture(path)[1]


def local_media(text: str) -> List[str]:
    """Paths of markdown media references that exist on disk, in order."""
    return [p for _a, p in _MEDIA.findall(text) if _local(p)]


def file_hash(path: Path) -> str:
    """SHA-256 of the file's bytes: the identity of a picture."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def digest_of(body: str) -> str:
    """The hash an "unchanged" check compares: the body with each local picture reference replaced by its file's SHA-256.

    A picture swapped for another file, or the same path with new bytes, changes it; the same bytes under another name do not."""
    def swap(m: "re.Match[str]") -> str:
        found = _local(m.group(2))
        return f"![{m.group(1)}](sha256:{file_hash(found)})" if found else m.group(0)
    return body_hash(strip_markers(_MEDIA.sub(swap, body)))


# MARK: - Gates

_WARNED = []


def denylist_required() -> bool:
    """Whether ``tools/triage/config.json`` makes a missing denylist a refusal (``house_scan.denylist_required``)."""
    return house_scan.denylist_required(ROOT / "tools" / "triage" / "config.json")


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
    ``build/evidence/<branch>/``, never above the checkout that holds the file. Every manifest shape is read by
    ``evidence_manifest.media_entries`` (path strings with a pose-level ``source``, ``{path, source}`` objects, a top-level
    ``media`` list). ``live`` wins over any other entry for the same file; ``None`` when no entry names it."""
    target = path.resolve()
    sources: List[str] = []
    root = (checkout_of(path) or ROOT).resolve()
    for folder in (target.parent, *target.parents):
        if folder != target.parent and not folder.is_relative_to(root):
            break  # never climb out of the checkout
        manifest = folder / "manifest.json"
        if manifest.is_file():
            for entry in evidence_manifest.media_entries(evidence_manifest.read(manifest)):
                if isinstance(entry["source"], str) and target in {
                        (base / entry["path"]).resolve() for base in (root, folder)}:
                    sources.append(entry["source"])
        if folder.parent.name == "evidence" or folder == root or folder == folder.parent:
            break
    return "live" if "live" in sources else (sources[0] if sources else None)


def media_gate(text: str, known: Optional[Dict[str, str]] = None) -> None:
    """Refuse (``Refusal``) a local picture or video that is not an atlas render or a demo/mockup manifest entry, or is over 10 MB.

    Files whose bytes were uploaded before (``known``, keyed by SHA-256) were checked when they went up."""
    for position, (_alt, ref) in enumerate(_MEDIA.findall(text), start=1):
        found = resolve_picture(ref, position)[1]
        if not found or file_hash(found) in (known or {}):
            continue
        atlas = ((checkout_of(found) or ROOT) / ATLAS).resolve()
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


def prepare(text: str, source: str, known: Optional[Dict[str, str]] = None) -> str:
    """``text`` made fit to post or queue: picture paths in their kept form first (``normalize_pictures``), then ``gate``.

    Returns the text to use from here on; raises ``Refusal`` as ``gate`` does."""
    text = normalize_pictures(text)
    gate(text, source, known)
    return text


# MARK: - Media memory

def notes_root() -> Path:
    """The shared notes folder: ``SH_PR_NOTES_DIR`` when set, else ``~/hass-agents/pr-notes``."""
    return Path(os.environ.get("SH_PR_NOTES_DIR") or NOTES_DIR)


def task_dir(task: str) -> Path:
    """``<notes root>/<task>/`` (created)."""
    path = notes_root() / task
    path.mkdir(parents=True, exist_ok=True)
    return path


def _read_json(path: Path) -> Dict[str, Any]:
    """A JSON object from ``path``; ``{}`` when it is missing, unreadable or not an object."""
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def load_media(task: str) -> Dict[str, str]:
    """File SHA-256 to uploaded URL, remembered so an edit keeps the pictures.

    Entries an older version keyed by path are not trusted (a later picture could carry an earlier one's URL): they are
    ignored and go at the next write, so such a picture is uploaded once more."""
    data = _read_json(task_dir(task) / "media.json")
    return {key: url for key, url in data.items() if _SHA.match(key) and isinstance(url, str)}


def load_hashes(task: str) -> Dict[str, Dict[str, Dict[str, str]]]:
    """``{pr: {sha256: {path, caption, owner}}}`` of the files posted so far, next to the URL cache. ``owner`` is the marker
    of the comment (or the block of the description) that shows the picture; ``path`` is only the reference it was named by."""
    return _read_json(task_dir(task) / "hashes.json")


class Rendered:
    """A text made fit to send: ``text`` (uploaded pictures as their URLs, repeated ones as ``Same as``, new files under their
    staged names ``<sha256><suffix>``), ``new`` (staged name to local file) and ``pics`` (hash, caption and reference of each
    picture the text shows)."""

    def __init__(self, text: str, new: Dict[str, Path], pics: List[Dict[str, str]]) -> None:
        self.text = text
        self.new = new
        self.pics = pics


def _owned(prior: Dict[str, str], owner: str, ref: str, found: Path) -> bool:
    """Whether the remembered picture ``prior`` is shown by ``owner`` itself (an entry from an older version: by its path)."""
    if "owner" in prior:
        return prior["owner"] == owner
    old = prior.get("path") or ""
    return old == ref or (bool(old) and os.path.abspath(old) == os.path.abspath(found))


def render(text: str, pr: int, task: str, owner: str) -> Rendered:
    """Resolve every local picture of ``text`` by its bytes, for the comment or block ``owner``.

    A file another owner shows on this PR, or that appears earlier in this text, becomes ``Same as <first caption>``: the
    same picture for iPhone, iPhone Duo and iPad is posted once whatever its path or class. A file with a remembered URL
    becomes that URL. Any other file is new: its reference becomes the staged name ``<sha256><suffix>`` for ``staged``."""
    seen = load_hashes(task).get(str(pr), {})
    media = load_media(task)
    here: Dict[str, str] = {}
    new: Dict[str, Path] = {}
    pics: List[Dict[str, str]] = []

    def swap(m: "re.Match[str]") -> str:
        alt, ref = m.group(1), m.group(2)
        found = _local(ref)
        if not found:
            return m.group(0)
        sha = file_hash(found)
        if sha in here:
            return f"Same as {here[sha]}"
        prior = seen.get(sha)
        if isinstance(prior, dict) and not _owned(prior, owner, ref, found):
            return f"Same as {prior.get('caption') or found.name}"
        here[sha] = alt or found.name
        pics.append({"sha": sha, "caption": alt or found.name, "path": ref})
        if sha in media:
            return f"![{alt}]({media[sha]})"
        name = sha + found.suffix.lower()
        new[name] = found
        return f"![{alt}]({name})"
    return Rendered(_MEDIA.sub(swap, text), new, pics)


@contextlib.contextmanager
def staged(text: str, new: Dict[str, Path]) -> "Iterator[tuple[List[str], Optional[str]]]":
    """``(gh arguments, stdin)`` that send ``text`` with its ``new`` files (``render``) attached.

    With no new file the text goes over stdin. Otherwise the files are copied under their staged names into a temporary
    folder next to the body file and passed with ``--attach``: ``gh`` reads the paths in a body file relative to its
    folder, so each reference is rewritten to its own uploaded asset, and no local path is in the text at any point."""
    if not new:
        yield ["--body-file", "-"], text
        return
    with tempfile.TemporaryDirectory(prefix="pr-note-") as tmp:
        folder = Path(tmp).resolve()  # one spelling of the folder, so the reference and the attached file are the same path
        args = ["--body-file", str(folder / "body.md")]
        for name, source in new.items():
            shutil.copyfile(source, folder / name)
            args += ["--attach", str(folder / name)]
        (folder / "body.md").write_text(text)
        yield args, None


def remember_hashes(pr: int, task: str, owner: str, pics: List[Dict[str, str]]) -> None:
    """After a post, remember each picture it shows by its hash, with its caption and ``owner`` (the first one wins)."""
    if not pics:
        return
    stored = load_hashes(task)
    mine = stored.setdefault(str(pr), {})
    for pic in pics:
        entry = mine.setdefault(pic["sha"], {"path": pic["path"], "caption": pic["caption"], "owner": owner})
        entry.setdefault("owner", owner)
    (task_dir(task) / "hashes.json").write_text(json.dumps(stored, indent=1, sort_keys=True))


def _images(text: str) -> List[str]:
    """The targets of the image references of ``text`` in order (a video is shown as a player, not as a reference)."""
    return [ref for _alt, ref in _MEDIA.findall(text) if not ref.lower().endswith(VIDEO)]


def remember_media(task: str, sent: str, posted: str, new: Dict[str, Path]) -> int:
    """After an upload, remember the URL of each new file by its hash. Returns how many were learned.

    The i-th image of the text that was sent is the i-th image of what GitHub now shows, so a file takes the URL at its own
    place and never one that belongs to an earlier picture. When the two do not line up nothing is remembered (the file
    is uploaded again next time) and one line says so."""
    if not new:
        return 0
    mine, theirs = _images(sent), _images(posted)
    if len(mine) != len(theirs):
        print("pr_note: warning, the posted pictures do not line up with the sent ones; their URLs were not remembered",
              file=sys.stderr)
        return 0
    media, learned = load_media(task), 0
    for ref, url in zip(mine, theirs):
        if ref in new and url.startswith("https://"):
            media[Path(ref).stem] = url
            learned += 1
        elif ref in new:
            print(f"pr_note: warning, picture {Path(ref).suffix or ref} was not attached by gh", file=sys.stderr)
    (task_dir(task) / "media.json").write_text(json.dumps(media, indent=1, sort_keys=True))
    return learned


# MARK: - Steps

_TAG = re.compile(r"<!-- (sh:[a-z]+:[^ ]+) -->$")


def tag_parts(inner: str, task: str) -> "Optional[tuple[str, Optional[str], str]]":
    """``(kind, class, key)`` of a marker's inner text (``sh:pick:T:1``, ``sh:evidence:T:duo:s4``), ``None`` when it is not
    one of ``task``. The key is ``s<step>`` in the step form and the round number in the older form."""
    head, sep, rest = inner.partition(f":{task}:")
    if not sep or not head.startswith("sh:"):
        return None
    kind, parts = head[3:], rest.split(":")
    if kind == "evidence":
        return (kind, parts[0], parts[1]) if len(parts) == 2 else None
    return (kind, None, parts[0]) if len(parts) == 1 else None


def find_matches(comments: List[Dict[str, Any]], task: str, kind: str, cls: Optional[str], round_no: int,
                 step: Optional[int] = None) -> "tuple[str, List[Dict[str, Any]]]":
    """``(marker, comments that carry it)`` for one note: by step when ``step`` is given, else by round.

    The exact marker wins. Otherwise the other form is read, so no posted comment is orphaned: a post by step finds the
    comment of its kind (and class) in the older round form whose header shows that step; a post by round finds the single
    comment of its kind in the step form whose header shows that round (two or more such comments decide nothing). The
    marker returned is the one the comment carries, so an edit keeps it."""
    exact = marker(kind, task, round_no, cls, step)
    hits = [c for c in comments if has_tag(c, exact)]
    if hits:
        return exact, hits
    groups: Dict[str, List[Dict[str, Any]]] = {}
    for c in comments:
        inner = comment_tag(c, task)
        parts = tag_parts(inner, task) if inner else None
        header = header_of(c)
        if not parts or not header or parts[:2] != (kind, cls if kind == "evidence" else None):
            continue
        stepped = parts[2].startswith("s")
        if (step is not None and not stepped and int(header.group(1)) == step) or (
                step is None and stepped and int(header.group(3)) == round_no):
            groups.setdefault(str(inner), []).append(c)
    if len(groups) == 1:
        inner, hits = groups.popitem()
        return f"<!-- {inner} -->", hits
    return exact, []


def missing_steps(comments: List[Dict[str, Any]], task: str, step: int) -> List[int]:
    """The steps below ``step`` that no comment of ``task`` on the PR shows yet."""
    have = {step_of(c) for c in comments if comment_tag(c, task)}
    return [n for n in range(1, step) if n not in have]


def note_tag(note: Dict[str, Any], task: str) -> str:
    """The marker of a queued note: by its step when it was queued with ``--step``, else by its round."""
    return marker(note["kind"], task, note["round"], note.get("class"), note.get("step") if by_step(note) else None)


def by_step(note: Dict[str, Any]) -> bool:
    """Whether a queued note is identified by its step (queued with ``--step``); notes from an older version are not."""
    return note.get("ident") == "step" and isinstance(note.get("step"), int)


def comment_tag(comment: Dict[str, Any], task: str) -> Optional[str]:
    """The marker in the trailer of a helper comment of ``task``, else ``None``."""
    m = _TAG.search((comment.get("body") or "").rstrip())
    return m.group(1) if m and f":{task}:" in m.group(1) else None


def header_of(comment: Dict[str, Any]) -> "Optional[re.Match[str]]":
    """The step header match in the first lines of a comment, else ``None``."""
    return _HEADER.search("\n".join((comment.get("body") or "").splitlines()[:6]))


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
                seen.add(note_tag(n, task)[5:-4])
            except (OSError, ValueError, KeyError):
                continue
    seen.discard(tag[5:-4])
    return len(seen) + 1


# MARK: - Comments

def post_comment(pr: int, task: str, kind: str, cls: Optional[str], round_no: int, body: str,
                 happened: Optional[str] = None, ident: Optional[Identity] = None, role: Optional[str] = None,
                 step: Optional[int] = None, head: Optional[str] = None, stepped: bool = False) -> str:
    """Post or edit the comment for this note; returns ``posted``, ``edited``, ``replaced`` or ``unchanged``.

    The comment is found by ``find_matches`` (by ``step`` when ``stepped``, else by round) whoever wrote it. The identity's
    own is edited; one by another author is replaced (new comment first, then the old one removed) because an app cannot
    edit the owner's comment, and so is the identity's own when the new text has a picture that is not uploaded yet (an edit
    cannot upload). The header shows ``step`` (an edit keeps its own), the role, the round, ``head`` and the time
    (``happened`` for a queued note). When the role's app call fails, one stderr line names the reason and the note is
    posted with the ``gh`` login instead."""
    ident = ident or _ACTIVE
    try:
        return _post_as(ident, pr, task, kind, cls, round_no, body, happened, role, step, head, stepped)
    except AppFailed as exc:
        print(f"pr_note: {ident.role} app failed ({exc}); posted with the gh login", file=sys.stderr)
        return _post_as(OWNER, pr, task, kind, cls, round_no, body, happened, role, step, head, stepped)


def _post_as(ident: Identity, pr: int, task: str, kind: str, cls: Optional[str], round_no: int, body: str,
             happened: Optional[str], role: Optional[str], step: Optional[int], head: Optional[str],
             stepped: bool = False) -> str:
    """``post_comment`` for one identity; raises ``AppFailed`` when that identity is an app whose call failed."""
    body = with_mention(kind, body, ident)
    digest = digest_of(body)  # after the pictures are resolved: a changed or corrected picture is a changed body
    comments = list_comments(pr)
    tag, matches = find_matches(comments, task, kind, cls, round_no, step if stepped else None)
    shown = render(body, pr, task, tag)
    if shown.new:  # an installation token cannot upload: this post goes out under the owner's login
        ident = OWNER
    own = next((c for c in matches if ident.mine(c)), None)
    foreign = [c for c in matches if not ident.mine(c) and ident.replaceable(c)]
    label = role_label(kind, role)
    note = f"happened {happened}, posted when the PR opened" if happened else None
    if own:
        m = _HASH.search(own["body"])
        if m and m.group(1) == digest and "#### Step " in own["body"]:  # an older, glued header is rewritten
            return "unchanged"
        number = step_of(own) or step or next_step(comments, task, tag)
        if not shown.new:
            header = header_line(number, label, round_no, head, now_z())
            ident.edit(own["id"], compose(shown.text, tag, f"updated {now_z()}", digest, header))
            remember_hashes(pr, task, tag, shown.pics)
            return "edited"
        step, note, foreign = number, f"updated {now_z()}", [own, *foreign]  # a new file: post anew, then drop the old copy
    number = step or next((step_of(c) for c in matches if step_of(c)), None) or next_step(comments, task, tag, happened is None)
    header = header_line(number, label, round_no, head, happened or now_z())
    text = compose(shown.text, tag, note, digest, header)
    if ident.role:
        ident.create(pr, text)
    else:
        with staged(text, shown.new) as (body_args, stdin):
            gh(["pr", "comment", str(pr), *body_args], stdin)
        if shown.new:
            posted = next((c for c in reversed(list_comments(pr)) if has_tag(c, tag)), None)
            if posted:
                remember_media(task, text, posted["body"], shown.new)
    remember_hashes(pr, task, tag, shown.pics)
    for old in foreign:
        try:
            remove_comment(old["id"])
        except NoteError:
            pass
    return "replaced" if foreign else "posted"


def resolve_handoff(pr: int, task: str, round_no: int, text: str, ident: Optional[Identity] = None) -> str:
    """Make the round's handoff start with ``**Resolved:**`` (another author's comment is edited as the owner)."""
    ident = ident or _ACTIVE
    _tag, matches = find_matches(list_comments(pr), task, "handoff", None, round_no)
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


def queue_note(task: str, kind: str, cls: Optional[str], round_no: int, body: str, target: "tuple[Optional[int], str]",
               role: Optional[str] = None, step: Optional[int] = None, head: Optional[str] = None,
               stepped: bool = False, now: bool = False) -> Path:
    """Write the note to the task's queue with its original time and its ``target`` (``queue_target``); names are unique and
    sort in posting order. ``stepped``: the note was given ``--step`` and is identified by it (``"ident": "step"``);
    ``now``: it is not held back for lower steps."""
    folder = queue_root(task)
    stamp = unique_stamp(folder)
    path = folder / f"{stamp:020d}-{kind}-{cls or 'all'}-{round_no}.json"
    path.write_text(json.dumps({"kind": kind, "class": cls, "round": round_no, "body": body, "time": now_z(),
                                "pr": target[0], "branch": target[1], "as": role, "step": step, "head": head,
                                "ident": "step" if stepped and step is not None else "round", "now": bool(now)}))
    return path


def current_branch() -> str:
    """The branch checked out in this checkout (``""`` when git cannot say, ``HEAD`` when none is)."""
    try:
        return subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True,
                              timeout=TIMEOUT, cwd=ROOT).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def pr_head_branch(pr: int) -> str:
    """The head branch of PR ``pr`` (``""`` when it cannot be read)."""
    try:
        return str(json.loads(gh(["pr", "view", str(pr), "--json", "headRefName"])).get("headRefName") or "")
    except (NoteError, ValueError, AttributeError):
        return ""


def queue_target(task: str, pr: Optional[int], head: str, branch: Optional[str],
                 ledger_dir: Optional[str] = None) -> "tuple[Optional[int], str]":
    """The one target a note is queued with: ``(pr, its head branch)`` when the PR is known, else ``(None, branch)`` for
    ``--branch`` or the writer's current branch.

    Refuses (``Refusal``) instead of guessing when nothing names the target and the writer's branch cannot be it: no branch is
    checked out, or a readable ledger for the task lists branches and this one is not among them."""
    if pr is not None:
        return pr, head
    if branch:
        return None, branch
    writer, listed = current_branch(), ledger_branches(task, ledger_dir)
    if writer in ("", "HEAD") or (listed and writer not in listed):
        where = f"the current branch {writer} is not one of the task's ledger branches" if listed else "no branch is checked out"
        raise Refusal(f"nothing says which pull request this note is for ({where}), not queued; pass --pr N or --branch B")
    return None, writer


def target_text(note: Dict[str, Any]) -> str:
    """A queued note's target in words: ``#N (head)``, ``branch B`` or ``no target`` (a note from an older version)."""
    number, branch = note.get("pr"), note.get("branch") or ""
    if number:
        return f"#{number} ({branch})" if branch else f"#{number}"
    return f"branch {branch}" if branch else "no target"


def is_for(note: Dict[str, Any], pr: int, head: str) -> bool:
    """Whether the note's target is PR ``pr`` (head branch ``head``): the same number, or the same branch. Nothing else."""
    branch = note.get("branch") or ""
    return note.get("pr") == pr or bool(branch and branch == head)


_WHY: Dict[str, str] = {}


def report_left(task: str, pr: Optional[int], head: str = "", waiting: str = "waiting for a pull request") -> int:
    """One stderr line for every note still queued: kind, round, target and why it was not sent (``waiting`` when this run
    reached no PR). Returns the count."""
    left = queue_files(task)
    for path in left:
        try:
            n = json.loads(path.read_text())
            if path.name in _WHY:
                why = _WHY[path.name]
            elif not (n.get("pr") or n.get("branch")):
                why = "written without a target; sent only with --pr or --branch while the task ledger lists at most one branch"
            elif pr is None:
                why = waiting
            elif is_for(n, pr, head):
                why = "its send failed; kept for the next flush"
            else:
                why = f"this is #{pr} ({head or 'head unknown'})"
            print(f"pr_note: queued {n['kind']} round {n['round']} for {target_text(n)} not sent ({path.name}): {why}",
                  file=sys.stderr)
        except (OSError, KeyError, ValueError) as exc:
            print(f"pr_note: warning, queued note {path.name} unreadable and kept: {exc}", file=sys.stderr)
    return len(left)


def drop_queued(task: str, kind: str, cls: Optional[str], round_no: int, pr: int, head: str,
                step: Optional[int] = None, stepped: bool = False) -> None:
    """Remove queued notes for the note that was just posted to PR ``pr`` (head ``head``): only those whose target is that PR
    and that are the same note (same kind and class, and the same step when ``stepped``, else the same round)."""
    for path in queue_files(task):
        try:
            n = json.loads(path.read_text())
            same = (by_step(n) and n["step"] == step) if stepped else (not by_step(n) and n["round"] == round_no)
            if (n["kind"], n["class"]) == (kind, cls) and same and is_for(n, pr, head):
                path.unlink()
        except (OSError, KeyError, ValueError):
            continue


def flush(task: str, pr: int, head: str, named: bool = False, ledger_dir: Optional[str] = None, quiet: bool = False,
          only: Optional[set] = None, keep_why: bool = False) -> int:
    """Post the queued notes whose target is PR ``pr`` (head branch ``head``), in order. Returns how many were posted.

    Every other note stays queued untouched. A note with no target (older version) goes only when the run named its PR (``named``:
    ``--pr`` or ``--branch``) and the ledger lists at most one branch. A queued note is gated again before it goes out. One whose
    comment is on the PR with the same body (hash) is dropped; with a different body it is applied as an edit, so an update that
    failed once is not lost. A role whose app fails is posted with the ``gh`` login. A note that is refused or fails stays queued
    and the notes behind it still go out.

    Step order: a note queued with ``--step N`` (and without ``--now``) whose comment is not on the PR waits while a step
    below N is not posted there; the queue is passed over again after every pass that sent something, so it goes out right
    after its predecessors and the page reads in step order. ``only`` limits the run to those file names; ``keep_why`` keeps
    the reasons an earlier flush of this run recorded. Unless ``quiet``, it ends with one stderr line per note left queued
    (``report_left``); if any was refused, ``Refusal`` is raised after that (exit 1)."""
    drain_legacy(task)
    if not keep_why:
        _WHY.clear()
    if not head:  # sending only the notes recorded by number would post them out of order
        raise NoteError(f"the head branch of #{pr} could not be read, queue not flushed")
    count, refused = 0, []
    idents: Dict[Optional[str], Identity] = {}
    comments = list_comments(pr)
    untargeted = named and len(ledger_branches(task, ledger_dir)) <= 1
    tried: set = set()
    progressed, stale = True, False
    while progressed:
        progressed = False
        for path in queue_files(task):
            if path.name in tried or (only is not None and path.name not in only):
                continue
            try:
                n = json.loads(path.read_text())
                if not (is_for(n, pr, head) or (untargeted and not (n.get("pr") or n.get("branch")))):
                    continue
                if stale:
                    comments, stale = list_comments(pr), False
                stepped = by_step(n)
                body = normalize_pictures(n["body"])
                _tag, matches = find_matches(comments, task, n["kind"], n.get("class"), n["round"],
                                             n["step"] if stepped else None)
                posted = next((_HASH.search(c["body"]) for c in matches), None)
                if posted and posted.group(1) == digest_of(redact(body)):
                    path.unlink()
                    continue
                if stepped and not matches and not n.get("now"):
                    missing = missing_steps(comments, task, n["step"])
                    if missing:
                        _WHY[path.name] = f"held until step {missing[0]} is posted (--now sends it at once)"
                        continue
                tried.add(path.name)
                gate(body, f"queued note {path.name}", load_media(task))
                role = n.get("as")
                if role not in idents:
                    idents[role] = resolve_identity(role)
                post_comment(pr, task, n["kind"], n["class"], n["round"], redact(body), happened=n["time"],
                             ident=idents[role], role=role, step=n.get("step"), head=n.get("head"), stepped=stepped)
            except Refusal as exc:
                _WHY[path.name] = f"refused: {exc}"
                refused.append(path.name)
                tried.add(path.name)
                continue
            except (NoteError, KeyError, ValueError) as exc:
                _WHY[path.name] = f"send failed: {exc}"
                tried.add(path.name)
                continue
            path.unlink()
            _WHY.pop(path.name, None)
            count += 1
            progressed = stale = True
    if not quiet:
        report_left(task, pr, head)
    if refused:
        raise Refusal(f"{len(refused)} queued note(s) refused and kept in the queue")
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
    """Write one block of the PR body; returns ``updated``, ``unchanged`` or ``no markers`` (``add_missing`` appends the block).

    With ``task`` the block's local pictures follow the picture rule (``render``, owner ``body:<name>``): uploaded ones keep
    their URL, new ones are attached and remembered by their bytes."""
    body = json.loads(gh(["pr", "view", str(pr), "--json", "body"]))["body"] or ""
    owner = f"body:{name}"
    shown = render(content, pr, task, owner) if task else Rendered(content, {}, [])
    new = replace_block(body, name, shown.text)
    if new is None and add_missing:
        new = body.rstrip("\n") + f"\n\n<!-- {name}:start -->\n{shown.text.strip(chr(10))}\n<!-- {name}:end -->\n"
    if new is None:
        return "no markers"
    if new == body:
        return "unchanged"
    with staged(new, shown.new) as (body_args, stdin):
        gh(["pr", "edit", str(pr), *body_args], stdin)
    if task:
        if shown.new:
            remember_media(task, new, json.loads(gh(["pr", "view", str(pr), "--json", "body"]))["body"] or "", shown.new)
        remember_hashes(pr, task, owner, shown.pics)
    return "updated"


# MARK: - Timeline

def first_sentence(comment: Dict[str, Any]) -> str:
    """The first sentence of a step comment's text (140 characters at most), without its header, mention and markers.

    The header is its own line; an older comment has the text on the header line, which is read too."""
    text = ""
    for ln in (x.strip() for x in strip_markers(comment.get("body") or "").splitlines()):
        if _HEADER.search(ln):
            ln = _HEADER.sub("", ln)
            ln = re.sub(r" · (?:updated|happened) [^·]*", "", ln).replace("·", " ")
            ln = ln.replace("####", "")
        if ln.strip() and not ln.startswith(("@", "<")):
            text = ln
            break
    lead = re.sub(r"^\*\*[^*]+\*\*\s*", "", text)  # a bold lead-in such as "**What I did.**" is a label, not the sentence
    text = re.sub(r"[*#`>]+|^\s*[-\d.]+\s+", "", lead if lead.strip() else text).strip()
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


def init_pr(pr: int, task: str, head: str, named: bool = False, ledger_dir: Optional[str] = None) -> str:
    """Append the marker blocks the PR body lacks, then flush the task's queue (legacy queue included)."""
    body = json.loads(gh(["pr", "view", str(pr), "--json", "body"]))["body"] or ""
    new = follow_template(body)
    state = "body kept"
    if new != body:
        gh(["pr", "edit", str(pr), "--body-file", "-"], new)
        state = "body updated"
    return f"{state}, flushed {flush(task, pr, head, named, ledger_dir)}"


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
    s.add_argument("--step", type=int, help="step number; it identifies the comment (default: this task's markers posted "
                   "or queued, plus one, and the comment is then identified by its round)")
    s.add_argument("--now", action="store_true", help="with --step: send at once even when a lower step is not posted yet")
    s.add_argument("--head", type=head_sha, help="head commit shown in the header (7 to 40 hex characters; first 7 shown)")
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


def _lookup(args: argparse.Namespace) -> "tuple[Optional[int], str]":
    """The PR for this command and its head branch (``find_pr``)."""
    return find_pr(args.pr, args.branch, args.task, args.ledger_dir)


def _post(args: argparse.Namespace) -> str:
    """``post``: prepare the body (picture paths, gates), find the PR, flush, post, then refresh the timeline.

    With no PR yet, or when ``gh`` fails, the note is queued with its one target (``queue_target``, which refuses a write that
    names none). A new comment with ``--step N`` is held in the queue (result ``held ...``) while a step below N is not on the
    PR, unless ``--now``; after a post the notes held behind it are sent. Every run ends with one stderr line per note left
    queued."""
    body = prepare(Path(args.body_file).read_text(), f"body file {Path(args.body_file).name}", load_media(args.task))
    named = bool(args.pr or args.branch)
    stepped = args.step is not None
    pr, head, failed, result, held = (int(args.pr) if args.pr else None), "", None, "", None
    try:
        pr, head = _lookup(args)
        if pr is not None:
            if not head:
                raise NoteError(f"the head branch of #{pr} could not be read")
            try:
                flush(args.task, pr, head, named, args.ledger_dir, quiet=True)
            except (NoteError, Refusal) as exc:
                print(f"pr_note: warning, queue not flushed: {exc}", file=sys.stderr)
            if stepped:
                comments = list_comments(pr)
                if not find_matches(comments, args.task, args.kind, args.cls, args.round, args.step)[1]:
                    missing = missing_steps(comments, args.task, args.step)
                    if missing and args.now:
                        print(f"pr_note: warning, step {args.step} posted before step {missing[0]}; the page is out of step "
                              f"order", file=sys.stderr)
                    elif missing:
                        held = missing[0]
            if held is None:
                result = post_comment(pr, args.task, args.kind, args.cls, args.round, redact(body), role=args.role,
                                      step=args.step, head=args.head, stepped=stepped)
                drop_queued(args.task, args.kind, args.cls, args.round, pr, head, args.step, stepped)
                waiting = {name for name, why in _WHY.items() if why.startswith("held")}
                if waiting and result != "unchanged":
                    try:
                        flush(args.task, pr, head, named, args.ledger_dir, quiet=True, only=waiting, keep_why=True)
                    except (NoteError, Refusal) as exc:
                        print(f"pr_note: warning, held notes not sent: {exc}", file=sys.stderr)
    except NoteError as exc:
        failed = exc
    if pr is None or failed or held is not None:
        target = queue_target(args.task, pr, head, args.branch, args.ledger_dir)
        step = args.step
        if not (step or failed):
            step = next_step([], args.task, marker(args.kind, args.task, args.round, args.cls), queued=True)
        name = queue_note(args.task, args.kind, args.cls, args.round, body, target, args.role, step, args.head,
                          stepped, args.now).name
        if held is not None:
            _WHY[name] = f"held until step {held} is posted (--now sends it at once)"
        report_left(args.task, pr, head)
        if failed:
            raise failed
        return f"held {name}: step {held} is not posted yet" if held is not None else f"queued {name}"
    report_left(args.task, pr, head)
    if result != "unchanged":
        try:
            state = timeline(pr, args.task)
            if state in ("no steps", "no markers"):
                print(f"pr_note: warning, timeline not updated: {state}", file=sys.stderr)
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
        devices = prepare(Path(args.file).read_text(), f"file {Path(args.file).name}", load_media(args.task))
    elif args.cmd == "resolve":
        gate(args.text, "the resolve text")
    if args.cmd in ("init", "flush"):
        drain_legacy(args.task)
        try:
            pr, head = _lookup(args)
            if pr is not None:
                named = bool(args.pr or args.branch)
                if args.cmd == "init":
                    return init_pr(pr, args.task, head, named, args.ledger_dir)
                return f"flushed {flush(args.task, pr, head, named, args.ledger_dir)}"
        except NoteError:
            report_left(args.task, None, waiting="gh failed in this run; kept for the next flush")
            raise
        report_left(args.task, None)
        return "no PR yet"
    pr, _head = _lookup(args)
    if pr is None:
        return "no PR yet"
    if args.cmd == "timeline":
        return timeline(pr, args.task)
    if args.cmd == "status":
        return update_block(pr, "sh-status", redact(args.line))
    if args.cmd == "devices":
        return update_block(pr, "sh-devices", redact(devices), args.task)
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
