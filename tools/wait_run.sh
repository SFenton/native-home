#!/usr/bin/env bash
# Waits (without polling) for a lane's tools/bg_run.py job to exit, then prints its digest.
#   tools/wait_run.sh LOG_PATH      (the build/runs/<label>.log a lane reported)
LOG="$1"; LABEL=$(basename "$LOG" .log); DIR=$(dirname "$LOG")
PID=$(pgrep -f "bg_run.py $LABEL " | head -1)
[[ -n "$PID" ]] && caffeinate -w "$PID"
cat "$DIR/$LABEL.digest" 2>/dev/null | head -25 || echo "no digest for $LABEL"
