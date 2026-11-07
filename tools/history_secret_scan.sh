#!/usr/bin/env bash
# One-time gate before plan step 13 (making the repository public): scan every commit on every branch for secrets.
#
#   tools/history_secret_scan.sh
#
# Runs gitleaks over the full history (--log-opts="--all") with redaction on, writes the JSON report to the git-ignored
# build/secret-scan/ folder (HISTORY_SCAN_OUT overrides the folder, for tests) and prints counts by rule, never a finding's value.
# Triaged false positives are listed by fingerprint in .gitleaksignore; fixture files are path-scoped in .gitleaks.toml (--config).
# gitleaks runs from the repo root so paths are repo-relative (the ^ anchors in .gitleaks.toml rely on it); an absolute-path
# dir scan fails closed (findings). Rules for adding an entry: .agents/workflow/secret-scan-triage.md.
# Needs gitleaks on PATH (brew install gitleaks); this script does not install it.
# gitleaks exits 1 for "leaks or an error", so leaks are asked to exit 3: 0 is a completed clean scan, 3 a completed scan with
# findings, anything else (1 included) a failed scan.
# Exit 0 clean, 1 findings, 2 gitleaks missing, failed, or no readable report.
# Not a per-PR check. Documentation: .agents/workflow/ci.md.
set -uo pipefail
cd "$(dirname "$0")/.."

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "history_secret_scan: gitleaks is not installed (brew install gitleaks); nothing was scanned" >&2
  exit 2
fi

OUT="${HISTORY_SCAN_OUT:-build/secret-scan}"
mkdir -p "$OUT"
REPORT="$OUT/report.json"
rm -f "$REPORT"

gitleaks git --redact --no-banner --config .gitleaks.toml --gitleaks-ignore-path .gitleaksignore --log-opts="--all" --report-format json --report-path "$REPORT" --exit-code 3 >"$OUT/gitleaks.log" 2>&1
CODE=$?
if [ "$CODE" -ne 0 ] && [ "$CODE" -ne 3 ]; then
  echo "history_secret_scan: gitleaks failed (exit $CODE); see $OUT/gitleaks.log" >&2
  exit 2
fi

python3 - "$REPORT" <<'PY'
import json
import sys
from collections import Counter

try:
    findings = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    print("history_secret_scan: no readable report; the scan did not complete", file=sys.stderr)
    sys.exit(2)
if not isinstance(findings, list):
    print("history_secret_scan: the report is not a list of findings", file=sys.stderr)
    sys.exit(2)
counts = Counter(f.get("RuleID", "unknown") for f in findings if isinstance(f, dict))
print(f"history_secret_scan: {len(findings)} finding(s) across all branches")
for rule, n in sorted(counts.items()):
    print(f"  {rule}: {n}")
sys.exit(1 if findings else 0)
PY
STATUS=$?
if [ "$STATUS" -eq 0 ] && [ "$CODE" -eq 3 ]; then
  echo "history_secret_scan: gitleaks reported leaks but the report lists none; treating as failed" >&2
  exit 2
fi
exit "$STATUS"
