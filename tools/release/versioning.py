#!/usr/bin/env python3
"""App versions, version tags and release-note trailers for S+H (the Fenton HASS Native app).

Ported from FestivalNativeApps ``tools/release/versioning.py`` (iOS only; What's New, TestFlight notes and
store text are not ported because this repo has no release pipeline yet).

Version scheme (the same as FestivalNativeApps): ``YYMM.DD.NN``, e.g. ``2610.26.01``. ``YYMM.DD`` is the UTC
date of the bump and ``NN`` a counter that restarts at ``01`` each day (two digits; at most 99 a day). Versions
live only in annotated git tags ``ios/v<version>`` on the bumped ``main`` commit, so bumping never commits to
``main``. The iPhone/iPad app, its extensions and the Watch app are one product with one version. Mapping:

- ``CFBundleShortVersionString`` / ``MARKETING_VERSION`` = the version (three integers).
- ``CFBundleVersion`` / ``CURRENT_PROJECT_VERSION`` = the build number (``describe --build``).
- ``HassGitSHA`` / ``HASS_GIT_SHA`` = the tagged commit.

A bump only happens when files under the app paths (``PLATFORMS``) changed since the previous tag, so docs,
tests and tooling never mint a version. Notes come from commit trailers on the first-parent history between two
tags::

    Release-Note: Rooms: The room list loads faster.   (any change that touched the app paths)
    Release-Note-iOS: Fixed the Duo hinge crash.        (iOS only, wins over the generic note)
    Release-Note: none                                  (explicitly nothing user-facing)

Commands (JSON on stdout, standard library only, Python 3.9+)::

    versioning.py bump [--force] [--push] [--head SHA] [--now ISO]
    versioning.py describe --tag ios/v2610.26.01 [--build 57]
    versioning.py build-settings --tag ios/v2610.26.01 --build 57   (xcodebuild arguments, one per line)
    versioning.py latest-tag
    versioning.py check-notes --base <sha> --head <sha> [--body-file pr.md]
    versioning.py pending-notes [--head HEAD]

Documentation: .agents/workflow/versioning.md.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import fnmatch
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Optional, Sequence, Tuple

# region Configuration

REPO_ROOT = Path(__file__).resolve().parents[2]
#: Note categories, in display order: the app's pages first. A note written "Rooms: The list loads faster."
#: belongs to Rooms; notes without a known category sort last, after "General".
CATEGORIES = ("Home", "Rooms", "Security", "Cameras", "Climate", "Lights", "Chores", "Food", "Inventory", "Media",
              "Vacuums", "Sprinklers", "Vacation", "Settings", "Notifications", "Live Activities", "Watch",
              "Navigation", "Accessibility", "Performance", "General")
CATEGORY_RE = re.compile(r"^\s*([A-Za-z][A-Za-z &'-]{1,24}):\s+\S")
#: Fallback for notes without a "Category:" prefix: first rule matching the note's opening words wins, then the
#: first rule matching anywhere. Order resolves overlaps ("camera notification" is Cameras).
CATEGORY_RULES: Tuple[Tuple[str, "re.Pattern[str]"], ...] = tuple((c, re.compile(rx, re.IGNORECASE)) for c, rx in (
    ("Cameras", r"\bcameras?\b|\bwebrtc\b|\bhls\b"),
    ("Live Activities", r"live activit|dynamic island"),
    ("Notifications", r"notification|\bpush\b"),
    ("Watch", r"\bwatch\b|apple watch"),
    ("Security", r"\bsecurity\b|\blocks?\b|\balarm"),
    ("Climate", r"climate|thermostat|\bhvac\b"),
    ("Lights", r"\blights?\b"),
    ("Chores", r"\bchores?\b"),
    ("Food", r"\bfood\b|recipe|grocer"),
    ("Inventory", r"inventory|barcode"),
    ("Media", r"\bmedia\b|remote control"),
    ("Vacuums", r"vacuum"),
    ("Sprinklers", r"sprinkler"),
    ("Vacation", r"vacation"),
    ("Settings", r"\bsettings\b|app icon"),
    ("Rooms", r"\brooms?\b"),
    ("Home", r"\bhome (page|screen|tab)\b|\bweather\b"),
    ("Navigation", r"navigation|\bsidebar\b|\bflyout\b|\btabs?\b"),
    ("Accessibility", r"voiceover|accessib|large text|dynamic type|screen reader"),
    ("Performance", r"\bcrash|\bhangs?\b|faster|performance|memory|battery|\bscroll"),
))
TITLE_PREFIX_RE = re.compile(r"^\s*\[[^\]]{1,20}\]\s*")
TITLE_SUFFIX_RE = re.compile(r"\s*\(#\d+\)\s*$")
VERSION_RE = re.compile(r"^(\d{4})\.(\d{2})\.(\d{2})$")
TRAILER_RE = re.compile(r"^\s*Release[- ]Notes?(?:-([A-Za-z]+))?\s*:\s*(.*?)\s*$", re.IGNORECASE)
#: ``Release-Note-Replaces: <earlier note>`` drops an earlier note in the same range (the change supersedes or
#: undoes it); ``Release-Note-Tester: <text>`` is a note for testers only (a fix to a change no release has had).
#: Either may take a platform suffix (``Release-Note-Tester-iOS``).
REVISION_RE = re.compile(r"^\s*Release[- ]Notes?-(Replaces|Tester)(?:-([A-Za-z]+))?\s*:\s*(.*?)\s*$", re.IGNORECASE)
REVERT_RE = re.compile(r"\bThis reverts commit ([0-9a-f]{7,40})\b")
NONE_NOTES = frozenset({"", "none", "n/a", "na", "-", "skip", "no", "internal"})
MERGE_SUBJECT_RE = re.compile(r"^Merge (pull request|branch|remote-tracking branch) ")
PULL_REQUEST_RE = re.compile(r"^Merge pull request #\d+ ")

#: Per platform: app paths (fnmatch, ``*`` crosses ``/``), excluded paths, display name. Only ``ios`` exists: the
#: Watch app, widgets and notification extensions ship inside it under one version. Tests, the mockup atlas and
#: Markdown never mint a version.
PLATFORMS: Dict[str, Dict[str, object]] = {
    "ios": {
        "include": ("apple/Sources/*", "apple/Package.swift", "apple/Package.resolved", "apple/project.yml",
                    "apple/Apps/*", "apple/Design/*"),
        "exclude": ("*.md", "apple/Apps/iOSTests/*", "apple/Apps/iOSUITests/*"),
        "display": "iOS",
    },
}

#: Trailer suffix (lower case) -> platform.
TRAILER_PLATFORMS = {"ios": "ios", "iphone": "ios", "ipad": "ios", "watch": "ios"}

# endregion

# region Versions


def parse_version(text: str) -> Tuple[int, int, int]:
    """Parse ``YYMM.DD.NN`` into ``(yymm, dd, nn)``.

    Args:
        text: Version string such as ``2610.01.01``.

    Returns:
        The comparable ``(yymm, dd, nn)`` triple.

    Raises:
        ValueError: ``text`` is not a ``YYMM.DD.NN`` version.
    """
    found = VERSION_RE.match(text or "")
    if not found or not 1 <= int(found.group(1)[2:]) <= 12 or not 1 <= int(found.group(2)) <= 31 \
            or int(found.group(3)) < 1:
        raise ValueError("not a YYMM.DD.NN version: %r" % text)
    return int(found.group(1)), int(found.group(2)), int(found.group(3))


def is_version(text: str) -> bool:
    """Return whether ``text`` is a ``YYMM.DD.NN`` version."""
    try:
        parse_version(text)
    except ValueError:
        return False
    return True


def format_version(yymm: int, dd: int, nn: int) -> str:
    """Format ``(yymm, dd, nn)`` as ``YYMM.DD.NN`` (``DD`` and ``NN`` zero-padded to two digits).

    Raises:
        ValueError: ``nn`` exceeds the 99 versions a platform may cut per day.
    """
    if not 1 <= nn <= 99:
        raise ValueError("at most 99 versions a day (NN=%d)" % nn)
    return "%04d.%02d.%02d" % (yymm, dd, nn)


def next_version(last: Optional[str], now: _dt.datetime) -> str:
    """Return the version after ``last`` for a bump at ``now``.

    Args:
        last: The platform's newest version, or ``None`` for its first.
        now: Bump time (converted to UTC).

    Returns:
        ``YYMM.DD.01`` on a new day, otherwise ``last`` with ``NN`` + 1. A clock behind ``last``'s day
        keeps counting on ``last``'s day so versions never go backwards.
    """
    utc = now.astimezone(_dt.timezone.utc) if now.tzinfo else now
    today = (int(utc.strftime("%y%m")), utc.day)
    if last is None:
        return format_version(today[0], today[1], 1)
    yymm, dd, nn = parse_version(last)
    if (yymm, dd) >= today:
        return format_version(yymm, dd, nn + 1)
    return format_version(today[0], today[1], 1)


def tag_for(platform: str, version: str) -> str:
    """Return the version tag name, e.g. ``ios/v2610.01.01``."""
    return "%s/v%s" % (platform, version)


def parse_tag(tag: str) -> Tuple[str, str]:
    """Split ``<platform>/v<version>`` (``refs/tags/`` optional) into ``(platform, version)``.

    Raises:
        ValueError: Unknown platform or malformed version.
    """
    name = tag[len("refs/tags/"):] if tag.startswith("refs/tags/") else tag
    platform, _, rest = name.partition("/v")
    if platform not in PLATFORMS or not is_version(rest):
        raise ValueError("not a version tag: %r" % tag)
    return platform, rest


# endregion

# region Git

Runner = Callable[[Sequence[str]], str]


class Git:
    """Thin ``git`` wrapper bound to one repository (injectable for tests)."""

    def __init__(self, root: Path = REPO_ROOT, runner: Optional[Runner] = None) -> None:
        self.root = Path(root)
        self._runner = runner

    def __call__(self, *args: str) -> str:
        """Run ``git <args>`` and return stdout (raises ``RuntimeError`` on failure)."""
        if self._runner is not None:
            return self._runner(list(args))
        proc = subprocess.run(["git", "-C", str(self.root)] + list(args), capture_output=True, text=True)
        if proc.returncode != 0:
            raise RuntimeError("git %s failed: %s" % (" ".join(args[:3]), (proc.stderr or "").strip()[-300:]))
        return proc.stdout

    def rev(self, ref: str) -> str:
        """Resolve ``ref`` to a commit SHA."""
        return self("rev-parse", "%s^{commit}" % ref).strip()

    def is_ancestor(self, ancestor: str, descendant: str) -> bool:
        """True when ``ancestor`` is reachable from ``descendant``."""
        try:
            self("merge-base", "--is-ancestor", ancestor, descendant)
        except RuntimeError:
            return False
        return True

    def version_tags(self, platform: str) -> List[Tuple[str, str]]:
        """Return ``[(version, tag)]`` for ``platform``, newest version first."""
        found = []
        for line in self("tag", "--list", "%s/v*" % platform).splitlines():
            try:
                _, version = parse_tag(line.strip())
            except ValueError:
                continue
            found.append((version, line.strip()))
        found.sort(key=lambda item: parse_version(item[0]), reverse=True)
        return found

    def released_from_tags(self, platform: str) -> List[str]:
        """Versions recorded by ``<platform>/released/<version>`` tags (stores without a history API)."""
        out = []
        for line in self("tag", "--list", "%s/released/*" % platform).splitlines():
            version = line.strip().rsplit("/", 1)[-1]
            if is_version(version):
                out.append(version)
        return sorted(set(out), key=parse_version, reverse=True)

    def first_parent(self, base: Optional[str], head: str) -> List[str]:
        """First-parent commits in ``(base, head]``, newest first."""
        spec = "%s..%s" % (base, head) if base else head
        return [line for line in self("rev-list", "--first-parent", spec).split() if line]

    def parents(self, sha: str) -> List[str]:
        """Parent SHAs of ``sha``."""
        return self("rev-list", "--parents", "-n", "1", sha).split()[1:]

    def changed_files(self, sha: str) -> List[str]:
        """Files ``sha`` changed relative to its first parent (all files for a root commit)."""
        parents = self.parents(sha)
        if parents:
            out = self("diff", "--name-only", "--no-renames", parents[0], sha)
        else:
            out = self("show", "--name-only", "--no-renames", "--format=", sha)
        return [line for line in out.splitlines() if line]

    def tree_files(self, ref: str) -> List[str]:
        """Every file path in ``ref``'s tree."""
        return [line for line in self("ls-tree", "-r", "--name-only", ref).splitlines() if line]

    def diff_files(self, base: str, head: str) -> List[str]:
        """Files changed between ``base`` and ``head``."""
        return [line for line in self("diff", "--name-only", "--no-renames", base, head).splitlines() if line]

    def message(self, sha: str) -> str:
        """Full commit message of ``sha``."""
        return self("log", "-1", "--format=%B", sha)

    def side_messages(self, merge: str) -> List[str]:
        """Messages of the commits a merge brought in (``merge^1..merge`` minus first-parent), leaving out
        commits reverted within the merge and their reverts."""
        parents = self.parents(merge)
        if len(parents) < 2:
            return []
        shas = [s for s in self("rev-list", "%s..%s" % (parents[0], merge)).split() if s and s != merge]
        messages = {s: self.message(s) for s in shas}
        # A commit reverted inside the same merge never shipped: drop it and its revert (with their trailers).
        reverted = {r for m in messages.values() for r in REVERT_RE.findall(m)}
        dropped = {s for s in shas if any(s.startswith(r) for r in reverted)}
        for sha, message in messages.items():
            targets = REVERT_RE.findall(message)
            if targets and all(any(d.startswith(t) for d in dropped) for t in targets):
                dropped.add(sha)
        return [messages[s] for s in shas if s not in dropped]


