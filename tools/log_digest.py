#!/usr/bin/env python3
"""Reduce an xcodebuild, ``swift test`` or script log to a digest of at most ~30 lines.

Agents read the digest, never the log: a result, the failing tests with their first assertion, the first
compile errors, and whether the run died of infrastructure (Device Hub, hung hold, unavailable simulator)
rather than a test. Run through ``tools/bg_run.py`` it is printed when the command exits.

A run that shows test evidence (an ``Executed N tests`` line, a Swift Testing run, ``** TEST SUCCEEDED **``) but ran no test, or
whose every test skipped, is ``RESULT: EMPTY``, never PASS (2026-11-03: journeys that skipped for lack of credentials reported PASS
in 13 s). ``--allow-empty``, or an ``allow-empty`` line in the log (tools/ios_uitest.sh prints it for its own flag), keeps PASS.

Usage: tools/log_digest.py LOG [--exit-code N] [--elapsed SECONDS] [--label NAME] [--max-lines N] [--allow-empty]
       some-command 2>&1 | tools/log_digest.py -
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import OrderedDict
from typing import Dict, Iterable, List, Optional, Tuple

RUNNER_FAILED = re.compile(r"Testing failed:|\*\* TEST EXECUTE FAILED \*\*|[Tt]est runner exited")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

XC_RESULT = re.compile(r"Test Case '-\[(?P<cls>[\w.]+) (?P<name>\w+)\]' (?P<state>passed|failed) \(")
XC_FAIL_MESSAGE = re.compile(r"(?P<where>[^\s:]+\.swift:\d+): error: -\[(?P<cls>[\w.]+) (?P<name>\w+)\] : (?P<msg>.*)")
XC_EXECUTED = re.compile(r"Executed (?P<n>\d+) tests?, with (?:(?P<s>\d+) tests? skipped and )?(?P<f>\d+) failures?")
XC_SKIPPED = re.compile(r"Test Case '-\[(?P<cls>[\w.]+) (?P<name>\w+)\]' skipped")
ST_ISSUE = re.compile(r"✘ Test (?P<name>[\w`' ]+?)(?:\([^)]*\))? recorded an issue at (?P<where>[^\s:]+\.swift:\d+)(?::\d+)?: (?P<msg>.*)")
ST_FAILED = re.compile(r"✘ Test (?P<name>[\w`' ]+?)(?:\([^)]*\))? failed after")
ST_PASSED = re.compile(r"✔ Test (?P<name>[\w`' ]+?)(?:\([^)]*\))? passed after")
ST_RUN_ISSUES = re.compile(r"Test run with \d+ tests?.*? with (?P<n>\d+) issues?")
ST_RUN = re.compile(r"[✔✘] Test run with (?P<n>\d+) tests?.*?(?P<state>passed|failed)")
COMPILE_ERROR = re.compile(r"(?P<where>/?[^\s:]+\.swift:\d+):\d+: error: (?P<msg>.*)")

#: The two lines devcap and bg_run print when they kill a run. They count only at the start of a line and only when the run
#: exited with `HOLD_TIMEOUT_EXITS`: a test that prints the words, or a log that quotes them, is not an infrastructure death.
HOLD_TIMEOUT = re.compile(r"^(?:devcap: HOLD TIMEOUT:|bg_run: hold timeout)")
HOLD_TIMEOUT_EXITS = (75, 124)
#: devcap's slot-wait timeout line. Same rule: line start, and only when the run exited `SLOT_WAIT_EXIT` (devcap's EX_TEMPFAIL).
SLOT_WAIT = re.compile(r"^devcap: gave up waiting")
SLOT_WAIT_EXIT = 75
#: unittest's own markers (tool tests): `FAIL: test_x (mod.Class.test_x)`, `ERROR: ...` and the `FAILED (failures=1)` summary.
#: Python 3.9 prints the class (`test_x (mod.Class)`), later versions the full test id (`test_x (mod.Class.test_x)`).
UT_FAILED = re.compile(r"^(?:FAIL|ERROR): (?P<name>\w+) \((?P<id>[\w.]+)\)\s*$")
UT_SUMMARY = re.compile(r"^FAILED \((?:failures|errors)=\d+")

#: (label, pattern, advice). The first match wins, so list the most specific first.
INFRA: List[Tuple[str, "re.Pattern[str]", str]] = [
    ("hung", re.compile(r"^INFRA: hung \(no output"), "tools/xc_watch.py killed a run that printed nothing; the `sample` of it is in the log; rerun once"),
    ("slow exit", re.compile(r"^INFRA: slow exit"), "xcodebuild did not exit after the suite finished and was killed; the result is the suite's own"),
    ("simulator unhealthy", re.compile(r"^INFRA: simulator unhealthy"), "bootstatus or a screenshot failed twice; `devcap.py status`, recreate the simulator"),
    ("credentials unavailable", re.compile(r"Live-server credentials unavailable"), "the runner's ~/.config/fenton-hass/env is missing or refused; fix the machine (tools/hass_creds.sh), rerun"),
    ("hold timeout", HOLD_TIMEOUT, "devcap killed a hung run; check `devcap.py status`, rerun once"),
    ("slot wait timeout", SLOT_WAIT, "devcap gave up waiting for a free simulator slot (exit 75); `devcap.py status`, rerun when the holder finishes"),
    ("Device Hub pose", re.compile(r"DeviceHubError|Pressed the unfolded control"), "the Duo pose control did not take; rerun once, then `tools/duo_pose.py --sim <UDID>` inside a devcap hold"),
    ("simulator unavailable", re.compile(r"^GAP:", re.M), "a gap, not a pass; create the simulator"),
    ("simulator boot/launch", re.compile(r"Unable to boot|Invalid device state|Failed to launch|Early unexpected exit"), "simulator did not come up; rerun once"),
    ("test host crash", re.compile(r"crashed with signal|Test crashed|signal code|Restarting after unexpected exit"), "the app or test host crashed; read the crash log named in the full log"),
    ("SwiftPM lock", re.compile(r"Another instance of SwiftPM|waiting for lock"), "another build holds the package; wait for it"),
]


#: A line longer than this is cut in the middle: the patterns below scan a run of non-blanks once per start position, so a
#: line of 500 000 NULs (ios_uitest's "INFRA: slow exit" after a killed xcodebuild) took hours instead of milliseconds.
MAX_LINE = 4000


def clean(text: str) -> str:
    """Strip ANSI colour codes and NULs, and bound a runaway line to its head and tail."""
    text = ANSI.sub("", text.replace("\x00", ""))
    if len(text) > MAX_LINE:
        half = MAX_LINE // 2
        text = text[:half] + " … " + text[-half:]
    return text


#: Infra kinds that say what happened on a line of their own, and that outrank a failed test in the verdict.
MARKED = {"hung", "slow exit", "simulator unhealthy"}
HARD = {"hung", "simulator unhealthy"}


def git_context(directory: Optional[str] = None) -> Tuple[str, str]:
    """(short SHA, worktree name) of the checkout, so failures can be counted per (test, SHA); empty when not in git."""
    def run(*args: str) -> str:
        try:
            out = subprocess.run(["git", *args], capture_output=True, text=True, cwd=directory, timeout=10)
        except (OSError, subprocess.TimeoutExpired):
            return ""
        return out.stdout.strip() if out.returncode == 0 else ""
    top = run("rev-parse", "--show-toplevel")
    return run("rev-parse", "--short=8", "HEAD"), top.rsplit("/", 1)[-1] if top else ""


def short(text: str, width: int = 170) -> str:
    """Collapse whitespace and cut to ``width`` characters."""
    text = " ".join(text.split())
    return text if len(text) <= width else text[: width - 1] + "…"


class Digest:
    """What one log said."""

    def __init__(self) -> None:
        self.passed: "OrderedDict[str, None]" = OrderedDict()
        self.failed: "OrderedDict[str, str]" = OrderedDict()  # test -> first message
        self.build_errors: "OrderedDict[str, None]" = OrderedDict()
        self.suite_status: Optional[str] = None  # "succeeded" / "failed" from ** TEST ** / ** BUILD **
        self.build_status: Optional[str] = None
        self.executed = 0
        self.executed_failures = 0
        self.named_failures: Dict[str, int] = {}  # XCTest failures the log attributes to a named test (failed or retried)
        self.retried: "OrderedDict[str, None]" = OrderedDict()  # failed once, then passed: a flaky pass, not a clean one
        self.runner_failed = False  # `** TEST EXECUTE FAILED **` / `Testing failed:`: xcodebuild could not run the tests
        self.executed_seen = False  # an ``Executed N tests`` line printed, even one that reads 0
        self.skipped = 0
        self.skipped_cases: "OrderedDict[str, None]" = OrderedDict()
        self.crashed = False  # the test runner or xcodebuild itself failed (a crash hidden in a mixed log must not read as EMPTY)
        self.empty_marker = False  # xc_watch.py printed `EMPTY: …`
        self.allow_empty = False  # the caller's --allow-empty
        self.allow_in_log = False  # an `allow-empty` line from a phase of the run; a later `EMPTY:` line (another phase) voids it
        self.st_run: Optional[Tuple[int, str]] = None
        self.st_issues = 0  # the issue count of the Swift Testing run line
        self.issue_lines = 0  # `recorded an issue` lines (Swift Testing) and `error: -[…]` lines (XCTest) the log itself shows
        self.infra: "OrderedDict[str, int]" = OrderedDict()
        self.unittest_failed = False  # a unittest `FAILED (failures=N)` summary: tool tests failed
        self.markers: "OrderedDict[str, None]" = OrderedDict()  # `INFRA: …` lines xc_watch.py and ios_uitest.sh print
        self.products: "OrderedDict[str, None]" = OrderedDict()  # `products: hit|built KEY …` from tools/products_cache.py
        self.tail: List[str] = []

    def feed(self, lines: Iterable[str]) -> None:
        """Read every line of a log."""
        recent: List[str] = []
        for raw in lines:
            line = clean(raw.rstrip("\n"))
            if line.strip():
                recent.append(line)
                if len(recent) > 12:
                    recent.pop(0)
            self._line(line)
        self.tail = recent

    def _line(self, line: str) -> None:
        if match := ST_RUN.search(line):
            self.st_run = (int(match["n"]), match["state"])
            if issues := ST_RUN_ISSUES.search(line):
                self.st_issues = max(self.st_issues, int(issues["n"]))
        elif match := XC_FAIL_MESSAGE.search(line):
            self.issue_lines += 1
            test = f"{match['cls'].split('.')[-1]}.{match['name']}"
            self.named_failures[test] = self.named_failures.get(test, 0) + 1
            self.failed.setdefault(test, f"{short(match['msg'], 140)} ({match['where'].split('/')[-1]})")
            self.passed.pop(test, None)
        elif match := XC_RESULT.search(line):
            test = f"{match['cls'].split('.')[-1]}.{match['name']}"
            if match["state"] == "passed":
                self.passed[test] = None
                # A retried test that finally passes is not a failure of the run, but the digest says it was flaky.
                if self.failed.pop(test, None) is not None:
                    self.retried[test] = None
            else:
                self.named_failures.setdefault(test, 1)
                self.failed.setdefault(test, "failed")
                self.passed.pop(test, None)
        elif match := ST_ISSUE.search(line):
            self.issue_lines += 1
            name = match["name"].strip()
            self.failed[name] = f"{short(match['msg'], 140)} ({match['where'].split('/')[-1]})"
        elif match := ST_FAILED.search(line):
            self.failed.setdefault(match["name"].strip(), "failed")
        elif match := UT_FAILED.match(line):
            test_id = match["id"] if match["id"].endswith("." + match["name"]) else f"{match['id']}.{match['name']}"
            self.failed.setdefault(test_id, "failed (unittest)")
        elif match := ST_PASSED.search(line):
            self.passed[match["name"].strip()] = None
        elif match := XC_SKIPPED.search(line):
            self.skipped_cases[f"{match['cls'].split('.')[-1]}.{match['name']}"] = None
        elif match := XC_EXECUTED.search(line):
            self.executed_seen = True
            if int(match["n"]) > 0:
                self.executed = max(self.executed, int(match["n"]))
                self.executed_failures = max(self.executed_failures, int(match["f"]))
            self.skipped = max(self.skipped, int(match["s"] or 0))
        elif match := COMPILE_ERROR.search(line):
            self.build_errors.setdefault(f"{match['where'].split('/')[-1]}: {short(match['msg'], 130)}", None)
        if "** TEST EXECUTE FAILED **" in line or line.startswith("Testing failed:"):
            self.runner_failed = True
        if "** TEST SUCCEEDED **" in line:
            self.suite_status = "succeeded"
        elif "** TEST FAILED **" in line:
            self.suite_status = "failed"
        elif "** BUILD FAILED **" in line:
            self.build_status = "failed"
        elif "** BUILD SUCCEEDED **" in line:
            self.build_status = "succeeded"
        if UT_SUMMARY.match(line):
            self.unittest_failed = True
        if line.startswith("products: "):
            self.products.setdefault(short(line, 150), None)
        if RUNNER_FAILED.search(line):
            self.crashed = True
        if line.startswith("EMPTY: "):
            self.empty_marker = True
            self.allow_in_log = False
        if re.match(r"^(== )?allow-empty\b", line):
            self.allow_in_log = True
        if line.startswith("INFRA: "):
            self.markers.setdefault(short(line, 150), None)
        for label, pattern, _ in INFRA:
            if pattern.search(line):
                self.infra[label] = self.infra.get(label, 0) + 1

    def counts(self) -> Tuple[int, int, int]:
        """(tests that ran, skipped, failed) as far as the log says; the first is 0 for an empty run."""
        total = max(self.executed, self.st_run[0] if self.st_run else 0, len(self.passed) + len(self.failed))
        skipped = max(self.skipped, len(self.skipped_cases))
        ran = max(total - skipped, len(self.passed) + len(self.failed))
        return ran, skipped, max(len(self.failed), self.executed_failures)

    def unnamed_failures(self) -> int:
        """Failures the XCTest summary counts that no named test (failed, or failed then passed on retry) accounts for.

        Limit: a log with several runs or families takes the largest ``Executed`` summary but sums the named failures of
        all of them, so a failure named in one family can hide an unnamed one in another.
        """
        return max(0, self.executed_failures - sum(self.named_failures.values()))

    def is_empty(self) -> bool:
        """True when the log shows a test run that executed nothing, or whose every test skipped."""
        if self.empty_marker:
            return True
        evidence = (self.executed_seen or self.st_run is not None or self.suite_status == "succeeded"
                    or bool(self.passed or self.failed or self.skipped_cases))  # grep'd `Test Case …` lines (perf scripts) count
        return evidence and self.counts()[0] <= 0

    def verdict(self, exit_code: Optional[int]) -> str:
        """``PASS``, ``FLAKY`` (passed after a retry), ``MISMATCH`` (exit 0 but the log failed), ``EMPTY`` (a pass that ran no test), ``FAIL`` (tests or build), ``INFRA`` (died of the machine) or ``UNKNOWN``."""
        self._gate_hold_timeout(exit_code)
        verdict = self._verdict(exit_code)
        if self.allow_empty or self.allow_in_log:
            return verdict
        if verdict == "PASS" and self.is_empty():
            return "EMPTY"
        # xc_watch exits 1 after printing its `EMPTY:` line: that is still an empty run unless something really failed.
        if (verdict == "FAIL" and exit_code == 1 and self.empty_marker and not self.crashed and not self.failed and self.suite_status != "failed"
                and self.build_status != "failed" and not self.build_errors and not HARD & set(self.infra)):
            return "EMPTY"
        return verdict

    def _gate_hold_timeout(self, exit_code: Optional[int]) -> None:
        """Keep a "hold timeout" line as infra only when the run exited 75 or 124 (a killed hold); at any other status the run ended by itself."""
        if exit_code not in HOLD_TIMEOUT_EXITS:
            self.infra.pop("hold timeout", None)
        if exit_code != SLOT_WAIT_EXIT:
            self.infra.pop("slot wait timeout", None)

    def _verdict(self, exit_code: Optional[int]) -> str:
        failed_tests = (bool(self.failed) or self.suite_status == "failed" or self.runner_failed
                        or bool(self.st_run and self.st_run[1] == "failed")
                        or self.unittest_failed or self.unnamed_failures() > 0)
        build_failed = self.build_status == "failed" or bool(self.build_errors and not self.passed)
        if exit_code == 0 and (failed_tests or build_failed):
            # The status says success and the log says otherwise (a wrapper such as `cmd || echo X` or `;` dropped the real
            # status): never PASS. The log wins, and the digest says the two disagree.
            return "MISMATCH"
        if exit_code == 0:
            return "FLAKY" if self.retried else "PASS"
        if exit_code != 0 and HARD & set(self.infra):
            return "INFRA"
        if failed_tests or build_failed:
            return "FAIL"
        if self.infra:
            return "INFRA"
        if exit_code is None:
            ok = self.suite_status == "succeeded" or (self.st_run and self.st_run[1] == "passed")
            return "PASS" if ok else "UNKNOWN"
        return "FAIL" if exit_code else "PASS"

    def render(self, exit_code: Optional[int], elapsed: Optional[float], label: str, log: str, max_lines: int,
               sha: str = "", lane: str = "") -> str:
        """Format the digest."""
        verdict = self.verdict(exit_code)
        head = f"RESULT: {verdict}"
        if exit_code is not None:
            head += f" (exit {exit_code})"
        if label:
            head += f"  {label}"
        if elapsed is not None:
            head += f"  {describe(elapsed)}"
        if sha or lane:
            head += "  " + " ".join(part for part in (f"sha={sha}" if sha else "", f"lane={lane}" if lane else "") if part)
        out = [head]

        counts = []
        ran, skipped, failed = self.counts()
        if self.executed_seen or self.st_run or self.suite_status or skipped:
            counts.append(f"executed {ran}, skipped {skipped}, failed {failed}")
        if self.st_run:
            counts.append(f"swift-testing: {self.st_run[0]} tests {self.st_run[1]}")
        if self.executed:
            counts.append(f"xctest executed {self.executed}, {self.executed_failures} failures")
        if self.passed or self.failed:
            counts.append(f"named: {len(self.passed)} passed, {len(self.failed)} failed")
        if counts:
            out.append("tests: " + "; ".join(counts))

        budget = max(4, max_lines - len(out) - 6)
        if self.failed:
            out.append(f"FAILED ({len(self.failed)}):")
            for test, message in list(self.failed.items())[: max(3, budget // 2)]:
                out.append(f"  {test}: {message}")
            if len(self.failed) > max(3, budget // 2):
                out.append(f"  … and {len(self.failed) - max(3, budget // 2)} more (grep 'failed (' in the log)")
        if self.build_errors:
            out.append(f"BUILD ERRORS ({len(self.build_errors)}):")
            for error in list(self.build_errors)[: max(3, budget // 2)]:
                out.append(f"  {error}")
        if self.unnamed_failures() > 0:
            out.append(f"XCTest summary counts {self.executed_failures} failure(s) but the log names only {sum(self.named_failures.values())}: treat as FAIL")
        if verdict == "MISMATCH":
            out.append("exit 0 but the log has failures (a wrapper dropped the real status, e.g. `cmd || echo X` or `a; b`): treat as FAIL")
        if self.runner_failed:
            out.append("xcodebuild could not run the tests (`** TEST EXECUTE FAILED **` / `Testing failed:`)")
        if self.retried:
            out.append(f"FLAKY ({len(self.retried)}): failed, then passed on retry: " + ", ".join(list(self.retried)[:5]))
        out.extend(self.products)
        out.extend(self.markers)
        if self.infra:
            for label_, pattern, advice in INFRA:
                if label_ in self.infra:
                    if label_ in MARKED:
                        out.append(f"  -> {advice}")
                        continue
                    kind = "INFRA (not a test failure)" if verdict in ("INFRA", "UNKNOWN") else "infra noise seen"
                    out.append(f"{kind}: {label_} x{self.infra[label_]}: {advice}")
        if verdict in ("UNKNOWN", "FAIL", "MISMATCH") and not (self.failed or self.build_errors or self.infra):
            out.append("last lines:")
            out.extend(f"  {short(line, 150)}" for line in self.tail[-8:])
        out.append(f"log: {log}" if log else "log: (stdin)")
        return "\n".join(out[: max_lines + 2])


def describe(seconds: float) -> str:
    """Format a duration as ``45s``, ``3m05s`` or ``2h05m``."""
    seconds = int(seconds)
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m{seconds % 60:02d}s"
    return f"{seconds // 3600}h{seconds % 3600 // 60:02d}m"


def digest_text(text: str, exit_code: Optional[int] = None, elapsed: Optional[float] = None, label: str = "",
                log: str = "", max_lines: int = 30, sha: str = "", lane: str = "", allow_empty: bool = False) -> str:
    """Digest a log held in memory; ``sha`` and ``lane`` (see ``git_context``) go on the RESULT line."""
    digest = Digest()
    digest.allow_empty = allow_empty
    digest.feed(text.splitlines())
    return digest.render(exit_code, elapsed, label, log, max_lines, sha, lane)


def main(argv: Optional[List[str]] = None) -> int:
    """CLI entry point; exits 0 whatever the verdict, so a digest never hides behind a status."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("log", help="log file, or - for stdin")
    parser.add_argument("--exit-code", type=int)
    parser.add_argument("--elapsed", type=float)
    parser.add_argument("--label", default="")
    parser.add_argument("--max-lines", type=int, default=30)
    parser.add_argument("--allow-empty", action="store_true", help="a run that executed no test is not EMPTY")
    args = parser.parse_args(argv)
    digest = Digest()
    digest.allow_empty = args.allow_empty
    if args.log == "-":
        digest.feed(sys.stdin)
    else:
        with open(args.log, encoding="utf-8", errors="replace") as handle:
            digest.feed(handle)
    sha, lane = git_context()
    print(digest.render(args.exit_code, args.elapsed, args.label, "" if args.log == "-" else args.log, args.max_lines, sha, lane))
    return 0


if __name__ == "__main__":
    sys.exit(main())
