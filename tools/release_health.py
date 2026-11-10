#!/usr/bin/env python3
"""Release health: one open issue per silent release failure.

    tools/release_health.py check [--repo OWNER/REPO] [--head REF] [--dist-not-after TEXT] [--dev-not-after TEXT] [--dry-run]

Run daily by ``.github/workflows/release-health.yml``. Three classes, each with a stable issue title and the label
``Workflow``:

* ``no-tag``: ``main`` has app changes since the newest ``ios/v*`` tag and that tag is older than 7 days. The "app
  changed since the previous tag" test is ``versioning.plan_bump`` (``tools/release/versioning.py``, imported, never
  copied), so the two cannot drift apart.
* ``release-failed``: the newest completed ``ios-release`` run on ``main`` concluded ``failure``. Cancelled and skipped
  runs are passed over (a dropped pending bump is not a failure).
* ``cert-expiry``: the Apple Distribution or Apple Development p12 expires in under 45 days. The workflow reads the two
  ``notAfter`` dates in a separate job (the only one with the signing environment) and hands over only those dates.

An open issue is created when a class fails and none is open; it is commented on and re-described only when its
fingerprint (the cause, for example the tag or the run id) changes, never daily; it is closed with a comment when the
class is healthy again. A class that could not be read (``unknown``) leaves its issue alone. Duplicate open issues of
one class are folded into the oldest.

The decisions are pure functions over plain inputs; every ``git`` and ``gh`` call goes through :class:`Git` (from
``versioning``) and :class:`GitHub`, which tests replace. Stdlib only (macOS system Python 3.9).
"""
from __future__ import annotations

import argparse
import datetime as dt
import importlib.util
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence

REPO_ROOT = Path(__file__).resolve().parents[1]

#: The label every release-health issue carries (the triage runner works ``Workflow`` issues).
LABEL = "Workflow"
#: Days without a tag, with app changes waiting, before ``no-tag`` fails.
NO_TAG_DAYS = 7
#: Days left on a certificate under which ``cert-expiry`` fails.
CERT_DAYS = 45
#: The release workflow file whose runs ``release-failed`` reads.
RELEASE_WORKFLOW = "ios-release.yml"
#: Hidden marker holding a class's fingerprint in its issue body.
MARKER_RE = re.compile(r"<!-- release-health:(?P<cls>[a-z-]+):(?P<fingerprint>[^>]*?) -->")

#: Class id -> stable issue title.
TITLES = {
    "no-tag": "Release health: no iOS version tag for 7 days",
    "release-failed": "Release health: the latest ios-release run failed",
    "cert-expiry": "Release health: a signing certificate expires within 45 days",
}
CLASSES = tuple(TITLES)

OK, FAILING, UNKNOWN = "ok", "failing", "unknown"


# region Loading