# endregion

# region Commits and notes


def matches(platform: str, path: str) -> bool:
    """Return whether ``path`` belongs to ``platform``'s shipped app."""
    spec = PLATFORMS[platform]
    if not any(fnmatch.fnmatchcase(path, pat) for pat in spec["include"]):  # type: ignore[union-attr]
        return False
    return not any(fnmatch.fnmatchcase(path, pat) for pat in spec["exclude"])  # type: ignore[union-attr]


def relevant(platform: str, files: Iterable[str]) -> bool:
    """Return whether any of ``files`` belongs to ``platform``'s app."""
    return any(matches(platform, f) for f in files)


def parse_trailers(message: str) -> Dict[str, List[str]]:
    """Return release-note trailers by key: ``"*"`` for generic, else the platform id.

    A value such as ``none`` is kept as an empty list so it suppresses the generic note.
    """
    found: Dict[str, List[str]] = {}
    for line in message.splitlines():
        hit = TRAILER_RE.match(line)
        if not hit:
            continue
        suffix = (hit.group(1) or "").lower()
        key = "*" if not suffix else TRAILER_PLATFORMS.get(suffix)
        if key is None:
            continue
        value = " ".join(hit.group(2).split())
        bucket = found.setdefault(key, [])
        if value.lower() not in NONE_NOTES:
            bucket.append(value)
    return found


