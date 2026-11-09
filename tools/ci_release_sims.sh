#!/usr/bin/env bash
# Hosted CI: shut down every booted simulator and stop any xcodebuild or xctest a hung run left behind, so the next device boots on an
# idle runner (tools/ci_macos.sh says why). Best effort and always exits 0. Hosted mode only: refuses anywhere else, because on the
# owner's Macs it would shut down simulators other lanes use.
set -uo pipefail
if [[ "${FENTON_CI_HOSTED:-}" != 1 || "${RUNNER_ENVIRONMENT:-}" != github-hosted ]]; then
  echo "ci_release_sims: needs FENTON_CI_HOSTED=1 on a GitHub-hosted runner; this is not one" >&2; exit 2
fi
booted="$(xcrun simctl list devices booted 2> /dev/null | grep -c Booted || true)"
echo "ci_release_sims: ${booted:-0} simulator(s) booted; shutting them down"
pkill -x xcodebuild 2> /dev/null || true
pkill -x xctest 2> /dev/null || true
xcrun simctl shutdown all > /dev/null 2>&1 || true
exit 0
