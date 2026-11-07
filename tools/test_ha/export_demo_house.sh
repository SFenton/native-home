#!/usr/bin/env bash
# Write build/ha/demo-house.json from DemoHouse (DEBUG only): the document plus one resting state per entity id.
#
#   tools/test_ha/export_demo_house.sh
#
# Runs the `exportsToThePathInTheEnvironment` test of HassCoreTests/DemoHouseExportTests with DEMO_HOUSE_EXPORT set, inside the
# machine-wide build slot (devcap). Launch it with tools/bg_run.py when run by hand; provision.sh calls it as a step.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export DEMO_HOUSE_EXPORT="$ROOT/build/ha/demo-house.json"
mkdir -p "$ROOT/build/ha"
python3 "$ROOT/tools/devcap.py" run --pool build --pool swift-test --hold 3000 --max-wait 1200 -- \
  swift test --package-path "$ROOT/apple" --filter DemoHouseExportTests
test -s "$DEMO_HOUSE_EXPORT" || { echo "export_demo_house: $DEMO_HOUSE_EXPORT was not written" >&2; exit 1; }
echo "wrote $DEMO_HOUSE_EXPORT"