def parse_revisions(message: str) -> Tuple[Dict[str, List[str]], Dict[str, List[str]]]:
    """``(replaces, tester)`` trailers by key (``"*"`` generic, else the platform id); see :data:`REVISION_RE`."""
    replaces: Dict[str, List[str]] = {}
    tester: Dict[str, List[str]] = {}
    for line in message.splitlines():
        hit = REVISION_RE.match(line)
        if not hit:
            continue
        value = " ".join(hit.group(3).split())
        suffix = (hit.group(2) or "").lower()
        key = "*" if not suffix else TRAILER_PLATFORMS.get(suffix)
        if key is None or value.lower() in NONE_NOTES:
            continue
        (replaces if hit.group(1).lower() == "replaces" else tester).setdefault(key, []).append(value)
    return replaces, tester


def subject(message: str) -> str:
    """Commit subject; for ``Merge pull request`` commits the PR title from the body."""
    lines = [line.strip() for line in message.splitlines()]
    first = lines[0] if lines else ""
    if MERGE_SUBJECT_RE.match(first):
        body = next((line for line in lines[1:] if line and not TRAILER_RE.match(line)), "")
        return body or first
    return first


class Change:
    """One first-parent commit with what it means for a platform."""

    def __init__(self, sha: str, subject_line: str, app: bool, notes: List[str], opted_out: bool = False,
                 pull_request: bool = False, replaces: Optional[List[str]] = None,
                 tester: Optional[List[str]] = None, reverts: Optional[List[str]] = None) -> None:
        self.sha = sha
        self.subject = subject_line
        self.app = app
        self.notes = notes
        #: A merged pull request (one check-in); ``subject`` is then the PR title.
        self.pull_request = pull_request
        #: The commit's applicable trailer was explicitly ``none`` (nothing user-facing).
        self.opted_out = opted_out
        #: Earlier notes this change supersedes or undoes (``Release-Note-Replaces``).
        self.replaces = replaces or []
        #: Tester-only notes (``Release-Note-Tester``).
        self.tester = tester or []
        #: Commits this change reverts (``This reverts commit <sha>``).
        self.reverts = reverts or []


