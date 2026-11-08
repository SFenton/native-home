"""Behaviour of the build-before-boot path: ``ios_uitest.sh --build-only``, the hosted-only build settings and the settle loop
of ``sim_settle.sh``, all run against stubbed ``xcodebuild``/``xcrun``/``sysctl``/``memory_pressure`` on PATH."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]

XCODEBUILD = r'''#!/bin/bash
echo "xcodebuild $*" >> "$STUB_LOG"
if [ "$1" = "-version" ]; then echo "Xcode 99.0"; exit 0; fi
while [ $# -gt 0 ]; do
  if [ "$1" = "-testProductsPath" ]; then out="$2"; fi
  shift
done
mkdir -p "$out/Binaries" "$out/Tests"
echo x > "$out/Binaries/app"
printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>' > "$out/Info.plist"
'''
XCRUN = '#!/bin/bash\necho "xcrun $*" >> "$STUB_LOG"\nif [ "$2" = "boot" ] && [ -n "$STUB_BOOT_FAIL" ]; then exit 1; fi\nif [ "$2" = "bootstatus" ] && [ -n "$STUB_BOOT_FAIL" ]; then exit 1; fi\nexit 0\n'
SYSCTL = '#!/bin/bash\nn=$(cat "$STUB_DIR/n" 2>/dev/null || echo 0); echo $((n+1)) > "$STUB_DIR/n"\nl=$(sed -n "$((n+1))p" "$STUB_DIR/loads"); [ -n "$l" ] || l=$(tail -1 "$STUB_DIR/loads")\necho "{ $l }"\n'


def stubs(tmp, loads="500 400 300", **files):
    bin_dir = Path(tmp) / "bin"
    bin_dir.mkdir()
    for name, body in {"xcodebuild": XCODEBUILD, "xcrun": XCRUN, "sysctl": SYSCTL, "memory_pressure": "#!/bin/bash\necho 'System-wide memory free percentage: 50%'\n",
                       "xcodegen": "#!/bin/bash\nmkdir -p FentonHome.xcodeproj\nexit 0\n"}.items():
        (bin_dir / name).write_text(body)
        (bin_dir / name).chmod(0o755)
    (Path(tmp) / "loads").write_text(loads.replace(";", "\n") + "\n")
    env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "STUB_LOG": str(Path(tmp) / "log"), "STUB_DIR": str(tmp)}
    return env


class BuildOnlyTests(unittest.TestCase):
    def run_build_only(self, tmp, **env):
        run_env = stubs(tmp)
        pool = Path(tmp) / "pool.txt"
        pool.write_text("-- iOS 27.1 --\n    iPhone 17 (11111111-1111-1111-1111-111111111111) (Shutdown) \n")
        run_env.update({"FENTON_PRODUCTS_DIR": str(Path(tmp) / "products"), "FENTON_CI_HOSTED": "1", "RUNNER_ENVIRONMENT": "github-hosted",
                        "FENTON_SIM_LIST_FILE": str(pool)})
        run_env.update(env)
        out = subprocess.run(["bash", str(TOOLS / "ios_uitest.sh"), "--only", "iphone", "--plan", "Smoke", "--force", "--build-only"],
                             env=run_env, capture_output=True, text=True)
        log = (Path(tmp) / "log").read_text() if (Path(tmp) / "log").exists() else ""
        return out, log, sorted(p.name for p in (Path(tmp) / "products").glob("*.xctestproducts"))

    def test_build_only_builds_and_exits_before_any_simulator_call(self):
        with tempfile.TemporaryDirectory() as tmp:
            out, log, bundles = self.run_build_only(tmp)
            self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
            self.assertIn("build-only: products ready", out.stdout)
            self.assertIn("build-for-testing", log)
            for verb in ("simctl boot", "simctl bootstatus", "simctl io", "simctl shutdown"):  # the one `simctl list` is the setup probe
                self.assertNotIn(verb, log)
            self.assertEqual(len(bundles), 1)

    def test_hosted_settings_join_the_build_and_the_key_only_in_hosted_mode(self):
        settings = "ARCHS=arm64 ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO"
        with tempfile.TemporaryDirectory() as tmp:
            out, log, bundles = self.run_build_only(tmp, FENTON_HOSTED_BUILD_SETTINGS=settings)
            self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
            for setting in settings.split():
                self.assertIn(setting, log)
            self.assertEqual(len(bundles), 1)
        with tempfile.TemporaryDirectory() as tmp2:
            out2, log2, bundles2 = self.run_build_only(tmp2)
            self.assertNotIn("ARCHS=arm64", log2)
            self.assertNotEqual(bundles, bundles2)  # hosted products have their own key

    def test_the_variable_alone_adds_no_settings_off_a_hosted_runner(self):
        script = (TOOLS / "ios_uitest.sh").read_text()
        self.assertIn('[[ $CI_HOSTED == 1 && -n "${FENTON_HOSTED_BUILD_SETTINGS:-}" ]]', script)
        self.assertIn('[[ "${FENTON_CI_HOSTED:-}" == 1 && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] && CI_HOSTED=1', script)


class SettleLoopTests(unittest.TestCase):
    def settle(self, loads, family="duo", **env):
        with tempfile.TemporaryDirectory() as tmp:
            run_env = stubs(tmp, loads)
            run_env.update({"FENTON_SETTLE_UDID": "UDID", "FENTON_SETTLE_POLL": "1", "FENTON_SETTLE_DWELL": "3", "FENTON_SETTLE_CAP": "8",
                            "FENTON_HEALTH_BOOT_WALL": "10"})
            run_env.update(env)
            out = subprocess.run(["bash", str(TOOLS / "sim_settle.sh"), family], env=run_env, capture_output=True, text=True, timeout=60)
            log = (Path(tmp) / "log").read_text() if (Path(tmp) / "log").exists() else ""
            return out, log

    def test_it_boots_and_waits_for_bootstatus_first(self):
        out, log = self.settle("5 5 5;5 5 5")
        self.assertLess(log.index("simctl boot UDID"), log.index("simctl bootstatus UDID -b"))
        self.assertEqual(out.returncode, 0, out.stdout)

    def test_a_low_first_reading_does_not_settle_before_the_dwell(self):
        out, _ = self.settle(";".join(["5 5 5"] * 10))
        self.assertEqual(out.returncode, 0)
        elapsed = int(out.stdout.split("settled after ")[1].split("s")[0])
        self.assertGreaterEqual(elapsed, 3)

    def test_it_needs_two_settled_polls_in_a_row(self):
        # dwell passes at once (0); a storm reading in between resets the count
        out, _ = self.settle("5 5 5;500 400 300;5 5 5;5 5 5;5 5 5", FENTON_SETTLE_DWELL="0", FENTON_SETTLE_CAP="20")
        self.assertIn("settled-polls=1", out.stdout)
        self.assertIn("settled-polls=0", out.stdout)
        self.assertIn("settled after", out.stdout)

    def test_it_gives_up_at_the_cap_with_zero(self):
        out, _ = self.settle("500 400 300", FENTON_SETTLE_CAP="4")
        self.assertEqual(out.returncode, 0)
        self.assertIn("gave up after 4s", out.stdout)

    def test_a_boot_failure_is_reported_and_exits_nonzero(self):
        out, _ = self.settle("5 5 5", STUB_BOOT_FAIL="1")
        self.assertEqual(out.returncode, 1)
        self.assertIn("boot failed", out.stdout)

    def test_a_bad_heartbeat_interval_is_a_usage_error(self):
        for args in (["-i"], ["-i", "abc", "--", "true"], ["-i", "0", "--", "true"]):
            out = subprocess.run(["bash", str(TOOLS / "ci_heartbeat.sh"), "run", *args], capture_output=True, text=True, timeout=10)
            self.assertEqual(out.returncode, 2, args)


if __name__ == "__main__":
    unittest.main()
