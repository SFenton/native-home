#!/usr/bin/env bash
# Prepares a GitHub-hosted macOS runner (the xcode-27 image) for the app jobs: xcodegen (not on the image), the first
# simctl call (it can fail right after boot, actions/runner-images#13570), and a printout of the Xcode and runtimes the
# job got, and, with FENTON_INSTALL_SIMSLIM=1, the pinned simslim. Idempotent. Hosted mode only: refuses to run on the owner's Macs, where the tools are already installed.
#
#   FENTON_CI_HOSTED=1 tools/ci_hosted_setup.sh
#   FENTON_INSTALL_SIMSLIM=1 also installs the pinned simslim release (the macOS job; its seconds join the timing table as install-simslim).
set -euo pipefail
if [[ "${FENTON_CI_HOSTED:-}" != 1 || "${RUNNER_ENVIRONMENT:-}" != github-hosted ]]; then
  echo "ci_hosted_setup: needs FENTON_CI_HOSTED=1 on a GitHub-hosted runner (RUNNER_ENVIRONMENT=github-hosted); this is not one" >&2; exit 2
fi
command -v xcodegen > /dev/null || brew install xcodegen
xcrun simctl list > /dev/null 2>&1 || true
xcodebuild -version
xcrun simctl list runtimes

# simslim v0.14.0 (MobAI-App/simslim, MIT), the arm64 release binary, checked against its published sha256. No sudo: it goes to a
# runner-temp directory that is put on PATH for the later steps. Same pin and source as the parallel-slim layout of run 42520886689.
# Loud on any failure (set -e): a slim measurement on stock simulators would be a wrong number.
if [[ "${FENTON_INSTALL_SIMSLIM:-}" == 1 ]]; then
  start=$SECONDS
  SIMSLIM_URL="https://github.com/MobAI-App/simslim/releases/download/v0.14.0/simslim-v0.14.0-macos-arm64.tar.gz"
  SIMSLIM_SHA256="a3db0de6f428f9f8fd5dff256b122f98791c138521dc1330d99643719d8fe9ff"
  bin="${RUNNER_TEMP:-/tmp}/simslim-bin"
  mkdir -p "$bin"
  curl -fsSL --max-time 120 --retry 3 --retry-delay 5 --retry-all-errors -o "$bin/simslim.tar.gz" "$SIMSLIM_URL"
  echo "$SIMSLIM_SHA256  $bin/simslim.tar.gz" | shasum -a 256 -c -
  tar -xzf "$bin/simslim.tar.gz" -C "$bin" simslim
  chmod +x "$bin/simslim"
  [[ -n "${GITHUB_PATH:-}" ]] || { echo "ci_hosted_setup: GITHUB_PATH is not set; simslim would not reach the later steps" >&2; exit 1; }
  echo "$bin" >> "$GITHUB_PATH"
  "$bin/simslim" --version || { echo "ci_hosted_setup: the installed simslim does not run" >&2; exit 1; }
  printf 'install-simslim\t%s\t0\n' "$((SECONDS - start))" >> "${CI_MACOS_TIMINGS:-${RUNNER_TEMP:-/tmp}/ci-timings.tsv}"
fi