def changes(git: Git, platform: str, base: Optional[str], head: str) -> List[Change]:
    """Collect ``platform`` changes in ``(base, head]`` (newest first).

    ``app`` is True when the commit (a merge: the whole merged branch) touched the platform's app paths.
    ``notes`` are the platform-specific trailers when present, else the generic trailers for app commits.
    Trailers on a merge's side commits count for the merge.
    """
    out = []
    for sha in git.first_parent(base, head):
        message = git.message(sha)
        messages = [message] + list(git.side_messages(sha))
        trailers: Dict[str, List[str]] = {}
        replaces: Dict[str, List[str]] = {}
        tester: Dict[str, List[str]] = {}
        for text in messages:
            for target, found in zip((trailers, replaces, tester), (parse_trailers(text),) + parse_revisions(text)):
                for key, values in found.items():
                    target.setdefault(key, []).extend(values)
        reverts = [m for text in messages for m in REVERT_RE.findall(text)]
        app = relevant(platform, git.changed_files(sha))
        if platform in trailers:
            notes, opted_out = trailers[platform], not trailers[platform]
        elif app:
            notes, opted_out = trailers.get("*", []), "*" in trailers and not trailers["*"]
        else:
            notes, opted_out = [], False
        mine_tester = tester.get(platform) or (tester.get("*", []) if app else [])
        mine_replaces = replaces.get(platform, []) + replaces.get("*", [])
        if app or notes or mine_tester or mine_replaces or reverts:
            out.append(Change(sha, subject(message), app, notes, opted_out,
                              bool(PULL_REQUEST_RE.match(message.lstrip())), mine_replaces, mine_tester, reverts))
    return out


