"""Phase bookkeeping of the coverage run (``tools/coverage_phases.sh``) with ``swift`` stubbed.

Each case sources the real shell library, runs fake instrumented phases, the real rerun function against the
stub and the real verdict, and checks the exit status and digest. Nothing here builds or boots anything.
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


def fail_line(cls: str, name: str, module: str = "HassCoreTests") -> str:
    return f"Test Case '-[{module}.{cls} {name}]' failed (1.0 seconds)."


class CoveragePhasesTests(unittest.TestCase):
    """The verdict is decided per phase, and a plain rerun must show an id passing."""

    def setUp(self) -> None:
        self.tmp = TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        (self.dir / "bin").mkdir()
        for name, body in (("swift", SWIFT_STUB),):
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
COV_CLASSIFY_ARGS="--offline --quarantine {self.quarantine}"
cov_state_reset
{phases}
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
        result = self.run_flow(self.phase("swift", "swift", 0, []))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("real: none", result.stdout)

    def test_named_failure_that_passes_plain_and_is_quarantined_passes(self) -> None:
        self.quarantine_ids("UKFooTests/testBar")
        result = self.run_flow(self.phase("swift", "swift", 1, [fail_line("UKFooTests", "testBar")]))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("coverage-only: UKFooTests/testBar", result.stdout)
        self.assertIn("--filter UKFooTests/testBar$", (self.dir / "swift-calls.txt").read_text(encoding="utf-8"))

    def test_one_phase_names_an_id_while_another_fails_silently(self) -> None:
        self.quarantine_ids("SomeTests/testOne")
        result = self.run_flow(self.phase("swift", "swift", 1, [fail_line("SomeTests", "testOne")])
                               + "\n" + self.phase("swift", "swift-b", 65, ["BUILD FAILED"]))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("phase: phase swift-b exited 65 and named no failing test", result.stdout)
        self.assertIn("coverage-only: SomeTests/testOne", result.stdout)

    def test_timeout_next_to_a_quarantined_id_fails(self) -> None:
        self.quarantine_ids("SomeTests/testOne")
        result = self.run_flow(self.phase("swift", "swift", 124, [fail_line("SomeTests", "testOne")]))
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
        self.quarantine_ids("SomeTests/testOne")
        result = self.run_flow(self.phase("swift", "swift", 1, [fail_line("SomeTests", "testOne"),
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
        result = self.run_flow(self.phase("swift", "swift", 1, [fail_line("UKFooTests", "testBar")]),
                               env={"STUB_SWIFT_PASS": "0"})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("real: UKFooTests/testBar", result.stdout)

    def test_unquarantined_coverage_only_fails(self) -> None:
        result = self.run_flow(self.phase("swift", "swift", 1, [fail_line("SomeTests", "testOne")]))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("unquarantined coverage-only: SomeTests/testOne", result.stdout)

    def test_green_run_does_not_need_gh(self) -> None:
        self.quarantine.write_text(json.dumps([{"id": "A/a", "date": "2026-11-04"}]), encoding="utf-8")
        result = self.run_flow(self.phase("swift", "swift", 0, []))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("warning: quarantine", result.stdout)


class ScriptWiringTests(unittest.TestCase):
    """The coverage script's use of the library, pinned statically (it cannot run here: it builds and boots)."""

    SCRIPT = (ROOT / "tools" / "apple_coverage.sh").read_text(encoding="utf-8")

    def test_calls_run_in_order(self) -> None:
        order = ["source \"$ROOT/tools/coverage_phases.sh\"", "cov_state_reset", "cov_phase swift", "xcrun llvm-cov export", "cov_rerun_swift", "cov_verdict"]
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
        unset = next(i for i, line in enumerate(lines) if line.startswith("unset COV_CLASSIFY_ARGS"))
        source = next(i for i, line in enumerate(lines) if line.startswith('source "$ROOT/tools/coverage_phases.sh"'))
        self.assertLess(unset, source)
        prelude = f"ROOT={ROOT}; CLASS_DIR=/nonexistent; CLASSIFY=/nonexistent\n{lines[unset]}\nsource {ROOT}/tools/coverage_phases.sh\n"
        result = subprocess.run(["bash", "-c", prelude + 'echo "[${COV_CLASSIFY_ARGS:-}]"'],
                                capture_output=True, text=True, check=False,
                                env={**os.environ, "COV_CLASSIFY_ARGS": "--offline"})
        self.assertEqual(result.stdout.strip(), "[]")

    def test_script_is_host_only(self) -> None:
        for needle in ("FENTON_COV_IOS", "ios_uitest", "coverage_ios", "UIKitPort", "simctl", "--impact"):
            self.assertNotIn(needle, self.SCRIPT)
        self.assertNotIn("cov_rerun_ios", (ROOT / "tools" / "coverage_phases.sh").read_text(encoding="utf-8"))


