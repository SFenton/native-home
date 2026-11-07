#!/bin/sh
# One-time (and idempotent) checkout setup: install the tracked git hooks and report the denylist state.
# Usage: tools/setup.sh
# Prints counts only, never a term. Exits 1 when python3 is missing or the hook cannot be made executable.
set -u
root="$(git rev-parse --show-toplevel)" || { echo "setup: not inside a git checkout" >&2; exit 1; }
cd "$root" || exit 1
rc=0

git config core.hooksPath .githooks
echo "setup: core.hooksPath = $(git config core.hooksPath)"

for hook in .githooks/*; do
  [ -f "$hook" ] || continue
  if [ ! -x "$hook" ]; then chmod +x "$hook" 2>/dev/null; fi
  if [ -x "$hook" ]; then echo "setup: $hook is executable"; else echo "setup: $hook is NOT executable" >&2; rc=1; fi
done

if command -v python3 >/dev/null 2>&1; then
  echo "setup: python3 found"
  python3 - <<'PY' || rc=1
import sys
sys.path.insert(0, "tools")
import house_scan
path, label = house_scan.denylist_source()
count = len(house_scan.load_denylist())
if count:
    print(f"setup: denylist found ({label}), {count} term(s)" + ("" if count >= 20 else "; fewer than 20, the public repo will refuse pushes"))
else:
    print("setup: no denylist found (HOUSE_SCAN_DENYLIST, the config folder or ~/hass-agents); pushes to the public repo are refused until one exists")
PY
else
  echo "setup: python3 not found; the pre-push hook needs it" >&2
  rc=1
fi
exit "$rc"