def clean_title(text: str) -> str:
    """A commit/PR title as a note: no ``[Bug]``-style prefix or ``(#12)`` suffix, first letter capitalized."""
    text = TITLE_SUFFIX_RE.sub("", TITLE_PREFIX_RE.sub("", " ".join(text.split())))
    first = text.split(" ", 1)[0]
    if any(c.isupper() for c in first[1:]):
        return text  # iOS, macOS, CHOpt: keep the brand's casing
    return text[:1].upper() + text[1:]


def note_category(note: str) -> Optional[str]:
    """The known category a note starts with ("Songs: …" → ``Songs``), else ``None``."""
    hit = CATEGORY_RE.match(note)
    if not hit:
        return None
    name = hit.group(1).strip().lower()
    return next((c for c in CATEGORIES if c.lower() == name), None)


def infer_category(note: str) -> Optional[str]:
    """Best-guess category for a note without a prefix (:data:`CATEGORY_RULES`), else ``None``."""
    opening = " ".join(note.split()[:4])
    for text in (opening, note):
        hit = next((c for c, rx in CATEGORY_RULES if rx.search(text)), None)
        if hit:
            return hit
    return None


def category_of(note: str) -> Optional[str]:
    """The note's explicit category prefix, else its inferred category, else ``None``."""
    return note_category(note) or infer_category(note)


def by_category(notes: Iterable[str]) -> List[str]:
    """Notes grouped by category (:func:`category_of`) in ``CATEGORIES`` order, stable within a category;
    uncategorized last."""
    order = {c: i for i, c in enumerate(CATEGORIES)}
    indexed = list(enumerate(notes))
    return [n for _i, n in sorted(indexed, key=lambda item: (order.get(category_of(item[1]) or "", len(order)),
                                                             item[0]))]