class ChangedSelectionTests(unittest.TestCase):
    """The --changed preamble of the coverage script, run against a stub affected_tests.py (nothing builds or boots)."""

    SCRIPT = (ROOT / "tools" / ("apple_cov" + "erage.sh")).read_text(encoding="utf-8")
    PREAMBLE = SCRIPT[SCRIPT.index("FILTER=()"):SCRIPT.index("# Every file under apple/Sources")]

    @classmethod
    def setUpClass(cls) -> None:
        sys.path.insert(0, str(ROOT / "tools"))
        import coverage_gate

        rules = json.loads(coverage_gate.RULES.read_text(encoding="utf-8"))
        categories, _, _ = coverage_gate.classify(coverage_gate.ROOT, rules, "swift")
        cls.logic_file = sorted(categories["logic"])[0]
        cls.ui_file = sorted(categories["unmeasured"])[0]

    def run_preamble(self, filter_words: str, status: int, changed: list[str]) -> subprocess.CompletedProcess:
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "tools").mkdir()
            (root / "tools" / "coverage_gate.py").symlink_to(ROOT / "tools" / "coverage_gate.py")
            (root / "tools" / "affected_tests.py").write_text(
                "import sys\n"
                "def changed_files():\n"
                f"    return {changed!r}\n"
                "if __name__ == '__main__':\n"
                f"    print({filter_words!r}); sys.exit({status})\n", encoding="utf-8")
            script = f'ROOT={root}; CHANGED=1\n{self.PREAMBLE}\necho "SOURCES=${{CHANGED_SOURCES[*]-}}"\n'
            return subprocess.run(["bash", "-c", script], capture_output=True, text=True, check=False)

    def test_only_changed_logic_files_are_gated(self) -> None:
        result = self.run_preamble("HassCoreTests", 0, [self.logic_file, self.ui_file, "README.md"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"SOURCES={self.logic_file}\n", result.stdout)
        self.assertIn("gating 1 changed logic source file(s)", result.stdout)

    def test_ui_only_diff_gates_nothing(self) -> None:
        result = self.run_preamble("HassUITests", 0, [self.ui_file])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SOURCES=\n", result.stdout)
        self.assertIn("gating 0 changed logic source file(s)", result.stdout)
        self.assertIn("== changed: no logic source changed; nothing to gate", self.SCRIPT)

    def test_diff_mapping_to_no_suite_keeps_the_early_exit(self) -> None:
        result = self.run_preamble("", 0, ["README.md", self.ui_file])
        self.assertEqual(result.returncode, 0)
        self.assertIn("nothing to run", result.stdout)
        self.assertNotIn("SOURCES=", result.stdout)

    def test_targeted_pick_request_still_exits_with_its_status(self) -> None:
        result = self.run_preamble("", 3, [self.logic_file])
        self.assertEqual(result.returncode, 3)
        self.assertNotIn("SOURCES=", result.stdout)

    def test_demo_house_is_classified(self) -> None:
        gate = subprocess.run([sys.executable, str(ROOT / "tools" / "coverage_gate.py"), "--language", "swift", "--classify-only"],
                              capture_output=True, text=True, check=False)
        self.assertEqual(gate.returncode, 0, gate.stdout + gate.stderr)


if __name__ == "__main__":
    unittest.main()
