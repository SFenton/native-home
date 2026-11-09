#!/usr/bin/env bash
# Rebuild the test Home Assistant VM from scratch on the Linux host (plan: build/research/test-ha-instance.md step 4 and 14).
#
#   tools/test_ha/rebuild.sh [--dry-run] [--destroy]
#
# Runs from the Mac over ssh to the libvirt host (alias in TEST_HA_HOST, default sfenton-hass-linux). Everything goes through
# `virsh -c qemu:///system`; no sudo. Steps: download the pinned HAOS qcow2.xz (haos.pin) and check its sha256, unpack it into
# ~/KVM/homeassistant-test (as on the live host), resize the disk to 32 GiB (thin), fill vm.xml.tmpl with a fresh UUID and the
# pinned MAC, define the domain (no autostart), start it. Then `provision.sh` pushes the configuration.
#
#   --dry-run  print what would run and the resolved domain XML (MAC masked); change nothing and contact nothing.
#   --destroy  first stop and undefine an existing homeassistant-test and delete its disk (a rebuild). Never touches any other VM.
#
# Without --destroy the script refuses when the domain or its disk already exists, so it can never overwrite a running VM.
# The MAC is read from build/ha/test-vm.mac (git-ignored) or TEST_HA_MAC; when neither exists a new one is generated and saved
# there, so the router's DHCP reservation survives a rebuild. The MAC is never printed.
# The domain name is fixed to homeassistant-test: a name check refuses to destroy anything else.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HOST="${TEST_HA_HOST:-sfenton-hass-linux}"
NAME="homeassistant-test"
DIR="/home/sfenton/KVM/homeassistant-test"
DISK="$DIR/haos-test.qcow2"
MAC_FILE="$ROOT/build/ha/test-vm.mac"
DRY=0
DESTROY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    --destroy) DESTROY=1 ;;
    *) echo "usage: rebuild.sh [--dry-run] [--destroy]" >&2; exit 2 ;;
  esac
done

# shellcheck disable=SC1091
source "$HERE/haos.pin"
VIRSH="virsh -c qemu:///system"

run() { # run a command line on the host (or print it)
  if (( DRY )); then echo "[dry-run] ssh $HOST: $*"; else ssh -o BatchMode=yes "$HOST" "$*"; fi
}

UUID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
MAC="${TEST_HA_MAC:-}"
[[ -z "$MAC" && -s "$MAC_FILE" ]] && MAC="$(tr -d '[:space:]' < "$MAC_FILE")"
if [[ -z "$MAC" ]]; then
  MAC="$(python3 -c 'import random; print("52:54:00:%02x:%02x:%02x" % tuple(random.randint(0, 255) for _ in range(3)))')"
  (( DRY )) || { mkdir -p "$(dirname "$MAC_FILE")"; printf '%s\n' "$MAC" > "$MAC_FILE"; }
fi
[[ "$MAC" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]] || { echo "rebuild: the MAC is not a lower-case colon address" >&2; exit 1; }
XML="$(sed -e "s|@NAME@|$NAME|g" -e "s|@UUID@|$UUID|" -e "s|@MAC@|$MAC|" -e "s|@DISK@|$DISK|" "$HERE/vm.xml.tmpl")"
if grep -q '@[A-Z]*@' <<<"$XML"; then echo "rebuild: an XML token was not filled" >&2; exit 1; fi

if (( DRY )); then
  echo "[dry-run] would refuse without --destroy if '$VIRSH dominfo $NAME' succeeds or '$DISK' exists"
else
  if (( ! DESTROY )); then
    if ssh -o BatchMode=yes "$HOST" "$VIRSH dominfo $NAME >/dev/null 2>&1 || [ -e '$DISK' ]"; then
      echo "rebuild: $NAME or its disk already exists; pass --destroy to replace it" >&2; exit 1
    fi
  fi
fi

if (( DESTROY )); then
  [[ "$NAME" == homeassistant-test ]] || { echo "rebuild: refusing to destroy $NAME" >&2; exit 1; }
  run "$VIRSH destroy $NAME 2>/dev/null || true; $VIRSH undefine $NAME --nvram 2>/dev/null || true; rm -f '$DISK'"
fi

run "mkdir -p '$DIR' && cd '$DIR' && { [ -f '$HAOS_ASSET' ] || curl -fL -o '$HAOS_ASSET' '$HAOS_URL'; } && echo '$HAOS_SHA256  $HAOS_ASSET' | sha256sum -c -"
run "cd '$DIR' && [ ! -e '$DISK' ] && xz -dkc '$HAOS_ASSET' > '$DISK' && qemu-img resize '$DISK' 32G && qemu-img info '$DISK' | grep -E 'virtual size|disk size'"

if (( DRY )); then
  echo "[dry-run] domain XML (MAC masked):"; echo "${XML//$MAC/xx:xx:xx:xx:xx:xx}"
  echo "[dry-run] then: $VIRSH define <xml>; $VIRSH start $NAME   (autostart stays off)"
  exit 0
fi
printf '%s\n' "$XML" | ssh -o BatchMode=yes "$HOST" "cat > '$DIR/$NAME.xml' && $VIRSH define '$DIR/$NAME.xml' && $VIRSH dominfo $NAME | grep -i autostart && $VIRSH start $NAME"
echo "rebuild: $NAME started. First boot takes several minutes; then onboard it (owner), set the ssh alias hass-test and run provision.sh."