def strip_category(note: str) -> str:
    """``note`` without its known category prefix ("Songs: Rows load faster." → "Rows load faster.")."""
    if note_category(note) is None:
        return note
    return note.split(":", 1)[1].strip()



def _note_key(note: str) -> str:
    """Identity of a note for de-duplication and ``Release-Note-Replaces`` matching (category prefix ignored)."""
    return _dedupe_key(strip_category(note))


def _dedupe_key(note: str) -> str:
    """Case-, quote- and whitespace-insensitive identity of a note ("“View All”" equals '"View all"')."""
    for curly, plain in (("“", '"'), ("”", '"'), ("‘", "'"), ("’", "'")):
        note = note.replace(curly, plain)
    return " ".join(note.lower().split())


def user_notes(git: Git, platform: str, base: Optional[str], head: str, tester: bool = False) -> List[str]:
    """User-facing notes in ``(base, head]``: the net difference between ``base`` and ``head``.

    Notes are grouped by category (:func:`by_category`), oldest first within a category. One check-in (a merged
    pull request) is one entry: its ``Release-Note`` trailers, or, when it has none, its cleaned PR title
    (:func:`clean_title`); ``Release-Note: none`` contributes nothing. Commits pushed straight to master without a
    trailer contribute nothing, so individual code commits never become bullets. The ``check-notes`` PR check
    keeps untrailered pull requests rare.

    Later changes revise earlier ones in the range: ``Release-Note-Replaces: <note>`` removes that earlier note
    (a superseding change brings its own ``Release-Note``; an undo says ``Release-Note: none``), and a revert
    (``This reverts commit <sha>``) removes the reverted change's notes. Notes differing only in case, quotes,
    spacing or category prefix appear once. ``tester`` adds ``Release-Note-Tester`` notes (TestFlight's list
    for one build).
    """
    kept: Dict[str, str] = {}
    added: Dict[str, List[str]] = {}
    for change in reversed(changes(git, platform, base, head)):
        for reverted in change.reverts:
            for sha, keys in added.items():
                if sha.startswith(reverted):
                    for key in keys:
                        kept.pop(key, None)
        for text in change.replaces:
            target = _note_key(text)
            for key in [k for k in kept if k == target or (len(target) >= 20 and k.startswith(target))]:
                kept.pop(key)
        notes = list(change.notes)
        if (not notes and change.app and change.pull_request and not change.opted_out and change.subject
                and not change.tester and not change.reverts and not change.replaces):
            notes = [clean_title(change.subject)]
        if tester:
            notes += change.tester
        added[change.sha] = []
        for note in notes:
            key = _note_key(note)
            if note and key not in kept:
                kept[key] = note
                added[change.sha].append(key)
    return by_category(list(kept.values()))



# endregion

# region Pending notes


def pending_notes(git: Git, platform: str, head: str = "HEAD", released: Iterable[str] = ()) -> Dict[str, object]:
    """Notes users will get that the latest release lacks: what a change may ``Release-Note-Replaces``.

    The release is the newest of ``released`` and ``<platform>/released/<v>`` tags that has a version tag
    (``None``: everything so far). Returns ``{platform, release, notes, tester}``; ``tester`` adds the
    ``Release-Note-Tester`` notes of the range.
    """
    tags = dict(git.version_tags(platform))
    shipped = sorted({v for v in list(released) + git.released_from_tags(platform) if is_version(v) and v in tags},
                     key=parse_version)
    base = tags[shipped[-1]] if shipped else None
    notes = user_notes(git, platform, base, head)
    everything = user_notes(git, platform, base, head, tester=True)
    keys = {_note_key(n) for n in notes}
    return {"platform": platform, "release": shipped[-1] if shipped else None, "notes": notes,
            "tester": [n for n in everything if _note_key(n) not in keys]}


