#!/usr/bin/env bash
# Builds the app (`FentonHome`, UIKit) for the iOS Simulator inside a devcap build hold.
#   tools/uikit_build.sh [--scheme FentonHome] [--optimized] [--dd DIR]
# --optimized builds Debug with -O (the Release code path with the galleries in), as tools/ios_scrollcost.sh does.
# The package checkouts are shared by every worktree of the port (build/uikit-spm under the main checkout's .claude dir).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
SCHEME=FentonHome
OPT=0
DD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scheme) SCHEME="$2"; shift 2 ;;
    --optimized) OPT=1; shift ;;
    --dd) DD="$2"; shift 2 ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
done
SUFFIX=""; if [[ $OPT == 1 ]]; then SUFFIX="-O"; fi
[[ -n "$DD" ]] || DD="$ROOT/apple/build/dd-$SCHEME$SUFFIX"
SPM="${UIKIT_SPM_DIR:-$HOME/Library/Caches/fenton-uikit-port/spm}"
mkdir -p "$SPM"
cd apple
# Regenerate whenever project.yml changed since the project was generated (a merged lane may add targets or sources).
if [[ ! -d FentonHome.xcodeproj || project.yml -nt FentonHome.xcodeproj/project.pbxproj ]]; then xcodegen generate >/dev/null; fi
EXTRA=()
if [[ $OPT == 1 ]]; then EXTRA+=(SWIFT_OPTIMIZATION_LEVEL=-O GCC_OPTIMIZATION_LEVEL=s); fi
exec python3 "$ROOT/tools/devcap.py" run --pool build --purpose "build $SCHEME" -- \
  xcodebuild -project FentonHome.xcodeproj -scheme "$SCHEME" -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DD" -clonedSourcePackagesDirPath "$SPM" \
  -skipPackagePluginValidation -quiet ${EXTRA[@]+"${EXTRA[@]}"} build
