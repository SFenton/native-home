#!/usr/bin/env bash
# Installs (or removes) the LaunchAgent that dispatches the nightly run at 02:00 local time (DST-safe, so 2 AM Pacific).
# Usage: tools/nightly_install.sh [--uninstall] [--script PATH] [--dry-run]
#   The plist runs tools/nightly_dispatch.sh from the triage clone (~/hass-agents/repos/Fenton-HASS-Native, which the triage
#   runner keeps at origin/main) so the schedule always runs main's script; --script overrides the path.
#   --dry-run prints the plist and writes nothing. Label: com.sfenton.hass-nightly.
set -euo pipefail
LABEL=com.sfenton.hass-nightly
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT="$HOME/hass-agents/repos/Fenton-HASS-Native/tools/nightly_dispatch.sh"
UNINSTALL=0
DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall) UNINSTALL=1; shift ;;
    --script) SCRIPT="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
LOG_DIR="$HOME/hass-agents/logs"

render() {
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$SCRIPT</string></array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>2</integer><key>Minute</key><integer>0</integer></dict>
  <key>RunAtLoad</key><false/>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>$LOG_DIR/nightly.log</string>
  <key>StandardErrorPath</key><string>$LOG_DIR/nightly.log</string>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string><key>HOME</key><string>$HOME</string></dict>
</dict>
</plist>
PLIST
}

if [[ $DRY == 1 ]]; then render; exit 0; fi
DOMAIN="gui/$(id -u)"
launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
if [[ $UNINSTALL == 1 ]]; then rm -f "$PLIST"; echo "Removed $LABEL."; exit 0; fi
mkdir -p "$(dirname "$PLIST")" "$LOG_DIR"
render > "$PLIST"
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Installed $PLIST: $SCRIPT at 02:00 local time."
echo "Wake the Mac for it (needs sudo, run once): sudo pmset repeat wakeorpoweron MTWRFSU 01:55:00"
