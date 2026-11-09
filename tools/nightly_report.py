#!/usr/bin/env python3
"""Nightly results: one JSON per shard, one digest per run, one `Nightly Fix` issue per failing area.

    tools/nightly_report.py result --area AREA --log LOG --exit-code N --elapsed S --out FILE [--shard LABEL]
    tools/nightly_report.py issues --results DIR [--repo OWNER/REPO] [--run-url URL] [--sha SHA] [--dry-run]

``result`` reduces a log with ``tools/log_digest.py`` to ``{area, shard, status: pass|fail|infra, failed, notes, digest}``.
``issues`` merges every ``result-*.json`` in DIR into one status per area (``fail`` if any shard failed; ``infra`` when a
shard died of the machine and none failed; ``pass`` only when every shard passed) and prints the run digest (Markdown, for
``$GITHUB_STEP_SUMMARY``). Then, on ``--repo``:

* a failing area opens one issue titled ``Nightly: AREA failing`` labelled ``Nightly Fix`` (deduplicated by title against
  open issues). An issue that already exists gets a comment with the new failures, and loses ``Awaiting Nightly`` so the
  triage runner works it again;
* a passing area closes its open issue with a comment, but only with ``--full-run`` (an unfiltered run);
* ``infra`` leaves the issue alone (a machine problem is not a code fix).

Contract: ``.agents/workflow/ci.md``. Stdlib only (macOS system Python 3.9).
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import log_digest  # noqa: E402

LABEL = "Nightly Fix"
AWAITING = "Awaiting Nightly"
COVERAGE_LINE = re.compile(r"^(?:swift\.\w+: .*(?:lines =|below)|ERROR: .*)", re.M)


def title(area: str) -> str:
    return "Nightly: %s failing" % area


def make_result(area: str, text: str, exit_code: int, elapsed: float, shard: str = "") -> Dict[str, Any]:
    """Reduce a log to the result document for one shard (or the coverage run)."""
    digest = log_digest.Digest()
    digest.feed(text.splitlines())
    verdict = digest.verdict(exit_code)
    if verdict == "EMPTY" and not re.search(r"^EMPTY: ", text, re.M):
        # Only the scripts' own `EMPTY:` lines (a run where no family ran a test, or nothing executed) count. A shard that skipped
        # everything and exited 0 is a family-gated shard, not an empty run.
        verdict = "PASS"
    # EMPTY (a run that executed no test) is never a "failing" issue: it is a setup gap (credentials, selection), reported as infra with a note.
    status = {"PASS": "pass", "INFRA": "infra", "EMPTY": "infra"}.get(verdict, "fail" if verdict == "FAIL" else "infra")
    failed = dict(digest.failed)
    notes = [m.group(0)[:300] for m in COVERAGE_LINE.finditer(text)] if area == "coverage" else []
    if verdict == "EMPTY":
        notes.append("EMPTY: the run executed no test or every test skipped (credentials or selection); not a test failure")
    if status == "fail" and not failed and not notes:
        failed = dict(("build: " + e, "") for e in list(digest.build_errors)[:10]) or {"(no test named)": "exit %d" % exit_code}
    return {"area": area, "shard": shard, "status": status, "failed": failed, "notes": notes,
            "digest": digest.render(exit_code, elapsed, "%s %s" % (area, shard) if shard else area, "", 24)}


def merge(results: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    """One entry per area: status, every failing test, notes and the digests."""
    areas: Dict[str, Dict[str, Any]] = {}
    for result in results:
        entry = areas.setdefault(result["area"], {"status": "pass", "failed": {}, "notes": [], "digests": []})
        entry["failed"].update(result.get("failed", {}))
        entry["notes"].extend(result.get("notes", []))
        entry["digests"].append(result.get("digest", ""))
        status = result["status"]
        if status == "fail" or entry["status"] == "fail":
            entry["status"] = "fail"
        elif status == "infra" or entry["status"] == "infra":
            entry["status"] = "infra"
    return areas


def require_complete(areas: Dict[str, Dict[str, Any]], expected: Dict[str, int], results: List[Dict[str, Any]]) -> None:
    """An area with fewer shard results than planned (a cancelled or lost job) cannot pass: it becomes `infra`."""
    for area, count in expected.items():
        have = len([r for r in results if r["area"] == area])
        entry = areas.setdefault(area, {"status": "infra", "failed": {}, "notes": [], "digests": []})
        if have < count:
            entry["digests"].append("only %d of %d shard results arrived" % (have, count))
            if entry["status"] == "pass":
                entry["status"] = "infra"


def summary(areas: Dict[str, Dict[str, Any]], run_url: str = "") -> str:
    """The run digest as Markdown."""
    lines = ["## Nightly digest", ""]
    if run_url:
        lines += ["Run: %s" % run_url, ""]
    lines += ["| Area | Result | Failing |", "|---|---|---|"]
    for area in sorted(areas):
        entry = areas[area]
        lines.append("| %s | %s | %d |" % (area, entry["status"].upper(), len(entry["failed"])))
    for area in sorted(areas):
        entry = areas[area]
        if entry["status"] != "pass":
            lines += ["", "### %s (%s)" % (area, entry["status"])]
            lines += ["- `%s` %s" % (t, m) for t, m in sorted(entry["failed"].items())[:40]]
            lines += ["- %s" % n for n in entry["notes"]]
            lines += ["", "```", "\n\n".join(entry["digests"])[:3500], "```"]
    return "\n".join(lines) + "\n"


def issue_body(area: str, entry: Dict[str, Any], run_url: str, sha: str) -> str:
    failing = "\n".join("- `%s` %s" % (t, m) for t, m in sorted(entry["failed"].items())[:60]) or "- (see the run)"
    notes = "\n".join("- %s" % n for n in entry["notes"])
    return (
        "The nightly full run failed in **%s**.\n\nRun: %s\nCommit: `%s`\n\n### Failing\n%s\n%s\n\n"
        "Fix the cause in the app or the test (never weaken a test to pass), land the fix through the PR lifecycle "
        "(`.agents/workflow/pr-lifecycle.md`). This issue closes itself when a nightly run passes this area again.\n"
        % (area, run_url or "(local)", sha[:10] or "unknown", failing, ("\n### Coverage\n" + notes) if notes else ""))


class GitHub:
    """The ``gh`` calls this tool makes; tests replace it."""

    def __init__(self, repo: str, dry_run: bool = False, run: Callable[..., Any] = subprocess.run):
        self.repo, self.dry_run, self.run = repo, dry_run, run

    def _gh(self, args: List[str], write: bool = False, stdin: Optional[str] = None) -> str:
        if write and self.dry_run:
            print("[dry-run] gh " + " ".join(args[:5]))
            return "{}"
        proc = self.run(["gh"] + args, input=stdin, capture_output=True, text=True)
        if proc.returncode != 0:
            raise RuntimeError("gh %s failed: %s" % (" ".join(args[:3]), (proc.stderr or "").strip()[:200]))
        return proc.stdout

    def open_issues(self) -> List[Dict[str, Any]]:
        out = self._gh(["issue", "list", "-R", self.repo, "--state", "open", "--limit", "200", "--json",
                        "number,title,labels"])
        return json.loads(out or "[]")

    def ensure_label(self) -> None:
        self._gh(["label", "create", LABEL, "-R", self.repo, "--color", "d93f0b", "--description",
                  "A nightly full-run failure for the triage agent to fix", "--force"], write=True)

    def create(self, issue_title: str, body: str) -> None:
        self._gh(["issue", "create", "-R", self.repo, "--title", issue_title, "--label", LABEL, "--body-file", "-"],
                 write=True, stdin=body)

    def comment(self, number: int, body: str) -> None:
        self._gh(["issue", "comment", str(number), "-R", self.repo, "--body-file", "-"], write=True, stdin=body)

    def unlabel(self, number: int, label: str) -> None:
        self._gh(["issue", "edit", str(number), "-R", self.repo, "--remove-label", label], write=True)

    def close(self, number: int) -> None:
        self._gh(["issue", "close", str(number), "-R", self.repo, "--reason", "completed"], write=True)


def sync_issues(gh: GitHub, areas: Dict[str, Dict[str, Any]], run_url: str = "", sha: str = "",
                allow_close: bool = False) -> List[str]:
    """Open, update or close the `Nightly Fix` issue of every area; returns what it did, one line each.

    A passing area closes its issue only when ``allow_close`` (a full, unfiltered run): a filtered run passes areas it
    did not fully run."""
    did: List[str] = []
    open_by_title = {i["title"]: i for i in gh.open_issues()}
    labelled = False
    for area in sorted(areas):
        entry, existing = areas[area], open_by_title.get(title(area))
        if entry["status"] == "fail":
            if existing:
                names = [l["name"] if isinstance(l, dict) else l for l in existing.get("labels", [])]
                gh.comment(existing["number"], "Still failing in the nightly run %s\n\n%s" % (run_url, issue_body(
                    area, entry, run_url, sha).split("### Failing", 1)[-1].split("Fix the cause", 1)[0].strip()))
                if AWAITING in names:
                    gh.unlabel(existing["number"], AWAITING)
                did.append("%s: still failing (#%d)" % (area, existing["number"]))
            else:
                if not labelled:
                    gh.ensure_label()
                    labelled = True
                gh.create(title(area), issue_body(area, entry, run_url, sha))
                did.append("%s: issue opened" % area)
        elif entry["status"] == "pass" and existing and not allow_close:
            did.append("%s: passed in a partial run; issue #%d stays open" % (area, existing["number"]))
        elif entry["status"] == "pass" and existing:
            gh.comment(existing["number"], "Passed in the nightly run %s (commit `%s`). Closing." % (run_url, sha[:10]))
            gh.close(existing["number"])
            did.append("%s: passed, closed #%d" % (area, existing["number"]))
    return did


def load_results(folder: Path) -> List[Dict[str, Any]]:
    return [json.loads(p.read_text()) for p in sorted(folder.rglob("result-*.json"))]


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("result")
    r.add_argument("--area", required=True)
    r.add_argument("--shard", default="")
    r.add_argument("--log", required=True)
    r.add_argument("--exit-code", type=int, required=True)
    r.add_argument("--elapsed", type=float, default=0)
    r.add_argument("--out", required=True)
    i = sub.add_parser("issues")
    i.add_argument("--results", required=True)
    i.add_argument("--repo", default="")
    i.add_argument("--run-url", default="")
    i.add_argument("--sha", default="")
    i.add_argument("--dry-run", action="store_true")
    i.add_argument("--full-run", action="store_true", help="the run was unfiltered: passing areas may close their issues")
    i.add_argument("--expect", default="", help="comma-separated AREA=N: shard results each area must have")
    args = parser.parse_args(argv)
    if args.cmd == "result":
        text = Path(args.log).read_text(encoding="utf-8", errors="replace") if Path(args.log).exists() else ""
        doc = make_result(args.area, text, args.exit_code, args.elapsed, args.shard)
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(json.dumps(doc, indent=1))
        print(doc["digest"])
        return 0
    results = load_results(Path(args.results))
    areas = merge(results)
    expected = {k: int(v) for k, _, v in (item.partition("=") for item in args.expect.split(",") if item)}
    require_complete(areas, expected, results)
    print(summary(areas, args.run_url))
    if args.repo:
        for line in sync_issues(GitHub(args.repo, args.dry_run), areas, args.run_url, args.sha, args.full_run):
            print("- " + line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