def load_versioning() -> Any:
    """Import ``tools/release/versioning.py`` by path (it is read, never edited, from here)."""
    name = "release_versioning"
    if name in sys.modules:
        return sys.modules[name]
    spec = importlib.util.spec_from_file_location(name, REPO_ROOT / "tools" / "release" / "versioning.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


# endregion

# region Class states


def state(cls: str, status: str, fingerprint: str = "", detail: str = "") -> Dict[str, str]:
    """One class's result: ``status`` is ``ok``, ``failing`` or ``unknown``; ``fingerprint`` names the cause."""
    return {"class": cls, "status": status, "fingerprint": fingerprint, "detail": detail}


def check_no_tag(plan: Dict[str, Any], tag_date: Optional[dt.datetime], now: dt.datetime,
                 max_days: int = NO_TAG_DAYS) -> Dict[str, str]:
    """``no-tag`` from a ``versioning.plan_bump`` result.

    Args:
        plan: ``plan_bump(git, "ios", head, now)``; ``reason`` ``app_changed`` or ``first_version`` means app
            changes wait for a tag, anything else (``no_app_changes``, ``already_tagged``, ...) means nothing waits.
        tag_date: When the newest ``ios/v*`` tag was made (None when there is none).
        now: The current time (timezone-aware).
        max_days: How old the newest tag may be while app changes wait.
    """
    reason = str(plan.get("reason"))
    previous = plan.get("previous")
    if reason == "first_version":
        return state("no-tag", FAILING, "none", "main has app files and no `ios/v*` tag exists.")
    if reason != "app_changed":
        return state("no-tag", OK, detail="no app change waits for a tag (%s)." % reason)
    if tag_date is None:
        return state("no-tag", UNKNOWN, detail="could not read the date of `ios/v%s`." % previous)
    age = now - tag_date
    if age < dt.timedelta(days=max_days):
        return state("no-tag", OK, detail="app changes wait, but `ios/v%s` is only %d days old." % (previous, age.days))
    return state("no-tag", FAILING, "ios/v%s" % previous,
                 "`main` has app changes since `ios/v%s`, made %d days ago (limit %d). The `bump` job of `ios-release` "
                 "should have tagged them." % (previous, age.days, max_days))


def check_release_failed(runs: Sequence[Dict[str, Any]]) -> Dict[str, str]:
    """``release-failed`` from ``ios-release`` runs on ``main``, newest first (``gh run list --json``).

    The newest run that concluded ``success`` or ``failure`` decides; runs still going, cancelled or skipped
    (a dropped pending bump) are passed over.
    """
    for run in runs:
        conclusion = run.get("conclusion")
        if conclusion == "success":
            return state("release-failed", OK, detail="the latest completed run succeeded.")
        if conclusion == "failure":
            url = run.get("url") or "(run %s)" % run.get("databaseId")
            return state("release-failed", FAILING, str(run.get("databaseId")),
                         "The newest completed `ios-release` run on `main` failed: %s (commit `%s`)."
                         % (url, str(run.get("headSha", ""))[:10] or "unknown"))
    return state("release-failed", OK, detail="no completed run to judge.")


def parse_not_after(text: str) -> Optional[dt.datetime]:
    """Parse an openssl ``notAfter`` date (``Nov 10 12:00:00 2027 GMT``, with or without ``notAfter=``) to UTC."""
    cleaned = re.sub(r"^notAfter=", "", (text or "").strip()).replace(" GMT", "")
    for fmt in ("%b %d %H:%M:%S %Y", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%d"):
        try:
            return dt.datetime.strptime(re.sub(r"\s+", " ", cleaned), fmt).replace(tzinfo=dt.timezone.utc)
        except ValueError:
            continue
    return None


def check_cert_expiry(dates: Dict[str, str], now: dt.datetime, min_days: int = CERT_DAYS) -> Dict[str, str]:
    """``cert-expiry`` from ``{"Apple Distribution": notAfter, "Apple Development": notAfter}``.

    A date that is missing or unreadable (secrets not set yet, no ``openssl`` read) makes that certificate unknown;
    the class fails if any readable one has fewer than ``min_days`` left (an expired one included), is unknown when
    none fails and one is unknown, and is ok otherwise.
    """
    soon, unknown, lines = [], [], []
    for name in sorted(dates):
        when = parse_not_after(dates[name])
        if when is None:
            unknown.append(name)
            continue
        days = (when - now).days
        lines.append("%s: expires %s (%d days)" % (name, when.date().isoformat(), days))
        if days < min_days:
            soon.append("%s=%s" % (name, when.date().isoformat()))
    if soon:
        return state("cert-expiry", FAILING, ";".join(soon),
                     "Under %d days left: %s. Renew as in the owner checklist (`.agents/platforms/apple/testflight.md`, "
                     "step 7) and update the `release-signing` secrets." % (min_days, "; ".join(lines)))
    if unknown:
        return state("cert-expiry", UNKNOWN, detail="could not read: %s." % ", ".join(unknown))
    return state("cert-expiry", OK, detail="; ".join(lines))


# endregion

# region Issues


def render_body(result: Dict[str, str]) -> str:
    """The issue body for a failing class, with the hidden fingerprint marker."""
    return (
        "%s\n\nThis issue is kept by `release-health` (`.github/workflows/release-health.yml`, `tools/release_health.py`): "
        "one open issue per failing class, a comment only when the cause changes, closed by itself when the class is "
        "healthy again.\n\n<!-- release-health:%s:%s -->\n" % (result["detail"], result["class"], result["fingerprint"]))


def fingerprint_of(body: str, cls: str) -> Optional[str]:
    """The fingerprint stored in an issue body for ``cls`` (None when the marker is absent)."""
    for match in MARKER_RE.finditer(body or ""):
        if match.group("cls") == cls:
            return match.group("fingerprint")
    return None


def plan_actions(results: Sequence[Dict[str, str]], open_issues: Sequence[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Decide the issue changes; each action is a dict with ``do`` in ``create``, ``update``, ``close``, ``fold``.

    Args:
        results: One state per class.
        open_issues: Open ``Workflow`` issues, each ``{number, title, body}``.

    Returns:
        Actions, in class order. ``update`` carries ``number``, ``body`` and ``comment``; ``close`` carries ``number``
        and ``comment``; ``create`` carries ``title`` and ``body``; ``fold`` closes a duplicate (``number``, ``into``).
    """
    by_title: Dict[str, List[Dict[str, Any]]] = {}
    for issue in open_issues:
        by_title.setdefault(issue.get("title", ""), []).append(issue)
    actions: List[Dict[str, Any]] = []
    for result in results:
        cls, status = result["class"], result["status"]
        mine = sorted(by_title.get(TITLES[cls], []), key=lambda i: i["number"])
        keep = mine[0] if mine else None
        for extra in mine[1:]:
            actions.append({"do": "fold", "class": cls, "number": extra["number"], "into": keep["number"],
                            "comment": "Duplicate of #%d (one open issue per class). Closing." % keep["number"]})
        if status == UNKNOWN:
            continue
        if status == FAILING and keep is None:
            actions.append({"do": "create", "class": cls, "title": TITLES[cls], "body": render_body(result)})
        elif status == FAILING and fingerprint_of(keep.get("body", ""), cls) != result["fingerprint"]:
            actions.append({"do": "update", "class": cls, "number": keep["number"], "body": render_body(result),
                            "comment": "State changed.\n\n%s" % result["detail"]})
        elif status == OK and keep is not None:
            actions.append({"do": "close", "class": cls, "number": keep["number"],
                            "comment": "Healthy again: %s Closing." % result["detail"]})
    return actions


class GitHub:
    """The ``gh`` calls this tool makes (one seam); tests replace it."""

    def __init__(self, repo: str, dry_run: bool = False, run: Callable[..., Any] = subprocess.run) -> None:
        self.repo, self.dry_run, self.run = repo, dry_run, run

    def _gh(self, args: List[str], write: bool = False, stdin: Optional[str] = None) -> str:
        if write and self.dry_run:
            print("[dry-run] gh " + " ".join(args[:5]))
            return ""
        proc = self.run(["gh"] + args, input=stdin, capture_output=True, text=True)
        if proc.returncode != 0:
            raise RuntimeError("gh %s failed: %s" % (" ".join(args[:3]), (proc.stderr or "").strip()[:200]))
        return proc.stdout

    def open_issues(self) -> List[Dict[str, Any]]:
        """Open ``Workflow`` issues as ``{number, title, body}``."""
        out = self._gh(["issue", "list", "-R", self.repo, "--label", LABEL, "--state", "open", "--limit", "200",
                        "--json", "number,title,body"])
        return json.loads(out or "[]")

    def release_runs(self) -> List[Dict[str, Any]]:
        """Completed ``ios-release`` runs on ``main``, newest first."""
        out = self._gh(["run", "list", "-R", self.repo, "--workflow", RELEASE_WORKFLOW, "--branch", "main",
                        "--status", "completed", "--limit", "20", "--json", "conclusion,url,databaseId,headSha"])
        return json.loads(out or "[]")

    def create(self, title: str, body: str) -> None:
        self._gh(["issue", "create", "-R", self.repo, "--title", title, "--label", LABEL, "--body-file", "-"],
                 write=True, stdin=body)

    def edit_body(self, number: int, body: str) -> None:
        self._gh(["issue", "edit", str(number), "-R", self.repo, "--body-file", "-"], write=True, stdin=body)

    def comment(self, number: int, body: str) -> None:
        self._gh(["issue", "comment", str(number), "-R", self.repo, "--body-file", "-"], write=True, stdin=body)

    def close(self, number: int) -> None:
        self._gh(["issue", "close", str(number), "-R", self.repo, "--reason", "completed"], write=True)


def apply_actions(gh: GitHub, actions: Sequence[Dict[str, Any]]) -> List[str]:
    """Carry the actions out through ``gh``; returns one line per action."""
    did = []
    for action in actions:
        kind, cls = action["do"], action["class"]
        if kind == "create":
            gh.create(action["title"], action["body"])
            did.append("%s: opened an issue" % cls)
        elif kind == "update":
            gh.edit_body(action["number"], action["body"])
            gh.comment(action["number"], action["comment"])
            did.append("%s: updated #%d" % (cls, action["number"]))
        else:  # close, fold
            gh.comment(action["number"], action["comment"])
            gh.close(action["number"])
            did.append("%s: closed #%d" % (cls, action["number"]))
    return did


# endregion

# region Collecting


def tag_date(git: Any, tag: str) -> Optional[dt.datetime]:
    """When ``tag`` was made (the tagger date of an annotated tag, else the commit date)."""
    try:
        text = git("for-each-ref", "--format=%(creatordate:iso-strict)", "refs/tags/%s" % tag).strip()
        return dt.datetime.fromisoformat(text).astimezone(dt.timezone.utc) if text else None
    except (RuntimeError, ValueError):
        return None


def collect(git: Any, gh: GitHub, head: str, dates: Dict[str, str], now: dt.datetime) -> List[Dict[str, str]]:
    """Gather the three class states; a failed read becomes ``unknown`` with the error in ``detail``."""
    versioning = load_versioning()
    results = []
    try:
        plan = versioning.plan_bump(git, versioning.PLATFORM, head, now)
        previous = plan.get("previous")
        results.append(check_no_tag(plan, tag_date(git, "ios/v%s" % previous) if previous else None, now))
    except Exception as exc:  # a broken read must not hide the other classes
        results.append(state("no-tag", UNKNOWN, detail="read failed: %s" % exc))
    try:
        results.append(check_release_failed(gh.release_runs()))
    except Exception as exc:
        results.append(state("release-failed", UNKNOWN, detail="read failed: %s" % exc))
    results.append(check_cert_expiry(dates, now))
    return results


def summary(results: Sequence[Dict[str, str]], did: Sequence[str]) -> str:
    """Markdown for ``$GITHUB_STEP_SUMMARY``."""
    lines = ["### release-health", "", "| class | status | detail |", "|---|---|---|"]
    lines += ["| %s | %s | %s |" % (r["class"], r["status"], r["detail"].replace("|", "/")) for r in results]
    lines += ["", ("Did: " + "; ".join(did)) if did else "No issue changed."]
    return "\n".join(lines)


# endregion


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    check = sub.add_parser("check", help="check the three classes and sync their issues")
    check.add_argument("--repo", default="", help="OWNER/REPO (default: $GITHUB_REPOSITORY)")
    check.add_argument("--head", default="origin/main", help="the commit to judge (default origin/main)")
    check.add_argument("--dist-not-after", default="", help="Apple Distribution p12 notAfter (openssl text)")
    check.add_argument("--dev-not-after", default="", help="Apple Development p12 notAfter (openssl text)")
    check.add_argument("--dry-run", action="store_true", help="print the writes instead of making them")
    args = parser.parse_args(argv)
    repo = args.repo or os.environ.get("GITHUB_REPOSITORY", "")
    if not repo:
        print("release_health: --repo or GITHUB_REPOSITORY is required", file=sys.stderr)
        return 2
    versioning = load_versioning()
    now = dt.datetime.now(dt.timezone.utc)
    gh = GitHub(repo, dry_run=args.dry_run)
    dates = {"Apple Distribution": args.dist_not_after, "Apple Development": args.dev_not_after}
    results = collect(versioning.Git(), gh, args.head, dates, now)
    for r in results:
        if r["status"] == UNKNOWN:
            print("::warning title=release-health %s unknown::%s" % (r["class"], r["detail"]))
    did = apply_actions(gh, plan_actions(results, gh.open_issues()))
    print(summary(results, did))
    # A class that could not be read because git or gh failed turns the run red; a missing certificate date does not.
    return 1 if any(r["detail"].startswith("read failed") for r in results) else 0


if __name__ == "__main__":
    sys.exit(main())
