"""Phase bookkeeping of the coverage run (``tools/coverage_phases.sh``) with ``ios_uitest.sh`` and ``swift`` stubbed.

Each case sources the real shell library, runs fake instrumented phases, the real rerun functions against the
stubs and the real verdict, and checks the exit status and digest. Nothing here builds or boots anything.
"""

from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[2]

IOS_STUB = """#!/usr/bin/env bash
# Stub ios_uitest.sh: records its arguments; passes the hosted classes or the --tests ids unless STUB_IOS_PASS=0.
echo "$@" >> "$STUB_DIR/ios-calls.txt"
[[ "${STUB_IOS_PASS:-1}" == 1 ]] || exit 0
if [[ " $* " == *" --hosted "* ]]; then
  for cls in $FENTON_HOSTED_FILTER; do echo "Test Case '-[FentonHomeTests.$cls ${STUB_HOSTED_METHOD:-testBar}]' passed (0.1 seconds)."; done
else
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == --tests ]]; then
      IFS=, read -ra ids <<<"$2"
      for id in "${ids[@]}"; do echo "Test Case '-[FentonHomeUITests.${id%%/*} ${id##*/}]' passed (1.0 seconds)."; done
    fi
    shift
  done
fi
"""

SWIFT_STUB = """#!/usr/bin/env bash
# Stub swift: records the filters; "passes" XCTest ids (Class/test$) unless STUB_SWIFT_PASS=0.
echo "$@" >> "$STUB_DIR/swift-calls.txt"
[[ "${STUB_SWIFT_PASS:-1}" == 1 ]] || exit 0
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --filter ]]; then
    f="${2%\\$}"
    if [[ "$f" == */* && "$f" != /* ]]; then echo "Test Case '-[HassCoreTests.${f%%/*} ${f##*/}]' passed (0.1 seconds)."; fi
  fi
  shift
done
"""


def fail_line(cls: str, name: str, module: str = "FentonHomeTests") -> str:
    return f"Test Case '-[{module}.{cls} {name}]' failed (1.0 seconds)."


class CoveragePhasesTests(unittest.TestCase):
    """The verdict is decided per phase, and a plain rerun must show an id passing."""

    def setUp(self) -> None:
        self.tmp = TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        (self.dir / "bin").mkdir()
        for name, body in (("ios_uitest.sh", IOS_STUB), ("swift", SWIFT_STUB)):
            path = self.dir / "bin" / name
            path.write_text(body, encoding="utf-8")
            path.chmod(path.stat().st_mode | stat.S_IEXEC)
        self.quarantine = self.dir / "q.json"
        self.quarantine.write_text("[]", encoding="utf-8")

    def quarantine_ids(self, *ids: str) -> None:
        self.quarantine.write_text(json.dumps([{"id": i, "issue": 9, "date": "2026-11-04"} for i in ids]), encoding="utf-8")

    def run_flow(self, phases: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess:
        """Source the library, run ``phases`` (shell), the reruns and the verdict; returns the process."""
        script = f"""set -euo pipefail
ROOT={ROOT}; CLASS_DIR={self.dir}/class; CLASSIFY=$ROOT/tools/coverage_classify.py
export STUB_DIR={self.dir}; PATH={self.dir}/bin:$PATH
source $ROOT/tools/coverage_phases.sh
COV_IOS_UITEST={self.dir}/bin/ios_uitest.sh
COV_CLASSIFY_ARGS="--offline --quarantine {self.quarantine}"
cov_state_reset
{phases}
cov_rerun_ios
cov_rerun_swift
V=0; cov_verdict || V=$?
exit $V
"""
        return subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                              env={**os.environ, **(env or {})}, timeout=120, check=False)

    def phase(self, kind: str, name: str, status: int, lines: list[str]) -> str:
        """Shell for one fake instrumented phase that prints ``lines`` and exits ``status``."""
        fixture = self.dir / f"{name}.fixture"
        fixture.write_text("".join(f"{line}\n" for line in lines), encoding="utf-8")
        return f"cov_phase {kind} {name} \"$CLASS_DIR/{name}.log\" -- bash -c 'cat {fixture}; exit {status}' >/dev/null"

    def test_clean_run_passes(self) -> None:
        result = self.run_flow(self.phase("hosted", "hosted", 0, []) + "\n" + self.phase("swift", "swift", 0, []))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("real: none", result.stdout)

    def test_named_failure_that_passes_plain_and_is_quarantined_passes(self) -> None:
        self.quarantine_ids("UKFooTests/testBar")
        result = self.run_flow(self.phase("hosted", "hosted", 1, [fail_line("UKFooTests", "testBar")]))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("coverage-only: UKFooTests/testBar", result.stdout)
        calls = (self.dir / "ios-calls.txt").read_text(encoding="utf-8")
        self.assertIn("--hosted", calls)
        self.assertIn("--force", calls)
        self.assertNotIn("--impact", calls)
        self.assertNotIn("--tests", calls)

    def test_one_part_names_an_id_while_another_fails_silently(self) -> None:
        self.quarantine_ids("JourneyA/testOne")
        result = self.run_flow(self.phase("journey", "journey-1", 1, [fail_line("JourneyA", "testOne", "FentonHomeUITests")])
                               + "\n" + self.phase("journey", "journey-2", 65, ["BUILD FAILED"]))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("phase: phase journey-2 exited 65 and named no failing test", result.stdout)
        self.assertIn("coverage-only: JourneyA/testOne", result.stdout)

    def test_timeout_next_to_a_quarantined_id_fails(self) -> None:
        self.quarantine_ids("JourneyA/testOne")
        result = self.run_flow(self.phase("journey", "journey-1", 124, [fail_line("JourneyA", "testOne", "FentonHomeUITests")]))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("timeout: yes", result.stdout)
        self.assertIn("exited 124", result.stdout)

    def test_swift_crash_after_a_named_failure_fails(self) -> None:
        self.quarantine_ids("SomeTests/testBoom")
        result = self.run_flow(self.phase("swift", "swift", 1, [fail_line("SomeTests", "testBoom", "HassCoreTests"),
                                                                "error: Exited with unexpected signal code 11"]))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("phase swift shows a crash marker", result.stdout)

    def test_xcodebuild_restart_after_crash_fails(self) -> None:
        self.quarantine_ids("JourneyA/testOne")
        result = self.run_flow(self.phase("journey", "journey-1", 1, [fail_line("JourneyA", "testOne", "FentonHomeUITests"),
                                                                      "Restarting after unexpected exit, crash, or test timeout"]))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("crash marker", result.stdout)

    def test_failure_count_the_log_cannot_explain_fails(self) -> None:
        self.quarantine_ids("SomeTests/testBoom")
        result = self.run_flow(self.phase("swift", "swift", 1, [fail_line("SomeTests", "testBoom", "HassCoreTests"),
                                                                "Executed 9 tests, with 3 failures (0 unexpected) in 1.0 (1.1) seconds"]))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("more failure(s) than its log explains", result.stdout)

    def test_swift_rerun_requires_tests_and_uses_filters(self) -> None:
        self.quarantine_ids("SomeTests/testBoom")
        result = self.run_flow(self.phase("swift", "swift", 1, [fail_line("SomeTests", "testBoom", "HassCoreTests")]))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("--filter SomeTests/testBoom$", (self.dir / "swift-calls.txt").read_text(encoding="utf-8"))

    def test_rerun_that_runs_nothing_is_real(self) -> None:
        self.quarantine_ids("UKFooTests/testBar")
        result = self.run_flow(self.phase("hosted", "hosted", 1, [fail_line("UKFooTests", "testBar")]),
                               env={"STUB_IOS_PASS": "0"})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("real: UKFooTests/testBar", result.stdout)

    def test_unquarantined_coverage_only_fails(self) -> None:
        result = self.run_flow(self.phase("journey", "journey-1", 1, [fail_line("JourneyA", "testOne", "FentonHomeUITests")]))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("unquarantined coverage-only: JourneyA/testOne", result.stdout)

    def test_green_run_does_not_need_gh(self) -> None:
        self.quarantine.write_text(json.dumps([{"id": "A/a", "date": "2026-11-04"}]), encoding="utf-8")
        result = self.run_flow(self.phase("swift", "swift", 0, []))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("warning: quarantine", result.stdout)

    def test_journey_rerun_uses_tests_selector(self) -> None:
        self.quarantine_ids("JourneyA/testOne")
        result = self.run_flow(self.phase("journey", "journey-1", 1, [fail_line("JourneyA", "testOne", "FentonHomeUITests")]))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("--tests JourneyA/testOne", (self.dir / "ios-calls.txt").read_text(encoding="utf-8"))


