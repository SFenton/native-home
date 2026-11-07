#!/usr/bin/env bash
# Prepares a GitHub-hosted macOS runner (the xcode-27 image) for the app jobs: xcodegen (not on the image), the first
# simctl call (it can fail right after boot, actions/runner-images#13570), and a printout of the Xcode and runtimes the
# job got. Idempotent. Hosted mode only: refuses to run on the owner's Macs, where the tools are already installed.
#
#   FENTON_CI_HOSTED=1 tools/ci_hosted_setup.sh
set -euo pipefail
if [[ "${FENTON_CI_HOSTED:-}" != 1 || "${RUNNER_ENVIRONMENT:-}" != github-hosted ]]; then
  echo "ci_hosted_setup: needs FENTON_CI_HOSTED=1 on a GitHub-hosted runner (RUNNER_ENVIRONMENT=github-hosted); this is not one" >&2; exit 2
fi
command -v xcodegen > /dev/null || brew install xcodegen
xcrun simctl list > /dev/null 2>&1 || true
xcodebuild -version
xcrun simctl list runtimes