def notes_check(git: Git, base: str, head: str, body: str = "") -> Dict[str, object]:
    """PR gate: a change touching any platform's app paths must carry a ``Release-Note`` trailer.

    Args:
        git: Repository.
        base: PR base commit; the diff starts at its merge base with ``head``.
        head: PR head commit.
        body: PR description (trailers there end up in the merge commit).

    Returns:
        ``{platforms, has_release_note, ok}``; ``none`` counts as a trailer (an explicit "nothing user-facing").
    """
    fork = git("merge-base", base, head).strip()
    touched = [p for p in PLATFORMS if relevant(p, git.diff_files(fork, head))]
    messages = [git.message(sha) for sha in git("rev-list", "%s..%s" % (fork, head)).split() if sha]
    has = any(TRAILER_RE.match(line) for text in messages + [body] for line in text.splitlines())
    return {"platforms": touched, "has_release_note": has, "ok": bool(has or not touched)}


# endregion

# region Bump


def plan_bump(git: Git, platform: str, head: str, now: _dt.datetime, force: bool = False) -> Dict[str, object]:
    """Decide whether ``platform`` needs a new version at ``head``.

    Returns:
        ``{platform, bump, reason, version?, tag?, previous?}``; ``bump`` is False when ``head`` already
        carries a version tag, is older than the previous tag, or no app path changed since the previous tag
        (unless ``force``).
    """
    tags = git.version_tags(platform)
    previous = tags[0] if tags else None
    result: Dict[str, object] = {"platform": platform, "previous": previous[0] if previous else None}
    head_sha = git.rev(head)
    if previous and git.rev(previous[1]) == head_sha:
        return dict(result, bump=False, reason="already_tagged")
    if previous and not git.is_ancestor(previous[1], head_sha):
        # A late run for an older push: the newer tag already covers this commit.
        return dict(result, bump=False, reason="behind_previous_tag")
    if previous is None:
        if not relevant(platform, git.tree_files(head_sha)):
            return dict(result, bump=False, reason="no_app_files")
        reason = "first_version"
    elif relevant(platform, git.diff_files(previous[1], head_sha)):
        reason = "app_changed"
    elif force:
        reason = "forced"
    else:
        return dict(result, bump=False, reason="no_app_changes")
    version = next_version(previous[0] if previous else None, now)
    return dict(result, bump=True, reason=reason, version=version, tag=tag_for(platform, version), sha=head_sha)


def bump(git: Git, platforms: Iterable[str], head: str, now: _dt.datetime, force: bool = False,
         push: bool = False) -> Dict[str, object]:
    """Tag every platform that needs a version at ``head``; optionally push the tags.

    Returns:
        ``{bumped: [plan], skipped: [plan]}``.
    """
    bumped, skipped = [], []
    for platform in platforms:
        plan = plan_bump(git, platform, head, now, force)
        if not plan["bump"]:
            skipped.append(plan)
            continue
        tag = str(plan["tag"])
        git("tag", "-a", tag, str(plan["sha"]), "-m",
            "%s %s (%s)" % (PLATFORMS[platform]["display"], plan["version"], plan["reason"]))
        if push:
            git("push", "origin", "refs/tags/%s" % tag)
        bumped.append(plan)
    return {"bumped": bumped, "skipped": skipped}


# endregion

# region CLI

#: The platform every command acts on (the repository ships one app).
PLATFORM = "ios"


def describe(git: Git, tag: str, build: Optional[int] = None) -> Dict[str, object]:
    """Return the facts a build needs about ``tag``: version, SHA, previous version and the Xcode settings."""
    platform, version = parse_tag(tag)
    tags = git.version_tags(platform)
    older = [v for v, _ in tags if parse_version(v) < parse_version(version)]
    sha = git.rev(tag)
    out: Dict[str, object] = {"platform": platform, "version": version, "tag": tag, "sha": sha,
                              "previous": older[0] if older else None}
    if build is not None:
        out["build"] = str(build)
    return out


def build_settings(git: Git, tag: str, build: int) -> List[str]:
    """``xcodebuild`` build-setting arguments that stamp ``tag``'s version, ``build`` and commit.

    The settings are the ones ``apple/project.yml`` reads for every target (app, extensions and Watch app):
    ``MARKETING_VERSION``, ``CURRENT_PROJECT_VERSION`` and ``HASS_GIT_SHA``.
    """
    facts = describe(git, tag, build)
    return ["MARKETING_VERSION=%s" % facts["version"], "CURRENT_PROJECT_VERSION=%s" % facts["build"],
            "HASS_GIT_SHA=%s" % facts["sha"]]


