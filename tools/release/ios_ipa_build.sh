#!/usr/bin/env bash
# Archives the app and exports a signed IPA (method app-store-connect, destination export: nothing is uploaded).
#
# Usage: tools/release/ios_ipa_build.sh TAG BUILD_NUMBER [--dry-run]
#        tools/release/ios_ipa_build.sh --probe-signing        (only checks that codesign works without a prompt)
#   TAG           the version tag to build, ios/v<YYMM.DD.NN>; the checkout must be at that tag
#   BUILD_NUMBER  CURRENT_PROJECT_VERSION (an integer that grows with every build)
# Output (build/release-ios/): FentonHome.xcarchive, export/ (the .ipa), FentonHome-<version>.ipa and
# FentonHome-<version>-dSYMs.zip. stdout ends with `ipa=…` and `dsyms=…` lines for the workflow.
# Signing: automatic, team 3Q9X8JX23S, the Apple Distribution identity in the login Keychain and the Apple ID signed in to
# Xcode (xcodebuild -allowProvisioningUpdates fetches the App Store profiles). When that is missing the script exits 4 with a
# message naming exactly what to provide. Documentation: .agents/workflow/ci.md.
set -euo pipefail

TAG="${1:?usage: ios_ipa_build.sh TAG BUILD_NUMBER [--dry-run] | --probe-signing}"
BUILD="${2:-0}"
DRY=0
[[ "${3:-}" == "--dry-run" ]] && DRY=1

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
OUT="${FENTON_IPA_OUT:-$ROOT/build/release-ios}"
ARCHIVE="$OUT/FentonHome.xcarchive"
EXPORT="$OUT/export"