class ScriptWiringTests(unittest.TestCase):
    """The coverage script's use of the library, pinned statically (it cannot run here: it builds and boots)."""

    SCRIPT = (ROOT / "tools" / "apple_coverage.sh").read_text(encoding="utf-8")

    def test_calls_run_in_order(self) -> None:
        order = ["source \"$ROOT/tools/coverage_phases.sh\"", "cov_state_reset", "cov_phase hosted", "cov_phase journey",
                 "cov_rerun_ios", "cov_phase swift", "xcrun llvm-cov export", "cov_rerun_swift", "cov_verdict"]
        last = -1
        for needle in order:
            index = self.SCRIPT.find(needle, last + 1)
            self.assertGreater(index, last, f"{needle!r} missing or out of order")
            last = index

    def test_classify_exit_takes_precedence_over_gate_status(self) -> None:
        tail = self.SCRIPT[self.SCRIPT.index("cov_verdict ||"):]
        self.assertLess(tail.index('exit "$CLASS_STATUS"'), tail.index('exit "$GATE_STATUS"'))
        self.assertIn("(( CLASS_STATUS != 0 ))", tail)

    def test_script_ignores_the_test_seam_variables(self) -> None:
        lines = self.SCRIPT.splitlines()
        unset = next(i for i, line in enumerate(lines) if line.startswith("unset COV_CLASSIFY_ARGS COV_IOS_UITEST"))
        source = next(i for i, line in enumerate(lines) if line.startswith('source "$ROOT/tools/coverage_phases.sh"'))
        self.assertLess(unset, source)
        prelude = f"ROOT={ROOT}; CLASS_DIR=/nonexistent; CLASSIFY=/nonexistent\n{lines[unset]}\nsource {ROOT}/tools/coverage_phases.sh\n"
        result = subprocess.run(["bash", "-c", prelude + 'echo "[${COV_CLASSIFY_ARGS:-}][${COV_IOS_UITEST:-}]"'],
                                capture_output=True, text=True, check=False,
                                env={**os.environ, "COV_CLASSIFY_ARGS": "--offline", "COV_IOS_UITEST": "/evil.sh"})
        self.assertEqual(result.stdout.strip(), "[][]")


if __name__ == "__main__":
    unittest.main()
