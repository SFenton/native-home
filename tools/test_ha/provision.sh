#!/usr/bin/env bash
# Push the DemoHouse configuration to the test Home Assistant and read it back (plan steps 8 and 9).
#
#   tools/test_ha/provision.sh [--with-extra] [--no-export] [--no-verify] [--dry-run]
#
# 1. export the DemoHouse document (tools/test_ha/export_demo_house.sh) unless --no-export or build/ha/demo-house.json is fresh;
# 2. generate the package (gen_demo_package.py) under build/ha/test-instance;
# 3. apply configuration.yaml, the package, fenton_home/house.json and the fenton_demo component in ONE
#    `tools/ha_change.py --host hass-test apply` (backup, write, `ha core check`, rollback on failure, restart), so every guardrail
#    and the change log hold. demo_house_extra.yaml (template climate, vacuum, alarm panel, weather) goes only
#    with --with-extra, once the step-6 spike has confirmed its keys;
# 4. http_config.py sets the proxy settings through Core's stored-config websocket (http/config/configure, then promote; skipped when
#    stable already matches), streamed into the SSH add-on. Core 2026.11 ignores an http: YAML block, and under Supervisor it listens
#    on port 80, not 8123;
# 5. verify.py reads every DemoHouse id back (needs FENTON_TEST_HA_URL and FENTON_TEST_HA_TOKEN: the test instance's own).
#
# `hass-test` is the ssh alias from tools/test_ha/ssh_config.template. Nothing here touches the house's `hass` alias, tokens or
# credentials folder. --dry-run stops after generating and prints the apply command.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
EXTRA=0 EXPORT=1 VERIFY=1 DRY=0
for arg in "$@"; do
  case "$arg" in
    --with-extra) EXTRA=1 ;;
    --no-export) EXPORT=0 ;;
    --no-verify) VERIFY=0 ;;
    --dry-run) DRY=1 ;;
    *) echo "usage: provision.sh [--with-extra] [--no-export] [--no-verify] [--dry-run]" >&2; exit 2 ;;
  esac
done

OUT="$ROOT/build/ha/test-instance/config"
(( EXPORT )) && "$HERE/export_demo_house.sh"
python3 "$HERE/gen_demo_package.py" --export "$ROOT/build/ha/demo-house.json" --out "$ROOT/build/ha/test-instance"

FILES=(
  "$HERE/configuration.yaml.tmpl:configuration.yaml"
  "$OUT/packages/demo_house.yaml:packages/demo_house.yaml"
  "$OUT/fenton_home/house.json:fenton_home/house.json"
)
(( EXTRA )) && FILES+=("$OUT/packages/demo_house_extra.yaml:packages/demo_house_extra.yaml")
for f in manifest.json __init__.py todo.py valve.py camera.py remote.py media_player.py; do
  FILES+=("$HERE/custom_components/fenton_demo/$f:custom_components/fenton_demo/$f")
done
FILES+=("$OUT/custom_components/fenton_demo/demo_data.json:custom_components/fenton_demo/demo_data.json")

CMD=(python3 "$ROOT/tools/ha_change.py" --host hass-test apply --files "${FILES[@]}" --reason "provision the DemoHouse test instance")
if (( DRY )); then printf '%q ' "${CMD[@]}"; echo; exit 0; fi
"${CMD[@]}"
ssh hass-test "python3 - ensure" < "$HERE/http_config.py"
(( VERIFY )) && python3 "$HERE/verify.py" --export "$ROOT/build/ha/demo-house.json"
exit 0