positive_int() { [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || { echo "[ios_ipa_build] $1 must be a positive integer, got '${2}'" >&2; exit 2; }; }
[[ -z "${FENTON_SIGN_PROBE_TIMEOUT+x}" ]] || positive_int FENTON_SIGN_PROBE_TIMEOUT "$FENTON_SIGN_PROBE_TIMEOUT"
[[ -z "${FENTON_IDLE_TIMEOUT_SECONDS+x}" ]] || positive_int FENTON_IDLE_TIMEOUT_SECONDS "$FENTON_IDLE_TIMEOUT_SECONDS"
# Test seams, honoured only when FENTON_IPA_TEST=1.
DEVCAP_PY="$ROOT/tools/devcap.py"; VERSIONING_PY="$ROOT/tools/release/versioning.py"
if [[ "${FENTON_IPA_TEST:-}" == "1" ]]; then DEVCAP_PY="${FENTON_DEVCAP:-$DEVCAP_PY}"; VERSIONING_PY="${FENTON_VERSIONING:-$VERSIONING_PY}"; fi
# The output directory is wiped with rm -rf: it must resolve under the repo's build/ or $TMPDIR.
if [[ -n "${FENTON_IPA_OUT:-}" ]]; then
  OUT_REAL="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$FENTON_IPA_OUT")"
  ok=0
  for base in "$ROOT/build" "${TMPDIR:-/tmp}"; do
    base_real="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$base")"
    [[ "$OUT_REAL" == "$base_real"/* ]] && ok=1
  done
  [[ $ok == 1 ]] || { echo "[ios_ipa_build] FENTON_IPA_OUT ($OUT_REAL) must be inside $ROOT/build or \$TMPDIR" >&2; exit 2; }
fi

log() { echo "[ios_ipa_build] $*" >&2; }
run() {
  if [[ $DRY == 1 ]]; then printf '+' >&2; printf ' %q' "$@" >&2; printf '\n' >&2; else "$@"; fi
}
missing() {
  log "BLOCKED: $1"
  log "Owner step (needs the login password, run once in Terminal on the runner Mac):"
  log "  security set-key-partition-list -S apple-tool:,apple: -s -k '<login password>' ~/Library/Keychains/login.keychain-db"
  log "(or open Keychain Access, the Apple Distribution private key > Access Control > add /usr/bin/codesign), and keep the user logged in and unlocked."
  log "Provide: an Apple Distribution certificate for team 3Q9X8JX23S (with its private key) in the login Keychain of the Mac"
  log "that runs the runner, and the Apple ID that owns the team signed in to Xcode (Settings > Accounts) so automatic"
  log "signing can create the App Store provisioning profiles. Alternatively an App Store Connect API key"
  log "(ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH) for xcodebuild -authenticationKeyPath."
  exit 4
}

# Signs a throwaway copy of /usr/bin/true with EVERY identity the archive and export can use, each under a short timeout:
# the Apple Distribution identity of team 3Q9X8JX23S (required) and each Apple Development identity (optional; automatic
# signing archives with Development, then export re-signs with Distribution). A keychain that wants a password prompt (a
# private key's access control, a locked keychain) would otherwise hang the archive for hours.
# FENTON_SIGN_PROBE_TIMEOUT seconds (default 20); CODESIGN_BIN lets tests stub it.
probe_identity() { # LABEL SHA1
  local probe rc=0
  probe="$(mktemp -d)/probe"
  cp /usr/bin/true "$probe"
  perl -e 'alarm shift; exec @ARGV' "${FENTON_SIGN_PROBE_TIMEOUT:-20}" "${CODESIGN_BIN:-codesign}" --force --sign "$2" "$probe" >/dev/null 2>&1 || rc=$?
  rm -rf "$(dirname "$probe")"
  [[ $rc == 0 ]] || missing "codesign with the $1 identity failed or waited for a prompt (exit $rc); that private key needs 'Always Allow' for codesign, or the keychain is locked"
}
# True when the keychain certificate whose SHA-1 is $1 belongs to team 3Q9X8JX23S (OU). Matches by hash, not by name: after a
# renewal two certificates share a name and `find-certificate -c` returns the first, not necessarily this identity. On false,
# SKIP_REASON says why (never key material).
dev_cert_in_team() { # SHA1
  local pem
  SKIP_REASON=""
  pem="$(security find-certificate -a -Z -p 2>/dev/null | awk -v want="$1" '
    /^SHA-1 hash:/ { cur = toupper($3); keep = (cur == toupper(want)); next }
    keep { print }
    /-----END CERTIFICATE-----/ { keep = 0 }')" || true
  if [[ -z "$pem" ]]; then SKIP_REASON="no keychain certificate with this SHA-1"; return 1; fi
  if openssl x509 -noout -subject <<< "$pem" 2>/dev/null | grep -q '3Q9X8JX23S'; then return 0; fi
  SKIP_REASON="certificate is not for team 3Q9X8JX23S"; return 1
}
probe_signing() {
  local listing dist sha name
  listing="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  dist="$(sed -n 's/.*\([0-9A-F]\{40\}\) "Apple Distribution: .*(3Q9X8JX23S)".*/\1/p' <<< "$listing" | head -n 1)"
  [[ -n "$dist" ]] || missing "no 'Apple Distribution' identity for team 3Q9X8JX23S in the keychain search list"
  probe_identity "Apple Distribution" "$dist"
  # Development certificates carry a personal id in their name, not the team id: read the team (OU) from the certificate and
  # probe only this team's, so other teams' keys (Festival, personal) cannot block a release.
  while IFS=$'\t' read -r sha name; do
    [[ -n "$sha" ]] || continue
    if dev_cert_in_team "$sha"; then
      probe_identity "Apple Development" "$sha"
    else
      log "skipping Apple Development identity $name ($sha): $SKIP_REASON"
    fi
  done < <(sed -n 's/.*\([0-9A-F]\{40\}\) "\(Apple Development: .*\)".*/\1\t\2/p' <<< "$listing")
}

# Runs a command and kills it when it prints nothing (stdout and stderr) for FENTON_IDLE_TIMEOUT_SECONDS (default 600): a
# signing step waiting on a Keychain prompt is silent. Exit 124 on a kill. Used inside the devcap hold so queueing for a
# slot is not counted.
IDLE_WATCHDOG='
use IO::Select; use POSIX ":sys_wait_h"; $| = 1;
my $idle = shift; pipe(my $or, my $ow); pipe(my $er, my $ew);
my $pid = fork; die "fork" unless defined $pid;
if (!$pid) { setpgrp(0, 0); open STDOUT, ">&", $ow; open STDERR, ">&", $ew; close $or; close $er; exec @ARGV or exit 127; }
close $ow; close $ew; my $sel = IO::Select->new($or, $er); my $last = time; my ($sig, $status);
$SIG{TERM} = sub { $sig = 15 }; $SIG{INT} = sub { $sig = 2 }; $SIG{HUP} = sub { $sig = 1 };
sub pump { my ($t) = @_; for my $fh ($sel->can_read($t)) {
    my $n = sysread($fh, my $buf, 65536);
    if (!$n) { $sel->remove($fh); next }
    $last = time; if ($fh == $or) { print STDOUT $buf } else { print STDERR $buf } } }
sub reap_group { # signal the group, a short grace, then KILL, and wait for the direct child
  my ($s) = @_; kill $s, -$pid;
  for (1 .. 30) { last if waitpid($pid, WNOHANG) == $pid; select(undef, undef, undef, 0.1) }
  kill "KILL", -$pid; waitpid($pid, WNOHANG);
}
while ($sel->count) {
  pump(1);
  if ($sig) { reap_group($sig == 2 ? "INT" : $sig == 1 ? "HUP" : "TERM"); exit 128 + $sig }
  my $w = waitpid($pid, WNOHANG);
  if ($w == $pid) { $status = $?; pump(0) for 1 .. 3; last } # child finished: a lingering helper holding a pipe does not matter
  if (time - $last > $idle) { reap_group("TERM"); exit 124 }
}
if (!defined $status) { waitpid($pid, 0); $status = $? }
exit($status & 127 ? 128 + ($status & 127) : $status >> 8);
'
guarded() { perl -e "$IDLE_WATCHDOG" "${FENTON_IDLE_TIMEOUT_SECONDS:-600}" "$@"; }
silent_hang() { # EXIT_CODE LABEL: exit 124 means the watchdog fired
  [[ $1 != 124 ]] || missing "$2 printed nothing for ${FENTON_IDLE_TIMEOUT_SECONDS:-600} s and was killed; it is almost certainly waiting on a Keychain prompt for a signing key"
}

if [[ "$TAG" == "--probe-signing" ]]; then probe_signing; echo "signing ok"; exit 0; fi
if [[ $DRY == 0 ]]; then probe_signing; fi

SETTINGS=()
if [[ $DRY == 1 ]]; then SETTINGS=("MARKETING_VERSION=<version>" "CURRENT_PROJECT_VERSION=$BUILD" "HASS_GIT_SHA=<sha>")
else
  # A failing versioning.py must stop the build: never archive an unstamped (0.1.0) IPA.
  SETTINGS_OUT="$(python3 "$VERSIONING_PY" --repo "$ROOT" build-settings --tag "$TAG" --build "$BUILD")" \
    || { log "versioning.py failed for $TAG: refusing to build an unstamped IPA"; exit 1; }
  while IFS= read -r line; do [[ -n "$line" ]] && SETTINGS+=("$line"); done <<< "$SETTINGS_OUT"
  [[ ${#SETTINGS[@]} -ge 3 ]] || { log "versioning.py returned no build settings for $TAG"; exit 1; }
fi
# The sign-in Server field default comes from the HASS_DEFAULT_SERVER repository variable; empty leaves the field blank.
[[ -z "${HASS_DEFAULT_SERVER:-}" ]] || SETTINGS+=("HASS_DEFAULT_SERVER=$HASS_DEFAULT_SERVER")
VERSION="${TAG#ios/v}"

rm -rf "$OUT"; mkdir -p "$OUT"
cd "$ROOT/apple"
run xcodegen generate --quiet

AUTH=()
if [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

run python3 "$DEVCAP_PY" run --pool build --hold 3600 --purpose "ios-release archive $TAG" -- \
  perl -e "$IDLE_WATCHDOG" "${FENTON_IDLE_TIMEOUT_SECONDS:-600}" \
  xcodebuild archive -project FentonHome.xcodeproj -scheme FentonHome -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -derivedDataPath "${FENTON_DERIVED_DATA:-$OUT/DerivedData}" -allowProvisioningUpdates \
    ${AUTH[@]+"${AUTH[@]}"} "${SETTINGS[@]}" \
  || { rc=$?; silent_hang "$rc" "xcodebuild archive"; log "archive failed (signing problems are named above in xcodebuild's output)"; exit 1; }

run guarded xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$ROOT/tools/release/ExportOptions-appstore.plist" -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
  || { rc=$?; silent_hang "$rc" "xcodebuild -exportArchive"; log "export failed"; exit 1; }

if [[ $DRY == 1 ]]; then exit 0; fi
IPA="$(find "$EXPORT" -maxdepth 1 -name '*.ipa' | head -n 1)"
[[ -n "$IPA" ]] || { log "export produced no .ipa"; exit 1; }
cp "$IPA" "$OUT/FentonHome-$VERSION.ipa"
ditto -c -k --keepParent "$ARCHIVE/dSYMs" "$OUT/FentonHome-$VERSION-dSYMs.zip"
echo "ipa=$OUT/FentonHome-$VERSION.ipa"
echo "dsyms=$OUT/FentonHome-$VERSION-dSYMs.zip"