def release_notes(git: Git, tag: str) -> str:
    """Markdown release notes for ``tag``: the ``Release-Note:`` trailers since the previous version tag.

    The first version covers every commit before it. With no user-facing change the text says so, so a
    GitHub Release is never empty.
    """
    platform, version = parse_tag(tag)
    older = [v for v, _ in git.version_tags(platform) if parse_version(v) < parse_version(version)]
    base = tag_for(platform, older[0]) if older else None
    notes = user_notes(git, platform, base, tag)
    lines = ["## What's new in %s" % version, ""]
    lines += ["- %s" % note for note in notes] or ["- Internal changes only."]
    if base:
        lines += ["", "Changes since `%s`." % base]
    return "\n".join(lines) + "\n"


def build_parser() -> argparse.ArgumentParser:
    """Create the command-line parser."""
    parser = argparse.ArgumentParser(prog="versioning.py", description=__doc__.split("\n")[0])
    parser.add_argument("--repo", default=str(REPO_ROOT))
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("bump", help="tag HEAD with the next ios/v<YYMM.DD.NN> when the app changed")
    p.add_argument("--head", default="HEAD")
    p.add_argument("--now", help="ISO time (default: now, UTC)")
    p.add_argument("--force", action="store_true", help="bump even without app changes since the previous tag")
    p.add_argument("--push", action="store_true", help="push the new tag to origin")
    p = sub.add_parser("describe")
    p.add_argument("--tag", required=True)
    p.add_argument("--build", type=int)
    p = sub.add_parser("build-settings", help="xcodebuild arguments stamping the tag's version, build and commit")
    p.add_argument("--tag", required=True)
    p.add_argument("--build", type=int, required=True)
    sub.add_parser("latest-tag")
    p = sub.add_parser("notes", help="Markdown release notes for a tag (Release-Note trailers since the previous tag)")
    p.add_argument("--tag", required=True)
    p = sub.add_parser("check-notes")
    p.add_argument("--base", required=True)
    p.add_argument("--head", required=True)
    p.add_argument("--body-file")
    p = sub.add_parser("pending-notes", help="notes since the latest release, for Release-Note-Replaces")
    p.add_argument("--head", default="HEAD")
    p.add_argument("--released", default="", help="comma-separated released versions (plus ios/released/ tags)")
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    """Run the CLI; returns the exit code (0 ok, 1 failure)."""
    args = build_parser().parse_args(argv)
    git = Git(Path(args.repo))
    try:
        if args.command == "bump":
            now = (_dt.datetime.fromisoformat(args.now.replace("Z", "+00:00")) if args.now
                   else _dt.datetime.now(_dt.timezone.utc))
            doc: object = bump(git, [PLATFORM], args.head, now, args.force, args.push)
        elif args.command == "describe":
            doc = describe(git, args.tag, args.build)
        elif args.command == "build-settings":
            print("\n".join(build_settings(git, args.tag, args.build)))
            return 0
        elif args.command == "notes":
            print(release_notes(git, args.tag), end="")
            return 0
        elif args.command == "latest-tag":
            tags = git.version_tags(PLATFORM)
            doc = {"platform": PLATFORM, "tag": tags[0][1] if tags else None,
                   "version": tags[0][0] if tags else None}
        elif args.command == "check-notes":
            body = Path(args.body_file).read_text(encoding="utf-8") if args.body_file else ""
            doc = notes_check(git, args.base, args.head, body)
            print(json.dumps(doc))
            if not doc["ok"]:
                print("This change touches app code but has no Release-Note trailer. Add "
                      "'Release-Note: <specific user-facing change>' (or 'Release-Note-iOS: ...'), or "
                      "'Release-Note: none' when users see nothing, to the PR description or a commit message.",
                      file=sys.stderr)
                return 1
            return 0
        else:
            doc = pending_notes(git, PLATFORM, args.head, [v.strip() for v in args.released.split(",") if v.strip()])
    except (ValueError, RuntimeError, OSError) as err:
        print(json.dumps({"error": str(err)}))
        return 1
    print(json.dumps(doc))
    return 0


# endregion

if __name__ == "__main__":
    sys.exit(main())
